# AtomLib v2 State Primitives Implementation Plan

Status: implementation plan, plan-review accepted, pre-implementation
Date: 2026-06-11
Spec: `docs/superpowers/specs/2026-06-11-atomlib-v2-state-primitives.md`

## Goal

Implement AtomLib v2 primitives and the first two measured adoptions:

1. Change-gated state primitives with structural enforcement.
2. Row-1 `RepoEnrichmentCacheAtom` adoption with per-worktree granularity.
3. `RepoCacheStore` revision observation.
4. Per-row hot-surface restructuring for repo explorer, tab bar, and cmd-P.
5. Row-2 derived memoization for hot derived read models.

This plan deliberately does not migrate every atom. Rows 3+ require
measurement or co-located work.

## Non-Goals

- No generic dependency-graph runtime.
- No macro/property-wrapper system.
- No permanent compatibility layer.
- No `WorktreeEnrichment: AtomContentEquatable`.
- No production `#if DEBUG` hooks.
- No wall-clock test sleeps.
- No merge/release/publish.
- No unsupervised tooling drift: changes to `.swiftlint.yml`, `.mise.toml`,
  hooks, lint scripts, boundary scripts, or compile-fail harnesses require a
  synchronous parent review before further Swift edits.

## Source Coverage

- Spec A: 572 lines, read fully after compile-time enforcement edits.
- Handoff packet: 204 lines, read fully.
- Relevant current code inspected:
  - `Sources/AgentStudio/Infrastructure/AtomLib/Atom.swift`
  - `Sources/AgentStudio/Infrastructure/AtomLib/AtomReader.swift`
  - `Sources/AgentStudio/Infrastructure/AtomLib/AtomScope.swift`
  - `Sources/AgentStudio/Infrastructure/AtomLib/Derived.swift`
  - `Sources/AgentStudio/Infrastructure/AtomLib/DerivedSelector.swift`
  - `Sources/AgentStudio/AtomRegistry.swift`
  - `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
  - `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
  - `.swiftlint.yml`

## Open Decisions To Surface

Recommended defaults, but not hidden:

- `AtomEntityMap` box type: use per-domain observable classes for the first two
  adoptions; extract generic only after a third instance proves it.
- Round-one store observation: migrate `RepoCacheStore` only; leave
  `WorkspaceStore` to pane-graph adoption.

## Phase A0 — Completed Spec Review And Normalization

- Completed before this plan-review:
  - `shravan-dev-workflow:spec-review-swarm` ran for the two-spec program.
  - The spec's older comparator wording was normalized to the final
    compile-forced `AtomContentEquatable` policy.
  - Review findings required enforcement to be compile/lint-bound, not
    documentation-only.
  - The two open decisions above remain surfaced, not silently resolved.

Proof:

- Review report says ready or lists accepted edits. No implementation begins
  while blocker/important findings remain.

## Phase A1 — Primitive Foundation And Enforcement

Write surfaces:

- `Sources/AgentStudio/Infrastructure/AtomLib/`
- `Tests/AgentStudioTests/Core/Atoms/AtomLibV2/`
- `tools/atomlib-v2-negative-fixtures/` or another reviewed path outside
  normal SwiftPM target membership and outside normal SwiftLint included paths.
- `.swiftlint.yml`
- `.mise.toml`
- boundary-check script or extension to existing lint scripts

Tooling guard: lint/mise/hook/script edits are security-reviewable. They must
be local-only, no-network, no git-config mutation, and parent-reviewed before
subagents continue with Swift implementation work.

Packet split: implement and parent-review the negative fixture harness,
`.mise.toml` tasks, SwiftLint rule wiring, and boundary ratchets before the
primitive Swift implementation proceeds. The harness must be green under normal
`mise run test` and `mise run lint` while still failing targeted negative cases
for the expected diagnostics.

### A1.1 AtomContentEquatable And AtomValue

