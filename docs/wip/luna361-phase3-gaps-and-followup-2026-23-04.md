# LUNA-361 Phase 3 — Current Checklist & Follow-up Inventory

**Date:** 2026-04-24
**Branch:** `notification-system-1-attended-pane`
**Current branch checked:** through `014f1c9` hardening restore plus `5ed91ee` plan cleanup
**Companion doc:** [luna361-phase3-system-overview-2026-23-04.md](./luna361-phase3-system-overview-2026-23-04.md)

This file replaces the earlier stale `b65f195` gap list. The old list was useful at the time, but several items it marked open were fixed in follow-up commits:

- `00876e2 fix(notification-inbox): address phase 3 review cleanup`
- `668feca test(notification-inbox): cover approval and security receive paths`
- `67c446d fix(window): simplify sidebar titlebar controls`

Last completed full verification run:

- After the `origin/main` merge and restored hardening commit `014f1c9`, `mise run build`, `mise run format && mise run lint`, `mise run test`, and `git diff --check` all exited `0`.
- The later `5ed91ee` commit removed superseded plan documents only; it did not change product code.
- E2E and Zmx E2E remain skipped by project defaults unless explicitly enabled.

The remaining completion gap is not headless code verification; it is the live native OSC visual smoke across every notification surface.

## Phase 3 Plan Checklist

The source plan is `docs/superpowers/plans/2026-04-20-00c-luna361-phase3-notification-inbox-feature.md`.

| Task | Status | Current read |
| --- | --- | --- |
| 1. Data types | Done | `InboxNotification` exists with discriminated `Source`; grouping/sort enums live in Core. |
| 2. `InboxNotificationAtom` | Done | Log mutations, id dedup, retention cap, denormalized `globalUnreadCount`, read/drawer dismissal APIs. |
| 3. `InboxNotificationPrefsAtom` | Done | Grouping, sort, and bell preference. |
| 4. `InboxNotificationStore` | Done | JSON persistence, debounce, corrupt-file quarantine, immediate save fallback on debounce clock failure. |
| 5. `PaneFocusTracker` | Done | Adapts `AttendedPaneAtom` transitions for focus-gained semantics. |
| 6. `InboxNotificationRouter` | Done | EventBus subscription, attended-pane gating, bell pref gate, per-pane sandbox health edge dedup, debug logging for ignored events. |
| 7. Bridge `inbox.post` RPC | Done | `InboxMethods` derives pane id server-side and emits runtime inbox events. |
| 8. Row/header/empty components | Done | `InboxRow`, `InboxNotificationGroupHeader`, `InboxNotificationEmptyState`. |
| 9. Sidebar inbox view | Done | Search, grouping, sorting, list navigation helpers, row actions, click-through/dead-pane fallback. |
| 9a. Sidebar toolbar bell | Done | Search/find icon removed; repo and bell toolbar icons are active-state toggles with padding and unread dot. |
| 10. Drawer trailing actions/bell | Done | Core seam is `PaneInboxPresentation`; Core does not reference feature types. |
| 11. Drawer bell host/popover | Done | Drawer popover filters by drawer pane ids and ignores drawer-dismissed notifications. |
| 12. Worktree unread pill | Done | Repo explorer row takes primitive unread count; tests cover show/hide. |
| 13. CommandBar inbox scope | Done | `InboxNotificationCommands` uses `Actions` + `Snapshot`; CommandBar consumes seam, no feature atom imports. |
| 14. `⌘⇧I` pane inbox command | Done | Dispatch path is wired and tested, including no-op logging paths. |
| 15. Sidebar surface swap/boot wiring | Done | Inbox sidebar is live through `SidebarSurfaceHost`; placeholder was removed. |
| 16. Integration verification | Mostly done | Headless tests cover bus→atom→model, Bridge RPC→router→atom, and approval/security receive-side routing. Full live OSC visual smoke remains manual/native evidence still needed for this PR. |

## Current Done / Not Done

### Done and verified in the tree

- Terminal notification paths land in the inbox receive path:
  - OSC desktop notification
  - terminal bell, gated by `bellEnabled`
  - long-running command finished, gated by attended pane and duration

- Bridge `inbox.post` lands in the inbox receive path.

- Approval/security receive-side handling is implemented and tested with synthetic runtime envelopes.

- The UI surfaces are live:
  - sidebar inbox
  - sidebar toolbar bell + unread dot
  - drawer bell + popover
  - worktree unread pill
  - CommandBar `.inbox` actions

