# Command Bar Recency Implementation Plan

Status: draft for plan review
Date: 2026-07-25
Baseline HEAD: `5a7bd64690a3566dcb57fdf4d5a6dd34f9ed056c`
Accepted spec:
`docs/specs/2026-07-24-command-bar-recency/2026-07-24-command-bar-recency.md`
Spec SHA-256:
`35750cab71162c958e23b7786eab4fcdc5611d72e0147fb1df03b6f07c736b98`
Revision assignment: `command-bar-recency-sol-plan-revision-v2`
Revision input plan SHA-256:
`6fcd96b84a2be06c39acfc123220cfbf1950850448373d72d3a1e73e74f435d4`

## Source Coverage

- Accepted spec: lines 1-897.
- Goal details:
  `tmp/workflow-state/2026-07-25-command-bar-recency-delivery/details.md`,
  lines 1-309.
- Prior spec review:
  `tmp/spec-review-workflows/2026-07-25-command-bar-recency-review/review-report.md`,
  lines 1-295.
- Revision input plan: lines 1-401.
- Current dirty Command Bar source/test diff and architecture-doc diff inspected.
- Live topology, local persistence, launcher, Command Bar result-session,
  action-success, attended-pane, boot/termination, test, and documentation
  owners inspected.
- Revision re-anchor inspected the existing `RepositoryTopologyAtom` entity/path
  indexes, `RepoPresentationItem` construction, stable-key path resolution,
  repository default-worktree semantics, canonical pane-row construction,
  targeted focus validation, query normalization, and every current
  `RecentWorkspaceTarget`/`local_recent_workspace_target` match.

Existing uncommitted source, tests, docs, and the spec are user work. Re-anchor
every edit against the live diff and preserve it.

## Goal And Boundaries

Implement the accepted contract with the smallest existing seams:

- application-global repository/worktree recency in
  `local_entity_recency`;
- workspace-owned pane recency in
  `local_workspace_entity_recency`;
- separate Command-Bar-owned typed `AppCommand` history in UserDefaults;
- empty-root recent projection for Main, `#`, `$`, and `>`;
- complete canonical search after a meaningful query;
- post-success entity recording, accepted-dispatch command recording, live
  activation resolution, launcher hard cut, accessibility, and current docs.

Non-goals:

- Recent CWD or Recent Tabs;
- session implementation or redesign;
- Git CLI, Worktrunk, or worktree management;
- a generalized activity/event framework, atom family, combined recency state,
  or compatibility path;
- broad source-property renaming;
- launcher redesign;
- merge.

The one-hour target is a simplicity constraint, not authority to weaken proof.
If an accepted proof gate cannot fit the focused implementation, stop and report
the proof gap instead of expanding architecture or silently skipping it.

## Architecture Guard

The accepted architecture is already fixed:

- `RepositoryTopologyAtom`, `Repo`, `Worktree`, `WatchedPath`, enrichment, and
  application recency are global and have no workspace relation.
- Panes, tabs, drawers, workspace cursors/sidebar state, and pane recency are
  workspace-owned.
- `activeWorkspaceId` in a wrapper may select a load/save partition; it does not
  establish entity ownership.
- Direct state owners are `ApplicationEntityRecencyAtom` and
  `WorkspaceEntityRecencyAtom`.
- One narrow persistence wrapper observes both atoms but exposes separate
  application and workspace lifecycle operations.
- Command Bar reads hydrated atoms and live models only.
- `RepositoryTopologyAtom` already owns rebuilt entity indexes. Extend that same
  responsibility with stable-key-to-entity-UUID indexes rebuilt whenever
  topology identity changes, outside Command Bar projection. Narrow stable-key
  lookup methods resolve those UUIDs through the existing `repo(_:)` and
  `worktree(_:)` ID-backed accessors, so metadata-only by-ID patches cannot
  leave cached whole entities stale. This is an implementation detail of the
  accepted existing owner: no new atom, schema, lifecycle, persisted index,
  façade, module, or generalized abstraction.

Stop for user concurrence before adding or changing a schema, atom owner,
module boundary, lifecycle, generalized abstraction, compatibility route, or
repository/worktree workspace relation beyond that contract.

## Execution Strategy

The work is serial. The dirty Command Bar files, persistence lifecycle,
`AtomRegistry`, app boot, launcher/controller, tests, and authoritative docs
overlap too heavily for safe parallel writes.

