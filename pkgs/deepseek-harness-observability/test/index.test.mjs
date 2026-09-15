// Projection tests for the OpenObserve session-telemetry backend.
//
// The projection is the redaction boundary: it decides which scalar fields
// leave the process. These tests pin both the fields a dashboard depends on and
// the absence of message, tool-argument and error-text content.

import assert from "node:assert/strict";
import test from "node:test";

import {
  LEDGER_EVENT_TYPES,
  projectLedgerRecord,
  projectOpsRecord,
} from "../index.js";

const SESSION_ID = "session-0001";

function assistantMessageEvent(overrides = {}) {
  return {
    type: "assistant/message",
    seq: 7,
    time: 1_760_000_000_000,
    data: {
      turn: 2,
      step: 3,
      message: {
        id: "message-1",
        role: "assistant",
        source: { kind: "model", provider: "opencode-go", model: "deepseek-v4.1-flash" },
        content: [{ type: "text", text: "SECRET ASSISTANT TEXT" }],
      },
      stream: [{ type: "text-delta", text: "SECRET STREAM FRAME" }],
      usage: {
        inputTokens: 1200,
        outputTokens: 340,
        totalTokens: 1540,
        cacheReadTokens: 900,
        cacheWriteTokens: 25,
        reasoningTokens: 60,
      },
      ...overrides,
    },
  };
}

test("an assistant message exports token accounting and its route", () => {
  const record = projectLedgerRecord(SESSION_ID, assistantMessageEvent());

  assert.equal(record.session_id, SESSION_ID);
  assert.equal(record.event_type, "assistant/message");
  assert.equal(record.event_seq, 7);
  assert.equal(record._timestamp, 1_760_000_000_000_000);
  assert.equal(record.turn, 2);
  assert.equal(record.step, 3);
  assert.equal(record.provider, "opencode-go");
  assert.equal(record.model, "deepseek-v4.1-flash");
  assert.equal(record.usage_reported, 1);
  assert.equal(record.input_tokens, 1200);
  assert.equal(record.output_tokens, 340);
  assert.equal(record.total_tokens, 1540);
  assert.equal(record.cache_read_tokens, 900);
  assert.equal(record.cache_write_tokens, 25);
  assert.equal(record.reasoning_tokens, 60);
});

test("no message, stream or source field reaches the record", () => {
  const serialized = JSON.stringify(projectLedgerRecord(SESSION_ID, assistantMessageEvent()));

  assert.ok(!serialized.includes("SECRET"), serialized);
  assert.ok(!serialized.includes("source"), serialized);
  assert.ok(!serialized.includes("content"), serialized);
});

test("a message without usage omits every token field", () => {
  const event = assistantMessageEvent({ usage: undefined });
  const record = projectLedgerRecord(SESSION_ID, event);

  assert.equal(record.usage_reported, undefined);
  assert.equal(record.input_tokens, undefined);
  assert.equal(record.provider, "opencode-go");
});

test("an interrupted assistant message is marked", () => {
  const record = projectLedgerRecord(SESSION_ID, assistantMessageEvent({ interrupted: true }));
  assert.equal(record.interrupted, 1);
});

test("a tool call exports the name but never the arguments", () => {
  const record = projectLedgerRecord(SESSION_ID, {
    type: "tool/call",
    seq: 9,
    time: 1_760_000_001_000,
    data: { turn: 2, step: 4, callId: "call-1", name: "bash", arguments: '{"command":"SECRET"}' },
  });

  assert.equal(record.tool_name, "bash");
  assert.ok(!JSON.stringify(record).includes("SECRET"));
});

test("a failed tool result exports identity but not the failure reason", () => {
  const record = projectLedgerRecord(SESSION_ID, {
    type: "tool/result",
    seq: 10,
    time: 1_760_000_002_000,
    data: {
      turn: 2,
      step: 4,
      message: { role: "user", content: [{ type: "tool-result", output: "SECRET OUTPUT" }] },
      error: { name: "ToolError", code: "E_TOOL", reason: "SECRET REASON" },
    },
  });

  assert.equal(record.tool_failed, 1);
  assert.equal(record.error_name, "ToolError");
  assert.equal(record.error_code, "E_TOOL");
  assert.ok(!JSON.stringify(record).includes("SECRET"));
});

test("a successful tool result is marked not failed", () => {
  const record = projectLedgerRecord(SESSION_ID, {
    type: "tool/result",
    seq: 11,
    time: 1_760_000_003_000,
    data: { turn: 2, step: 4, message: { role: "user", content: [] } },
  });

  assert.equal(record.tool_failed, 0);
  assert.equal(record.error_name, undefined);
});

test("event types outside the allowlist are dropped", () => {
  const record = projectLedgerRecord(SESSION_ID, {
    type: "system/message",
    seq: 1,
    time: 1_760_000_000_000,
    data: { turn: 1, step: 1, message: { role: "system", content: "SECRET SYSTEM PROMPT" } },
  });

  assert.equal(record, undefined);
  assert.ok(LEDGER_EVENT_TYPES.includes("assistant/message"));
});

test("a malformed event is dropped rather than throwing", () => {
  assert.equal(projectLedgerRecord(SESSION_ID, undefined), undefined);
  assert.equal(projectLedgerRecord(SESSION_ID, null), undefined);
  assert.equal(projectLedgerRecord(SESSION_ID, "assistant/message"), undefined);

  // A recognized type with no payload is still a legitimate emission: identity
  // survives and no field is invented.
  const record = projectLedgerRecord(SESSION_ID, { type: "tool/call" });
  assert.equal(record.event_type, "tool/call");
  assert.equal(record.session_id, SESSION_ID);
  assert.equal(record.event_seq, undefined);
  assert.equal(record.tool_name, undefined);
});

test("an undefined session id is preserved as undefined", () => {
  const record = projectLedgerRecord(undefined, assistantMessageEvent());
  assert.equal(record.session_id, undefined);
});

test("an agent error exports identity without the error message", () => {
  const error = new Error("SECRET FAILURE TEXT");
  error.name = "ProviderError";

  const record = projectOpsRecord({
    agent: { id: "agent-1", session: { id: SESSION_ID } },
    turn: 4,
    step: 2,
    error,
  });

  assert.equal(record.signal, "ops");
  assert.equal(record.severity, "error");
  assert.equal(record.event_type, "agent/error");
  assert.equal(record.session_id, SESSION_ID);
  assert.equal(record.turn, 4);
  assert.equal(record.step, 2);
  assert.equal(record.error_name, "ProviderError");
  assert.ok(!JSON.stringify(record).includes("SECRET"));
});

test("an agent error with an unknown error value still reports the emission", () => {
  const record = projectOpsRecord({ agent: { session: { id: SESSION_ID } }, turn: 1, step: 1, error: "boom" });
  assert.equal(record.event_type, "agent/error");
  assert.equal(record.error_name, undefined);
});
