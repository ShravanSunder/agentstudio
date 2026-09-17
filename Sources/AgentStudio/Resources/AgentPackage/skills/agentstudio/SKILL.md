---
name: agentstudio
description: Report your status to the Agent Studio pane you are running in. Use when you need the user's attention, when you finish the work they asked for, or when you have one short thing to tell them while they are looking elsewhere.
---

# Reporting to Agent Studio

You are running inside an Agent Studio terminal pane. Agent Studio shows the
user one status per pane, so they can leave you working and look away.

## Before you call anything

Run the command only if `AGENTSTUDIO_CLI` is set in your environment. If it is
missing or empty you are not in an Agent Studio pane: say nothing and carry on.

Each call prints one short line and exits. Nothing else is expected from you.

## The four calls

```sh
"$AGENTSTUDIO_CLI" needs-you "waiting on your approval"
"$AGENTSTUDIO_CLI" needs-you --clear
"$AGENTSTUDIO_CLI" done
"$AGENTSTUDIO_CLI" message "the migration finished"
```

- `needs-you` — you are blocked on the user. The reason is one short phrase.
- `needs-you --clear` — you are unblocked and working again.
- `done` — you finished what the user asked for.
- `message` — one thing worth reading later. Not progress narration.

## What to expect back

One line, such as `needs-you recorded` or `done recorded`. That is the whole
reply. Do not parse it, retry it, or report it to the user.

If a call answers `bindingRequired`, Agent Studio is not tracking this session
because its Claude Code hooks are not installed. Tell the user once:

> Agent Studio is not tracking this session. Run
> `"$AGENTSTUDIO_CLI" package install claude` and restart Claude Code.

Then carry on without calling the status verbs again this session. A free-text
`session.message` still works and is still worth sending.

## Rules

- You are the main agent. If you are a subagent, never call `done` or
  `needs-you`: the main agent owns the pane's status.
- Report the user-visible truth, not every internal step. One `done` per piece
  of work the user asked for.
- These calls are for the user's attention only. They never change what you do
  next, and no answer comes back through them.
