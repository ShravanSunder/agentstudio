# LUNA-361 Sidebar + Notification Hardening Follow-up

**Date:** 2026-04-24

**Status:** Closed as a follow-up bucket. The review items that belonged in the current PR were pulled into the branch.

## Scope

This file records hardening items that were considered separately and then resolved in the current PR, plus the one future-only migration concern.

## Items

1. Future schema migrations
   - Current state: v1 persistence hard-fails unsupported schemas and quarantines/resets through the owning store where appropriate.
   - Gap: no v2 migration exists because no v2 on-disk format exists yet.
   - Decision needed later: when introducing v2, add explicit migration code and tests instead of relaxing v1 decode.

## Pulled Into Current PR

- Sidebar cache key consolidation: `SidebarGroupKey`, `SidebarCheckoutColorKey`, and
  `InboxNotificationGroupKey` now share one typed sidebar-cache key wrapper while preserving
  distinct compile-time aliases at call sites.
- Persistence implementation cleanup: `WorkspacePersistor` now centralizes JSON encoder
  construction for workspace, cache, UI, and sidebar-cache saves.
- Inbox filter draft API cleanup: `InboxFilterDraftAtom.set(_:)` now only accepts a real
  `InboxFilter`; clearing is expressed through `clear()` or consuming the one-shot draft.
- Persistence schema-version v1 policy: required identity/schema
  fields now fail the file, while recoverable fields default only their own slice.
- User-surfaced persistence recovery feedback: stores emit `PersistenceRecoveryEvent`; AppDelegate
  buffers boot-time events until the inbox store is loaded and then creates global inbox
  notifications.
- Workspace persistence file split: file I/O/quarantine remains in `WorkspacePersistor.swift`;
  persisted payload contracts live in `WorkspacePersistor+Payloads.swift`.
- Inbox sidebar callback cleanup: `InboxSidebarActions` replaced the loose callback prop drill.

## Explicitly Not Here

- Raw terminal output parsing, printed file links, diagnostics, and structured agent status updates live in:
  `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`
- Approval/security product emitters remain separate product/subsystem work.
- Live OSC visual smoke evidence remains the manual/native Phase 3c verification artifact.
