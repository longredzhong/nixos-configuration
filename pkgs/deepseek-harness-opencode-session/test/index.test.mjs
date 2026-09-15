import assert from "node:assert/strict";
import { AsyncLocalStorage } from "node:async_hooks";
import test from "node:test";

import {
  OPENCODE_GO_CATALOG_URL,
  buildOpenCodeGoRoutes,
  createSessionFetch,
  fetchOpenCodeGoCatalog,
  isOpenCodeGoProvider,
  parseOpenCodeGoCatalog,
  syncOpenCodeGoCatalog,
  withSessionStream,
} from "../index.js";

const catalog = {
  models: [
    {
      id: "chat-model",
      name: "Chat model",
      api: "openai-completions",
      baseUrl: "https://opencode.ai/zen/go/v1",
      input: ["text", "audio"],
      contextWindow: 100_000,
      maxTokens: 10_000,
      reasoning: true,
      compat: {
        maxTokensField: "max_tokens",
        supportsDeveloperRole: false,
        unsupportedField: "discard me",
      },
      thinkingLevelMap: { low: "low", high: "high" },
    },
    {
      id: "response-model",
      name: "Response model",
      api: "openai-responses",
      baseUrl: "https://opencode.ai/zen/go/v1",
      input: ["text", "image"],
      contextWindow: 200_000,
      maxTokens: 20_000,
      reasoning: false,
    },
    {
      id: "messages-model",
      name: "Messages model",
      api: "anthropic-messages",
      baseUrl: "https://opencode.ai/zen/go",
      input: ["text"],
      contextWindow: 300_000,
      maxTokens: 30_000,
    },
  ],
};

test("translates the mixed catalog into protocol-specific routes", () => {
  const routes = buildOpenCodeGoRoutes(parseOpenCodeGoCatalog(catalog));

  assert.deepEqual(Object.keys(routes).sort(), [
    "opencode-go-live-chat",
    "opencode-go-live-messages",
    "opencode-go-live-responses",
  ]);
  assert.equal(routes["opencode-go-live-chat"].api, "openai-completions");
  assert.equal(routes["opencode-go-live-messages"].baseURL, "https://opencode.ai/zen/go");
  assert.equal(routes["opencode-go-live-chat"].models[0].input[0], "text");
  assert.equal(
    routes["opencode-go-live-chat"].models[0].compat.supportsDeveloperRole,
    false,
  );
  assert.equal(
    routes["opencode-go-live-chat"].models[0].compat.unsupportedField,
    undefined,
  );
  assert.deepEqual(
    routes["opencode-go-live-responses"].models[0].reasoningEfforts,
    false,
  );
});

test("fetches the public provider catalog without credentials", async () => {
  let request;
  const entries = await fetchOpenCodeGoCatalog(async (url, init) => {
    request = { url, init };
    return { ok: true, async json() { return catalog; } };
  });

  assert.equal(request.url, OPENCODE_GO_CATALOG_URL);
  assert.equal(request.init.headers.authorization, undefined);
  assert.equal(entries.length, 3);
});

test("writes all live routes through the settings mutation seam", async () => {
  const descriptor = {
    ns: "llm-pi-ai",
    revision: 7,
    user: { providers: {} },
  };
  let mutation;
  const settings = {
    describe() {
      return [descriptor];
    },
    async mutate(ns, operations, revision) {
      mutation = { ns, operations, revision };
      for (const operation of operations) {
        const [, provider] = operation.path;
        if (operation.op === "set") descriptor.user.providers[provider] = operation.value;
        else delete descriptor.user.providers[provider];
      }
      descriptor.revision += 1;
    },
  };

  const result = await syncOpenCodeGoCatalog(settings, {
    fetchImplementation: async () => ({ ok: true, async json() { return catalog; } }),
  });

  assert.equal(result.changed, true);
  assert.equal(mutation.ns, "llm-pi-ai");
  assert.equal(mutation.revision, 7);
  assert.equal(mutation.operations.length, 3);
  assert.equal(
    descriptor.user.providers["opencode-go-live-chat"].apiKeyEnv,
    "OPENCODE_GO_API_KEY",
  );
  assert.equal(
    Object.hasOwn(descriptor.user.providers["opencode-go-live-chat"], "apiKey"),
    false,
  );
});

test("retries one optimistic settings revision conflict", async () => {
  const descriptor = {
    ns: "llm-pi-ai",
    revision: 3,
    user: { providers: {} },
  };
  const revisions = [];
  let attempts = 0;
  const settings = {
    describe() {
      return [descriptor];
    },
    async mutate(_ns, _operations, revision) {
      revisions.push(revision);
      attempts += 1;
      if (attempts === 1) {
        descriptor.revision = 4;
        const error = new Error("revision changed");
        error.code = "SETTINGS_CONFLICT";
        throw error;
      }
    },
  };

  const result = await syncOpenCodeGoCatalog(settings, {
    fetchImplementation: async () => ({ ok: true, async json() { return catalog; } }),
  });

  assert.equal(result.changed, true);
  assert.deepEqual(revisions, [3, 4]);
});

test("adds the session header to live OpenCode Go routes", async () => {
  assert.equal(isOpenCodeGoProvider("opencode-go"), true);
  assert.equal(isOpenCodeGoProvider("opencode-go-live-responses"), true);
  assert.equal(isOpenCodeGoProvider("openai"), false);

  const storage = new AsyncLocalStorage();
  const calls = [];
  const fetch = createSessionFetch(async (url, init) => {
    calls.push({ url, headers: new Headers(init?.headers) });
    return new Response("ok");
  }, storage);

  const stream = withSessionStream(
    "session-123",
    () => (async function* () {
      await fetch("https://opencode.ai/zen/go/v1/responses", {
        headers: { "x-opencode-session": "stale" },
      });
      yield "done";
    })(),
    storage,
  );
  await stream.next();

  assert.equal(calls[0].headers.get("x-opencode-session"), "session-123");
});
