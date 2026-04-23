# LUNA-361 Phase 3 — Current Checklist & Follow-up Inventory

**Date:** 2026-04-23
**Branch:** `notification-system-1-attended-pane`
**Current HEAD checked:** `67c446d`
**Companion doc:** [luna361-phase3-system-overview-2026-23-04.md](./luna361-phase3-system-overview-2026-23-04.md)

This file replaces the earlier stale `b65f195` gap list. The old list was useful at the time, but several items it marked open were fixed in follow-up commits:

- `00876e2 fix(notification-inbox): address phase 3 review cleanup`
- `668feca test(notification-inbox): cover approval and security receive paths`
- `67c446d fix(window): simplify sidebar titlebar controls`

Current verification run:

- `mise run lint && mise run test` exited `0` on 2026-04-23.
- `swift-format` passed.
- `swiftlint` passed across 662 Swift files.
- Full test gate passed, including the serialized WebKit suites. E2E and Zmx E2E remain skipped by project defaults unless explicitly enabled.

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
| 10. Drawer trailing actions/bell | Done | Core seam is `DrawerInboxPresentation`; Core does not reference feature types. |
| 11. Drawer bell host/popover | Done | Drawer popover filters by drawer pane ids and ignores drawer-dismissed notifications. |
| 12. Worktree unread pill | Done | Repo explorer row takes primitive unread count; tests cover show/hide. |
| 13. CommandBar inbox scope | Done | `InboxNotificationCommands` uses `Actions` + `Snapshot`; CommandBar consumes seam, no feature atom imports. |
| 14. `⌘⇧I` drawer inbox command | Done | Dispatch path is wired and tested, including no-op logging paths. |
| 15. Sidebar surface swap/boot wiring | Done | Inbox sidebar is live through `SidebarSurfaceHost`; placeholder was removed. |
| 16. Integration verification | Mostly done | Headless tests cover bus→atom→model, Bridge RPC→router→atom, and approval/security receive-side routing. Full live OSC visual smoke remains optional manual evidence, see below. |

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

### Still worth tracking as UI/state follow-up

- Collapsible inbox groups are not implemented.
  - Current behavior is always-expanded groups.
  - If added, collapsed state should be temporary UI state unless we explicitly decide it belongs in persisted prefs.

- Repo explorer expanded/collapsed group state and sidebar width persistence are not part of this Phase 3 inbox slice.
  - These belong in UI shell state, likely `UIStateAtom` / UI persistence, not in the inbox feature atom.

- Worktree pill click-to-filter is not implemented.
  - Today the pill is an unread indicator.
  - A future version could click the pill to open the inbox with a worktree-scoped filter, but that needs a design decision because it changes sidebar inbox state and routing.

- Fuzzy search is not implemented and is not needed for this ticket.
  - Current target is case-insensitive substring matching / partial search.

- Rich notification content is not implemented and is not needed now.
  - Do not hard-code assumptions that every notification is only title/body forever; future rich content should be additive, not a rewrite of routing.

- Unified keyboard dispatcher remains a broader input-system refactor.
  - The inbox has local key routing/tests; the app-wide unified dispatcher is separate scope.

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
