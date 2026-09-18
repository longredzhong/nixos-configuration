import { AsyncLocalStorage } from "node:async_hooks";

export const name = "deepseek-harness-opencode-session";
export const OPENCODE_GO_PROVIDER = "opencode-go";
export const OPENCODE_GO_LIVE_PROVIDER_PREFIX = "opencode-go-live-";
export const OPENCODE_SESSION_HEADER = "x-opencode-session";
export const OPENCODE_GO_CATALOG_URL =
  "https://pi.dev/api/models/providers/opencode-go";
export const OPENCODE_GO_SYNC_START_DELAY_MS = 5_000;
export const OPENCODE_GO_SYNC_RETRY_INTERVAL_MS = 5 * 60 * 1_000;
export const OPENCODE_GO_SYNC_INTERVAL_MS = 4 * 60 * 60 * 1_000;

const OPENCODE_GO_V1_BASE_URL = "https://opencode.ai/zen/go/v1";
const OPENCODE_GO_ANTHROPIC_BASE_URL = "https://opencode.ai/zen/go";
const OPENCODE_GO_APIS = new Set([
  "openai-completions",
  "openai-responses",
  "anthropic-messages",
]);
const OPENCODE_GO_INPUT_MODALITIES = new Set(["text", "image"]);
const REASONING_LEVELS = [
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
  "off",
];
const COMPAT_KEYS = new Set([
  "supportsStore",
  "supportsDeveloperRole",
  "supportsReasoningEffort",
  "supportsUsageInStreaming",
  "supportsFinishReason",
  "maxTokensField",
  "requiresToolResultName",
  "requiresAssistantAfterToolResult",
  "requiresThinkingAsText",
  "requiresReasoningContentOnAssistantMessages",
  "thinkingFormat",
  "chatTemplateKwargs",
  "chatTemplateArgs",
  "supportsThinkingTokenBudget",
  "thinkingTokenBudgetField",
  "vllmPriority",
  "supportsMaxOutputTokens",
  "supportsStrictMode",
  "cacheControlFormat",
  "supportsLongCacheRetention",
  "supportsEagerToolInputStreaming",
  "supportsCacheControlOnTools",
  "supportsTemperature",
  "forceAdaptiveThinking",
  "allowEmptySignature",
  "supportsStrictTools",
]);

/**
 * These routes are owned by this plugin. A separate route is required for
 * each protocol because dsh 0.1.6-alpha.2 stores `api` and `baseURL` at the
 * provider level, while the OpenCode Go catalog is mixed-protocol.
 */
export const OPENCODE_GO_LIVE_ROUTES = Object.freeze({
  "openai-completions": Object.freeze({
    id: "opencode-go-live-chat",
    displayName: "OpenCode Go (Chat Completions)",
    api: "openai-completions",
    baseURL: OPENCODE_GO_V1_BASE_URL,
  }),
  "openai-responses": Object.freeze({
    id: "opencode-go-live-responses",
    displayName: "OpenCode Go (Responses)",
    api: "openai-responses",
    baseURL: OPENCODE_GO_V1_BASE_URL,
  }),
  "anthropic-messages": Object.freeze({
    id: "opencode-go-live-messages",
    displayName: "OpenCode Go (Anthropic Messages)",
    api: "anthropic-messages",
    baseURL: OPENCODE_GO_ANTHROPIC_BASE_URL,
  }),
});

const sessionStorage = new AsyncLocalStorage();

export function isOpenCodeGoProvider(provider) {
  return (
    provider === OPENCODE_GO_PROVIDER ||
    (typeof provider === "string" &&
      provider.startsWith(OPENCODE_GO_LIVE_PROVIDER_PREFIX))
  );
}

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

function isPositiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

function catalogObjectEntries(value) {
  if (Array.isArray(value)) return value.map((entry, index) => [String(index), entry]);
  if (value === null || typeof value !== "object") return [];

  if (Array.isArray(value.models)) {
    return value.models.map((entry, index) => [String(index), entry]);
  }
  if (value.models !== null && typeof value.models === "object") {
    return Object.entries(value.models);
  }
  return Object.entries(value);
}

