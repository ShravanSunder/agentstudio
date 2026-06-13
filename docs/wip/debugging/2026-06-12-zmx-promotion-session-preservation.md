# zmx Promotion Session Preservation Runbook

Date: 2026-06-12

Purpose: prove a debug or beta promotion candidate does not destroy, corrupt,
or strand existing zmx sessions or SQLite workspace state.

This runbook is intentionally conservative. Stable production state is
inventory-only unless the user explicitly approves launching a candidate against
`~/.agentstudio`.

## Stop Conditions

Stop promotion immediately if any of these occur:

1. A pre-existing debug, beta, or stable zmx session disappears outside an
   explicitly isolated test harness.
2. `core.sqlite` or any `*.local.sqlite` reports anything other than `ok`.
3. VictoriaLogs has no records for the current run marker after the app boots.
4. The app logs any boot-time `zmx kill`, "Killed orphan zmx session", or
   startup reconciliation failure.
5. A debug launch uses a shared root such as `~/.agentstudio-db/z` instead of
   the per-worktree root reported in `tmp/debug-observability/latest-observability.env`.

## Launch Isolation Model

Debug promotion proof uses the launcher-created bundle:

```bash
mise run run-debug-observability -- --detach
```

The launcher computes a deterministic four-character base36 worktree code,
builds `Agent Studio Debug <code>.app` under `~/.agentstudio-db/<code>/apps`,
launches with targeted environment scrubbing, and sets:

```bash
AGENTSTUDIO_DATA_DIR="$HOME/.agentstudio-db/<code>"
ZMX_DIR_EFFECTIVE="$HOME/.agentstudio-db/<code>/z"
```

The code is intentionally short so bundle ids, app names, zmx names, and Unix
socket paths do not drift toward platform length limits. Keeping the generated
debug app, traces, logs, and zmx root under `~/.agentstudio-db/<code>` also
avoids prompting for `~/Documents` access merely because a worktree checkout
lives under Documents. Do not copy production or beta state into this root for
promotion proof; if a fixture is needed, create it explicitly inside the
reported debug root.

If the launcher reports `Agent Studio Debug <code> is already running`, stop
there. That is a safety guard, not a failure to bypass: one worktree code maps
to one debug app identity and one debug zmx/data root. Quit the reported PID
before starting a fresh promotion-proof run. The refusal state file uses
`AGENTSTUDIO_OBSERVABILITY_STATUS=already_running`; do not treat that as a
valid Victoria proof marker.

Local PR-branch proof uses the isolated debug runner. Beta proof keeps the
normal beta root (`~/.agent-studio-b`) and is run against the accepted/notarized
beta artifact produced by the GitHub release workflow; it also launches with the
same targeted environment scrubbing. Always pass the exact downloaded artifact
path with `--app`; do not let the helper select a local diagnostic bundle or an
older installed beta by default:

```bash
mise run run-beta-observability -- --app "$DOWNLOADED_WORKFLOW_BETA_APP" --detach
```

Both observability launchers run under `/bin/bash` and try LaunchServices
`open` first from a minimal clean environment plus explicit `open --env`
trace/data variables. If LaunchServices rejects a generated debug bundle, the
debug helper may fall back to direct `Contents/MacOS/AgentStudio` execution and
records `AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable`. That is
accepted for debug Victoria/OTLP proof because it keeps the isolated debug data
and zmx roots, but it is not full GUI proof.

Beta promotion proof is stricter. If LaunchServices fails for beta, the helper
writes `AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed` and exits non-zero.
Beta promotion proof must use an accepted/notarized beta bundle. The normal path
is the GitHub release workflow output from a beta tag. Local Developer ID
signing remains opt-in through `SIGNING_IDENTITY` for diagnostic bundles, but a
Developer ID signed bundle without notarization can still be rejected by
Gatekeeper and is not promotion proof. Local beta bundle artifacts, launcher
logs, and traces default to `~/.agentstudio-db/beta-observability/`; the
repo-local `tmp/beta-observability/latest-observability.env` file remains the
verifier handoff point.

## Inventory Helpers

```bash
mkdir -p tmp/debug-observability/session-preservation

ZMX_BIN="${ZMX_BIN:-vendor/zmx/zig-out/bin/zmx}"
BETA_ROOT="${BETA_ROOT:-$HOME/.agent-studio-b}"
STABLE_ROOT="${STABLE_ROOT:-$HOME/.agentstudio}"

load_debug_state() {
  local state="${1:-tmp/debug-observability/latest-observability.env}"
  [ -f "$state" ] || {
    echo "missing debug state file: $state" >&2
    return 1
  }
  # shellcheck disable=SC1090
  . "$state"
  DEBUG_ROOT="${AGENTSTUDIO_OBSERVABILITY_DATA_DIR:?missing debug data dir in $state}"
}

snapshot_zmx_dir() {
  local label="$1"
  local root="$2"
  local out="tmp/debug-observability/session-preservation/${label}.zmx.txt"
  if [ -x "$ZMX_BIN" ] && [ -d "$root/z" ]; then
    env ZMX_DIR="$root/z" "$ZMX_BIN" list 2>&1 | sort > "$out"
  else
    printf 'no zmx inventory: bin=%s root=%s\n' "$ZMX_BIN" "$root" > "$out"
  fi
  echo "$out"
}

sqlite_integrity() {
  local label="$1"
  local root="$2"
  local out="tmp/debug-observability/session-preservation/${label}.sqlite-integrity.txt"
  : > "$out"
  if [ -f "$root/core.sqlite" ]; then
    printf '%s: ' "$root/core.sqlite" >> "$out"
    sqlite3 "$root/core.sqlite" 'PRAGMA integrity_check;' >> "$out"
  else
    printf 'missing: %s\n' "$root/core.sqlite" >> "$out"
  fi
  local found_local=0
  for db in "$root"/workspaces/*.local.sqlite; do
    [ -e "$db" ] || continue
    found_local=1
    printf '%s: ' "$db" >> "$out"
    sqlite3 "$db" 'PRAGMA integrity_check;' >> "$out"
  done
  if [ "$found_local" -eq 0 ]; then
    printf 'no local sqlite files: %s\n' "$root/workspaces" >> "$out"
  fi
  echo "$out"
}
```

