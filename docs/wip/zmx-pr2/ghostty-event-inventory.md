# Ghostty event and callback inventory

Source version: Ghostty `82232ecde55405559dec29c5466cb9e39938cb41`.
Generated framework and vendor headers were refreshed with `mise run copy-xcframework`.

## Runtime callbacks

| Ghostty callback | AgentStudio owner | Crossing | Coverage |
| --- | --- | --- | --- |
| `wakeup_cb` | `Ghostty.CallbackRouter` → `App.tick()` | C callback captures pointer bits, hops to MainActor | `GhosttyCallbackRouterTests` runtime configuration |
| `action_cb` | `Ghostty.ActionRouter.handleAction` | synchronous C callback; typed action routing | `GhosttyAdapterTests`, `GhosttyActionRouterTests`, local-drain tests |
| `read_clipboard_cb` | `CallbackRouter.readClipboard` | synchronous; supports plain text only; explicit completion payload | callback router tests |
| `confirm_read_clipboard_cb` | `confirmReadClipboard` | synchronous; preserves beta auto-approval, no persistent remember grant | callback router tests |
| `write_clipboard_cb` | `writeClipboard` | synchronous; validates MIME and byte length | callback router tests |
| `close_surface_cb` | `closeSurface` | callback schedules surface teardown | surface lifecycle tests |

## Routed action families

`GhosttyAdapter` translates and tests title/tab-title, cwd, command-finished,
new split, split focus/resize/equalize, tab close/navigation/move, progress,
read-only, secure-input, renderer health, cell/initial/limit sizes, mouse shape/
visibility/link, key sequence/table, color/config reload/config change, search,
scrollbar, prompt title, desktop notification, and URL actions.

The router explicitly classifies app-intercepted window actions separately from
terminal actions. Unknown tags remain `.unhandled`; payload-shape mismatches are
reported rather than silently coerced.

## Upstream actions not currently routed

The Ghostty `82232ecde554` header exposes four actions that AgentStudio deliberately
classifies as unsupported: `set_window_title`, `selection_changed`,
`export_terminal_io`, and `move_tab_to_new_window`. The first two can be emitted
by a surface; the latter two belong to Ghostty inspector/window UI. AgentStudio now returns `false` for these known unsupported tags, preserving the
pre-existing unhandled behavior without trapping in the adapter. They remain compatibility gaps to address in a separate
runtime-event decision; this beta does not invent host behavior for them.

## Surface calls

`GhosttySurfaceView` owns surface creation, content scale, pixel size, refresh,
text reads, and teardown. `SurfaceRendererStateDelivery` is the sole path for
focus and occlusion. `SurfaceManager` suppresses equal focus/visibility writes.

## Compatibility checks

- Refreshed framework header matches the pinned vendor header for the clipboard
  callback ABI.
- Focused callback and vendor-wiring tests: 18/18 passed.
- Full `mise run test`: passed, including serialized E2E and zmx integration.
- Debug app rebuilt and relaunched from the refreshed framework: vx09 PID 5255.

This inventory is a review aid; it does not add a second event system or change
runtime ownership.
