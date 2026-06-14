# Zmx Restore and Sizing

## Goal

Keep session restore reliable while ensuring restored panes get correct terminal geometry (`cols`/`rows`) without requiring manual input.

## Identity Source of Truth

`PaneId` is the primary identity. zmx session names are deterministic
spawn-time anchors stored on `TerminalState.zmxSessionId`. For UUIDv7 pane IDs,
zmx uses the UUID tail segment for `pane16` to preserve entropy and avoid
same-millisecond prefix collisions. Canonical minting and lookup ownership live in:
[Session Lifecycle — Identity Contract (Canonical)](session_lifecycle.md#identity-contract-canonical).

## Lifecycle Facts (Ghostty + zmx)

1. Ghostty surface creation, geometry, visibility, and focus are separate concerns.
2. `ghostty_surface_set_size` updates terminal geometry even when a surface is not visible.
3. `ghostty_surface_set_occlusion` controls visibility/occlusion separately from geometry. Ghostty's renderer skips draw when not visible (`if (!self.flags.visible) return;` in `renderer/Thread.zig:496`), but queues rendering upstream when occlusion state changes.
4. zmx can attach at placeholder size and reconcile later resize, but this may cause temporary reflow/flicker.
5. For best UX, attach should prefer known-good geometry when available.
6. Ghostty surface starts at 800x600 placeholder size (`embedded.zig:475`). The surface spawns its PTY process immediately on creation (`ghostty_surface_new`).

## The Two-Terminal Problem

zmx has two terminals processing the same byte stream:

- **Outer terminal** (Ghostty surface) — what the user sees, renders at the actual window dimensions
- **Inner terminal** (daemon's `ghostty_vt`) — shadow tracker for state capture and serialization

These can diverge in behavior. Every zmx-specific bug traces to this divergence:

### Prompt Disappearance on Resize (FIXED — zmx PR #112)

**Root cause:** OSC 133;A shell integration sequences pass through zmx raw. The outer terminal sees them and sets `shell_redraws_prompt = true`. On resize, the outer terminal clears prompt rows expecting the shell to redraw. But the shell's redraw goes through zmx's IPC relay with cursor coordinates relative to the inner PTY, not the outer terminal.

**Fix:** `rewritePromptRedraw()` in `vendor/zmx/src/util.zig` rewrites OSC 133;A to include `redraw=0` before the terminator (BEL `\x07` or ST `\x1b\\`). Applied in two paths:
- Live broadcast: daemon reads PTY → rewrites → forwards to clients
- Session restore: `serializeTerminalState` → rewrites → sends to re-attaching client

### Daemon State Corruption During Resize (FIXED — zmx PR #112)

**Root cause:** The daemon's internal `ghostty_vt` has `shell_redraws_prompt = true` (set by the raw OSC 133;A it processes from PTY output). When `handleResize` calls `term.resize()`, the internal terminal clears prompt rows — corrupting the daemon's state used for session restore serialization.

**Fix:** Disable `shell_redraws_prompt` on the daemon's terminal before resize:

```zig
const saved = term.flags.shell_redraws_prompt;
term.flags.shell_redraws_prompt = .false;
defer term.flags.shell_redraws_prompt = saved;
try term.resize(self.alloc, resize.cols, resize.rows);
```

Applied in both `handleInit` and `handleResize` in `vendor/zmx/src/main.zig`.

### Cursor Position Offset at Narrow Widths (PARTIALLY ADDRESSED)

Two sources of divergence:

1. **Reflow mismatch:** The daemon's `term.resize()` reflows text differently than the outer terminal (different font metrics, unicode width calculations). Skipping `term.resize()` in `handleResize` improves this — the internal terminal doesn't need live-accurate dimensions, only correct dimensions at serialization time.

2. **SIGWINCH relay latency:** Inherent to zmx's architecture. The resize reaches the outer terminal instantly but takes 3 extra hops to reach the shell: `Ghostty → zmx client → IPC → daemon → ioctl(PTY-B) → shell`. During that window, the shell draws for the old width on the new-width terminal.

**Status:** Experiment branch (`experiment/skip-resize-internal-terminal`) shows improvement for reflow mismatch. SIGWINCH latency is inherent and unfixable without architecture changes. Cosmetic — auto-corrects on next prompt.

## SIGWINCH Relay Path

```
User resizes window
  │
  ├─ Ghostty resizes PTY-A immediately (outer terminal reflows)
  │
  ├─ SIGWINCH → zmx client process
  │               ├─ reads new size via ioctl(TIOCGWINSZ)
  │               └─ sends Resize IPC message to daemon
  │                    │
  │                    ▼
  │                  zmx daemon receives Resize
  │                    ├─ ioctl(TIOCSWINSZ) on PTY-B → kernel SIGWINCH → shell
  │                    └─ term.resize() on internal terminal (optional)
  │                         │
  │                         ▼
  │                       Shell receives SIGWINCH, redraws prompt
  │                       Output: PTY-B → daemon → IPC → client → Ghostty
  │
  Direct terminal: resize + shell notification are atomic on the same PTY.
  With zmx: 3 extra IPC hops before the shell knows about the resize.
```

See [zmx Terminal Integration](zmx_terminal_integration_lessons.md) for the full investigation (21 debugging epochs) and design principles.

## Runtime Flow

1. Pane startup launches an interactive shell first (`zsh -i -l`).
2. Zmx attach command is stored as `deferredStartupCommand`.
3. Ghostty surface waits for readiness:
   - surface is in a window,
   - content size is non-zero,
   - process is still alive,
   - deferred attach was not already sent.
4. Once ready, AgentStudio injects zmx attach text and sends a real Return key event.

This prevents early attach against placeholder geometry during startup.

## Two Attach Paths (Current + Target)

1. Active/visible panes:
   - Keep strict readiness (window + non-zero content size + process alive).
   - Attach after first stable size signal.
2. Background panes:
   - Preferred target: attach with persisted geometry (no visibility requirement), then reconcile on reveal.
   - Fallback: shell warm in background, deferred attach when visibility gate opens.

This split maps directly to anti-flicker goals for LUNA-295 while preserving startup safety for visible panes.

## Why Not Immediate Attach

Immediate attach during startup was tested and produced unstable behavior:

1. restored panes could keep wrong width/column state,
2. startup flicker increased,
3. attach timing was sensitive to view/window ordering.

Deferred attach after readiness is the stable default.

## Startup zmx Session Reconciliation (LUNA-324)

On app launch, restore flow reconciles persisted state against live zmx daemons
before surface creation only when a persistent zmx pane needs anchor repair. This
startup path is an anchor-hydration and classification pass, not a reaper.

1. Skip live inventory entirely when every persistent zmx pane already has a
   valid stored anchor for its pane identity.
2. Otherwise run one `zmx list` snapshot (with `ZMX_DIR`) and build the live
   session set.
3. Return valid stored `TerminalState.zmxSessionId` values as source of truth.
4. For legacy rows missing a stored anchor, or rows with an invalid/foreign
   stored anchor, adopt a unique same-kind live zmx session that matches the
   pane segment; otherwise fall back to deterministic legacy derivation without
   destroying anything.
5. Persist any hydrated anchors before restore/attach logic depends on them.
6. Log runtime-only sessions as future janitor candidates, but never kill them
   during boot.
7. Start periodic health monitoring after restore.

`sessionId` in this document means the zmx daemon session name, not the primary
pane identity.

## Debug and Beta Proof Launchers

Startup reconciliation proof must use bundled app identities, not raw SwiftPM
executables. The debug observability launcher creates
`Agent Studio Debug <code>.app` with `AGENTSTUDIO_DATA_DIR` set to
`~/.agentstudio-db/<code>`, where `<code>` is a deterministic four-character
base36 worktree hash. Beta proof uses `Agent Studio Beta` and `~/.agent-studio-b`.
Both launchers use a scrubbed environment so inherited `ZMX_DIR`, `ZMX_SESSION`,
Ghostty resource variables, or production app identity cannot select the wrong
socket directory. Launchers use LaunchServices `open` for app-bundle semantics;
debug and beta diverge after a LaunchServices refusal. Debug may fall back to
direct `Contents/MacOS/AgentStudio` execution and records
`AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable`; that is accepted
for Victoria/OTLP debug proof because it keeps the isolated data/zmx root, but
it is not full GUI proof. Beta does not use this fallback: if LaunchServices
refuses the beta bundle, the state file is marked `launch_failed` and promotion
proof is not started. Proof comes from the per-run state marker, VictoriaLogs
query, PID/window inspection where LaunchServices succeeds, and SQLite integrity
checks.

See [Session Lifecycle — Debug App Identity Budget](session_lifecycle.md#debug-app-identity-budget).

## Future Background Janitor Policy

Destructive cleanup is not part of startup. A future background janitor may
delete runtime-only sessions only after it has stronger ownership proof than
`as-*` prefix membership and shared `ZMX_DIR` membership.

Minimum policy for that future job:

1. Never run at boot.
2. Prove instance/workspace ownership before deleting.
3. Use a grace TTL and re-check liveness before kill.
4. Never destroy a live session whose kind-aware pane segment matches a
   persisted pane.
5. Log discovery time, ownership proof, kill attempt time, and outcome.

## Test Coverage

### Unit

1. `DeferredStartupReadinessTests`
   - validates readiness policy for scheduling and execution.
   - protects sizing gate semantics (window + non-zero dimensions required).

2. `ZmxBackendTests`
   - validates zmx session name format, kind-aware pane matching, attach command shape, env handling, and kill/discover logic.

### Integration

1. `ZmxBackendIntegrationTests`
   - validates behavior against a real zmx binary with isolated `ZMX_DIR`.

### End-to-End

1. `ZmxE2ETests`
   - validates real-zmx anchor hydration/adoption, boot-time non-destruction, shared-`ZMX_DIR` preservation, and scrollback preservation for roamed legacy panes.
   - validates explicit backend lifecycle operations, including create, health
     check, orphan discovery, and explicit kill APIs outside the boot path.
   - validates restore semantics without using boot as a reaper: backend
     recreation can rediscover existing live sessions and attach/restore logic
     keeps stored anchors stable.

## What Is Not Fully Automated Yet

GUI-level verification of rendered prompt wrapping/visual flicker across pane resize still requires manual validation, because current test targets do not drive AppKit layout + Ghostty rendering end-to-end.

The automated suites cover the attach/sizing gate policy and zmx daemon lifecycle to reduce regression risk in restore behavior.

## Ticket Mapping

- `LUNA-295`: `Two Attach Paths (Current + Target)` → see also [Contract 5a: Attach Readiness Policy](pane_runtime_architecture.md#contract-5a-attach-readiness-policy-luna-295)
- `LUNA-324`: `Startup zmx Session Reconciliation (LUNA-324)` and future background janitor policy → see also [Contract 5b: Restart Reconcile Policy](pane_runtime_architecture.md#contract-5b-restart-reconcile-policy-luna-324)
- `LUNA-342`: `Lifecycle Facts (Ghostty + zmx)` and contract wording in this document
- `LUNA-354`: ZmxIPCClient — direct IPC replacing CLI shell-outs (spec: `docs/superpowers/specs/2026-03-30-zmx-ipc-client-design.md`)

## Related Documentation

- **[zmx Terminal Integration](zmx_terminal_integration_lessons.md)** — Two-terminal problem investigation, OSC 133 fix, design principles
- **[Session Lifecycle](session_lifecycle.md)** — zmx IPC protocol, binary format, session restore flow
- **[Remote zmx Architecture Ideas](remote_zmx_architecture_ideas.md)** — SSH tunnel architecture, fork strategy
- **[Surface Architecture](ghostty_surface_architecture.md)** — Ghostty C API, surface lifecycle, occlusion
