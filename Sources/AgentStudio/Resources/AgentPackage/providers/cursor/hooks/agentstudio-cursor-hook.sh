#!/bin/sh
# Projects one Cursor hook event onto Agent Studio's session.event method.
#
# Arguments: $1 the Cursor hook event name, $2 the Cursor release the hooks were
# installed against. The hook document arrives on stdin and is forwarded
# untouched.
#
# Outside an Agent Studio pane there is no CLI and no pane credential, so the
# hook exits 0 in silence: Cursor must never fail a turn because Agent Studio is
# not listening. Stdout stays empty because Cursor reads a hook's stdout as a
# decision document, and on a permission-gating event a stray body would answer
# for the user.
[ -x "${AGENTSTUDIO_CLI:-}" ] || exit 0
exec "$AGENTSTUDIO_CLI" hook cursor "$1" --provider-version "$2"