## Debug Candidate Proof

```bash
mise run observability:up
mise run observability:smoke

if [ -f tmp/debug-observability/latest-observability.env ]; then
  load_debug_state
  snapshot_zmx_dir debug-before "$DEBUG_ROOT"
  sqlite_integrity debug-before "$DEBUG_ROOT"
fi

scripts/run-debug-observability.sh --print-identity > tmp/debug-observability/prelaunch-identity.env
. tmp/debug-observability/prelaunch-identity.env
debug_before_zmx="$(snapshot_zmx_dir debug-before "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR")"

if grep -q '^no sessions found' "$debug_before_zmx" || grep -q '^no zmx inventory:' "$debug_before_zmx"; then
  echo "debug-before zmx inventory is empty; preseed a zmx session before using this as preservation proof" >&2
  exit 1
fi

mise run run-debug-observability -- --detach
load_debug_state
mise run verify-debug-observability

snapshot_zmx_dir debug-after-launch "$DEBUG_ROOT"
sqlite_integrity debug-after-launch "$DEBUG_ROOT"

sleep 5
snapshot_zmx_dir debug-after-settle "$DEBUG_ROOT"
sqlite_integrity debug-after-settle "$DEBUG_ROOT"
```

Expected:

- the debug state file reports `AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE`,
  `AGENTSTUDIO_OBSERVABILITY_APP`, `AGENTSTUDIO_OBSERVABILITY_DATA_DIR`, and
  `AGENTSTUDIO_OBSERVABILITY_ZMX_DIR`;
- the debug app path contains `AgentStudio Debug <code>.app`;
- the debug data root is `~/.agentstudio-db/<code>`;
- `AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD` is either `launchservices` or
  `direct_executable`; only `launchservices` is full GUI proof;
- any zmx sessions created during the run stay within that debug root;
- every present SQLite database reports `ok`;
- absent databases are recorded as `missing:` or `no local sqlite files:`;
- app log has startup reconciliation lines and no boot-time `zmx kill`.

## Beta Candidate Proof

```bash
# After the beta tag workflow publishes a signed/notarized artifact, set this to
# the exact downloaded workflow artifact. Do not use an old installed beta
# against a DB already migrated by this branch.
DOWNLOADED_WORKFLOW_BETA_APP="${DOWNLOADED_WORKFLOW_BETA_APP:?set downloaded workflow beta app path}"

snapshot_zmx_dir beta-before "$BETA_ROOT"
sqlite_integrity beta-before "$BETA_ROOT"

mise run run-beta-observability -- --app "$DOWNLOADED_WORKFLOW_BETA_APP" --detach
AGENTSTUDIO_EXPECTED_BETA_APP="$DOWNLOADED_WORKFLOW_BETA_APP" mise run verify-beta-observability

sleep 5
snapshot_zmx_dir beta-after "$BETA_ROOT"
sqlite_integrity beta-after "$BETA_ROOT"
```

Expected:

- every `beta-before` zmx session is present in `beta-after`;
- `verify-beta-observability` reports the current marker in VictoriaLogs;
- `tmp/beta-observability/latest-observability.env` records
  `AGENTSTUDIO_OBSERVABILITY_APP=$DOWNLOADED_WORKFLOW_BETA_APP`;
- every present SQLite database reports `ok`;
- absent databases are recorded as `missing:` or `no local sqlite files:`;
- beta app log has startup reconciliation lines and no boot-time `zmx kill`.

## Stable Production Guard

Do not launch this branch against stable data unless explicitly approved.

Inventory-only stable proof:

```bash
snapshot_zmx_dir stable-inventory "$STABLE_ROOT"
sqlite_integrity stable-inventory "$STABLE_ROOT"
```

## Evidence Bundle

Keep these artifacts together when reporting promotion proof:

1. `tmp/debug-observability/session-preservation/*.zmx.txt`
2. `tmp/debug-observability/session-preservation/*.sqlite-integrity.txt`
3. `tmp/debug-observability/latest-observability.env`
4. `tmp/beta-observability/latest-observability.env`
5. debug and beta launcher logs named in those state files
6. VictoriaLogs verification output
