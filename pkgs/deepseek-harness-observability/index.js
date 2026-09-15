// DeepSeek Harness session telemetry backend for OpenObserve.
//
// Why this package exists: the shipped @deepseek-ai/dsh-session-telemetry-otel
// row only implements FEEDBACK_ONLY — its mode enum has no value that enables
// live capture, and its constructor hardcodes `capture: "on-demand"` plus a
// `feedback/record` filter, so it can only ever upload user feedback. Token,
// tool and error telemetry therefore has no backend unless a deployment
// supplies one. This is that backend.
//
// Why it has no npm dependencies: the profile loader installs its resolution
// router only for importers whose parent URL sits inside the profile
// directory (`startsWithin(parent, profileUrls)` in @deepseek-ai/dsh-app-boot).
// This package is linked from /nix/store, so Node's native resolver handles its
// imports and cannot see the dsh install's node_modules. Node builtins plus the
// global `fetch` of Node 22 are the only things this file may use. The OTLP
// pipeline is replaced by OpenObserve's native JSON ingestion endpoint, which
// needs nothing but an HTTP POST.
//
// Redaction is fail-closed by construction: every record is built by picking
// named scalar fields off the event. Message content, tool arguments, tool
// output, stream frames and error text are never read, so there is no field to
// redact and no dependency on a `session-telemetry/record` rule being mounted.
// If this projection is ever widened to carry free text, that rule becomes
// mandatory.

import { readFileSync } from "node:fs";

export const name = "@longred/deepseek-harness-observability";

const ENDPOINT_ENV = "DSH_OBSERVABILITY_URL";
const TOKEN_FILE_ENV = "DSH_OBSERVABILITY_TOKEN_FILE";
const LEDGER_STREAM_ENV = "DSH_OBSERVABILITY_LEDGER_STREAM";
const OPS_STREAM_ENV = "DSH_OBSERVABILITY_OPS_STREAM";

const DEFAULT_LEDGER_STREAM = "dsh_ledger";
const DEFAULT_OPS_STREAM = "dsh_ops";

/** Flush cadence and buffer bounds keep a slow OpenObserve off the agent loop. */
const FLUSH_INTERVAL_MS = 5_000;
const MAX_BUFFERED_RECORDS = 5_000;
const MAX_BATCH_RECORDS = 500;
const REQUEST_TIMEOUT_MS = 15_000;

/**
 * Session event types projected into the ledger stream. The allowlist is
 * deliberate: an unrecognized event type is dropped rather than exported with
 * an opaque body.
 */
export const LEDGER_EVENT_TYPES = Object.freeze([
  "user/message",
  "assistant/message",
  "assistant/attempt",
  "tool/call",
  "tool/result",
]);

const LEDGER_EVENT_TYPE_SET = new Set(LEDGER_EVENT_TYPES);