Slices 1-3 form one compile-integrated hard-cut window. Migration 002 removes
the legacy table immediately, so Slice 1 must also delete the datastore,
repository, codec, and `RepoCacheStore` persistence route that targets that
table. The launcher, activity route, and current dirty Command Bar prototype
still consume the legacy Swift model and in-memory atom surface. Those
unpersisted symbols are deleted only after every remaining consumer has cut over
in Slice 3. This is implementation sequencing, not a compatibility design: add
no new legacy writes, readers, adapters, or dual-write path, and do not treat a
focused sub-slice pass as a whole-product green gate.

```text
gate 0: re-anchor source and establish expected RED tests
  ↓
slice 1: typed atoms + migration + persistence hard cut
  ↓ focused domain and real-SQLite proof + Opus review + parent reduction
slice 2: action recording + pane observer + launcher cutover
  ↓ interaction/lifecycle proof + Opus review + parent reduction
slice 3: root projection + commands + activation + scope/AX
  ↓ Command Bar/view/architecture proof + Opus review + parent reduction
slice 4: authoritative docs + historical classification
  ↓ stale-term/path/link proof
full lint/test/build + debug/native/AX/privacy proof
  ↓
implementation review
  ↓
PR wrap-up and readiness proof; no merge
```

Every reviewer finding is candidate advice. Before an edit, the parent records
`valid`, `invalid`, `out-of-scope`, `deferred`, or `needs-user-decision` with
current source/spec evidence. Architecture-changing findings always need user
concurrence.

## Slice 0 — Re-anchor And RED Proof

1. Reconfirm HEAD, spec hash, dirty-file inventory, migration order, exact
   symbols/files, and test filter names.
2. Preserve the existing prototype as input; do not build recents destructively
   into the canonical root candidates.
3. Add the smallest permanent failing tests for each behavior before its
   implementation:
   - entity validation/MRU;
   - real SQLite lifecycle and hard cut;
   - action recording and pane transitions;
   - root projection/query reversal/activation;
   - typed command history;
   - scope/accessibility contracts.
4. Confirm each RED failure is the expected missing behavior, not unrelated
   worktree health.

Gate: no implementation begins from a test whose failure is unexplained.

## Slice 1 — Typed Recency And Persistence Hard Cut

1. Add the accepted typed models and direct-owner atoms:
   - repository/worktree facts use current symlink-resolved path-derived stable
     keys;
   - pane facts use canonical pane UUIDs captured with workspace identity;
   - deterministic order is timestamp descending, typed key ascending;
   - retention is 15 independently per application kind and per
     `(workspace_id, workspace kind)`.
2. Extend `RepositoryTopologyAtom`'s existing entity-index rebuild with
   repository/worktree stable-key-to-UUID lookup dictionaries. Build keys when
   topology identity changes; narrow lookup methods pass the UUID through
   existing `repo(_:)` / `worktree(_:)` accessors. Command Bar and launcher
   consume those in-memory lookups and never derive stable keys in projection.
3. Append local migration `002`; do not rewrite shipped migration `001`.
   Migration `002` drops `local_recent_workspace_target` and creates the exact
   accepted `local_entity_recency` and
   `local_workspace_entity_recency` tables/indexes.
4. Keep product vocabulary in Swift codecs. SQL owns structural nullability,
   primary keys, uniqueness, and indexes; add no SQL enum-list checks.
5. Add narrow repository/datastore operations and one `EntityRecencyStore`:
   - application restore/save has no workspace parameter and hydrates once;
   - workspace restore/save requires explicit workspace ID and follows active
     workspace transitions;
   - observation starts only after the corresponding lane hydrates;
   - termination flushes both lanes;
   - lane failure defaults only that lane unless physical local corruption
     triggers existing whole-local recovery.
6. Delete the legacy persistence route in the same Slice 1 cut as migration
   `002`: remove datastore recent-target load/save parameters, repository
   storage/codec operations, and `RepoCacheStore` hydrate/capture/observation
   wiring. Build the exact remaining legacy deletion inventory, but defer
   deleting only the unpersisted Swift model/in-memory atom surface until the
   Slice 3 integration cut after launcher, activity, and Command Bar consumers
   have moved. Add no new legacy writes, readers, adapters, or dual-write path.
   Do not import old rows.

Likely files:

