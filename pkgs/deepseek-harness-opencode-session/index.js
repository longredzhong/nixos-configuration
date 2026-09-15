import { AsyncLocalStorage } from "node:async_hooks";

export const name = "deepseek-harness-opencode-session";
export const OPENCODE_GO_PROVIDER = "opencode-go";
export const OPENCODE_SESSION_HEADER = "x-opencode-session";

const sessionStorage = new AsyncLocalStorage();

function normalizeSessionId(value) {
  if (typeof value !== "string") return undefined;
  const sessionId = value;
  return sessionId.length === 0 ? undefined : sessionId;
}

function requestHeaders(input, init, sessionId) {
  const inherited = typeof Request !== "undefined" && input instanceof Request
    ? input.headers
    : undefined;
  const headers = new Headers(inherited);

  if (init?.headers !== undefined) {
    for (const [name, value] of new Headers(init.headers)) headers.set(name, value);
  }

  if (sessionId === undefined) headers.delete(OPENCODE_SESSION_HEADER);
  else headers.set(OPENCODE_SESSION_HEADER, sessionId);
  return headers;
}

/**
 * Wrap one fetch implementation with the session value carried by storage.
 * The wrapper leaves requests outside an OpenCode Go stream byte-for-byte
 * untouched. Inside the stream it overwrites a conflicting header with the
 * exact DSH session, or removes a stale static header when no session exists.
 */
export function createSessionFetch(fetchImplementation, storage = sessionStorage) {
  return (input, init) => {
    const scope = storage.getStore();
    if (scope === undefined) return fetchImplementation(input, init);

    return fetchImplementation(input, {
      ...init,
      headers: requestHeaders(input, init, scope.sessionId),
    });
  };
}

/**
 * Keep the DSH session context active while a lazy LLM stream is consumed.
 * pi-ai creates its OpenAI client and invokes fetch during iterator.next(),
 * after the llm/stream waterfall has returned, so wrapping only next() is
 * necessary for the header to follow the actual provider request.
 */
export function withSessionStream(sessionId, next, storage = sessionStorage) {
  const normalized = normalizeSessionId(sessionId);
  const scope = { sessionId: normalized };

  return (async function* () {
    let stream;
    let iterator;
    let completed = false;

    try {
      stream = storage.run(scope, next);
      iterator = stream[Symbol.asyncIterator]();

      while (true) {
        const result = await storage.run(scope, () => iterator.next());
        if (result.done) {
          completed = true;
          return;
        }
        yield result.value;
      }
    } finally {
      if (!completed && iterator?.return !== undefined) {
        await storage.run(scope, () => iterator.return());
      }
    }
  })();
}

export function apply(ctx) {
  if (typeof globalThis.fetch !== "function") {
    throw new Error("deepseek-harness-opencode-session: global fetch is unavailable");
  }

  const originalFetch = globalThis.fetch;
  const wrappedFetch = createSessionFetch(originalFetch);
  globalThis.fetch = wrappedFetch;

  ctx.on("llm/stream", (options, next) => {
    if (options.provider !== OPENCODE_GO_PROVIDER) return next();
    return withSessionStream(options.sessionId, next);
  }, { global: true });

  return () => {
    if (globalThis.fetch === wrappedFetch) globalThis.fetch = originalFetch;
  };
}
