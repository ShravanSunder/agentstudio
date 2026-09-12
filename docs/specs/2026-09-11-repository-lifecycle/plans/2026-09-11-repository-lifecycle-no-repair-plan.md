# Repository lifecycle implementation plan — automatic location retention

## Canonical record

- Originating planner: plan-implementation
- Planning result: ready
- Requested terminal: plan-only
- Delivery grouping: single:repository-lifecycle
- PR topology: not-applicable
- Governing basis: reviewed-three-artifact-design
- Requirements: [requirements.md](../requirements.md)
- Specification: [specification.md](../specification.md)
- Program Design: [program-design.md](../program-design.md)
- Review: [complete Claude Fable three-artifact receipt](../../../../tmp/research-workflows/2026-09-11-git-worktree-identity/fable-design-review.txt)
- Current coverage: [parent-verified bounded remediation](../../../../tmp/research-workflows/2026-09-11-git-worktree-identity/design-review-reduction.md)
- Planned source: repo-bugs, c64e3caded34a9cb1e4617592c4cdf44f7bd9146; package pin c8dbd7ef0f344293160b8f7d72d93931328761fd.

This is the sole ready plan. The earlier 2026-09-11-repository-lifecycle-implementation.md is revision-requested and not executable. Review pointers are checkout-local evidence; a handoff must carry them. This plan does not authorize implementation.

## Goal and scope

Correct automatic watched-location disappearance, cold-start reconciliation, same-path return, separate checkout identity, 30-day collection, stale producer/save rejection, and pane continuity. Different canonical paths are independent; no Repair/Locate action or cross-path matching is added. Same-path current-family changes re-parent the existing checkout record under validated package evidence.

The write scope is this app's Core topology/persistence/runtime contracts, App composition/effects, Repo Explorer projection, applicable tests, and the owning architecture docs. No agentstudio-git implementation/pin change is needed: current-path discovery is sufficient. No vendor changes, direct Git/wt data plane, persistent move identity, hidden-items UI, user-folder deletion, or pane/session/undo/history deletion. Explicit Remove/unwatch semantics remain outside the automatic retention change. Live beta/production databases are not repair targets for implementation validation; use isolated fixtures and debug data.

## Current evidence

- FilesystemActor initial inventory is empty; the current complete/partial reducer must be reused rather than replaced.
- Checkout reconciliation matches main role or name and subtracts candidates from a whole family; both conflict with exact-location scoped retention.
- `RepositoryTopologyStore` saves whole snapshots; topology save does not currently share workspace persistence ordering/revision protection.
- Repository availability is a Set and unavailable SQL rows are replaced each save. New timestamp records must survive full save/readback.
- Surface CWD and Undo restoration can preserve hidden facets. Repo Explorer includes unavailable rows, unlike existing launcher filtering.
- Optional live pane facets must clear across every workspace; inspect final migrated schema rather than relying on historical FK definitions.

## Dependency graph

```text
A  Durable absence + exact-location domain transitions
   |
B  Real authoritative scan -> retained/available topology -> pane/scope/UI effects
   |
C  Ordered persistence, stale-save and observation-lifetime rejection
   |
D  Deadline validation -> core collection -> recoverable local cleanup
   |
E  Native/runtime and aggregate proof
```

A is a contract/migration slice consumed immediately by B. B–D are vertical integration slices, kept serial because they share topology mutation and persistence boundaries. Each slice must be buildable and preserve protected behavior; do not land a schema-only change as feature completion.

## A — Canonical absence and matching

Write surfaces: `RepositoryTopologyAtom`, `RepositoryTopologyReplacement`, `WorkspaceMutationCoordinator+RepositoryTopology`, `RepositoryTopologySQLiteSnapshot`, `RepositoryTopologyStore`, core migration and topology repository codecs.

Implement the PD's separate typed repo/worktree absence records under existing owners. Legacy unknown age remains untimed until authoritative validation. Derived unavailable ID/index views replace duplicate writable sets. Add the intended family-with-hidden/collected-main invariant and per-checkout launchability. Remove name-only/main-role matching. Add same-path validated re-parent preconditions and one global unique-location mutation/SQL operation; ordinary unexplained cross-family saves still fail.

Red signal: permanent domain/SQL tests showing repeated disappearance resets/lacks age, same-name cross-path UUID reuse, cross-family same-path collision, and unavailable-main assumptions. Extend existing `RepositoryTopologyAtomIdentityReconciliationTests`, `RepositoryTopologyAtomTests` and paired persistence tests. Use UUIDv7 and populated old-schema fixtures.

Proof: first-write-wins absence, timestamp-preserving unrelated saves, legacy migration/readback, same-path ID reuse, different-path IDs, one-to-one re-parent, independent clone preservation, final-schema foreign-key integrity, and family survival after main-location collection. No fake Git identity invented in fixtures.

## B — Scan-to-user-state integration

Write surfaces: `FilesystemActor+WatchedFolderScanning`, `FilesystemActor+WatchedFolderResultApplication`, `WatchedFolderInventoryReducer`, `RuntimeEnvelopeCore`, `FilesystemGitPipeline`, `AppDelegate+WorkspaceBoot`, `WorkspaceCacheCoordinator`, `WorkspaceSurfaceCoordinator` and Repo Explorer capture/observation.

Pass restored canonical baseline before first scan. Reuse scheduler coverage/generation gates; add the scoped reconciliation receipt and distinguish removed authorization from authoritative filesystem negatives. Patch family memberships from positives/covered negatives rather than replacing a whole family from one source. Retain hidden checkout records and exclude only unavailable launch targets. Ensure empty authoritative scans carry completion evidence.