- new recency model under `Sources/AgentStudio/Core/Models/`;
- new direct-owner atom file under
  `Sources/AgentStudio/Core/State/MainActor/Atoms/`;
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`;
- `Sources/AgentStudio/Core/Models/RecentWorkspaceTarget.swift` (delete);
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Persistence/SQLiteLocalUXStorage.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Codecs.swift`;
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Storage.swift`;
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`;
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreTypes.swift`;
- new store beside existing persistence wrappers;
- `Sources/AgentStudio/AtomRegistry.swift`;
- app workspace boot and termination files;
- `Tests/AgentStudioTests/Core/Models/RecentWorkspaceTargetCodableTests.swift`
  (delete);
- `Tests/AgentStudioTests/Core/State/MainActor/Atoms/RepositoryTopologyAtomTests.swift`;
- `Tests/AgentStudioTests/Core/Stores/RepoCacheStoreTests.swift`;
- `Tests/AgentStudioTests/Core/Stores/WorkspaceLocalMigrationTests.swift`;
- `Tests/AgentStudioTests/Core/Stores/WorkspaceLocalRepositoryTests.swift`;
- `Tests/AgentStudioTests/Core/Stores/WorkspaceLocalSchemaContractTests.swift`;
- `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift`;
- permanent new recency model/atom/store integration tests.

Gate: domain and real SQLite tests prove validation, per-kind retention,
hydration equivalence, two-table coexistence, global survival, workspace
isolation/cleanup, malformed-row skipping, lane failure isolation,
transactional repository/worktree save, and no enum checks. This focused gate
does not claim whole-product green while legacy consumers still await the
compile-integrated Slice 3 cut.
Topology-atom unit tests prove stable-key lookups refresh after replace/add,
worktree reconciliation, and path-changing topology updates, drop removed keys,
remain equivalent to existing ID lookups, and return entities updated through
both `applyValidatedRepositoryMetadata` and `applyValidatedWorktreeNote`.
Architecture proof requires Command Bar projection to contain no call to
`Repo.stableKey`, `Worktree.stableKey`, `StableKey.fromPath`,
`resolvingSymlinksInPath`, or filesystem APIs.

## Slice 2 — Semantic Recording And Launcher Cutover

1. Record one coherent post-success application interaction at the existing
   repository/worktree action-success owner:
   - repository open records repository;
   - worktree open records worktree and containing repository with one
     timestamp and coherent MainActor mutation;
   - rejected/failed/drill-in activity records nothing.
2. Add one narrow app-owned observer over
   `AttendedPaneDerived.attendedPaneId`:
   - retain the last non-nil identity across temporary nil;
   - record only a transition to a different eligible pane after derived focus
     changes;
   - eligibility means active workspace ownership, `.active` residency, a
     canonical `$` pane row in one tab's active arrangement, and targetability
     by the existing focus command;
   - reject drawer children, backgrounded, pending-undo, orphaned, and
     unreachable panes at recording time; display revalidates the same live
     eligibility before projection and activation;
   - include successful durable-pane creation when the derived read changes;
   - exclude same-pane reassertion, window key loss/regain, management
     entry/exit, failed focus, and restoration/refocus;
   - do not reuse or generalize Inbox-owned `PaneFocusTracker`.
3. Cut the tabless launcher to the application recency atom and live topology.
   Remove `cwdOnly` cards and persisted title/path execution authority. Preserve
   existing repository/worktree continuation behavior only.
4. Re-resolve current live topology/pane ownership immediately before
   activation. Missing targets dispatch nothing, record nothing, prune
   best-effort, keep Command Bar usable, and repair selection.

Likely files:

- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift`;
- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/WorkspaceActivityEvent.swift`;
- `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`;
- new narrow app-owned pane-recency observer near existing app lifecycle
  coordination;
- `Sources/AgentStudio/App/Panes/PaneTabEmptyStateViewFactory.swift`;
- `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`;
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`;
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`;
- boot/termination composition;
- `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`;
- permanent interaction, eligibility, and launcher tests.

Gate: tests prove coherent repository/worktree recording, rejection exclusion,
`A → nil → A`, `A → nil → B`, same-pane repeats, captured workspace identity,
and record/display exclusion for drawer children, backgrounded, pending-undo,
orphaned, unreachable, non-active-workspace, non-canonical-arrangement, and
non-targetable panes. They also prove launcher live resolution and stale
no-dispatch behavior without wall-clock sleeps.

## Slice 3 — Command Bar Projection, Commands, Scope, And Accessibility

1. Keep canonical root candidates complete. Add a pure empty-root projection
   that resolves live entities in bounded in-memory passes:
   - Main: Recent Repositories max 3, Repos, Panes, Tabs, Commands;
   - `#`: Recent Repositories max 5, Recent Worktrees max 5, Repositories;
   - `$`: Recent Panes max 5, then existing tab/pane groups;
   - `>`: Recent Commands max 5, then existing command categories.
   Resolve repository/worktree recency through the topology atom's prebuilt
   stable-key indexes. Do not construct `RepoPresentationItem` as a lookup
   shortcut because its initializer computes `Repo.stableKey`.