/** Read one finite number, or undefined when the field is absent or unusable. */
function numberOrUndefined(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/** Read one non-empty string, or undefined. Branded ids are plain strings. */
function stringOrUndefined(value) {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/** Read one record-shaped value, or undefined for null, arrays and primitives. */
function recordOrUndefined(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value
    : undefined;
}

/**
 * Convert an epoch-millisecond session timestamp to the microsecond unit
 * OpenObserve reads from `_timestamp`.
 */
function toMicroseconds(time) {
  return Number.isFinite(time) ? Math.round(time * 1000) : Math.round(Date.now() * 1000);
}

/** Identity fields every ledger record carries. */
function ledgerBase(sessionId, event) {
  return {
    _timestamp: toMicroseconds(event.time),
    signal: "ledger",
    service: "deepseek-harness",
    event_type: stringOrUndefined(event.type),
    event_seq: numberOrUndefined(event.seq),
    session_id: sessionId,
  };
}

/**
 * Project one session event onto the flat scalar record OpenObserve stores.
 *
 * Only named fields are read; the event's `data` is never copied. Returns
 * undefined for an event type outside the allowlist.
 *
 * @param sessionId - the owning session's id, already reduced to a string.
 * @param event - one canonical session-log event.
 * @returns the ledger record, or undefined when this type is not exported.
 */
export function projectLedgerRecord(sessionId, event) {
  if (recordOrUndefined(event) === undefined) return undefined;
  if (!LEDGER_EVENT_TYPE_SET.has(event.type)) return undefined;

  const record = ledgerBase(sessionId, event);
  const data = recordOrUndefined(event.data);
  if (data === undefined) return record;

  const turn = numberOrUndefined(data.turn);
  const step = numberOrUndefined(data.step);
  if (turn !== undefined) record.turn = turn;
  if (step !== undefined) record.step = step;

  switch (event.type) {
    case "assistant/message": {
      const message = recordOrUndefined(data.message);
      const source = message === undefined ? undefined : recordOrUndefined(message.source);
      if (source !== undefined && source.kind === "model") {
        record.provider = stringOrUndefined(source.provider);
        record.model = stringOrUndefined(source.model);
      }
      // `usage` is the only home of token accounting in the session log: the
      // seam documents that there is no separate usage record, and it is
      // absent when the adapter reported none.
      const usage = recordOrUndefined(data.usage);
      if (usage !== undefined) {
        record.usage_reported = 1;
        record.input_tokens = numberOrUndefined(usage.inputTokens);
        record.output_tokens = numberOrUndefined(usage.outputTokens);
        record.total_tokens = numberOrUndefined(usage.totalTokens);
        record.cache_read_tokens = numberOrUndefined(usage.cacheReadTokens);
        record.cache_write_tokens = numberOrUndefined(usage.cacheWriteTokens);
        record.reasoning_tokens = numberOrUndefined(usage.reasoningTokens);
      }
      if (data.interrupted === true) record.interrupted = 1;
      break;
    }
    case "tool/call": {
      record.tool_name = stringOrUndefined(data.name);
      break;
    }
    case "tool/result": {
      // `error.reason` is raw user-facing text and is deliberately not read.
      const error = recordOrUndefined(data.error);
      if (error === undefined) {
        record.tool_failed = 0;
      } else {
        record.tool_failed = 1;
        record.error_name = stringOrUndefined(error.name);
        record.error_code = stringOrUndefined(error.code);
      }
      break;
    }
    default:
      break;
  }

  return record;
}

/**
 * Project one `agent/error` bus emission onto an operational record.
 *
 * @param payload - the event payload carrying the agent, turn, step and error.
 * @returns the ops record.
 */
export function projectOpsRecord(payload) {
  const payloadRecord = recordOrUndefined(payload) ?? {};
  const agent = recordOrUndefined(payloadRecord.agent);
  const session = agent === undefined ? undefined : recordOrUndefined(agent.session);
  const error = payloadRecord.error;

  return {
    _timestamp: Math.round(Date.now() * 1000),
    signal: "ops",
    service: "deepseek-harness",
    event_type: "agent/error",
    severity: "error",
    session_id: session === undefined ? undefined : stringOrUndefined(session.id),
    turn: numberOrUndefined(payloadRecord.turn),
    step: numberOrUndefined(payloadRecord.step),
    error_name:
      stringOrUndefined(error?.name) ??
      (error instanceof Error ? stringOrUndefined(error.name) : undefined),
  };
}

/** Drop undefined-valued keys so OpenObserve stores only present fields. */
function compact(record) {
  const out = {};
  for (const [key, value] of Object.entries(record)) {
    if (value !== undefined) out[key] = value;
  }
  return out;
}

/**
 * POST one batch to OpenObserve's native JSON ingestion endpoint.
 *
 * @param endpoint - base URL including the organization, without a trailing slash.
 * @param stream - target stream name.
 * @param authorization - the complete Authorization header value.
 * @param records - the batch, already compacted.
 * @returns resolves on a 2xx response.
 */
async function postBatch(endpoint, stream, authorization, records) {
  const response = await fetch(`${endpoint}/${encodeURIComponent(stream)}/_json`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization,
    },
    body: JSON.stringify(records),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (response.ok !== true) {
    throw new Error(`OpenObserve ingestion failed (${response.status})`);
  }
}

/** Read the ingestion credential; agenix writes the file at service start. */
function readAuthorization(tokenFile) {
  const value = readFileSync(tokenFile, "utf8").trim();
  if (value.length === 0) throw new Error(`${TOKEN_FILE_ENV} is empty`);
  return value;
}

export function apply(ctx) {
  if (typeof globalThis.fetch !== "function") {
    throw new Error(`${name}: global fetch is unavailable`);
  }

  const endpoint = (process.env[ENDPOINT_ENV] ?? "").replace(/\/+$/, "");
  const tokenFile = process.env[TOKEN_FILE_ENV] ?? "";
  const ledgerStream = process.env[LEDGER_STREAM_ENV] || DEFAULT_LEDGER_STREAM;
  const opsStream = process.env[OPS_STREAM_ENV] || DEFAULT_OPS_STREAM;

  // Fail open at load: an unconfigured or unreachable observability backend
  // must not keep the harness from starting. The row stays mounted and simply
  // contributes nothing until the environment is complete.
  if (endpoint.length === 0 || tokenFile.length === 0) {
    ctx.logger?.warn?.(
      `${name}: disabled because ${ENDPOINT_ENV} or ${TOKEN_FILE_ENV} is unset`,
    );
    return;
  }

  // Read the credential once. A missing file means agenix has not produced the
  // secret yet; disable rather than warn on every flush interval. Rotating the
  // credential therefore takes a harness restart.
  let authorization;
  try {
    authorization = readAuthorization(tokenFile);
  } catch (error) {
    ctx.logger?.warn?.(
      `${name}: disabled because the ingestion credential is unreadable: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return;
  }

  const buffers = new Map([
    [ledgerStream, []],
    [opsStream, []],
  ]);
  let dropped = 0;
  let draining = false;

  const push = (stream, record) => {
    const buffer = buffers.get(stream);
    if (buffer === undefined) return;
    if (buffer.length >= MAX_BUFFERED_RECORDS) {
      dropped += 1;
      return;
    }
    buffer.push(compact(record));
  };

  const drain = async () => {
    if (draining) return;
    draining = true;
    try {
      for (const [stream, buffer] of buffers) {
        while (buffer.length > 0) {
          const batch = buffer.splice(0, MAX_BATCH_RECORDS);
          await postBatch(endpoint, stream, authorization, batch);
        }
      }
      if (dropped > 0) {
        ctx.logger?.warn?.(`${name}: dropped ${dropped} record(s) over the buffer bound`);
        dropped = 0;
      }
    } catch (error) {
      // Keep the export failure off the agent loop and off the session log.
      ctx.logger?.warn?.(
        `${name}: export failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    } finally {
      draining = false;
    }
  };

  /** Resolve the owning session id without retaining the live Session object. */
  const sessionIdOf = (session) => {
    const record = recordOrUndefined(session);
    return record === undefined ? undefined : stringOrUndefined(record.id);
  };

  ctx.on("session/event", (session, event) => {
    try {
      const record = projectLedgerRecord(sessionIdOf(session), event);
      if (record !== undefined) push(ledgerStream, record);
    } catch (error) {
      ctx.logger?.warn?.(
        `${name}: projection failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  });

  ctx.on("agent/error", (payload) => {
    try {
      push(opsStream, projectOpsRecord(payload));
    } catch (error) {
      ctx.logger?.warn?.(
        `${name}: projection failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  });

  // The timer and the final drain both belong to this fiber: stopping or
  // updating the row clears the interval and flushes what is buffered.
  ctx.effect(() => {
    const interval = setInterval(() => {
      void drain();
    }, FLUSH_INTERVAL_MS);

    return () => {
      clearInterval(interval);
      void drain();
    };
  });

  ctx.logger?.info?.(
    `${name}: exporting ${LEDGER_EVENT_TYPES.length} session event type(s) to ${ledgerStream} and agent errors to ${opsStream}`,
  );
}