- The data model is ready for future expansion:
  - `InboxNotification.Source` is now a discriminated union, so source context is not seven unrelated optional fields.
  - Rich notification payloads are not implemented, but the current model can grow additively with a content/payload enum later.

- The important review cleanup from the stale gap list is done:
  - router comment fixed
  - list model memoized in the sidebar view
  - router unknown/ignored events log
  - `⌘⇧I` no-op branches log
  - CommandBar nil commands log
  - MainWindowController requires injected inbox atoms
  - `AttendedPaneAtom.stop()` final refresh added
  - `globalUnreadCount` denormalized
  - store debounce clock failure saves immediately
  - stale inbox-specific rot strings removed
  - CommandBar actions covered beyond the old 2/10 gap
  - endpoint first/last navigation covered
  - RepoExplorer row pill tests expanded
  - Drawer request seam collapsed to one request reader + clearer
  - Commands split into actions/snapshot
  - Source union adopted

### Not done, but not a Phase 3 blocker

- Real upstream approval emitters do not exist yet.
  - Inbox receive-side support exists.
  - End-to-end approval flow needs the future approval/artifact subsystem.

- Real upstream security/sandbox emitters do not exist yet.
  - Inbox receive-side support exists.
  - End-to-end security notifications need the future sandbox/security subsystem.

- Full live manual OSC visual smoke across every surface has not been re-run as a single scripted proof after the latest commits.
  - Headless tests cover the receive paths and UI seams.
  - Peekaboo visual evidence exists for the titlebar icon/padding cleanup.
  - A stricter manual smoke would be: launch app, emit OSC from a terminal pane, verify sidebar row + toolbar dot + drawer bell + worktree pill.
  - This is the only current-PR work item still not claimed complete.

## Plan / Spec Reconciliation

This section reconciles the surviving LUNA-361 docs so old plan language does not create a second task list.

| Source doc | Current disposition |
| --- | --- |
| Phase 1 sidebar composition foundation | Covered in the tree. `SidebarSurfaceHost`, `UIStateAtom` shell state, repo/inbox surface switching, and sidebar focus plumbing exist with tests. |
| Phase 2 keyboard owner | Covered in the tree. `KeyboardOwner` and `KeyboardOwnerDerived` exist; CommandBar defaults to `.inbox` when the inbox owns keyboard focus. The broader unified keyboard dispatcher remains explicitly out of scope. |
| Phase 3 notification inbox feature | Covered for implemented product systems. Inbox model/atom/store/router, bridge `inbox.post`, sidebar, drawer, toolbar bell, worktree pill, CommandBar actions, persistence, and headless integration coverage exist. The live all-surface OSC smoke remains current-PR verification. |
| Phase 3b sidebar cache and linkable filters | Covered in the tree. This supersedes the older Phase 3 non-goal that said collapsible groups were out; collapsible inbox groups are now implemented through `SidebarCacheAtom.collapsedInboxGroups`. |
| Phase 3c Ghostty terminal intelligence and OSC smoke | Code and headless tests are covered. The plan's remaining live-smoke task points at `docs/wip/luna361-phase3c-ghostty-terminal-intelligence-smoke-2026-04-24.md`. |
| Notification inbox design spec | Covered where source systems exist. Terminal and bridge sources are live; approval and security rows are receive-side ready but upstream emitters do not exist and are not silently counted as done. |
| Interaction model WIP | Covered for LUNA-361's needed slice: keyboard ownership and inbox shortcuts. Future unified dispatch remains an explicitly deferred input-system refactor, not a hidden Phase 3 gap. |

Two follow-up buckets remain:

1. `docs/superpowers/plans/2026-04-24-luna361-sidebar-notification-hardening-followup.md`
   - Closed for current-PR hardening.
   - Only future schema migrations remain, and they should be designed when a v2 on-disk format exists.

2. `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`
   - Owns raw terminal output, printed file links, diagnostics, structured agent status, and semantic artifact projection.
   - It must start with source research; scrollbar growth and `openURLRequested` are not substitutes for terminal text extraction.

Explicitly refuted as current-PR scope:

- Approval/security upstream emitters: receive-side inbox handling is ready and tested, but the product subsystems that would emit real events are separate future work.
- macOS `UNUserNotificationCenter`, cross-workspace aggregation, rich notification content, fuzzy search, email/Slack/remote fan-out, and user-configurable routing beyond bell on/off: all remain non-goals from the Phase 3 plan/spec.

