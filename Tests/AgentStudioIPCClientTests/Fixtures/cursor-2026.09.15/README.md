# Cursor CLI 2026.09.15-d2fe57e hook documents

`sessionStart.json`, `beforeSubmitPrompt.json`, `preToolUse.json`,
`postToolUse.json`, `stop.json`, `afterAgentResponse.json` and `sessionEnd.json`
are shaped from real documents captured from `cursor-agent` on 2026-09-17 by
pointing every hook at a logging stub; conversation, generation and session
identifiers, paths, e-mail and prompt text were replaced with fixture values and
nothing else was changed. The raw captures are in the branch's
`tmp/ipc-v2-proof/w6-*-events.jsonl`.

`subagentStart.json` and `subagentStop.json` are schema-derived from the hooks
reference at <https://cursor.com/docs/agent/hooks>; the probe sessions spawned no
subagent.

Two properties of the real capture are preserved deliberately, because the
projection depends on both:

- `generation_id` equals `conversation_id` on `sessionStart`, `sessionEnd`,
  `preToolUse` and `postToolUse`, and is a distinct per-turn value shared by
  `beforeSubmitPrompt`, `stop` and `afterAgentResponse`. That is what decides
  whether an event reports a turn at all.
- `preToolUse.tool_use_id` contains a literal newline and is per
  assistant-message chunk rather than per call, so it is not on its own a unique
  occurrence key.

There is no permission fixture because Cursor has no permission event. Its
CLI bundle maps Claude Code's `PermissionRequest` to `null`.
