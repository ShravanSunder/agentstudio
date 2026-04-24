# LUNA-361 Phase 3b/3c Review Buckets

**Date:** 2026-04-24

## Bucket 1: In This PR

These review findings are implemented in the current branch and covered by tests/lint.

- `ChaosStoreSeeder` exists and drives the nine planned chaos flavors.
- Persistence chaos coverage now spans workspace state, repo cache, UI state, sidebar cache, and inbox notification persistence.
- `PersistableState` and `PersistableCacheState` use per-field recoverable decode; the old tests that codified whole-workspace wipe were updated.
- `SidebarCacheStoreTests` cover round-trip, missing-file defaults, corrupt quarantine, and partial-payload defaults.
- `InboxNotificationSidebarView` reacts to `InboxFilterDraftAtom.pendingFilter` while already mounted and consumes pre-seeded drafts on mount.
- The worktree unread pill path sets the filter draft before dispatching existing `.showInboxNotifications`.
- `InboxFilter.matches(_:)` owns matching with an exhaustive switch; worktree and repo filters are tested.
- `RepoExplorerView` reads expanded groups and checkout colors from `SidebarCacheAtom` instead of local shadow state.
- `SidebarCacheAtom` documents its ownership boundary: durable sidebar memory only.
- `InboxNotificationRouter` logs unclassified events at info level and prunes edge detector maps on pane close.
- `InboxNotificationSidebarView.swift` was split into root, components, keyboard, focus bridge, and activation files.
- The old tautological sidebar view test was replaced with mounted draft-consumption behavior.
- Secure input true-edge is an inbox notification as `.terminalSecureInputRequested`.
- Progress error and renderer unhealthy are edge-triggered inbox notifications.
- Non-error progress, CWD, URL open requests, secure-input state, and scrollbar/output-burst totals are captured as terminal activity state.
- `TerminalActivityRouter` has restart/idempotence, stop, and non-terminal filtering coverage.
- The `"all"` ungrouped sentinel was renamed to `"__ungrouped__"`.
- Dead `InboxFilter.accessibilityDescription` was removed.
- Sidebar cache key wrappers now share one typed implementation while preserving distinct compile-time key aliases.
- `WorkspacePersistor` centralizes JSON encoder construction across persisted workspace files.
- `WorkspacePersistor` payload contracts were split from file I/O: `WorkspacePersistor.swift` owns paths/load/save/quarantine, while `WorkspacePersistor+Payloads.swift` owns persisted schema contracts.
- Store recovery events are typed as `PersistenceRecoveryEvent` and surfaced as global inbox notifications after boot-time buffering.
- `InboxFilterDraftAtom.set(_:)` accepts only concrete filters; clearing is explicit through `clear()` or `consume()`.
- Workspace and inbox persistence have an explicit v1 schema policy: required identity/schema fields fail the file, while recoverable fields keep valid slices and default only that slice.
- `InboxSidebarRootContainer` now takes a typed `InboxSidebarActions` bundle instead of a loose prop-drill of callbacks.

## Bucket 2: Other Plan Or Manual Verification

These are intentionally not implemented as code in this PR.

- Live OSC visual smoke
  - Location: `docs/superpowers/plans/2026-04-23-luna361-phase3c-ghostty-terminal-intelligence-and-osc-smoke.md`
  - Status: manual/native verification still needed.
  - Reason: headless event paths are tested; visual proof requires launching the app and capturing UI evidence.

- Raw terminal output parsing and file-link tracking
  - Location: `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`
  - Status: follow-up.
  - Reason: Ghostty scrollbar totals prove output volume, not output text. Printed file links, diagnostics, and structured agent status need a separate extraction pipeline.

- Approval/security upstream emitters
  - Location: future product/subsystem epics.
  - Status: receive-side inbox routing is ready; upstream source systems are not built here.
  - Reason: Phase 3c explicitly does not invent fake approval/security emitters.

- Future schema migrations
  - Location: `docs/superpowers/plans/2026-04-24-luna361-sidebar-notification-hardening-followup.md`
  - Status: follow-up.
  - Reason: v1 hard-fails unsupported versions; a real migration step only exists once a v2 on-disk format exists.
