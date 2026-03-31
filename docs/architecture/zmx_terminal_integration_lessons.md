# zmx Terminal Integration

How zmx session multiplexing works with Ghostty in Agent Studio, what bugs we found, how we fixed them, and what remains.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Agent Studio                         │
│                                                          │
│  ┌──────────────┐   ┌──────────────┐                     │
│  │ Ghostty      │   │ Ghostty      │   ... N surfaces    │
│  │ Surface      │   │ Surface      │                     │
│  │ (PTY-A)      │   │ (PTY-A)      │                     │
│  └──────┬───────┘   └──────┬───────┘                     │
└─────────┼──────────────────┼─────────────────────────────┘
          │ stdin/stdout     │
          ▼                  ▼
   ┌──────────────┐   ┌──────────────┐
   │ zmx client   │   │ zmx client   │   One per pane
   └──────┬───────┘   └──────┬───────┘
          │ IPC socket       │
          ▼                  ▼
   ┌──────────────┐   ┌──────────────┐
   │ zmx daemon   │   │ zmx daemon   │   Persists across
   │              │   │              │   app restarts
   │ ┌──────────┐ │   │ ┌──────────┐ │
   │ │ghostty_vt│ │   │ │ghostty_vt│ │   Shadow terminal
   │ │(tracker) │ │   │ │(tracker) │ │   for state capture
   │ └──────────┘ │   │ └──────────┘ │
   │ PTY-B master │   │ PTY-B master │
   └──────┬───────┘   └──────┬───────┘
          ▼                  ▼
   ┌──────────────┐   ┌──────────────┐
   │  Shell (zsh) │   │  Shell (zsh) │   Real shells
   │  + agents    │   │  + agents    │   (persist!)
   └──────────────┘   └──────────────┘
```

Each pane gets its own zmx session (unique ID from repo+worktree+pane keys).
The daemon persists the shell process across app restarts. On re-launch, the
client re-attaches to the existing daemon and receives serialized terminal
state for visual restoration.

## What zmx gives us

1. **Process persistence** — shell survives app restarts. Agent tasks keep running.
2. **State capture** — daemon's ghostty_vt tracks screen content, cursor, modes, scrollback.
3. **Session restore** — `serializeTerminalState()` exports as VT sequences, replayed into new Ghostty surface.
4. **Deterministic identity** — session IDs derived from repo+worktree+pane, so same pane always reconnects to same daemon.

## The two-terminal problem

zmx has two terminals processing the same bytes:

- **Outer terminal** (Ghostty) — what the user sees
- **Inner terminal** (daemon's ghostty_vt) — shadow tracker for state capture

These can diverge in behavior. Every bug we found traces to this divergence.

## Bug 1: Prompt disappearance on resize (FIXED)

**Root cause:** OSC 133;A shell integration sequences pass through zmx raw.
The outer terminal sees them and sets `shell_redraws_prompt = true`. On resize,
the outer terminal clears prompt rows expecting the shell to redraw. But the
shell's redraw goes through zmx's IPC relay with cursor coordinates relative
to the inner PTY, not the outer terminal. Cursor desync → blank prompt.

**Fix:** Rewrite OSC 133;A to include `redraw=0` in the daemon's output path.
This tells the outer terminal "this process cannot redraw prompts — don't
clear them on resize." Uses the standard Kitty protocol extension.

```
Shell output:  \x1b]133;A\x07
                    │
               zmx daemon rewrites
                    │
                    ▼
Forwarded:     \x1b]133;A;redraw=0\x07
                    │
                    ▼
Outer terminal: shell_redraws_prompt = false → no clearing on resize
```

**Applied in two paths:**
- Live broadcast (daemon reads PTY → forwards to clients)
- Session restore (serializeTerminalState → send to re-attaching client)

**Status:** Merged upstream (neurosnap/zmx#112). Also fixes issue #99 (focus toggle prompt loss).

## Bug 2: Daemon state corruption during resize (FIXED)

**Root cause:** The daemon's internal ghostty_vt terminal has `shell_redraws_prompt = true`
(set by the raw OSC 133;A it processes from PTY output). When `handleResize` calls
`term.resize()`, the internal terminal clears prompt rows — corrupting the daemon's
state used for session restore serialization.

**Fix:** Disable `shell_redraws_prompt` on the daemon's terminal before `term.resize()`:

```zig
const saved = term.flags.shell_redraws_prompt;
term.flags.shell_redraws_prompt = .false;
defer term.flags.shell_redraws_prompt = saved;
try term.resize(self.alloc, resize.cols, resize.rows);
```

Applied in both `handleInit` and `handleResize`.

**Status:** Merged upstream (neurosnap/zmx#112).

## Bug 3: Cursor position offset at narrow widths (PARTIALLY ADDRESSED)

**Root cause:** Two sources of divergence:

1. The daemon's `term.resize()` reflows text differently than the outer terminal
   (different font metrics, unicode width calculations). Skipping `term.resize()`
   in `handleResize` improves this — the internal terminal doesn't need live-accurate
   dimensions, only correct dimensions at serialization time.

2. SIGWINCH relay latency — inherent to zmx's architecture. The resize reaches the
   outer terminal instantly but takes 3 extra hops to reach the shell:
   `Ghostty → zmx client → IPC → daemon → ioctl(PTY-B) → shell`.
   During that window, the shell draws for the old width on the new-width terminal.

**Status:** Experiment branch (`experiment/skip-resize-internal-terminal`) shows
improvement. SIGWINCH latency is inherent and unfixable without architecture changes.
Cosmetic — auto-corrects on next prompt.

## Resize flow (SIGWINCH)

```
User resizes window
  │
  ▼