### Phase 3b sidebar/filter work now addressed in this branch

- Repo explorer expanded/collapsed group memory moved out of `UIStateAtom` and into `SidebarCacheAtom`.
  - The refactor is a hard cutover: repo expansion and checkout colors read/write the sidebar cache, not the composition atom.
  - Cache key domains use typed wrappers (`SidebarGroupKey`, `SidebarCheckoutColorKey`, `InboxNotificationGroupKey`) instead of mixing raw strings in memory.

- Sidebar width stays on `WorkspaceMetadataAtom`.
  - This is intentional: width is workspace/window geometry, not sidebar cache.
  - It already persists through workspace metadata.

- Inbox group collapse is implemented.
  - `SidebarCacheAtom.collapsedInboxGroups` tracks only collapsed group keys.
  - Empty set means all groups expanded by default.
  - `InboxNotificationListModel` keeps section counts but hides collapsed rows from display/navigation.

- Worktree pill click-to-filter is implemented.
  - The unread pill is now clickable.
  - It sets a short-lived `InboxFilterDraftAtom` value and dispatches the existing `.showInboxNotifications` command.
  - The inbox sidebar consumes the draft on mount and applies the typed `InboxFilter.worktree(id:)` filter.

- UI/sidebar persistence recovery is broadened.
  - `PersistableUIState` now defaults bad optional composition/filter fields without corrupting sibling fields.
  - `PersistableSidebarCache` defaults bad cache slices independently.

- Fuzzy search is not implemented and is not needed for this ticket.
  - Current target is case-insensitive substring matching / partial search.

- Rich notification content is not implemented and is not needed now.
  - Do not hard-code assumptions that every notification is only title/body forever; future rich content should be additive, not a rewrite of routing.

- Unified keyboard dispatcher remains a broader input-system refactor.
  - The inbox has local key routing/tests; the app-wide unified dispatcher is separate scope.

### Phase 3c Ghostty terminal-intelligence work now addressed in this branch

- Additional Ghostty-originated terminal signals are routed or documented by purpose:
  - progress error edges route to inbox as `.terminalProgressError`
  - renderer healthy→unhealthy edges route to inbox as `.terminalRendererUnhealthy`
  - progress non-error states, cwd, title/tab title, scrollbar, and interaction state remain runtime state instead of inbox noise

- The branch has headless coverage for the Ghostty adapter/action-router/runtime/router paths.

- The live OSC visual smoke across every surface is still not claimed complete.
  - That remains the manual/native proof: launch the app, emit real OSC/BEL/progress/error sequences from an embedded terminal pane, and visually confirm inbox rows plus toolbar/drawer/worktree indicators.

## Review-list items that were still open before the latest sidebar test pass

These are now addressed on top of the earlier refresh:

- Mounted sidebar focus-bridge coverage now exists.
  - `InboxNotificationSidebarViewTests` mounts the real SwiftUI view in an `NSHostingView` and asserts that first-responder changes publish `sidebarHasFocus`, plus that the focus bridge's escape path calls `onRefocusActivePane`.

- Dead-pane fallback coverage now exists.
  - `InboxSidebarActivationResolver` is tested for both stale-pane flash behavior and live-pane focus behavior.

- `PaneFocusTracker` now carries the single-consumer note inline, so future fan-out work is less likely to accidentally tap the wrong stream boundary.

## Testing Pyramid Status

Most useful coverage is headless, which matches the desired pyramid:

- Unit/model:
  - notification model/source roundtrips
  - atom mutations/counting/dedup/retention
  - list model filtering/grouping/sorting/navigation
  - prefs/store persistence

- Boundary/integration:
  - EventBus/runtime envelope to router/atom/list model
  - Bridge `inbox.post` to runtime event to inbox atom
  - approval/security receive-side events to inbox/list/drawer
  - drawer presentation seam
  - CommandBar inbox actions
  - titlebar toolbar buttons through controller harness

- Visual/manual:
  - latest titlebar icon/padding change was visually verified.
  - full live OSC across all surfaces remains a manual smoke option, not a substitute for the headless suite.

## Merge Readiness

My current read: Phase 3 meets the requirements for the parts whose upstream systems exist today.

The only honest caveat is source coverage:

- terminal + bridge notifications are live end-to-end
- approval + security are receive-side ready and tested, but upstream emitters are future work

That caveat should be described explicitly in release/PR notes so nobody reads "approval/security inbox complete" as "the approval/security subsystems exist."
