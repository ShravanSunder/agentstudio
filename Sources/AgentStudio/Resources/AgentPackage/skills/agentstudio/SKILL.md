---
name: agentstudio
description: Tell the person running Agent Studio what is happening in this pane — send a message, say you need them, or say you are done.
---

# Agent Studio

You are running inside an Agent Studio pane. Agent Studio shows the person one
row per pane: whether you are working, whether you are waiting on them, and
whatever you last told them. These calls are how that row gets filled in.

## Before you call anything

```sh
[ -x "${AGENTSTUDIO_CLI:-}" ] || echo "not running in an Agent Studio pane"
```

If `AGENTSTUDIO_CLI` is unset or not executable, you are not in a pane. Do not
call anything and do not mention it again.

## The four calls

```sh
"$AGENTSTUDIO_CLI" message "the migration finished on staging"
"$AGENTSTUDIO_CLI" needs-you "waiting on the production credential"
"$AGENTSTUDIO_CLI" needs-you --clear
"$AGENTSTUDIO_CLI" done
```

- `message <text>` — one short line the person will read in the sidebar. Use it
  when something happened that they would want to know without opening the pane.
- `needs-you [why]` — you are blocked on them. Say what you need in a few words.
- `needs-you --clear` — you are unblocked and working again.
- `done` — the work you were asked to do is finished.

Each call prints one short line and exits. That line is the whole reply; there
is nothing to parse and nothing to follow up on. Say nothing about the call in
your own output.

## When to use them

Call `needs-you` the moment you are actually waiting on the person, not before.
Call `done` once, when the task is finished — not at the end of every step. Use
`message` sparingly; a row that updates constantly tells the person nothing.

## If a call is refused

If a call replies `bindingRequired`, the Agent Studio hooks are not installed
for this provider. Tell the person once, in one line, and carry on with the
work — the hooks are theirs to install, not yours.

## If you are a subagent

Do not call `done` and do not call `needs-you`. Those speak for the whole pane
and only the main agent owns that. `message` is fine if you have something the
person genuinely needs to see.
