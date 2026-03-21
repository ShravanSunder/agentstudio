# Ghostling Analysis: Lessons for Agent Studio

**Date:** 2026-03-21
**Source:** [ghostty-org/ghostling](https://github.com/ghostty-org/ghostling) — ~600 lines of C, a minimal terminal on `libghostty-vt`

## Executive Summary

Ghostling is a proof-of-concept terminal emulator built on **`libghostty-vt`** (the VT-only subset of libghostty) + Raylib for windowing. It demonstrates that Ghostty's terminal emulation can be cleanly separated from Ghostty's platform layer (Metal renderer, AppKit integration, surface management).

**The key revelation:** There are now **two distinct libghostty API surfaces**:

| API | Header | What It Provides | What It Doesn't |
|-----|--------|-------------------|-----------------|
| `ghostty/ghostty.h` (full) | Full platform integration | Surfaces, Metal rendering, PTY management, config, actions | — |
| `ghostty/vt.h` (VT-only) | VT parsing + terminal state | Terminal grid, styles, modes, encoders, render state | No PTY, no renderer, no platform |

Agent Studio currently uses the **full API** via `ghostty_app_t` / `ghostty_surface_t`. Ghostling uses **only the VT API** and manages its own PTY, rendering, and input encoding.

---

## Architecture Comparison

### Ghostling's Approach (VT-only)

```
User Input (Raylib)
    │
    ├─► GhosttyKeyEncoder ──► encode ──► raw bytes ──► PTY master fd
    ├─► GhosttyMouseEncoder ──► encode ──► raw bytes ──► PTY master fd
    │
PTY slave (shell)
    │
    ▼
PTY master fd ──► read() ──► ghostty_terminal_vt_write() ──► GhosttyTerminal
    │
    ▼
ghostty_render_state_update() ──► GhosttyRenderState
    │
    ▼
Row iterator ──► Cell iterator ──► graphemes + styles ──► Raylib DrawTextEx()
```

**Ghostling owns:** PTY lifecycle, input encoding dispatch, rendering, window management
**Ghostty owns:** VT parsing, terminal state, key/mouse encoding logic, render state snapshots

### Agent Studio's Approach (Full API)

```
NSEvent (AppKit)
    │
    ▼
GhosttySurfaceView (NSView) ──► ghostty_surface_key() / ghostty_surface_mouse_*()
    │
    ▼
ghostty_surface_t ──► [internal PTY + VT + Metal renderer]
    │
    ▼
ghostty_runtime_config_s callbacks ──► action_cb ──► GhosttyAdapter ──► EventBus
```

**Ghostty owns:** PTY, VT, rendering (Metal), input processing
**Agent Studio owns:** Surface lifecycle (SurfaceManager), action routing, session management (zmx)

---

## Key APIs Demonstrated by Ghostling

These APIs are available in `ghostty/vt.h` and represent capabilities Agent Studio isn't currently using:

### 1. Key Encoder (standalone input encoding)

```c
GhosttyKeyEncoder key_encoder;
ghostty_key_encoder_new(NULL, &key_encoder);

GhosttyKeyEvent key_event;
ghostty_key_event_new(NULL, &key_event);

// Sync encoder with terminal modes (cursor keys, kitty protocol, etc.)
ghostty_key_encoder_setopt_from_terminal(encoder, terminal);

// Set event properties
ghostty_key_event_set_key(event, GHOSTTY_KEY_A);
ghostty_key_event_set_action(event, GHOSTTY_KEY_ACTION_PRESS);
ghostty_key_event_set_mods(event, GHOSTTY_MODS_CTRL);
ghostty_key_event_set_unshifted_codepoint(event, 'a');
ghostty_key_event_set_consumed_mods(event, consumed);
ghostty_key_event_set_utf8(event, utf8_buf, utf8_len);

// Encode to VT sequence
char buf[128];
size_t written = 0;
ghostty_key_encoder_encode(encoder, event, buf, sizeof(buf), &written);
write(pty_fd, buf, written);
```

### 2. Mouse Encoder (standalone mouse encoding)

```c
GhosttyMouseEncoder mouse_encoder;
ghostty_mouse_encoder_new(NULL, &mouse_encoder);

// Sync tracking mode + format from terminal state
ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal);

// Provide geometry for pixel→cell conversion
GhosttyMouseEncoderSize enc_size = { .size = sizeof(...), ... };
ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &enc_size);

// Motion dedup
bool track_cell = true;
ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL, &track_cell);
```

### 3. Render State Iteration (cell-by-cell access)

```c
GhosttyRenderState render_state;
ghostty_render_state_new(NULL, &render_state);

// Snapshot terminal → render state (thread-safe copy)
ghostty_render_state_update(render_state, terminal);

// Colors (palette, default fg/bg, cursor)
GhosttyRenderStateColors colors;
ghostty_render_state_colors_get(render_state, &colors);

// Iterate rows → cells → graphemes + styles
ghostty_render_state_get(render_state, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &row_iter);
while (ghostty_render_state_row_iterator_next(row_iter)) {
    ghostty_render_state_row_get(row_iter, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cells);
    while (ghostty_render_state_row_cells_next(cells)) {
        // grapheme_len, codepoints, style (fg, bg, bold, italic, inverse)
    }
}

// Cursor position + visibility
ghostty_render_state_get(render_state, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &visible);
ghostty_render_state_get(render_state, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cx);
```

### 4. Terminal Mode Queries

```c
bool mode_val = false;
ghostty_terminal_mode_get(terminal, GHOSTTY_MODE_X10_MOUSE, &mode_val);
ghostty_terminal_mode_get(terminal, GHOSTTY_MODE_NORMAL_MOUSE, &mode_val);
// etc.
```

### 5. Focus Encoding

```c
char focus_buf[8];
size_t written = 0;
ghostty_focus_encode(GHOSTTY_FOCUS_GAINED, focus_buf, sizeof(focus_buf), &written);
write(pty_fd, focus_buf, written);
```

### 6. Scrollbar State

```c
GhosttyTerminalScrollbar scrollbar;
ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &scrollbar);
// scrollbar.total, scrollbar.len, scrollbar.offset
```

---

## Lessons for Agent Studio

### Lesson 1: libghostty-vt Exists and Is Production-Ready

The VT-only API is a first-class citizen. Mitchell built Ghostling in 2 hours to prove it. This means:

- **zmx could use `libghostty-vt` directly** for headless terminal sessions rather than requiring full Ghostty surfaces. A zmx session could be a `GhosttyTerminal` + PTY fd without any rendering overhead.
- **Bridge panes could render terminal content** using the render state iteration API, enabling terminal content in WebView contexts (React-based terminal rendering).
- **Testing terminal behavior** becomes possible without surfaces — create a `GhosttyTerminal`, feed it VT sequences, inspect the render state.

### Lesson 2: Encoder APIs Decouple Input From Surfaces

Ghostling's key/mouse encoder pattern shows that input encoding is fully separable from surface management:

```
Input Event → Encoder (synced with terminal modes) → VT bytes → PTY
```

**Current Agent Studio pattern:** Input goes through `GhosttySurfaceView` which calls `ghostty_surface_key()` — the surface handles encoding internally.

**What this enables:** If we ever need to send synthetic input to a terminal (e.g., from a bridge pane, from automation, from zmx replay), we could use the encoder APIs directly rather than simulating NSEvents through a surface view.

### Lesson 3: Render State is a Thread-Safe Snapshot

`ghostty_render_state_update(render_state, terminal)` creates a snapshot that can be read independently of the terminal's mutation thread. This is the clean read path:

- Terminal gets mutated by VT writes (potentially from any thread)
- Render state snapshot captures a consistent view
- Iteration happens on the render thread without locking the terminal

**Relevance:** If Agent Studio ever needs to read terminal content (for AI context, for search, for session preview thumbnails), the render state API is the correct way to do it — not by reaching into Ghostty's internal state.

### Lesson 4: PTY Management is Simple

Ghostling's PTY code is ~50 lines. `forkpty()` + non-blocking `read()` in a game loop. The interesting bits:

- Non-blocking master fd (`O_NONBLOCK`) — drain in a loop until `EAGAIN`
- `TIOCSWINSZ` ioctl on resize — separate from `ghostty_terminal_resize()`
- `TERM=xterm-256color` — simple env setup
- Shell detection: `$SHELL` → `getpwuid()` → `/bin/sh`

**Relevance for zmx:** zmx presumably handles PTY management for multiplexed sessions. If we ever need to manage PTYs directly (e.g., for non-zmx single sessions, for testing), this is the minimal pattern.

### Lesson 5: Focus/Resize Are Explicit Operations

Ghostling explicitly calls:
- `ghostty_terminal_resize()` on window resize
- `ghostty_focus_encode()` on focus change → writes CSI I/O to PTY

In Agent Studio, these go through the surface API (`ghostty_surface_set_focus`, `ghostty_surface_set_size`). But knowing the underlying encoding exists means:
- Focus events for hidden/background terminals could be managed without surfaces
- zmx session restore could correctly signal focus state

### Lesson 6: Dirty Tracking for Efficient Rendering

Ghostling uses render state dirty flags:
```c
GhosttyRenderStateDirty clean_state = GHOSTTY_RENDER_STATE_DIRTY_FALSE;
ghostty_render_state_set(render_state, GHOSTTY_RENDER_STATE_OPTION_DIRTY, &clean_state);
```

And per-row dirty flags after rendering each row. This enables skip-unchanged-rows optimization. Agent Studio's Metal renderer (via Ghostty's built-in renderer) likely does this internally, but it's good to know the API exposes it for custom renderers.