Run the existing topology effect handler on disappearance; loaded/durable invalid facets clear without affecting pane membership. Remove the temporarily-unavailable deferral for invalid facets and sanitize Undo restore. Keyed Repo Explorer capture observes/filters availability; Panes membership remains independent and expensive grouping remains detached.

Red signal/proof: extend `TopologyEventPipelineIntegrationTests`, `WatchedFolderInventoryReducerTests`, `WorkspaceTopologyBootRepairIntegrationTests`, `WorkspaceCacheCoordinatorRepoMoveTests`, Repo Explorer and pane-CWD integration coverage. Prove closed-app deletion, partial/inaccessible scan preservation, current overlapping scopes, disjoint watched folders sharing one family, main/linked absence independently, hidden row removal without Scanning, pane persistence/navigation unchanged, and same-path return. Early integration gate: real bus/coordinator/SQL/projection connection; scanner fake cases prove policy only, not package discovery.

## C — Prevent old work from restoring retired state

Write surfaces: Git/Forge request/result contracts and coalescers, pipeline registration calls, cache apply paths, `WorkspaceSQLiteDatastore` and its persistence-order extension, topology/workspace capture revisions, local cache/recency save admission.

Implement PD's launch/lifetime revision identity through request admission, queued fact and publication. Guard snapshot, branch, origin, status, PR and awaiting-origin paths, including hide-return with the same UUID. Await/supersede physical unregister through the sole surface/pipeline effect path. Register the cache coordinator's collection admission owner and route conflicting topology mutations through it; no SQL work on MainActor.

Join topology save/collection to ordered datastore admission; reject stale topology captures. Invalid facet pairs are nulled on SQL save/Undo hydration rather than rejecting a pane bundle. Add local save fences/surviving-ID filters for cache/recency re-entry. No epoch stored as move identity.

Proof: real coordinator publication with late facts for old lifetimes; old unregister after new registration; delayed whole snapshots after hide, re-parent and collection; inactive-workspace/Undo stale facets sanitized; no valid pane save rejection. Tests wait on events/state or injected clocks and fully join work.

## D — Retention and cross-database recovery

Write surfaces: new Core retention policy/scheduler, App composition and cache coordinator admission, existing core/local repository/datastore operations, policies and bounded telemetry.

Implement one injected-clock scheduler and PD time anchors, due-scope authoritative revalidation, bounded collection reservation and committed-result publication. Use AppPolicies for the 30-day duration, batch cap and existing-style retry parameters; do not add per-repository loops. Partial/no-longer-authorized scope defers without an expired-deadline spin. Explicit commands retain their separate behavior.

Core collection validates revision/absence/time/coverage and clears invalid optional references across workspaces before deleting eligible rows. Then deterministic local orphan pruning runs against surviving core IDs/keys under local save admission; crashes before local cleanup recover on startup. Protect shared keys, volume cursors, pane recency and unsettled owned activity/promotion operations. No deletion journal or universal history sweep.

Proof: before/exact/after deadline, repeated absence, sleep/restart, observed wall jumps, legacy age, staggered family/member deadlines, return before reservation/commit, cancellation before/after core commit, stale rescan, unavailable local database, crash between DB commits, local resurrection attempt, retry idempotency and preservation of every protected row category. Use populated persistent fixtures and real transactions, with injected faults at commit boundaries.

## E — Complete real-path proof

Use isolated debug data and real package-backed repositories with several linked checkouts. Drive delete/return, independent new location, cross-scope family, and same-path family-change scenarios through the runnable app; do not mutate the user's beta/prod data. Verify visible repository list, stable distinct checkout IDs, panes remaining present/unassociated, no unexpected activation of another terminal, and runtime registration readback. Accelerated/injected time belongs in the established test seam, never a production DEBUG bypass; durable expiry proof comes from the real persistence harness.

Record marker-scoped MainActor occupancy, admitted scan/drain counts, rejected stale outcomes and bounded deadline work separately. No unsupported speedup claim. Static import/lint checks do not alone prove no Git subprocess; inspect changed source and observe package-backed runtime behavior.

## Commands and proof mapping

From repository root, use focused filters on the existing suites via `mise run test:swift -- --filter '<suite>'` during each slice. Run applicable Swift formatting through the repository formatter for changed files, then `mise run lint`, `mise run test:swift`, `mise run test:architecture` if lint tooling changes, and `git diff --check`. Before delivery/PR readiness, `mise run test` is mandatory. No raw swift build/test invocation.

| Spec | Slice | Required proof boundary |
|---|---|---|
| C1/V3 identity | A, B, E | package discovery + global canonical uniqueness/re-parent SQL + live location behavior |
| C2/V1,V6 coverage | B, E | cold-start and multi-scope scan through real event/mutation/projection owners |
| C3/V2,V5 timing | A, D | durable first absence, clock admission, return/commit interleavings |
| C4/V4 panes | B, C, D, E | live and inactive-workspace facet persistence, Undo restore, native pane/navigation continuity |
| C5/V5 cleanup | C, D | two real DBs, snapshot fences, crash/retry and protected-row readback |
| C6/V1,V7 runtime | B–E | actual scope unregister, late-fact rejection, UI capture and measured off-main work |

Stop for a source/contract contradiction, an unprovable identity claim, unrequested package/vendor/schema authority expansion, a new manual Repair flow, a weakened proof gate, or an unrelated tool/environment layer failure. Report the exact scoped gate and return to its owner; do not solve it by guessing a new design. No commits, pushes, merges, or implementation execution are part of this plan-only task.
