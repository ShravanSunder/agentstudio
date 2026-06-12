# SQLite Drawer Persistence: Round-Trip Proof, Crash-Window Tests, Read-Side Validation

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

The SQLite cutover (be44db31, hardened in #158) implements a two-phase commit
protocol (core staged → local completed → core committed) whose crash-recovery
semantics are *deliberately lossy for local UX state* — staged-only recovery
synthesizes `defaultCursorState()` (all drawers collapsed, cursors reset). The
protocol design held up under adversarial audit (two independent "bug" claims
— save reordering and dangling cursor IDs — were refuted by the actor
serialization, the `completed_at = NULL` staging semantics, and hydrate-side ID
validation). What did NOT hold up:

1. **No drawer round-trip test exists.** `WorkspaceStoreDrawerTests` saves but
   never restores; no test proves drawer identity, child ordering, and
   expansion survive save → load.
2. **The lossy crash windows are untested and silent.** Crash between local
   write and core commit, and staged-only restore, are recoverable by design —
   but no test pins the recovery behavior, and the emitted recovery event does
   not say *what* was reset, so a user's drawers silently collapse with no
   diagnostic trail.
3. **Drawer parent linkage is validated only at write time.** A corrupt or
   hand-edited core DB can hand a drawer to the wrong pane at read time.
4. **Quarantine can partially move sidecars and still report cleanly.** If the
   `.db` moves but `-wal`/`-shm` move fails, orphaned sidecars remain and the
   outcome reporting does not distinguish partial success.

## Current Evidence

- `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift` —
  mutation coverage only; the SQLite-save test does not restore and verify.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift:614-625`
  — `defaultCursorState` returns `drawerExpansionByDrawerId: [:]`;
  `WorkspaceSQLiteStoreBackend.swift:877` hydrates expansion with `?? false`.
  Together: any local-state reset silently collapses all drawers.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift:185-198`
  — local completed write and core commit are separate transactions on
  separate databases (inherent to the two-DB design); the
  local-succeeded/core-commit-failed ordering has no test
  (`WorkspaceSQLiteCommitProtocolTests` covers staged-only and
  failed-local-save, not this ordering).
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift:236-240`
  — staging sets `completed_at = NULL` (verified: this is what makes the
  stale-local pairing impossible; keep as a pinned invariant test).
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphValidation.swift`
  (~line 163) — `drawer.parentPaneId == pane.id` enforced on write;
  `WorkspaceCoreRepository+PaneGraphCodecs.swift:106-130` fetch path has no
  mirror check.
- `Sources/AgentStudio/Infrastructure/SQLite/SQLiteSidecarQuarantine.swift:37-51`
  — per-file move with per-file failure collection; verify and tighten the
  success reporting contract for partial moves.
- Refuted during audit (do not re-implement): "stale drawer cursor rows"
  (cursor writes are full-replace —
  `WorkspaceLocalRepository+Storage.swift:19`), "drawer changes dropped on
  quit" (`AppDelegate+Termination.swift` flushes all stores), "dangling cursor
  IDs on staged restore" (token mismatch → defaults; hydrate validates IDs),
  "IOERR should quarantine" (corruption-only is the documented invariant).

## Non-Goals

- No change to the two-phase commit protocol or the two-database split.
- No attempt to make local UX state crash-durable (the lossy window is an
  accepted design decision — this plan makes it *proven and observable*, not
  gone).
- No schema migrations.

## Scope

Write surfaces:
- `Tests/AgentStudioTests/Core/Stores/` — new
  `WorkspaceSQLiteDrawerRoundTripTests.swift` and crash-window additions to
  `WorkspaceSQLiteCommitProtocolTests.swift`.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphCodecs.swift`
  — read-side drawer parent validation.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreTypes.swift`
  (or wherever `PersistenceRecoveryEvent` lives) — enrich the
  local-state-reset recovery event with what was reset (count of drawers
  collapsed, cursors defaulted).
- `Sources/AgentStudio/Infrastructure/SQLite/SQLiteSidecarQuarantine.swift` —
  partial-move outcome reporting.

Read-only context:
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift` —
  save sequencing (actor-serialized; lines 61-139).
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceDrawerCursorAtom.swift:25-38`
  — hydrate/prune validation to mirror in tests.
- CLAUDE.md "SQLite recovery invariants".

## Task Sequence

1. **Drawer round-trip suite.** Save → load → assert: drawer identity, child
   pane IDs *in order*, expansion state, drawer-child placement, and
   arrangement drawer-view cursors all survive. Cases: empty drawer, one
   child, many children, reordered children (save twice), expanded/collapsed,
   drawer deleted between saves (cursor table fully replaced — pin the
   full-replace behavior with an assertion on row count).
2. **Crash-window tests.** Using the existing failure-injection seams from
   `WorkspaceSQLiteCommitProtocolTests`: (a) local write succeeds → core
   commit fails → reload: assert staged core is recovered, local defaults are
   synthesized OR the matching local is repaired — pin whichever the code
   does; (b) staged-only restore with an expanded drawer: assert drawers come
   back collapsed AND a recovery event reporting the reset is emitted (this
   will fail until task 4). Also pin the `completed_at = NULL` staging
   invariant with a direct repository test so a future refactor cannot
   reintroduce the stale-local pairing.
3. **Read-side drawer parent validation.** In the fetch path, throw the
   existing `drawerParentMismatch` error when a fetched drawer's
   `parent_pane_id` does not match the decoded pane; test with a hand-corrupted
   fixture DB.
4. **Recovery event enrichment.** When local state is synthesized or repaired,
   include counts (drawers reset, cursors defaulted) in the recovery event so
   the inbox `persistenceRecovery` notification (already non-auto-clearable)
   tells the user what was lost. Wire through the existing
   `recoveryReporter` path; no new UI.
5. **Quarantine partial-move reporting.** Make the quarantine outcome
   distinguish full vs partial sidecar moves; on partial move, log loudly and
   include the leftover filenames. Test with a read-only `-wal` fixture.

## Proof Gates

- Red/green: task 1 suite must fail if drawer ordering or expansion mapping is
  broken (validate by locally inverting the `?? false` default); task 2b fails
  before task 4 lands.
- Focused validation: `mise run test -- --filter "DrawerRoundTrip"`,
  `mise run test -- --filter "CommitProtocol"`,
  `mise run test -- --filter "SidecarQuarantine"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: create drawers, expand, quit, relaunch — drawers restore expanded;
  then simulate the lossy path (delete the local `<workspace>.local.sqlite`
  while app is closed), relaunch — drawers collapsed AND a persistence
  recovery notification appears in the inbox.

## Stop Conditions

- Stop if round-trip tests reveal an actual ordering or identity bug in the
  live path (not just missing coverage) — report the failing case before
  patching the production code; the fix may need its own plan.
- Stop if enriching the recovery event requires changing the
  `PersistenceRecoveryEvent` shape consumed by other stores — enumerate
  consumers and confirm before widening.

## Risks

- Fixture DBs for corruption tests can be brittle across GRDB versions — build
  them programmatically in-test (write valid DB, then corrupt bytes), never
  check in binary fixtures.
- Read-side validation (task 3) turns previously-silent corrupt reads into
  thrown errors; confirm the caller path treats this as a recoverable load
  failure (quarantine/rebuild), not a crash.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-sqlite-drawer-persistence-proof.md
Start by validating the plan against current git state before editing files.
Tasks 1-2 are test-first and define behavior; task 4 makes 2b pass. Tasks 3
and 5 are independent slices. Parent owns integration and final proof
(mise run test, mise run lint).
```
