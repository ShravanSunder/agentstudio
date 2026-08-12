# Tab Context Menu Investigation

## Bug packet

- Expected: secondary-clicking a visible tab pill presents its SwiftUI context menu.
- Actual: the secondary click produces no menu and does not change tab selection.
- Reproduction: in debug app `s08a`, primary-click a visible tab as a positive control, then secondary-click another visible tab at the same pill centerline.
- Scope: tab pills hosted inside the native `NSToolbar` workspace-tabs item.

## Current evidence

- Computer Use reproduced the failure on 2026-08-12 in the isolated `Agent Studio Debug s08a` app.
- A primary click at `(610, 13)` selected the neighboring tab, providing a positive control for the toolbar coordinates.
- A secondary click at `(470, 13)` presented no menu.
- Marker-scoped VictoriaLogs for `debug-observability-s08a-1786532536-61109` recorded `phase=input`, `tab_hit=true`, then `phase=host_hit_test`, `host_hit=true`, `hit_view_class=_TtCC7SwiftUI17HostingScrollView22PlatformGroupContainer`, and `static_menu_available=false`.
- Moving the existing dynamic `.contextMenu` from `tabContent` to the `TabPillView` root did not change the failure in fresh marker `debug-observability-s08a-1786534514-14617`; the experiment was reverted.
- A second diagnostic attached a static one-item `Context Menu Probe` directly to the horizontal `ScrollView`. Secondary-clicking the same tab still presented no menu in fresh marker `debug-observability-s08a-1786534741-26540`; the probe was reverted.
- The second diagnostic marker again recorded `tab_hit=true` and the SwiftUI `HostingScrollView.PlatformGroupContainer` as the AppKit hit-test winner.

## Working boundary map

1. AppKit admits a `.rightMouseDown` event for the target window.
2. Window-rooted hit testing resolves an AppKit view and tab/empty-strip classification.
3. The event reaches the SwiftUI hosting boundary.
4. SwiftUI requests and presents the tab pill context menu.

Instrumentation now observes boundaries 1 through 3. It is pass-through, records no tab UUIDs or paths, and uses the existing performance trace pipeline only when enabled. SwiftUI exposes no presentation callback for boundary 4.

## Mental-model break

- Assumption: the existing SwiftUI `.contextMenu` ownership remains valid when the tab strip is hosted inside the native toolbar.
- Finding: neither the per-tab dynamic menu, the same menu moved to the tab root, nor a static menu attached directly to the scroll container presents. AppKit admits and hit-tests each secondary click into the SwiftUI scroll subtree.
- Meaning: this is not a tab-frame, draggable-window, or modifier-depth failure. Context-menu presentation is unreliable across this native-toolbar/SwiftUI-scroll hosting boundary. Repairing it requires a deliberate menu-presentation owner outside that failing SwiftUI path, most narrowly at `DraggableTabBarHostingView`.

## Proof plan

1. Keep SwiftUI as the visual and primary-click owner.
2. Let `DraggableTabBarHostingView`, which already resolves tab frames and receives the admitted AppKit event, own secondary-click menu presentation only.
3. Reuse the existing command eligibility and dispatch closures; do not create parallel command identity or execution logic.
4. Add a failing host-level regression before the repair, then verify menu construction and target routing without weakening draggable-tab or draggable-window coverage.
5. Prove the final behavior in a fresh debug marker with Computer Use: context menu visible, left-click selection works, tab dragging works, and empty-strip window dragging works when the running workspace exposes empty strip.

## Implemented repair

- `DraggableTabBarHostingView` keeps SwiftUI as the visual and primary-click owner, but admits secondary clicks through a pass-through local AppKit event monitor.
- The hosting view resolves the clicked tab through the existing tab-frame geometry and consumes the event only after a menu presenter accepts it.
- `TabContextMenuPresenter` builds an `NSMenu` using the existing `AppCommand` labels, presentation filters, capability checks, command dispatcher, separators, submenu hierarchy, and `Command-W` equivalent.
- `PaneTabViewController` owns the presenter and binds each menu invocation to the clicked tab ID.
- The nonfunctional SwiftUI `.contextMenu` attachment was removed. No tab layout, paint, sizing, spacing, hover, or toolbar control changed.

## Final proof

- RED: before the repair, the host regression did not compile because `contextMenuRequestHandler`, `processRightMouseDown`, and `TabContextMenuPresenter` did not exist.
- GREEN: `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1200 mise run test:swift -- --filter 'DraggableTabBarWindowDragTests|PaneTabViewControllerTabContextMenuCommandTests'` passed 28 tests in 2 suites. The suite covers secondary-click admission/consumption, unchanged empty-strip window dragging, tab-pill non-drag behavior, menu hierarchy, command enablement, clicked-tab targeting, and arrangement routing.
- Quality: `mise run format` exited 0. `mise run lint` exited 0 with swift-format OK, 0 SwiftLint violations in 1,978 files, architecture lint OK, and release-script verification passed.
- Computer Use secondary-clicked `(470, 13)` in `Agent Studio Debug s08a`. Accessibility reported the native menu with `Rename Tab...`, `Close Tab`, `Add Terminal to Tab` (`Split Right`, `Split Left`), `New Floating Terminal`, and `Arrangements` (`Show Arrangements`, `Save Arrangement As...`).
- Computer Use primary-clicked `(755, 13)` after dismissing the menu; the target tab selected normally.
- Computer Use entered management mode, dragged the active tab from `(610, 13)` to `(790, 13)`, observed it reorder, then dragged it back and exited management mode, restoring the original order.
- The running workspace contains 13 overflowing tabs, so it exposes no genuine empty tab-strip region for live window-drag proof. A toolbar-background drag attempt did not move the window and is not counted as proof. The unchanged empty-strip path remains covered by the focused host suite.
- Full PR gate: `mise run test` exited 0 after all configured lint, architecture, BridgeWeb unit/integration/browser/E2E, Swift, serialized WebKit, and general E2E lanes completed. The final runner duration was 236.40 seconds.
- Fresh observability run: `mise run run-debug-observability -- --detach` launched the current source through LaunchServices as PID `69585` with marker `debug-observability-s08a-1786537209-67895`; `mise run verify-debug-observability` exited 0 and found `app.did_finish_launching.succeeded` for that run.
- Fresh post-gate Computer Use proof against PID `69585`: the tab strip retained its existing visual treatment; secondary-clicking `(470, 13)` exposed the same native menu hierarchy; dismissing it and primary-clicking `(755, 13)` selected the target tab normally.
- `git diff --check` exited 0. The tab-bar diff adds no layout, sizing, spacing, color, hover, selection, or animation modifier; it only removes the failed SwiftUI context-menu attachment and routes secondary-click presentation through AppKit.