2. Make Recent Repository rows live-resolve the current repository and enter
   its existing repository menu in Main and `#`. Omit a recent repository with
   no current launchable worktree. Recent Worktree rows live-resolve the current
   worktree and enter its existing worktree action menu.
3. For Recent Panes, filter out the currently attended pane and every
   live-ineligible pane before applying the visible cap of five.
4. Promote matching canonical repository/pane/command rows out of normal groups
   only while the recent projection is visible. Recent worktrees are
   empty-root-only shortcuts. Promotion reuses each canonical row ID and typed
   entity; `recentItemIds` therefore remains valid fuzzy-score history for that
   same canonical entity.
5. Use one trimmed normalized root query for projection gating and fuzzy input.
   Trimming intentionally removes leading/trailing whitespace before fuzzy
   search while preserving internal whitespace.
   Extend root snapshot identity with empty-versus-meaningful state so it
   rebuilds only when crossing that boundary, not for every query character.
   Meaningful search sees every canonical candidate exactly once.
6. Give every group within a root a distinct priority and add deterministic
   name tie-breaking as a defensive fallback.
7. Add a separate typed `[AppCommand]` MRU in Command-Bar-owned UserDefaults:
   - cap 8, dedupe/move-to-front;
   - record direct commands after accepted Commands-root dispatch initiation;
   - record targeted commands only after a valid target begins dispatch;
   - drill-in/rejected/unavailable activity records nothing;
   - existing `recentItemIds` remains fuzzy-score history.
8. Bind activation to presenting root-session/workspace generations. A
   dismissal, scope/workspace change, or superseding activation invalidates
   late completion.
9. Make Main/Repositories/Panes/Commands root identity visible and accessible.
   Nested navigation retains root and ancestry. Recent rows remain leaves except
   Recent Worktree, which enters the existing worktree action level, and
   canonical targeted-command drill-in.
10. Reuse existing Command Bar view/design-system components for group headers,
   row labels/hints, selection, breadcrumb/back semantics, full disambiguating
   identity, and VoiceOver traits.
11. Complete the compile-integrated hard cut after every consumer above has
    moved: delete `RecentWorkspaceTarget`, `RecentWorkspaceTargetAtom`, legacy
    codecs/table operations, repo-cache payload ownership, the old activity
    event route, and legacy tests. No compatibility reader or launcher-only
    model remains.

Likely files:

