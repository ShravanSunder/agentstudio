# Ghostling Analysis: What It Means for Agent Studio

**Date:** 2026-03-21
**Source:** [ghostty-org/ghostling](https://github.com/ghostty-org/ghostling) — ~600 lines of C, minimal terminal on `libghostty-vt`

---

## What Ghostling Actually Is

Ghostling is NOT another Ghostty. It's a proof that `libghostty` has a **second, standalone API** (`ghostty/vt.h`) that provides terminal emulation without Metal, without AppKit, without PTY management — just the VT state machine, input encoders, and a render state you can iterate cell-by-cell.

Mitchell built it in 2 hours on Raylib (a C game framework). No AppKit, no Metal, no surfaces. Just:

```
forkpty() → shell
    │
read(pty_fd) → ghostty_terminal_vt_write(terminal, bytes)
    │
ghostty_render_state_update(render_state, terminal)
    │
iterate rows → iterate cells → DrawTextEx() per glyph
```

And input goes the other direction:

```
Raylib key event → ghostty_key_encoder_encode() → raw VT bytes → write(pty_fd)
Raylib mouse event → ghostty_mouse_encoder_encode() → raw VT bytes → write(pty_fd)
```

The terminal object has zero knowledge of the PTY. The encoders have zero knowledge of the renderer. Everything is composable.

---

## Ghostling's Architecture In Detail

### Initialization Sequence

```c
// 1. Create terminal (just a VT state machine + grid)
GhosttyTerminalOptions opts = { .cols = 80, .rows = 24, .max_scrollback = 1000 };
ghostty_terminal_new(NULL, &terminal, opts);

// 2. Create encoders (reused every frame, never recreated)
ghostty_key_encoder_new(NULL, &key_encoder);
ghostty_key_event_new(NULL, &key_event);
ghostty_mouse_encoder_new(NULL, &mouse_encoder);
ghostty_mouse_event_new(NULL, &mouse_event);

// 3. Create render state + iterators (reused every frame)
ghostty_render_state_new(NULL, &render_state);
ghostty_render_state_row_iterator_new(NULL, &row_iter);
ghostty_render_state_row_cells_new(NULL, &row_cells);

// 4. Spawn shell via forkpty() — completely separate from ghostty
int pty_fd = pty_spawn(&child, cols, rows);
```

### Per-Frame Loop (order matters)

```c
while (!WindowShouldClose()) {
    // 1. Handle resize — BOTH terminal grid AND pty winsize
    if (IsWindowResized()) {
        ghostty_terminal_resize(terminal, new_cols, new_rows);  // reflows text
        ioctl(pty_fd, TIOCSWINSZ, &new_ws);                    // tells shell
    }

    // 2. Focus tracking — explicit encode to VT bytes
    if (focused != prev_focused) {
        ghostty_focus_encode(focused ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST,
                             buf, sizeof(buf), &written);
        write(pty_fd, buf, written);  // CSI I or CSI O
    }

    // 3. Drain PTY output → feed to terminal
    while (read(pty_fd, buf, sizeof(buf)) > 0)
        ghostty_terminal_vt_write(terminal, buf, n);

    // 4. Encode keyboard input → write to PTY
    ghostty_key_encoder_setopt_from_terminal(encoder, terminal);  // sync modes!
    // ... build key event, encode, write(pty_fd, buf, written)

    // 5. Encode mouse input → write to PTY
    ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal);  // sync modes!
    // ... build mouse event, encode, write(pty_fd, buf, written)

    // 6. Snapshot terminal → render state (thread-safe copy)
    ghostty_render_state_update(render_state, terminal);

    // 7. Iterate and draw
    // row_iter → cells → graphemes + style → draw
}
```

### Key Design Decisions in Ghostling

**Encoder auto-sync:** Every frame, both key and mouse encoders call `setopt_from_terminal()`. This means if a terminal app enables Kitty keyboard protocol or SGR mouse reporting mid-session, the encoders immediately respect it. No manual mode tracking needed.

**Mouse scroll branching:** Ghostling checks terminal modes to decide scroll behavior:
```c
// If app has mouse tracking enabled → forward scroll as button 4/5 press/release
// If no tracking → scroll the viewport via ghostty_terminal_scroll_viewport()
const GhosttyMode tracking_modes[] = {
    GHOSTTY_MODE_X10_MOUSE, GHOSTTY_MODE_NORMAL_MOUSE,
    GHOSTTY_MODE_BUTTON_MOUSE, GHOSTTY_MODE_ANY_MOUSE,
};
for (i = 0; i < 4; i++) {
    if (ghostty_terminal_mode_get(terminal, tracking_modes[i], &val) == GHOSTTY_SUCCESS && val)
        mouse_tracking = true;
}
```

**Render state is a snapshot boundary:** After `ghostty_render_state_update()`, the terminal can keep mutating. The render state is frozen. Rendering reads from the snapshot, not from the live terminal. This is the thread-safety model.

**Object reuse:** Encoders, events, iterators, cells — all created once at startup, reused every frame. No per-event allocation.

**Explicit cleanup order:** Free mouse event/encoder → key event/encoder → row cells → row iterator → render state → terminal. Reverse of creation.

---

## What Agent Studio Does vs What Ghostling Reveals

### The zmx attach pattern — the biggest smell

**Current Agent Studio flow (`PaneCoordinator+ViewLifecycle.swift:97-105`):**

```
1. Create Ghostty surface with default shell (zsh -i -l)
2. Ghostty spawns PTY with shell at placeholder 800×600
3. Wait for window attachment + Auto Layout
4. Wait additional 180ms hardcoded delay
5. sendText(" zmx attach <session-id> <shell> -i -l")   ← types into shell
6. sendProgrammaticReturnKey()                           ← presses Enter
```

**Problems with this:**
- **180ms hardcoded delay** (`deferredStartupDelaySeconds = 0.18`) — arbitrary, can fire before or after the real resize depending on system load
- **Text injection hack** — literally typing a command into the shell via `ghostty_surface_text()`. If shell has custom prompts, hooks, or slow startup, the text can arrive at the wrong time
- **Shell history pollution** — mitigated by leading space, but still fragile
- **Double process chain** — shell → zmx → inner shell. The outer shell is vestigial after zmx attaches
- **Shell escape complexity** — `ZmxBackend.shellEscape()` has to handle `\`, `"`, `$`, `` ` ``, `!` because the command goes through shell interpretation

**What Ghostling shows is possible:**
Ghostling manages its PTY directly — `forkpty()` with the command you want. No intermediate shell. The `surfaceCommand` path in Agent Studio already does this via `surfaceConfig.command`, which tells Ghostty to exec that command instead of the default shell.

**Why Agent Studio doesn't use `surfaceCommand` for zmx:**
The docs (`zmx_restore_and_sizing.md:46-53`) explain: immediate attach at placeholder 800×600 produced wrong column state, startup flicker, and timing sensitivity. Deferred attach waits for real geometry.

**But this reasoning has a gap:** Ghostty's surface handles resize internally. When the real frame arrives via `setFrameSize → sizeDidChange → ghostty_surface_set_size()`, the PTY gets SIGWINCH. zmx should handle SIGWINCH and reflow. The flicker from brief wrong-size-then-resize is the same flicker you'd get from any terminal window that starts before its final size is known — which is every terminal ever.

**The trade-off is:** deferred attach adds 180ms latency + text injection fragility to avoid a sub-frame reflow that zmx should handle. Worth testing `surfaceCommand` again now that the startup sequence is more stable.

### Terminal content reading — the missing capability

Agent Studio uses these `ghostty_surface_*` functions:
- `ghostty_surface_new/free` — lifecycle
- `ghostty_surface_key` — keyboard input
- `ghostty_surface_mouse_button/pos/scroll` — mouse input
- `ghostty_surface_set_size/focus/occlusion/content_scale` — state
- `ghostty_surface_text` — text injection
- `ghostty_surface_binding_action` — action dispatch (copy, paste, clear)
- `ghostty_surface_process_exited/needs_confirm_quit` — queries
- `ghostty_surface_userdata` — resolve surface → view
- `ghostty_surface_request_close` — close

**What's completely missing:** Any way to **read what's on the terminal screen**.

Ghostling's render state API provides exactly this:
```c
ghostty_render_state_update(render_state, terminal);
// iterate rows → cells → get grapheme codepoints + style (fg, bg, bold, italic, inverse)
// get cursor position + visibility
// get scrollbar state (total, visible, offset)
```

This matters for Agent Studio because:
- **AI context** — Claude Code or any agent running in a pane could benefit from knowing what's visible on screen
- **Search** — find text across terminal panes
- **Session thumbnails** — preview content for tab/pane switcher
- **Smart copy** — select and copy terminal content programmatically

**The blocker:** These APIs live in `ghostty/vt.h` and operate on `GhosttyTerminal`, not `ghostty_surface_t`. The full surface API doesn't expose render state iteration. This would require either:
1. Ghostty adding a `ghostty_surface_render_state()` bridge function to the full API
2. Agent Studio linking `libghostty-vt` alongside the full library and somehow getting access to the terminal inside the surface
3. Using Ghostty's inspector API if it exposes content (unclear without headers)

**Action:** This is a feature request for upstream Ghostty — expose render state access through the surface API. Mitchell clearly has the VT-level APIs ready; they just aren't wired through `ghostty_surface_t`.

### Focus handling — subtle gap

**Ghostling:** Explicitly encodes focus as VT bytes and writes them to the PTY:
```c
ghostty_focus_encode(GHOSTTY_FOCUS_GAINED, buf, sizeof(buf), &written);
write(pty_fd, buf, written);
```

**Agent Studio:** Calls `ghostty_surface_set_focus(surface, true/false)` which presumably does the same thing internally. But there's a subtlety.

**Agent Studio also calls `ghostty_app_set_focus(app, true/false)`** when the application itself activates/deactivates (`Ghostty.swift:110-142`). This is separate from per-surface focus. The per-surface focus sync (`SurfaceManager.syncFocus()`) correctly sets only one surface to focused and all others to unfocused.

**Potential issue:** When a surface is detached (hidden), it gets `setOcclusion(false)` but **not** `setFocus(false)`. The `setFocus` method (`SurfaceManager.swift:801-811`) only operates on `activeSurfaces`, not `hiddenSurfaces`. If a surface was focused when it got hidden, it might never receive a focus-lost event. Whether this matters depends on Ghostty's internal behavior — does setting occlusion also clear focus?

### Resize handling — Agent Studio is correct but fragile

**Ghostling's resize:** Two separate calls:
```c
ghostty_terminal_resize(terminal, new_cols, new_rows);  // reflows text internally
ioctl(pty_fd, TIOCSWINSZ, &new_ws);                    // tells PTY/child process
```

**Agent Studio's resize:** Single call:
```swift
ghostty_surface_set_size(surface, UInt32(backingSize.width), UInt32(backingSize.height))
```

The full API combines both operations internally. Agent Studio passes **pixel dimensions** (backing coordinates), and Ghostty calculates cols/rows from its font metrics. This is correct.

**But:** The placeholder 800×600 at surface creation (`GhosttySurfaceView.swift:131`) means the initial `ghostty_surface_set_size()` in `sizeDidChange()` at line 229 sends a placeholder-derived grid to the PTY before the view has its real dimensions. The async re-send at `viewDidMoveToWindow()` fixes this, but there's a window where the PTY has wrong dimensions.

### Input handling — Agent Studio matches Ghostty patterns well

Agent Studio's keyboard handling in `GhosttySurfaceView` correctly:
- Routes through `interpretKeyEvents` for IME/dead key support
- Strips control characters < 0x20 (lets Ghostty encode them)
- Filters PUA function keys (0xF700-0xF8FF)
- Computes unshifted codepoints via `characters(byApplyingModifiers: [])`
- Tracks consumed mods (subtracting control and command)
- Handles Ctrl+/ → Ctrl+_ conversion

This maps cleanly to what Ghostling does — the patterns are equivalent, just expressed through NSView vs Raylib.

---

## Concrete Recommendations

### 1. Test `surfaceCommand` for zmx attach (eliminate deferred hack)

The 180ms `sendText` injection should be validated against the simpler `surfaceConfig.command` path. If zmx handles SIGWINCH correctly (and it should — it's a terminal multiplexer), the brief reflow from placeholder→real size is acceptable and eliminates:
- The hardcoded delay
- The shell escape complexity
- The text injection fragility
- The double shell process
- The shell history pollution

**Test approach:** Change `PaneCoordinator+ViewLifecycle.swift:105` from `.deferredInShell(command: attachCommand)` to `.surfaceCommand(attachCommand)` and verify:
1. zmx session connects at correct dimensions after resize
2. No persistent wrong-column rendering
3. Session restore works across app restart

### 2. Request render state access from upstream Ghostty

File a feature request or discuss with Mitchell: expose `ghostty_render_state` (or equivalent) through the `ghostty_surface_t` API. The VT-level APIs are clearly ready. Ghostling proves the render state iteration pattern works. What's needed is a bridge:

```c
// Proposed API addition to ghostty.h
ghostty_result ghostty_surface_render_state_update(
    ghostty_surface_t surface, ghostty_render_state_t render_state);
```

This would unlock terminal content reading for AI context, search, and previews without needing to link a second library.

### 3. Audit focus on detach

Verify that `SurfaceManager.detach()` sends `ghostty_surface_set_focus(surface, false)` before `setOcclusion(false)`. Currently it only calls `setOcclusion`. If Ghostty doesn't implicitly clear focus on occlusion, a hidden surface might still think it's focused, which could cause apps inside the terminal to misbehave (e.g., not pausing cursor blink).

### 4. Consider terminal mode queries

Ghostling queries terminal modes (`ghostty_terminal_mode_get`) to decide behavior (e.g., whether scroll events go to the app or viewport). Agent Studio doesn't query modes at all — it delegates everything to the surface. But mode awareness could enable:
- Smart scroll behavior in the Agent Studio UI layer
- Knowing if the app is in alternate screen (for better session state display)
- Knowing if mouse tracking is active (for cursor styling)

This also requires the full API to expose mode queries, which it may already do (need to check headers once submodule is initialized).

---

## Ghostling API Reference

All from `ghostty/vt.h`:

| Category | Create | Key Functions | Free |
|----------|--------|---------------|------|
| Terminal | `ghostty_terminal_new(alloc, &t, opts)` | `vt_write`, `resize`, `scroll_viewport`, `mode_get`, `get` | `ghostty_terminal_free` |
| Key Encoder | `ghostty_key_encoder_new(alloc, &e)` | `encode`, `setopt_from_terminal` | `ghostty_key_encoder_free` |
| Key Event | `ghostty_key_event_new(alloc, &e)` | `set_key`, `set_action`, `set_mods`, `set_unshifted_codepoint`, `set_consumed_mods`, `set_utf8` | `ghostty_key_event_free` |
| Mouse Encoder | `ghostty_mouse_encoder_new(alloc, &e)` | `encode`, `setopt_from_terminal`, `setopt` | `ghostty_mouse_encoder_free` |
| Mouse Event | `ghostty_mouse_event_new(alloc, &e)` | `set_action`, `set_button`, `set_mods`, `set_position`, `clear_button` | `ghostty_mouse_event_free` |
| Render State | `ghostty_render_state_new(alloc, &rs)` | `update(rs, terminal)`, `get`, `set`, `colors_get` | `ghostty_render_state_free` |
| Row Iterator | `ghostty_render_state_row_iterator_new` | `next`, `row_get`, `row_set` (dirty flag) | `_free` |
| Row Cells | `ghostty_render_state_row_cells_new` | `next`, `cells_get` (graphemes, style, raw cell) | `_free` |
| Focus | (standalone fn) | `ghostty_focus_encode(event, buf, len, &written)` | — |

### Key Patterns

- **Object reuse:** Create encoders/events/iterators once, reuse every frame
- **Auto-sync:** Call `setopt_from_terminal` every frame to pick up mode changes
- **Snapshot boundary:** `render_state_update()` freezes state; terminal can keep mutating
- **Dirty tracking:** Per-row dirty flags + global dirty state for efficient partial redraws
- **Sized structs:** `GHOSTTY_INIT_SIZED(TypeName)` for versioned ABI compatibility