- [ ] Add `AtomContentEquatable: Equatable` marker.
- [ ] Add `AtomValue<Value>` with exactly two construction paths:
  - no-comparator initializer only when `Value: AtomContentEquatable`
  - comparator initializer for all other payloads
- [ ] Forbid per-set comparators.
- [ ] Forbid ungated always-fire variants.
- [ ] Track and expose a revision that changes only on accepted changes.

Proof:

- V1 equal write: no observation, no revision bump.
- V2 unequal write: one observation, one revision bump.
- V3 injected comparator: `updatedAt`-only `WorktreeEnrichment` delta does not
  fire; snapshot-only delta does fire.
- Compile proof that a non-`AtomContentEquatable` payload cannot use the
  no-comparator initializer.

### A1.2 Owner-Typed Mutation Token Transaction

- [ ] Add transaction token API so primitive setters require an owner-typed
  token (`TransactionToken<Owner>`) or yielded owner mutator obtainable only
  from the owning atom transaction scope.
- [ ] Make cross-atom token misuse fail at compile time; a token from Atom A
  must not satisfy Atom B's primitive setters.
- [ ] Aggregate revision bumps once at scope exit if at least one write was
  accepted.
- [ ] Make forgetting the bump structurally impossible through the transaction
  API, not a convention.

Proof:

- T1 multi-field mutation bumps aggregate revision exactly once.
- No observer sees a partial tuple.
- Compile-negative fixture proves a token from one owner cannot be passed to
  another owner's primitive setter.

### A1.3 AtomEntityMap

- [ ] Add owner-managed per-key optional slots.
- [ ] `entity(for:)` performs untracked dictionary lookup.
- [ ] Missing-key reads create a slot only for owner-accepted keys.
- [ ] nil-to-value writes fire the slot registrar.
- [ ] removal writes nil and prunes on topology exit.
- [ ] expose membership revision separately from value slots.
- [ ] add internal `boxCount` seam only.

Proof:

- E1 write A does not invalidate B value reader.
- E7 missing-key read later wakes on nil-to-value.
- E2 membership churn for C does not invalidate B value reader.
- E3 value writes do not invalidate membership; add/remove does.
- E4 remove writes nil and prevents resurrection.
- E5 hydrate/clear cycles have exact box counts and deallocation proof.
- E6 compat dict tracking remains coarse-correct until migration.

### A1.4 DerivedValue

- [ ] Add `DerivedValue<Value: Equatable>` beside current `Derived`.
- [ ] Do not replace current `Derived` globally.
- [ ] Inputs drive both revision stamp and compute closure parameters.
- [ ] Compute receives no `AtomReader`.
- [ ] Compute closure is `@Sendable`.
- [ ] Recursive pull ordering reads input `.value` before `.revision`.
- [ ] Own revision bumps only when recompute result changes.

Proof:

- D1 unmoved revisions: zero recompute.
- D2 moved/different: recompute once and bump own revision.
- D3 moved/equal: recompute once and do not bump own revision.
- D4 chained derived does not recompute on equal-result upstream.
- D5 constructor inputs drive stamp and parameters; lint rejects global atom
  access inside `DerivedValue` compute closures.

### A1.5 Enforcement Ratchets

- [ ] Add swiftlint rule banning `atom(\...)` and `AtomScope` inside
  `DerivedValue` compute closures.
- [ ] Add boundary ratchet for no new fleet-sized observable collections.
- [ ] Add boundary ratchet that row-1 compat surface usage may only shrink
  once migration starts.
- [ ] Add a permanent compile-fail fixture script for initializer and
  transaction-token negative cases. The script should compile fixture sources
  that are expected to fail and assert the diagnostic class, without adding
  those sources to the normal app/test target.
- [ ] Add a permanent swiftlint-negative fixture for the `DerivedValue`
  global-access ban outside normal lint paths; the targeted lint task must pass
  the fixture path explicitly.