- `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`;
- `Sources/AgentStudio/Features/CommandBar/CommandBarResultSession.swift`;
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` and row
  extensions;
- `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`;
- `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`;
- Command Bar views under `Sources/AgentStudio/Features/CommandBar/Views/`;
- `Sources/AgentStudio/App/Commands/AppCommand+CommandBarGroupPriority.swift`;
- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`;
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`;
- `Tests/AgentStudioTests/Architecture/CommandBarHotPathArchitectureTests.swift`;
- corresponding state/data-source/session/controller/view tests.

Gate: RED/GREEN tests prove exact four-root composition, caps, empty-group
omission, canonical promotion/uniqueness, whitespace/meaningful/clear
transitions, snapshot boundary behavior, deterministic ordering, nested
unchanged behavior, safe selection, stale and late activation, typed command
history, scope/breadcrumb models, and accessibility semantics. Focused cases
prove Recent Repository live resolution and entry into the current repository
menu plus no-launchable-worktree omission; Recent Worktree live resolution and
entry into the current worktree action menu; currently attended pane exclusion
before cap five; leading/trailing whitespace trimming passed to fuzzy search;
promotion retaining the canonical row ID; and pairwise-distinct priorities
within each root. The integration gate also compiles the full target, runs the
affected launcher/action/repo-cache/persistence suites, and proves
`RecentWorkspaceTarget`, `RecentWorkspaceTargetAtom`, and
`local_recent_workspace_target` have no live source/test matches.

## Slice 4 — Documentation Reconciliation

Current code and the accepted design drive documentation.

| Document | Required disposition |
| --- | --- |
| `AGENTS.md` | Name real `RepositoryTopologyAtom` and file; describe global topology/enrichment/application recency versus workspace pane/layout/sidebar/pane recency. |
| `docs/architecture/README.md` | Correct atom vocabulary, data map, and topology/store ownership. |
| `docs/architecture/component_architecture.md` | Correct prose, Mermaid, field tables, and file map. |
| `docs/architecture/atom_persistence_boundaries.md` | Remove live recent-target ownership; document both entity-recency owners and separate command history. |
| `docs/architecture/workspace_data_architecture.md` | Describe app-root `local.sqlite`, global topology, workspace partition semantics, and the hard cut. |
| `docs/architecture/appkit_swiftui_architecture.md` | Update only if Command Bar projection/activation/presentation ownership is stale. |
| `docs/architecture/commands_and_shortcuts.md` | Document root groups, query transition, activation, and breadcrumbs. |
| session/pane-runtime docs already dirty | Audit only for direct false ownership claims; preserve user WIP and do not redesign sessions. |
| `docs/superpowers/specs/sqlite/*` | Classify superseded/historical SQLite designs and remove current-authority links; preserve historical bodies. |

Gate: authoritative docs contain no nonexistent
`WorkspaceRepositoryTopologyAtom` type/path, per-workspace topology claim, old
recent-target ownership, or stale per-workspace-`local.sqlite` claim. Historical
matches are allowed only under explicit historical/superseded classification.

## Requirements/Proof Matrix

| Requirement | Slice | Proof layer and evidence | Freshness/fit guard |
| --- | --- | --- | --- |
| Typed feeds, validation, MRU, retention | 1 | domain unit, RED/GREEN | current diff; direct owners only |
| Two tables and schema hard cut | 1 | real SQLite integration/schema inspection | disposable DB after migration 002 |
| Global/workspace lifecycle separation | 1 | store/datastore integration | workspace switch/delete; application rows survive |
| Repository/worktree recording | 2 | mutation unit + action-owner integration | current success seam; no framework |
| Pane attendance recording | 2 | observer transition + composition integration | no sleeps; current derived owner |
| Launcher live cutover | 2 | projector/action tests + native check | no persisted path/title authority |
| Four empty roots and meaningful search | 3 | data-source/result-session unit, including trimmed fuzzy input | current root/session generation |
| Stable-key lookup stays outside projection | 1, 3 | topology-index refresh unit + Command Bar architecture test | topology replacement/path change; forbidden-call scan |
| Recent repository menu navigation | 3 | data-source/controller unit + native check | live re-resolution before entering current menu |
| Recent worktree action-menu navigation | 3 | data-source/controller unit + native check | live re-resolution before entering current menu |
| Pane eligibility and useful cap | 2-3 | observer/projection unit | record/display revalidation; exclude current before cap |
| Safe stale/late activation | 2-3 | controller/action integration + native check | live re-resolution at dispatch |
| Typed command history | 3 | state codec/MRU + dispatch-boundary tests | separate UserDefaults key |
| Scope/breadcrumb/accessibility | 3 | view/AX tests + PID-targeted native/VoiceOver proof | current debug identity |
| No Command Bar hot-path I/O | 1-3 | architecture tests | scan final source/new files |
| No raw recency OTLP export | 1-3 | sentinel projection test + marker-scoped collector query | current run marker |
| Documentation ownership | 4 | diff + stale-term/path/link checks | after code/docs converge |
| Repository quality | terminal | `mise run lint`, `mise run test`, `mise run build` | after final reviewed diff |
| PR readiness | terminal | pushed SHA, blocking checks, comments/threads, mergeability | fresh PR state; no merge |

No RED/GREEN exception is authorized. Screenshots support visual order and
breadcrumbs only; they do not prove activation, focus semantics, stale handling,
deduplication, or query reversal.

## Validation Commands

Re-anchor exact filters before running:

```bash
mise run test -- --filter EntityRecency
mise run test -- --filter PaneRecency
mise run test -- --filter RepositoryTopologyAtom
mise run test -- --filter CommandBarState
mise run test -- --filter CommandBarDataSource
mise run test -- --filter CommandBarResultSession
mise run test -- --filter CommandBarPanelController
mise run test -- --filter CommandBarHotPathArchitecture
```

Terminal automated gates:

```bash
mise run lint
mise run test
mise run build
```

Ownership/removal gates:

```bash
rg -n "WorkspaceRepositoryTopologyAtom|Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift" AGENTS.md docs/architecture
test ! -e Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift
rg -n "RecentWorkspaceTarget|local_recent_workspace_target" Sources/AgentStudio Tests/AgentStudioTests AGENTS.md docs/architecture
```

The searches must return no authoritative matches. Search historical SQLite
artifacts separately and accept old terms only under explicit
historical/superseded classification.

Runtime gates:

```bash
mise run observability:up
scripts/run-debug-observability.sh --print-identity
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

PID-target the current debug app. Exercise real shortcuts, root labels/group
order, meaningful/clear query, keyboard/click activation for every recent kind,
scrolling/focus restoration, stale behavior, duplicate/long-name
disambiguation, and VoiceOver semantics.

PR gate:

```bash
gh pr checks <pr> --watch --interval 120
```

Then inspect current comments, unresolved threads, mergeability, and pushed
commit SHA. Do not merge.

## Reliability, Security, And Recovery

- Treat local SQLite/UserDefaults rows as malformed or stale input.
- Persist stable keys/typed identity/timestamps only; live models authorize
  presentation and activation.
- Persistence/prune failure does not block app boot or roll back a successful
  user action.
- Raw paths, labels, prompts, UUIDs, row payloads, and raw errors do not enter
  new OTLP recency records.
- Use disposable databases for destructive migration tests.
- Product rollback is code rollback plus loss of rebuildable local recency; no
  compatibility import remains.
- Preserve unrelated dirty files and stage only scoped work.
- An unrelated test/toolchain/CI failure is a proof blocker, not authority to
  edit infrastructure.

## Candidate-Review Validation Ledger

| Candidate | Parent classification | Disposition |
| --- | --- | --- |
| Global entities need a workspace relation | invalid | Models, migration 013, and topology store prove global ownership. |
| Preserve prototype promotion from `RecentWorkspaceTarget` | invalid | Conflicts with hard cut and complete meaningful-query corpus. |
| Generalize focus/activity events | out-of-scope | Use direct owner APIs and one narrow pane observer. |
| Rename every `workspaceRepositoryTopology` property | deferred | Broad naming cleanup is a non-goal; correct authoritative type/path docs. |
| Rewrite historical SQLite specs as current | invalid | Classify/link them; preserve historical bodies. |
| Redesign sessions or add session recency | out-of-scope | Audit false ownership claims only. |
| Add telemetry for row identity/path | invalid | Privacy contract forbids raw identifying export. |
| Add another schema/atom/store/lifecycle | needs-user-decision | Requires source evidence and explicit concurrence. |
| Skip native/AX/privacy proof for the time target | invalid | Report a proof gap; do not relabel lower proof. |
| Compute stable-key dictionaries in Command Bar or treat `RepoPresentationItem` as precomputed | valid gap; proposed remedy rejected | Extend existing `RepositoryTopologyAtom` entity-index rebuild with in-memory stable-key lookups; add refresh and forbidden-call proof. |
| Recent Repository behavior can remain implicit | valid | Require live repository-menu navigation and omission without a launchable worktree. |
| Apply Recent Pane cap before excluding current pane | valid | Exclude the attended pane and all ineligible panes before cap five. |
| Leave pane eligibility as an undefined adjective | valid | Record/display must enforce active workspace, active residency, canonical active-arrangement row, and focus targetability; exclude drawer/background/undo/orphan/unreachable cases. |
| Hard-cut file inventory is incomplete | valid | Use the exact Slice 1-3 source/test inventory and final removal search; delete the legacy model and its codec test. |
| Query trimming needs explicit behavioral proof | valid nit | Prove leading/trailing whitespace is removed before fuzzy search and internal whitespace remains. |
| Prescribe a new negative priority band | invalid; already covered | Distinct per-root priorities plus deterministic tie-break are the contract; no arbitrary band. |
| Add a telemetry framework for privacy proof | invalid; already covered | Preserve sentinel projection and marker-scoped collector proof. |
| Recent projection needs different row identities | invalid | Promotion intentionally reuses canonical row IDs/typed entities; existing fuzzy history remains correct. |
| Drop proof to meet the one-hour target | invalid; already covered | Simplicity constrains design; a proof gap stops or splits work. |
| N-2 review note | informational | No plan change. |

## Phase Footer

```text
phase_result: complete
evidence: this plan, full source coverage, live source/path validation, and plan ledger
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: The accepted spec now has a focused serial implementation and proof contract; implementation remains prohibited until parent-validated plan review is ready.
```