function canonicalBaseURL(api) {
  return api === "anthropic-messages"
    ? OPENCODE_GO_ANTHROPIC_BASE_URL
    : OPENCODE_GO_V1_BASE_URL;
}

function normalizeCatalogEntry(value, fallbackId) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  const id = typeof value.id === "string" && value.id.length > 0
    ? value.id
    : fallbackId;
  const api = typeof value.api === "string" ? value.api : undefined;
  if (!id || !OPENCODE_GO_APIS.has(api)) return undefined;

  const baseURL = typeof value.baseUrl === "string"
    ? value.baseUrl
    : typeof value.baseURL === "string"
      ? value.baseURL
      : canonicalBaseURL(api);

  // Only accept the canonical OpenCode Go origin. The catalog is public, but
  // a compromised catalog must not redirect model traffic to another host.
  if (baseURL !== canonicalBaseURL(api)) return undefined;

  return {
    id,
    api,
    baseURL,
    name: typeof value.name === "string" && value.name.length > 0
      ? value.name
      : id,
    contextWindow: isPositiveInteger(value.contextWindow)
      ? value.contextWindow
      : undefined,
    maxTokens: isPositiveInteger(value.maxTokens) ? value.maxTokens : undefined,
    input: Array.isArray(value.input) ? value.input : [],
    reasoning: value.reasoning === true
      ? true
      : value.reasoning === false
        ? false
        : undefined,
    compat: value.compat !== null && typeof value.compat === "object"
      ? value.compat
      : undefined,
    thinkingLevelMap:
      value.thinkingLevelMap !== null &&
      typeof value.thinkingLevelMap === "object"
        ? value.thinkingLevelMap
        : undefined,
  };
}

/**
 * Parse the public pi.dev provider catalog into the small, validated shape
 * used by the settings writer. pi.dev carries the protocol and compatibility
 * fields that the raw OpenCode `/models` endpoint does not expose.
 */