- [ ] Add explicit `.mise.toml` tasks named
  `check-atomlib-v2-negative-fixtures` and
  `check-atomlib-v2-lint-fixtures`.
- [ ] Wire both negative fixture tasks into the primary `mise run lint` path
  after the normal swift-format/swiftlint/boundary checks, so enforcement cannot
  pass only when a human remembers extra closeout commands.
- [ ] Keep both tasks callable directly for red-first development and failure
  isolation.

Proof:

- `mise run lint` runs both negative fixture tasks and fails if either expected
  diagnostic is missing.
- targeted negative compile/lint scripts fail on intentionally bad fixtures
  before the rule exists and pass after the rule rejects them.
- bad fixtures remain outside normal target membership and normal lint/format
  discovery; `mise run test` and `mise run lint` pass with fixtures present.
- Ratchet baselines are explicit and updated only as part of the migration.

## Phase A2 — Row-1 Guards Before Migration

Write surfaces:

- tests first, especially for sidebar row, tab bar, and cmd-P read models.

Tasks:

- [ ] Add Z1 staleness guard for sidebar row.
- [ ] Add Z1 staleness guard for tab bar.
- [ ] Add Z1 staleness guard for cmd-P row.
- [ ] Add real-atom A1/A2 tests against current baseline before privatization.

Proof:

- Z1 guards are green before migration and remain green after.
- A1 proves per-worktree isolation on real atom after migration.
- A2 preserves facade observation regression behavior until compat is removed.

## Phase A3 — RepoEnrichmentCacheAtom Adoption

Write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- row-1 tests

Tasks:

- [ ] Replace internal fleet dict owners with primitives.
- [ ] Keep same-name compat computed properties temporarily.
- [ ] Add granular `entity(for:)` / membership surfaces.
- [ ] Use construction-time content comparator for `WorktreeEnrichment`.
- [ ] Do not make `WorktreeEnrichment` conform to `AtomContentEquatable`.
- [ ] If Spec B's interim `hasSameCacheContent` helper/gate exists, delete and
  absorb it in this phase. The primitive comparator becomes the single
  production cache-content gate.
- [ ] Ensure `hydrate`, `removeWorktree`, `removeRepo`, `markRebuilt`, and
  `clear` use transaction scope and aggregate revision.
- [ ] Keep raw writes method-mediated.

Proof:

- V/T/E/A rows pass on the real atom.
- Compat properties still satisfy current unmigrated readers.
- No dual Spec B interim gate remains after Spec A row-1 hard cutover:
  `rg "hasSameCacheContent" Sources Tests` returns no production/test gate.

## Phase A4 — RepoCacheStore Revision Observation

Write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- store tests

Tasks:

- [ ] Observe cache aggregate revision and recent-target revision instead of
  all raw dictionaries.
- [ ] Preserve `isRestoringState` suppression.
- [ ] Preserve projection equality before disk write.
- [ ] Keep scope to `RepoCacheStore`; do not pull `WorkspaceStore` into row 1.

Proof:

- S1 accepted-change burst schedules exactly one debounced save.
- S1 equal-write burst schedules zero saves.
- S2 restore does not trigger save.

## Phase A5 — Hot Surface Per-Row Restructuring

Write surfaces:

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- supporting shared/read-model files as needed

Tasks:

- [ ] Move hot row reads from whole compat dictionaries to per-entity handles.
- [ ] Treat `TabBarAdapter` as a hot UI adapter, not a generic long-lived
  aggregate-revision observer. Its migrated path must consume row-scoped read
  models/per-entity handles.
- [ ] Name and implement the `TabBarAdapter` row boundary explicitly
  (per-tab observer/slot or diffed item replacement). A loop over entity
  handles from one aggregate observer does not count as migrated.
- [ ] Name and implement the cmd-P row/build boundary explicitly: command-bar
  item construction, worktree presence building, filtering, and rebuild timing
  are measured together at production scale.
