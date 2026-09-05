// stats — API usage stats (example extension)
//
// Purpose: add per-stream token/speed stats. The kernel emits no token or
// progress events (usage passes through untouched); this extension
// overrides agsh.api.stream and wraps the original stream — it estimates
// progress and speed from characters as the stream flows, then emits one
// exact token event at stream end from the API usage.
// Not loading this extension means no stats.
//
// Loading: AGENT_PRELOAD env channel (user .agshrc exports space-separated
// absolute paths; agent.zsh builds --preload):
//   AGENT_PRELOAD='/abs/path/agsh-stdlib/stats.ts'
import { agsh } from "../agent-shell/src/agsh.ts";
import type { StreamEvent, AgshApi } from "../agent-shell/src/types.ts";

const CHARS_PER_TOKEN = 3;
const MIN_PROGRESS_INTERVAL_MS = 100;

function computeSpeed(totalTokens: number, firstTokenTime: number | null): number {
  if (!firstTokenTime) return 0;
  const elapsedMs = Date.now() - firstTokenTime;
  if (elapsedMs <= 0) return 0;
  return Math.round((totalTokens / elapsedMs) * 1000);
}

async function* streamWithStats(
  messages: Parameters<AgshApi["api"]["stream"]>[0],
  apiKey: string,
  baseUrl: string,
  model: string,
  reasoningEffort: string,
  originalStream: AgshApi["api"]["stream"],
): AsyncGenerator<StreamEvent> {
  let firstTokenTime: number | null = null;
  let lastProgressTime: number | null = null;
  let contentChars = 0;
  let reasoningChars = 0;

  for await (const event of originalStream(messages, apiKey, baseUrl, model, reasoningEffort)) {
    if (event.type === "content") {
      if (event.delta) {
        contentChars += event.delta.length;
        if (firstTokenTime === null) firstTokenTime = Date.now();
      } else if (event.reasoningDelta) {
        reasoningChars += event.reasoningDelta.length;
        if (firstTokenTime === null) firstTokenTime = Date.now();
      }
      // Live progress while streaming: estimate tokens + speed, throttled to 100 ms
      const now = Date.now();
      if (firstTokenTime !== null && (lastProgressTime === null || now - lastProgressTime >= MIN_PROGRESS_INTERVAL_MS)) {
        lastProgressTime = now;
        const estimatedContentTokens = Math.round(contentChars / CHARS_PER_TOKEN);
        const estimatedReasoningTokens = Math.round(reasoningChars / CHARS_PER_TOKEN);
        const totalEstimatedTokens = Math.max(1, estimatedContentTokens + estimatedReasoningTokens);
        yield {
          type: "progress",
          tokens: totalEstimatedTokens,
          speed: computeSpeed(totalEstimatedTokens, firstTokenTime),
          elapsedMs: now - firstTokenTime,
          estimatedTokens: totalEstimatedTokens,
          reasoning: estimatedReasoningTokens,
        };
      }
      yield event;
    } else if (event.type === "done" && event.usage) {
      // usage arrived at stream end: emit one exact token event from the API usage, then pass the done event through
      const u = event.usage;
      yield {
        type: "token",
        count: u.total_tokens,
        completionTokens: u.completion_tokens,
        reasoning: u.reasoning_tokens,
        tokens: u.total_tokens,
        speed: computeSpeed(u.total_tokens, firstTokenTime),
      };
      yield event;
    } else {
      yield event;
    }
  }
}

// Property override acts as a virtual-function override: save the original
// stream reference, wrap it, then re-attach it to agsh.api.stream
const originalStream = agsh.api.stream;
agsh.api.stream = (messages, apiKey, baseUrl, model, reasoningEffort) =>
  streamWithStats(messages, apiKey, baseUrl, model, reasoningEffort, originalStream);
