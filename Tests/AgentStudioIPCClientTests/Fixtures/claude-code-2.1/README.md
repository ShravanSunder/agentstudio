# Claude Code 2.1.274 hook documents

`SessionStart.json`, `UserPromptSubmit.json`, `PreToolUse.json`, `Stop.json` and
`SessionEnd.json` are real documents captured from `claude` 2.1.274 on
2026-09-17 by pointing every hook at a logging stub; session identifiers,
paths and prompt text were replaced with fixture values and nothing else was
changed.

`PermissionRequest.json`, `SubagentStart.json`, `SubagentStop.json`,
`PostToolUse.json` and `Notification.json` are schema-derived from the hooks
reference at <https://code.claude.com/docs/en/hooks> (sections "Hook lifecycle"
and the per-event input schemas); the probe session triggered no permission
prompt, no subagent and no notification.