- [ ] Row views consume entity slots and membership revisions.
- [ ] Add structural pin that migrated row views do not accept whole dicts.
- [ ] Delete compat usage per surface only after that surface's Z1 guard
  passes.

Proof:

- R1 hosted probe rows: write X increments only X.
- R2 migrated row surfaces take per-entity handles, not whole dicts.
- Z1 guards stay green.
- Z2 hosted `RepoExplorerView` production-scale fixture updates one row.
- Z3 `TabBarAdapter` proof: 3 tabs / 3 worktrees, mutate worktree X, only tab
  X's item/projection changes; no tracking read of
  `worktreeEnrichmentByWorktreeId` remains in the migrated adapter path.
- Z4 cmd-P proof: 118/163 fixture records command-bar item construction,
  presence map/build, filter, sort, and total rebuild distributions; pure
  `CommandBarSearch.filter` timing is supporting evidence only.

## Phase A6 — DerivedValue Row-2 Migration

Write surfaces:

- `Sources/AgentStudio/AtomRegistry.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- any other row-2 derived named by the plan-review result

Tasks:

- [ ] Convert registry surfaces for migrated deriveds from computed fresh
  structs to long-lived per-registry `lazy var` instances.
- [ ] Leave unmigrated `Derived` and `DerivedSelector` with old semantics.
- [ ] Declare all inputs; no `AtomReader` inside `DerivedValue`.
- [ ] Audit discovered-to-declared input changes.
- [ ] Audit same-mutation derived reads.
- [ ] Audit compute purity and constructor wiring isolation.

Proof:

- D1-D5 pass.
- Fresh test registry does not share cached values with production registry.
- Mutate-each-input tests prove no hidden stale dependency.

## Phase A7 — Rows 3+ Gate

- [ ] Re-profile after row 1 and row 2.
- [ ] Adopt runtime atoms only with measurement or co-located work.
- [ ] Do not expand the AtomLib program into a 16-atom migration without a new
  reviewed plan.

## Requirements And Proof Matrix

| Requirement | Phase | Proof | Layer | Red/Green |
|---|---|---|---|---|
| Equality safety is compile-forced | A1 | V1-V3 + initializer compile tests | unit/compile | yes |
| Transactions prevent torn revisions | A1 | T1 | unit | yes |
| Per-key slots isolate row invalidation | A1/A3 | E1-E7 + A1 | unit | yes |
| Missing-key rows wake when enrichment arrives | A1/A3/A5 | E7 + Z1 | unit/smoke | yes |
| Derived recompute is revision-gated | A1/A6 | D1-D5 | unit/lint | yes |
| Enforcement is not documentation-only | A1 | swiftlint + boundary ratchets | lint | yes |
| Row-1 preserves existing facade until migration | A3 | A2 + compat tests | unit | guard |
| Store observation avoids whole dict tracking | A4 | S1/S2 | integration | yes |
| Hot surfaces actually move per-row | A5 | R1/R2/Z1/Z2 | integration/smoke | yes |
| Hard cutover absorbs Spec B gate | A3 | no dual gate in final diff | review/test | no waiver |

## Validation Commands

Run by phase and again at closeout:

```bash
mise run check-atomlib-v2-negative-fixtures
mise run check-atomlib-v2-lint-fixtures
mise run test
mise run lint
```

Additional workload proof comes from Spec B after row-1/row-2 adoption if the
program executes both specs in one PR stack.

## Review And Execution Route

1. `shravan-dev-workflow:spec-review-swarm` for A0.
2. `shravan-dev-workflow:plan-review-swarm` on this plan.
3. `shravan-dev-workflow:implementation-execute-plan` after accepted review.
4. `shravan-dev-workflow:implementation-review-swarm` before PR readiness.

Claude/Gemini review lanes are run when explicitly requested and available;
otherwise produce copy-paste prompts and record the missing lane.