---

## Implications for zmx Integration

### Current zmx Pattern (Agent Studio)

```
zmx attach <session-id> <shell> → runs inside Ghostty surface's PTY
Ghostty surface owns the PTY that zmx attaches to
```

### Alternative Pattern (Ghostling-inspired)

```
GhosttyTerminal (VT-only) ←→ PTY fd ←→ zmx session
                                          │
                              render_state_update() for preview/AI context
                              key_encoder for synthetic input
```

This would enable:
1. **Headless sessions** — zmx sessions that exist without a visible surface, saving GPU/Metal resources for background terminals
2. **Session preview** — Read render state to generate text snapshots for tab previews, AI context, or session restore thumbnails
3. **Input injection** — Send keystrokes to a session via the encoder API without needing an NSView

### Practical Next Steps

These are observations, not action items. The full Ghostty surface API serves Agent Studio well for its primary use case (interactive terminals with Metal rendering). The VT-only API becomes relevant when:

1. We need terminal state without rendering (headless/background sessions)
2. We need to read terminal content programmatically (AI context, search)
3. We need custom rendering (terminal content in a WebView/bridge pane)
4. We need synthetic input (automation, testing)

---

## API Reference Quick Sheet

All from `ghostty/vt.h`:

| Category | Create | Use | Free |
|----------|--------|-----|------|
| Terminal | `ghostty_terminal_new` | `ghostty_terminal_vt_write`, `ghostty_terminal_resize`, `ghostty_terminal_scroll_viewport`, `ghostty_terminal_mode_get`, `ghostty_terminal_get` | `ghostty_terminal_free` |
| Key Encoder | `ghostty_key_encoder_new` | `ghostty_key_encoder_encode`, `ghostty_key_encoder_setopt_from_terminal` | `ghostty_key_encoder_free` |
| Key Event | `ghostty_key_event_new` | `set_key`, `set_action`, `set_mods`, `set_unshifted_codepoint`, `set_consumed_mods`, `set_utf8` | `ghostty_key_event_free` |
| Mouse Encoder | `ghostty_mouse_encoder_new` | `ghostty_mouse_encoder_encode`, `setopt_from_terminal`, `setopt` | `ghostty_mouse_encoder_free` |
| Mouse Event | `ghostty_mouse_event_new` | `set_action`, `set_button`, `set_mods`, `set_position`, `clear_button` | `ghostty_mouse_event_free` |
| Render State | `ghostty_render_state_new` | `ghostty_render_state_update`, `ghostty_render_state_get`, `ghostty_render_state_colors_get` | `ghostty_render_state_free` |
| Row Iterator | `ghostty_render_state_row_iterator_new` | `ghostty_render_state_row_iterator_next`, `ghostty_render_state_row_get` | `_free` |
| Row Cells | `ghostty_render_state_row_cells_new` | `ghostty_render_state_row_cells_next`, `ghostty_render_state_row_cells_get` | `_free` |
| Focus | — | `ghostty_focus_encode` | — |