Ghostty resizes PTY-A immediately
  │
  ├─ SIGWINCH → zmx client process
  │               │
  │               ├─ reads new size via ioctl(TIOCGWINSZ)
  │               ├─ sends Resize IPC message to daemon
  │               │
  │               ▼
  │             zmx daemon receives Resize
  │               │
  │               ├─ ioctl(TIOCSWINSZ) on PTY-B → kernel sends SIGWINCH to shell
  │               ├─ term.resize() on internal terminal (optional, see Bug 3)
  │               │
  │               ▼
  │             Shell receives SIGWINCH
  │               │
  │               ├─ reads new size
  │               ├─ redraws prompt
  │               ├─ output flows: PTY-B → daemon → IPC → client → stdout → Ghostty
  │               │
  │               ▼
  │             Ghostty renders the redrawn prompt
```

Direct terminal: steps 1-2 are atomic on the same PTY.
With zmx: 3 extra IPC hops before the shell knows about the resize.

## Session restore flow

```
App launches → creates Ghostty surface with zmx attach command
  │
  ▼
zmx client connects to existing daemon
  │
  ▼
Daemon receives Init message with new client dimensions
  │
  ├─ Serializes internal terminal state (serializeTerminalState)
  │   └─ Rewrites OSC 133;A with redraw=0 in serialized output
  ├─ Sends serialized state as Output message to client
  ├─ Resizes PTY and internal terminal to new client dimensions
  │
  ▼
Client receives serialized state → writes to stdout → Ghostty renders
  │
  ▼
Shell's SIGWINCH redraw arrives → Ghostty renders current prompt
```

## Key Ghostty primitives we use

| API | Purpose |
|-----|---------|
| `ghostty_surface_new(app, config)` | Create surface with zmx attach as command |
| `ghostty_surface_set_size(surface, w, h)` | Set pixel dimensions |
| `ghostty_surface_refresh(surface)` | Schedule render |
| `ghostty_surface_set_occlusion(surface, visible)` | Control render skipping |
| `ghostty_surface_set_focus(surface, focused)` | Focus state |
| `ghostty_surface_binding_action(surface, action, len)` | Execute terminal actions |

Ghostty's embedded runtime handles the PTY, terminal state, and Metal rendering.
We provide the NSView, set dimensions, and manage lifecycle. Ghostty's renderer
auto-renders when PTY output arrives on a visible surface.

## What we don't change in Agent Studio

The zmx fixes are entirely in `vendor/zmx/src/`. Zero changes to Agent Studio's
Ghostty hosting code (GhosttySurfaceView, SurfaceManager, PaneCoordinator).

The hosting code was investigated extensively (19 debugging epochs) and confirmed
correct — the bug reproduced in Ghostty's own app, proving it was a zmx issue.

## Design principles for zmx integration

1. **zmx's internal terminal should be passive** — track bytes for state capture,
   don't let its state affect forwarded output or behavior.

2. **OSC sequences need multiplexer awareness** — sequences designed for
   direct shell-to-terminal communication (like OSC 133 `redraw`) must be
   adapted when a multiplexer sits in the path.

3. **Resize the internal terminal at serialization boundaries, not live** —
   the shadow terminal only needs accurate dimensions when someone reads it.

4. **The relay latency tax is inherent** — accept cosmetic resize artifacts
   as the cost of process persistence. Don't fight it with workarounds.

## File inventory

| File | What |
|------|------|
| `vendor/zmx/src/util.zig` | `rewritePromptRedraw()` — OSC 133;A rewrite |
| `vendor/zmx/src/main.zig` | Daemon broadcast path, handleInit, handleResize |
| `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md` | Full investigation log (21 epochs) |

## Upstream status

| Item | PR/Issue | Status |
|------|----------|--------|
| OSC 133;A redraw=0 rewrite | neurosnap/zmx#112 | Merged |
| Prompt loss on resize | neurosnap/zmx#111 | Fixed by #112 |
| Prompt loss on focus toggle | neurosnap/zmx#99 | Likely fixed by #112 |
| Skip internal term.resize | experiment branch | Validated, not proposed yet |
| Cursor offset at narrow widths | Not filed | Cosmetic, inherent to relay |

## Related documentation

| Document | Relevance |
|----------|-----------|
| [Session Lifecycle](session_lifecycle.md) | zmx IPC protocol, binary format, session name derivation, restore flow |
| [Zmx Restore and Sizing](zmx_restore_and_sizing.md) | Deferred attach sequencing, geometry readiness, SIGWINCH relay path |
| [Remote zmx Architecture Ideas](remote_zmx_architecture_ideas.md) | Future: SSH tunnel architecture, fork strategy, security model |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface lifecycle, C API primitives |
| [ZmxIPCClient Design Spec](../superpowers/specs/2026-03-30-zmx-ipc-client-design.md) | Future: direct IPC replacing CLI shell-outs |