export function parseOpenCodeGoCatalog(value) {
  const models = new Map();

  for (const [key, entry] of catalogObjectEntries(value)) {
    const normalized = normalizeCatalogEntry(entry, key);
    if (normalized !== undefined) models.set(normalized.id, normalized);
  }

  if (models.size === 0) {
    throw new Error("OpenCode Go catalog contains no supported models");
  }

  return [...models.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function modelInput(entry) {
  const input = entry.input.filter((value) => OPENCODE_GO_INPUT_MODALITIES.has(value));
  return input.length > 0 ? [...new Set(input)] : ["text"];
}

function modelCompat(entry) {
  if (entry.compat === undefined) return undefined;

  const compat = {};
  for (const [key, value] of Object.entries(entry.compat)) {
    if (!COMPAT_KEYS.has(key) || value === null || value === undefined) continue;
    if (
      typeof value === "boolean" ||
      typeof value === "string" ||
      (typeof value === "object" && !Array.isArray(value))
    ) {
      compat[key] = value;
    }
  }
  return Object.keys(compat).length > 0 ? compat : undefined;
}

function modelReasoningEfforts(entry, compat) {
  if (entry.reasoning === false) return false;

  const efforts = {};
  if (entry.thinkingLevelMap !== undefined) {
    for (const level of REASONING_LEVELS) {
      const mapped = entry.thinkingLevelMap[level];
      if (typeof mapped === "string" && mapped.length > 0) efforts[level] = mapped;
    }
  }

  if (Object.keys(efforts).some((level) => level !== "off")) return efforts;
  if (entry.reasoning === true && compat?.supportsReasoningEffort !== false) {
    // Some OpenCode Go models advertise reasoning but omit the level map.
    // This is the same safe fallback used by pi's model translator.
    return { low: "low", high: "high" };
  }
  if (entry.reasoning === true) return false;
  return undefined;
}

function modelProfile(entry) {
  const compat = modelCompat(entry);
  const profile = {
    id: entry.id,
    name: entry.name,
    input: modelInput(entry),
  };

  if (entry.contextWindow !== undefined) profile.contextWindow = entry.contextWindow;
  // dsh uses its route default when maxTokens is absent. Avoid emitting an
  // invalid profile if a remote catalog briefly reports an oversized value.
  if (
    entry.maxTokens !== undefined &&
    (entry.contextWindow === undefined || entry.maxTokens < entry.contextWindow)
  ) {
    profile.maxTokens = entry.maxTokens;
  }
  if (compat !== undefined) profile.compat = compat;

  const reasoningEfforts = modelReasoningEfforts(entry, compat);
  if (reasoningEfforts !== undefined) profile.reasoningEfforts = reasoningEfforts;
  return profile;
}

/**
 * Translate a mixed OpenCode Go catalog into one settings provider per wire
 * protocol. The provider routes contain only data returned by the catalog;
 * the API key remains an environment reference and is never fetched or saved.
 */
export function buildOpenCodeGoRoutes(entries) {
  const grouped = new Map();
  for (const entry of entries) {
    const route = OPENCODE_GO_LIVE_ROUTES[entry.api];
    if (route === undefined || entry.baseURL !== route.baseURL) continue;
    const models = grouped.get(entry.api) ?? new Map();
    models.set(entry.id, modelProfile(entry));
    grouped.set(entry.api, models);
  }

  const routes = {};
  for (const [api, models] of grouped) {
    const route = OPENCODE_GO_LIVE_ROUTES[api];
    routes[route.id] = {
      apiKeyEnv: "OPENCODE_GO_API_KEY",
      displayName: route.displayName,
      api: route.api,
      baseURL: route.baseURL,
      models: [...models.values()].sort((left, right) => left.id.localeCompare(right.id)),
    };
  }
  return routes;
}

function timeoutForFetch(signal, timeoutMs) {
  if (signal !== undefined) return { signal, cancel: () => {} };
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  return { signal: controller.signal, cancel: () => clearTimeout(timeout) };
}

export async function fetchOpenCodeGoCatalog(
  fetchImplementation = globalThis.fetch,
  { signal, timeoutMs = 20_000 } = {},
) {
  if (typeof fetchImplementation !== "function") {
    throw new Error("OpenCode Go catalog fetch is unavailable");
  }

  const timeout = timeoutForFetch(signal, timeoutMs);
  try {
    const response = await fetchImplementation(OPENCODE_GO_CATALOG_URL, {
      method: "GET",
      headers: { accept: "application/json" },
      signal: timeout.signal,
    });
    if (!response || response.ok === false) {
      const status = response?.status === undefined ? "unknown" : response.status;
      throw new Error(`OpenCode Go catalog request failed (${status})`);
    }
    return parseOpenCodeGoCatalog(await response.json());
  } finally {
    timeout.cancel();
  }
}

function sameJson(left, right) {
  if (left === right) return true;
  if (left === null || right === null || typeof left !== typeof right) return false;
  if (typeof left !== "object") return false;
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
      return false;
    }
    return left.every((value, index) => sameJson(value, right[index]));
  }

  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  return (
    leftKeys.length === rightKeys.length &&
    leftKeys.every((key, index) => key === rightKeys[index] && sameJson(left[key], right[key]))
  );
}

function userProviderConfig(descriptor, provider) {
  const providers = descriptor?.user?.providers;
  return providers !== null && typeof providers === "object"
    ? providers[provider]
    : undefined;
}

function settingsOperations(descriptor, routes) {
  const operations = [];
  for (const route of Object.values(OPENCODE_GO_LIVE_ROUTES)) {
    const existing = userProviderConfig(descriptor, route.id);
    const desired = routes[route.id];
    if (desired === undefined) {
      if (existing !== undefined) {
        operations.push({ op: "unset", path: ["providers", route.id] });
      }
      continue;
    }
    if (!sameJson(existing, desired)) {
      operations.push({
        op: "set",
        path: ["providers", route.id],
        value: desired,
      });
    }
  }
  return operations;
}

function settingsDescriptor(settings) {
  const descriptors = settings.describe();
  return Array.isArray(descriptors)
    ? descriptors.find((descriptor) => descriptor.ns === "llm-pi-ai")
    : undefined;
}

/**
 * Fetch and persist the live catalog through the official DSH Settings seam.
 * A revision conflict is retried once. A failed refresh never removes the
 * last good live routes, so the static legacy route remains available.
 */
