# LUNA-361 Sidebar + Notification Hardening Follow-up

**Date:** 2026-04-24

**Status:** Follow-up plan. Do not treat these as Phase 3b/3c merge blockers unless the PR owner explicitly pulls them into the current branch.

## Scope

This plan owns remaining non-blocking hardening that needs a little more design or does not change the current Phase 3b/3c user-visible behavior.

## Items

1. User-surfaced persistence recovery feedback
   - Current state: corrupt persistence files are quarantined and logged.
   - Gap: the user does not get a visible explanation that sidebar/inbox memory reset because a file was corrupt.
   - Decision needed: whether this should be an `AppEventBus` fact, an inbox notification, a status strip message, or a settings/debug surface.

2. Persistence schema-version policy
   - Current state: `PersistableSidebarCache.schemaVersion` round-trips and unknown schema versions currently recover by defaulting fields.
   - Gap: no explicit migration switch exists yet.
   - Decision needed: first real schema migration policy before adding migration scaffolding.

3. Sidebar cache key consolidation
   - Current state: `SidebarGroupKey`, `SidebarCheckoutColorKey`, and `InboxNotificationGroupKey` are separate stable wrappers.
   - Gap: they are repetitive.
   - Decision needed: whether a generic `StableKey<Tag>` improves readability enough to justify the refactor.

4. Persistence implementation cleanup
   - Current state: `WorkspacePersistor` has repeated encoder construction.
   - Gap: small duplication.
   - Follow-up: extract `makeEncoder()` if the file gets touched for another persistence change.

5. Inbox filter draft API cleanup
   - Current state: `set(nil)` and `clear()` both clear the draft; `clear()` reads better at UI call sites.
   - Decision needed: keep semantic method or collapse to a single API.

## Explicitly Not Here

- Raw terminal output parsing, printed file links, diagnostics, and structured agent status updates live in:
  `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`
- Approval/security product emitters remain separate product/subsystem work.
- Live OSC visual smoke evidence remains the manual/native Phase 3c verification artifact.
