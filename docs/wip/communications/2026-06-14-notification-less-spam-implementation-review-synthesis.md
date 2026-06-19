# Notification Less Spam Implementation Review Synthesis

## Scope

Implemented the notification inbox less-spam design from:

- `docs/superpowers/specs/2026-06-14-notification-less-spam-rollup-alerts.md`
- `docs/plans/2026-06-14-notification-less-spam-rollup-alerts-implementation.md`

The implementation changes pane/tab/sidebar chrome to attention-only roll-up alerts, keeps activity as row-level blue dots only, persists read/filter preferences, and adds UI controls for row-state and content-mode filtering.

## Review Findings Resolved

- Security: bounded notification title/body text by UTF-8 byte budget as well as scalar budget so combining-mark payloads cannot bypass limits.
- Reliability: allowed read activity rows to reopen when same-session action or safety arrives, including persisted SQLite rows.
- Chrome semantics: toolbar, pane, worktree, launcher, and tab counts now use roll-up alert counts, not generic unread activity.
- Pane inbox state: moved content mode and row-state filter ownership into persisted `InboxNotificationPrefsAtom` so pane and sidebar inboxes do not split-brain after restart.
- Chrome retargeting: global/pane/worktree inbox chrome opens roll-up-alert unread scope without collapsing an already visible inbox during retarget.
- Accessibility: row accessibility labels now include unread/read state and lane semantics.

## Proof

- Baseline was fast-forwarded to current `origin/main` at `f8857db9330cb3e96f3e805ad2011b5144933497`.
- `mise run format` passed after the fast-forward.
- `mise run lint` passed after the fast-forward: swift-format OK, SwiftLint 0 violations across 1138 files, release script verification passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test -- --filter "PaneInboxNotificationPopover|PaneInboxPresentationAtom|PaneInboxPresentation|PaneLeafContainerPaneInbox|MainSplitViewControllerCompositeCommand|InboxPromoter|InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxSidebarState|WorkspaceSettingsStore|InboxNotificationPrefsAtom|InboxNotificationListModel|TabBarAdapter|WorkspaceNotificationCountOwnership|InboxRow|SidebarSurfaceHost|InboxNotificationTextPolicy"` passed 194 tests in 21 suites.
- `SWIFT_TEST_TIMEOUT_SECONDS=240 mise run test` passed after rerun on the latest `origin/main` baseline. The run included the serialized WebKit suites; the E2E and Zmx E2E suites remained skipped by their default environment gates.
- The earlier serialized WebKit signal-11 was investigated as a transient stale build/test-process state after the latest-main fast-forward: clean `origin/main`, clean `origin/main` plus the WebKit test diff, clean `origin/main` plus branch source/test changes, and the primary worktree exact filter all passed before the full-suite rerun passed.
- `mise run observability:up` passed with VictoriaMetrics, VictoriaLogs, VictoriaTraces, and OTEL collector healthy.
- `mise run run-debug-observability -- --detach` launched fresh debug app PID 5538 via LaunchServices with marker `debug-observability-akm3-1781491226-143`.
- `mise run verify-debug-observability` passed and found marker-scoped `app.zmx_startup_reconciliation.completed` in VictoriaLogs.
- Peekaboo could list the debug window for PID 5538 / window 344373, but screenshot capture was blocked by ScreenCaptureKit `SCStreamErrorDomain -3811`; the classic fallback reported no displays available for window capture. `peekaboo inspect-ui` reached the app/window but found zero accessible child elements.

## Residual Risk

Visual/pixel proof is blocked by the current Peekaboo capture environment, not by a failing app launch. The app is running, the window is visible to Peekaboo metadata, and Victoria observability verified startup behavior through the shared stack.

Full-suite proof passed after investigating and clearing the earlier transient serialized WebKit signal-11 runner failure.