export async function syncOpenCodeGoCatalog(
  settings,
  { fetchImplementation = globalThis.fetch, timeoutMs } = {},
) {
  const entries = await fetchOpenCodeGoCatalog(fetchImplementation, { timeoutMs });
  const routes = buildOpenCodeGoRoutes(entries);
  const missingApis = Object.entries(OPENCODE_GO_LIVE_ROUTES)
    .filter(([, route]) => routes[route.id] === undefined)
    .map(([api]) => api);
  if (missingApis.length > 0) {
    throw new Error(`OpenCode Go catalog is missing protocols: ${missingApis.join(", ")}`);
  }
  const routeCounts = Object.fromEntries(
    Object.entries(routes).map(([provider, config]) => [provider, config.models.length]),
  );

  if (
    settings === undefined ||
    typeof settings.describe !== "function" ||
    typeof settings.mutate !== "function"
  ) {
    return { changed: false, skipped: true, entries, routeCounts };
  }

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const descriptor = settingsDescriptor(settings);
    if (descriptor === undefined) {
      return { changed: false, skipped: true, entries, routeCounts };
    }

    const operations = settingsOperations(descriptor, routes);
    if (operations.length === 0) {
      return { changed: false, entries, routeCounts };
    }

    try {
      await settings.mutate("llm-pi-ai", operations, descriptor.revision);
      return { changed: true, entries, routeCounts, operations };
    } catch (error) {
      if (error?.code !== "SETTINGS_CONFLICT" || attempt !== 0) throw error;
    }
  }

  throw new Error("OpenCode Go settings conflict retry failed");
}

function serviceFromContext(context, serviceName) {
  if (context?.[serviceName] !== undefined) return context[serviceName];
  if (typeof context?.get === "function") return context.get(serviceName);
  return undefined;
}

function installCatalogSync(ctx, settings) {
  let stopped = false;
  let retryTimer;

  const scheduleRetry = () => {
    if (stopped || retryTimer !== undefined) return;
    retryTimer = setTimeout(() => {
      retryTimer = undefined;
      refresh();
    }, OPENCODE_GO_SYNC_RETRY_INTERVAL_MS);
  };

  const refresh = () => {
    syncOpenCodeGoCatalog(settings).then((result) => {
      if (stopped) return;
      if (result.skipped) {
        scheduleRetry();
        return;
      }
      const counts = Object.entries(result.routeCounts)
        .map(([provider, count]) => `${provider}=${count}`)
        .join(", ");
      const message = result.changed
        ? "OpenCode Go model catalog synchronized: "
        : "OpenCode Go model catalog is current: ";
      ctx.logger?.info?.(`${message}${counts}`);
    }).catch((error) => {
      if (!stopped) {
        ctx.logger?.warn?.(
          `OpenCode Go model catalog refresh failed: ${error instanceof Error ? error.message : String(error)}`,
        );
        scheduleRetry();
      }
    });
  };

  const startupTimer = setTimeout(refresh, OPENCODE_GO_SYNC_START_DELAY_MS);
  const intervalTimer = setInterval(refresh, OPENCODE_GO_SYNC_INTERVAL_MS);
  return () => {
    stopped = true;
    clearTimeout(startupTimer);
    clearTimeout(retryTimer);
    clearInterval(intervalTimer);
  };
}

export function apply(ctx) {
  if (typeof globalThis.fetch !== "function") {
    throw new Error("deepseek-harness-opencode-session: global fetch is unavailable");
  }

  const originalFetch = globalThis.fetch;
  const wrappedFetch = createSessionFetch(originalFetch);
  globalThis.fetch = wrappedFetch;

  ctx.on("llm/stream", (options, next) => {
    if (!isOpenCodeGoProvider(options.provider)) return next();
    return withSessionStream(options.sessionId, next);
  }, { global: true });

  ctx.inject(["settings"], (settingsCtx) => {
    const settings = serviceFromContext(settingsCtx, "settings");
    const disposeSync = installCatalogSync(ctx, settings);
    ctx.effect?.(() => disposeSync);
  });

  return () => {
    if (globalThis.fetch === wrappedFetch) globalThis.fetch = originalFetch;
  };
}
