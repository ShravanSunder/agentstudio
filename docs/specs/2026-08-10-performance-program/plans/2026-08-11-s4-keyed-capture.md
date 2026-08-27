# Slice 4 Keyed Capture and Off-Main Projection (LUNA-403) Implementation Plan

> Planning result: **ready**. This is a mechanics-only plan record authored by
> `plan-implementation`. It implements the reviewed slice-4 design; requested
> terminal `pr-ready-unmerged` (owner-authorized 2026-08-11), delivery grouping
> `single:s4-keyed-capture`, PR topology `stacked-on:perf/s3-triggers`.

**Goal:** Make Repo Explorer and its row-level presentation consumers observe
only declared entity/facet keys, reuse the existing `EagerDerivedAtomFamily`
for cancellation-safe off-main materialization, and leave MainActor work
bounded to keyed capture plus current-generation binding/publication.

**Governing authority:**

- `docs/specs/2026-08-10-performance-program/requirements.md`
- `docs/specs/2026-08-10-performance-program/2026-08-10-performance-program.md`
- `docs/specs/2026-08-10-performance-program/program-design.md`
- `docs/specs/2026-08-10-performance-program/doc-drift-inventory.md`
- repository operating contract: `AGENTS.md` / supplied worktree instructions

**Delivery context:**

```text
delivery context:
  requested terminal: pr-ready-unmerged (owner-authorized 2026-08-11)
  delivery grouping: single:s4-keyed-capture
  PR topology: stacked-on:perf/s3-triggers
```

**Planned snapshot and applicability:** branch `perf/s4-repo-explorer`, HEAD
`1753666fbc45022ef240951ec22bde1da7e389f4`. This branch is intentionally based
at the slice-1 tip while planning. Before implementation it will be restacked
onto the then-current tip of `perf/s3-triggers`; T0 must reconcile the resulting
HEAD, diff, paths, lint severities, tests, and proof rails before any source edit.
This plan remains applicable only if that reconciliation preserves R14-R16
ownership, the existing `EagerDerivedAtomFamily` lifecycle, and the current
Repo Explorer broad-wake defect. Otherwise T0 returns `[BLOCKER-FOR-PARENT]`.

## Scope and authority anchors

- R-INV requires sequence-end published state to match the ungated reference;
  missing/ambiguous keyed facts proceed rather than suppress
  (`2026-08-10-performance-program.md:163-178`; `program-design.md:70-89`).
- R14 requires writes outside Repo Explorer's rendered/derived entity and facet
  set not to wake its capture, including unrelated worktrees, tabs,
  arrangements, panes, and unrendered Bridge attendance
  (`2026-08-10-performance-program.md:279-287`).
- R15 requires inbox unread, zoom, capability, and attendance facts to wake only
  their owning rows through keyed reads (`2026-08-10-performance-program.md:288-292`).
- R16 keeps heavy projection/snapshot composition off MainActor and forbids a
  full-topology eager input (`2026-08-10-performance-program.md:293-298`).
- The generic lifecycle is already implemented by `EagerDerivedAtomFamily` and
  must be reused unchanged. Product capture adapters remain Core/Feature owned;
  only a concretely proven missing generic operation may expand AtomLib
  (`program-design.md:664-676`).
- Broad arrays/dictionaries remain legal only for persistence, cold bulk
  bridges, and mutation-side accumulation. Hot observation capture uses keyed
  slots plus structural membership generations (`program-design.md:369-398`).
- C1 telemetry stays on existing trace tags and OTLP scrub rules. V2 observes
  capture/apply/worker outcomes; V3 proves deterministic key isolation and
  R-INV; V8 compares completed marker-scoped windows through `perf:report`
  (`2026-08-10-performance-program.md:335-404`).
- R18 assigns slice 4 D3, D15, D16, M1, M2, M3, M5, and M12. R19 requires the
  cleaned observation-capture guard to become blocking in this PR
  (`doc-drift-inventory.md:19-31,41-53`; specification R18-R19).

## Current-source anchor reconciliation

Design citations describe an older `origin/main`. Implementation uses the
restacked current worktree only after T0 repeats this table.

| Design anchor | Current observation at planned HEAD | Planning consequence |
|---|---|---|
| `RepoExplorerView.swift:106-155,641-669` | State/request composition is now `106-166`; the live capture closure is `observeProjectionInputs` at `651-679`, wrapping the computed `projectionRequest`. | Pin the RED test at the real closure/request boundary; do not test only a helper or worker. |
| `RepositoryTopologyAtom.swift:14-58,198-209` | `repos` remains one observable array at `63`; `repo(_:)` and `worktree(_:)` at `142-149` still read `_ = repos`, so nominally keyed lookups wake on any topology write. No topology `AtomFamily` exists yet. | Add Core-owned repo/worktree families plus membership ordering/generation; migrate hot reads while retaining cold snapshots. |
| Repo Explorer broad topology read | `sidebarRepos` maps the full `repositoryTopologyAtom.repos` at `116-118`; its enrichment is already keyed per repo/worktree through `RepoCacheAtom`. | Preserve the keyed cache edge; replace only topology and dependent broad capture edges. |
| Repo Explorer all pane/tab placement | `makeSidebarSnapshot` constructs `WorkspaceTabLayoutDerived` and calls `WorkspaceLookupDerived.paneLocationsByWorktreeId`; that derived reader traverses all pane ids/tab ownership. | Introduce a consumer-owned keyed capture adapter over declared pane/tab/worktree keys; no new global lookup owner. |
| Repo Explorer Bridge attendance | `bridgePaneCommandCandidatesByWorktreeId` calls injected `bridgeAttendanceSnapshot()` once and indexes the whole dictionary. `BridgePaneAttendanceAtom` stores one observable dictionary; `ordinal(for:)` is not slot-isolated. | App composition supplies a read-only keyed attendance projection; Repo Explorer never imports/mutates Bridge state. |
| Repo cache | `RepoEnrichmentCacheAtom` already owns `AtomFamily` slots and `worktreeFacts(for:)`; tests already prove unrelated worktree cache writes do not wake helper capture. | Reuse unchanged and keep its existing missing-key insertion proof; it is not the documented broad-wake defect. |
| Generic eager seam | `Infrastructure/AtomLib/EagerDerivedAtomFamily.swift:1-150` already owns per-key materialization, identity, readiness, cancellation, removal, and stale completion rejection. | Reuse unchanged. Any proposed new primitive is `[BLOCKER-FOR-PARENT]` unless T0/T2 proves one exact generic operation is absent. |
| `AtomEntityMap` design vocabulary | Current implementation is named `AtomFamily` (`Infrastructure/AtomLib/AtomFamily.swift:27-229`) and telemetry labels it `entity_map`. | Use current `AtomFamily` name in code/tasks; do not invent or rename a primitive for terminology parity. |
| Command presentation | `RepoExplorerCommandPresentationBatch.observeApprovedCapabilityFacts` broad-reads all tabs, zoom map, topology repos, and every pane before building visible-worktree requests. | Migrate to visible/declared keys and keyed zoom/pane/topology reads; retain dispatcher authority and advisory snapshot semantics. |
| Zoom and attendance facets | Zoom already exposes `zoomPresentation(forTab:)` over `AtomFamily`; attendance exposes only dictionary-backed `ordinal(for:)`. | Reuse keyed zoom reader; convert attendance storage/read to keyed slots without changing its event semantics. |
| Slice-1 rails | `.mise.toml` has `verify-sidebar-performance-workload` and `perf:report`; the workload captures repo request-build, worker, row-index, apply, and surface-switch metrics. | T0 uses the existing runner for baseline; T6 extends it only for slice-4 outcome/key-wake assertions. |
| R4/R19 lint | `ObservationCaptureKeyedReadsRule` is registered with stable id `agentstudio_observation_capture_keyed_reads`, severity `.report`; inventory agrees. It recognizes named broad calls inside `withObservationTracking`. | After all covered slice-4 findings are clean, flip this rule to blocking and update fixtures/inventory. Do not broaden or weaken it merely to force the flip. |

## Explicit non-goals

- No replacement/rename of `AtomFamily`, `EagerDerivedAtom`, or
  `EagerDerivedAtomFamily`; no second eager lifecycle or per-surface clone.
- No new ambient Feature registry, sibling Feature import, mutable Bridge access,
  persistence schema, cache, coordinator, service, IPC surface, event plane,
  trust boundary, compatibility shim, feature flag, or vendor change.
- No slice-3 trigger/cadence/coalescing work and no slice-5 startup/renderer work.
- No native SwiftUI diff-completion claim. The existing R2 outline proxy remains
  invocation-to-return only.
- No UI presentation, grouping, sorting, command authority, row identity,
  navigation, visibility, inbox semantics, zoom semantics, or Bridge-attendance
  semantic change; only observation/admission and placement of derivation move.
- No broad-reader purge outside slice-4 hot capture. Persistence, cold bridge,
  mutation accumulation, and measured exceptions retain snapshots.
- No threshold relaxation, proof-gate deletion, JSONL fallback, wall-clock test
  sleep, or production `#if DEBUG` hook.

## Numeric V1/V2/V8 gates

These values are immutable plan meaning and must be evaluated on completed,
marker-scoped, fixture-compatible baseline/candidate windows.

| Gate | Required candidate result |
|---|---|
| R14 unrelated-key wake | Across at least 100 mutations each to an unrelated worktree, unrelated tab/arrangement/pane, and unrendered Bridge-attendance key: Repo Explorer capture rebuild count = 0, eager admission count = 0, worker count = 0, and MainActor apply count = 0. |
| R14 relevant/missing key | Each relevant changed key wakes/admit exactly once; insertion into a previously missing declared key wakes/admit exactly once; final projection equals ungated reference. |
| R15 row facets | An unread, zoom, capability, or attendance change for one rendered row invalidates only that owning row/key; unrelated row invalidation and whole-surface projection admission = 0. |
| R16 MainActor capture | Repo `request_build_mainactor` p95 improves by at least 50% versus the immediately preceding compatible baseline and is no worse than 1.0 ms p95; no broad snapshot appears in the admitted eager request. |
| R16 off-main/bind | Projection and row-index construction remain off-main; `mainactor_apply` p95 is no worse than 1.0 ms and no worse than baseline; stale/superseded completions publish 0 results. |
| R16 workload | Repo projection-worker admissions per 100 unrelated-key mutations drop by 100%; relevant-key worker/apply counts equal admitted semantic changes. |
| R20 interactions | Command bar open/close, tab move, and Cmd+R remain p95 <= 2 frames and p99 <= 4 frames; divider remains <= 1 frame per admitted sample; each is at-or-better than the preceding completed baseline. |

A missing completed baseline, fixture mismatch, absent required lane, threshold
miss, or incomplete window fails V8. It does not authorize changing the number
or fixing another slice.

## Scope-expansion record convention

If implementation needs an unlisted file, stop before editing it and append to
the implementation handoff:

```text
[SCOPE-EXPANSION]
task: T<n>
file: <repo-relative path>
current-source evidence: <symbol and line>
design authority: <program-design/spec citation>
why required: <mechanical dependency>
behavior/owner change: none | [BLOCKER-FOR-PARENT]
proof added: <focused gate>
```

Only a reversible mechanical dependency of an already-decided edge is
admissible. A changed owner/public contract/persistence/trust boundary/proof
gate/grouping/threshold, new primitive, or new semantic choice is
`[BLOCKER-FOR-PARENT]`.

## Task DAG

```text
T0 applicability/restack freeze + slice-1 baseline
 └─requires─► T1 pinned unrelated-key wake RED/GREEN
                ├─requires─► T2 topology keyed slots + membership capture
                │              └─requires─► T3 Repo Explorer eager keyed cutover
                └─requires─► T4 keyed sibling/row facets

T3 + T4 ─requires─► T5 deterministic R-INV and lifecycle integration
T5      ─requires─► T6 marker-scoped V2/V8 workload and numeric gates
T5      ─requires─► T7 docs ride-along + slice-4 lint flip
T6 + T7 ─requires─► T8 aggregate current-HEAD proof

Serial write collisions:
  T1 <-> T3 <-> T5  RepoExplorer observation/request and focused tests
  T2 <-> T3         topology adapters and request composition
  T3 <-> T4         declared key-set and command/row facet composition
  T6 <-> T8         current-HEAD workload artifacts

Integration gates:
  T3 first joins declared keys, existing eager lifecycle, worker, and view bind.
  T5 first proves topology plus sibling facets as one lossless projection path.
  T6 first proves the hard cutover through the real authenticated product path.
```

## Standard task table

| Task | Outcome | Depends on | Primary proof |
|---|---|---|---|
| T0 | Freeze restacked applicability, lint/doc inventory, and completed baseline | — | read-only anchors + `verify-sidebar-performance-workload --baseline` + `perf:report` |
| T1 | Prove and fix the documented unrelated-key capture wake first | T0 | failing then passing real observation-capture test |
| T2 | Give topology keyed repo/worktree slots plus membership ordering | T1 | missing/relevant/unrelated membership and slot tests |
| T3 | Hard-cut Repo Explorer to declared keyed capture and existing eager family | T2 | eager lifecycle, off-main worker, current-generation bind tests |
| T4 | Key Bridge attendance, zoom/capability, inbox/read-row facets | T1 | owning-row-only observation tests |
| T5 | Prove full R-INV, cancellation, removal, and no broad hot reads | T3,T4 | reference-vs-keyed sequence matrix + architecture fixtures |
| T6 | Prove numeric V2/V8 gates on Victoria | T5 | completed candidate vs baseline report |
| T7 | Resolve slice-4 docs and flip applicable lint blocking | T5 | V7 diff + V5 output |
| T8 | Run full current-HEAD quality, tests, manual, and telemetry proof | T6,T7 | focused + aggregate + authenticated product proof |

## T0 — Freeze restacked applicability and baseline through slice-1 rails

**Files:** no edits. Proof artifacts remain under repo `tmp/` or the runner's
existing `/tmp/agentstudio-sidebar-performance` root.

**Mechanics:** after the parent restacks this branch on the exact
`perf/s3-triggers` tip, record branch/HEAD/base, `git status`, diff, changed
upstream owners, and line-resolved versions of every anchor table row. Confirm
`scripts/perf-report.sh`, `mise run perf:report`, and
`mise run verify-sidebar-performance-workload` are present and runnable. Run
the slice-1 rails baseline before source edits:

```bash
git status --short --branch
git rev-parse HEAD
git merge-base HEAD perf/s3-triggers
mise run observability:up
mise run verify-sidebar-performance-workload -- --baseline
mise run perf:report -- --channel debug --lane performance.sidebar
mise run lint
```

Record completed marker, fixture keys/cycles, all repo request-build/worker/
row-index/apply p95 and counts, outline outcome/waste, R1 lanes, and current
`agentstudio_observation_capture_keyed_reads` findings/severity. The baseline
must include `AGENTSTUDIO_TRACE_TAGS=performance,atoms` when atom-edge
attribution remains necessary after the existing R2 probe; do not add a new
runner or telemetry lifecycle.

**Stop:** `[BLOCKER-FOR-PARENT]` if restack changes R14-R16 ownership, removes
the defect, lacks slice-1 rails/completed comparable windows, conflicts with
local work, or requires a new semantic decision. Do not begin T1.

## T1 — Pin the real unrelated-key wake RED, then establish keyed capture

**Files:**

- Modify: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewProjectionHelperTests.swift`
- Modify: `Tests/AgentStudioTests/Architecture/RepoExplorerHotPathArchitectureTests.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift`

**Authority:** R14/V3 and the current wake path
(`program-design.md:302-347`; specification R14).

**Red-first mechanics:** build the fixture around the actual
`observeProjectionInputs`/`projectionRequest` dependency path, with counters at
capture request build, eager admission/worker, and apply. Render one declared
repo/worktree/pane/tab set, then mutate separately: a different topology
worktree, a different tab/arrangement/pane, and a Bridge attendance key absent
from the rendered set. The pre-change test must fail because the closure wakes
and rebuilds from `repos`/all placement/attendance even if request-key equality
later prevents worker admission. Do not use the already-green repo-cache helper
test as the RED.

```bash
mise run test:swift -- --filter "RepoExplorerViewProjectionHelperTests"
mise run test:swift -- --filter "RepoExplorerHotPathArchitectureTests"
```

Implement the smallest capture seam that reads a declared key set and delegates
key materialization to T2/T3 owners. Preserve force/initial admission and
uncertain/missing-key progress. GREEN requires zero capture rebuilds for each
unrelated mutation and exactly one for a relevant mutation.

## T2 — Add Core-owned keyed topology slots and structural membership

**Files:**

- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomFamily.swift` only if
  tests prove an existing package operation, not a new primitive, is missing
- Modify: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/RepositoryTopologyAtomTests.swift`
- Modify: `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomFamilyTests.swift` only for an admitted generic-operation expansion

**Authority:** Core topology ownership and the reuse resolution
(`program-design.md:349-376,664-676`).

**Mechanics:** retain canonical mutation ownership in
`RepositoryTopologyAtom`, but pair it with `AtomFamily<UUID, Repo>` and
`AtomFamily<UUID, Worktree>` slots plus an ordered membership revision/read.
Insert/remove/reorder changes membership; metadata changes wake only the owning
slot. `repo(_:)`/`worktree(_:)` hot reads use the slots rather than `_ = repos`.
Keep `repos`, dictionaries, and `captureReadSnapshot()` for persistence, cold
bulk bridges, path resolution, and mutation accumulation; classify their
callers in T7 rather than deleting them.

**Red-first proof:** tests first show unrelated metadata currently wakes a
reader of another id, then prove relevant update, missing-slot insertion,
removal, reorder/membership, equal write suppression, and cold snapshot parity.
Use Swift Testing/`withObservationTracking`; no sleeps.

```bash
mise run test:swift -- --filter "RepositoryTopologyAtomTests"
mise run test:swift -- --filter "AtomFamilyTests"
```

## T3 — Reuse `EagerDerivedAtomFamily` for Repo Explorer keyed projection

**Files:**

- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift` only if request/result composition must expose the existing pure projector
- Create or modify one Feature-owned keyed capture adapter adjacent to Repo Explorer models
- Modify: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionWorkerTests.swift`
- Modify: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`
- Modify: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewProjectionHelperTests.swift`
- Modify: `Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomFamilyTests.swift`

**Authority:** R14/R16 and the selected component tree
(`program-design.md:349-436,664-676`).

**Mechanics:** compose an immutable Sendable request identity exclusively from
declared repo/worktree/pane/tab/cache/facet keyed reads and structural
membership. Admit it to the existing `EagerDerivedAtomFamily`; keep
`RepoExplorerProjectionWorker` pure/cancellation-aware and keep final binding
on MainActor. Remove the Feature-local duplicate generation/task/readiness
lifecycle only after the eager path proves parity; hard cut, no dual path.
Removing a key invokes existing family removal/settlement behavior. Equal
completion becomes current without revision/publication; changed current
generation binds; cancelled/superseded/revoked completion never binds.

**Red-first proof:** add request-identity and lifecycle tests for missing key,
relevant change, unrelated change, equal completion, supersession, removal
while in flight, stale completion, stop, complete retained set readiness, and
off-main projection/MainActor bind boundary. Tests control operations/events,
not time.

```bash
mise run test:swift -- --filter "EagerDerivedAtomFamilyTests"
mise run test:swift -- --filter "RepoExplorerProjectionWorkerTests"
mise run test:swift -- --filter "RepoExplorerViewTests"
```

**Stop:** a required product concept in AtomLib, a second lifecycle, or an API
beyond one concretely missing generic operation is `[BLOCKER-FOR-PARENT]`.

## T4 — Key sibling and row-level facets without crossing Feature ownership

**Files:**

- Modify: `Sources/AgentStudio/Features/Bridge/State/MainActor/Atoms/BridgePaneAttendanceAtom.swift`
- Modify: `Sources/AgentStudio/App/Windows/RepoExplorerCommandPresentationBatch.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePanePresentationAtom.swift` only for existing keyed-reader composition
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- Modify App composition that injects Repo Explorer's read-only attendance/capability projections, if T0 confirms its current path
- Modify corresponding Bridge attendance, workspace presentation, inbox sidebar, and command-presentation tests

**Authority:** R15 and App-composed sibling read-only projections
(`program-design.md:377-398,414-436`; specification R15).

**Mechanics:** back Bridge attendance with `AtomFamily` and expose a read-only
keyed `ordinal(for:)` projection through App composition. Reuse
`zoomPresentation(forTab:)`; do not read `zoomPresentationsByTabId`. Build
command-presentation requests from visible declared worktree/tab/pane keys, not
all tabs/topology/panes. Give inbox unread/roll-up facts a keyed row reader so a
single notification facet invalidates only that row. Mutable Feature atoms
remain private to their owners; dispatcher remains command authority.

**Red-first proof:** for every facet, observe row A, mutate row B (zero wake),
then mutate/insert row A (one wake and updated value). Add command-presentation
proof that unrelated tab/zoom/topology/pane mutation produces zero refresh and
the relevant visible item still refreshes once.

## T5 — Prove lossless integrated keying and remove broad hot capture

**Files:** focused tests from T1-T4 plus architecture lint fixtures; no new
production owner.

**Authority:** R-INV, R14-R16, V3, and the false-green boundaries in
`program-design.md:601-617`.

**Mechanics/proof:** run a deterministic reference-vs-keyed sequence matrix
covering insertion, removal, reorder, relevant metadata/facet change,
unrelated change, ambiguity, cancellation, supersession, and stop. Compare
complete final projection, row ids/order, command candidates, unread/zoom/
attendance presentation, and published generations. Add Good/Bad lint fixtures
for the actual cleaned capture shapes. Prove hot capture contains no
`repos`/whole topology snapshot, all-tab/pane traversal, attendance snapshot,
or zoom map read; cold callers remain explicitly classified.

```bash
mise run test:swift -- --filter "RepoExplorer"
mise run test:swift -- --filter "BridgePaneAttendanceAtomTests"
mise run test:swift -- --filter "WorkspacePanePresentationAtomObservationTests"
mise run test:architecture
```

## T6 — Extend the existing workload and pass V2/V8 numeric gates

**Files:**

- Modify: `scripts/verify-sidebar-performance-workload.sh`
- Modify existing telemetry projection tests only if new safe outcome/count labels require coverage
- Proof artifacts remain under the runner's established temporary root

**Authority:** C1, V2, V8, R14-R16, R20; reuse the existing runner and C2
report (`program-design.md:583-585`; specification proof table).

**Mechanics:** extend `sidebar-performance-proof` to perform at least 100
fixture-compatible unrelated mutations per R14 class and matching relevant
mutations. Query marker-scoped capture-build, eager admission, worker, apply,
outline proxy, affected-row, and atom slot metrics. Export only safe lane,
outcome, count, and duration dimensions; never raw ids/paths/content. Preserve
the runner's completion record and `perf:report` resolver identity.

```bash
mise run observability:up
mise run verify-sidebar-performance-workload -- --compare
mise run perf:report -- --channel debug --lane performance.sidebar
mise run perf:report -- --channel debug --lane performance.atom
```

Record baseline/candidate identities, fixture keys, sample counts, each numeric
gate, p95s, deltas, and waste ratios. JSONL is not fallback proof.

## T7 — Resolve slice-4 docs and flip keyed-capture lint to blocking

**Files:**

- Modify: `docs/architecture/state/atom_persistence_boundaries.md` (D3; M1-M3, M12)
- Modify: `docs/architecture/structure/component_architecture.md` (D15)
- Modify: `AGENTS.md` or the current owning architecture table source (D16)
- Modify the owning Repo Explorer/sidebar architecture doc for M5; if no
  current owner exists, use the narrowest existing architecture doc and record
  that placement in the inventory
- Modify: `docs/specs/2026-08-10-performance-program/doc-drift-inventory.md`
- Modify: `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/ObservationCaptureKeyedReadsRule.swift`
- Modify its Good/Bad fixtures and rule tests
- Modify: `docs/architecture/structure/architecture_lint_inventory.md`

**Authority:** R18/R19, closed inventory, and C3/V5.

**Mechanics:** document current canonical/structural families, atomic paired
commits and accepted revision, per-pane structural reads,
`PaneObservationResolver`, eager slot population, keyed Repo Explorer capture,
off-main worker/row index, and cold-vs-hot broad-reader classification. Resolve
D3/D15/D16/M1/M2/M3/M5/M12 exactly once without deletion or reassignment.
After T5 proves the cleaned lexical surface has zero findings, change stable id
`agentstudio_observation_capture_keyed_reads` from `.report` to blocking
severity, update fixtures and inventory, and prove it appears in `mise run lint`.
Do not flip the other three R4 rules unless T0 proves their documented surface
is both slice-4-owned and fully cleaned; record `checked—no slice-4-owned flip`
for each non-applicable rule.

**Stop:** if making the keyed-read rule blocking requires an allowlist that
hides the cleaned hot path, weakening its detection, or deleting a gate, return
`[BLOCKER-FOR-PARENT]`.

## T8 — Aggregate current-HEAD proof and manual product observation

Run from repository root after all edits:

```bash
mise run format
mise run test:swift -- --filter "RepositoryTopologyAtomTests"
mise run test:swift -- --filter "AtomFamilyTests"
mise run test:swift -- --filter "EagerDerivedAtomFamilyTests"
mise run test:swift -- --filter "RepoExplorer"
mise run test:swift -- --filter "BridgePaneAttendanceAtomTests"
mise run test:swift -- --filter "WorkspacePanePresentationAtomObservationTests"
mise run test:architecture
mise run lint
mise run test
git diff --check
```

Then repeat T6 on current HEAD; earlier markers are history, not candidate
proof. Manually use the authenticated standard debug-observability product path
to display Repo Explorer, mutate unrelated then relevant fixture entities, and
observe unchanged unrelated rows plus correct relevant row/projection updates.
Query the completed marker with `perf:report` and record what was observed.

**Acceptance evidence:** every command has exit code and pass/fail count;
T1-T5 retain RED/GREEN transcripts; current-HEAD marker and baseline/candidate
identities pass every numeric gate; manual final rows/order/commands match the
reference; formatting/lint/tests/privacy are clean. Missing focused, aggregate,
manual, or live telemetry proof means not done.

## Obligation and proof map

| Obligation | Tasks | Proof |
|---|---|---|
| R-INV | T1-T5 | deterministic ungated-vs-keyed final projection/row/facet sequence |
| R14 unrelated/relevant keyed wakes | T1-T3,T5,T6 | real capture counters + slot/membership tests + zero-wake V2/V3/V8 |
| R15 facet-scoped rows | T4-T6 | row A/B observation tests + affected-row marker counts |
| R16 off-main derivation/bind | T3,T5,T6 | eager lifecycle/executor tests + request/apply/worker p95 gates |
| C1 privacy/telemetry | T6,T8 | safe projection tests + completed marker report |
| R18 D3/D15/D16/M1/M2/M3/M5/M12 | T7 | owning-doc and closed-inventory V7 diff |
| R19/C3 | T5,T7,T8 | Good/Bad fixtures + blocking V5 output |
| R20 no regression | T0,T6,T8 | slice-1 V1 interaction gates vs completed baseline |

## False-green risks and stop/replan conditions

- A helper-only unrelated-cache test is not the defect proof; the real
  Repo Explorer observation closure must stay asleep.
- Request-key equality after broad capture is too late: zero worker with a
  nonzero capture rebuild still fails R14.
- A dictionary lookup inside an `@Observable` whole dictionary is not keyed
  observation. The backing slot must isolate revision/wake behavior.
- Filtering a full snapshot after reading it remains a broad wake and fails.
- Moving existing broad request construction into a detached task still copies
  full topology on MainActor and fails R16.
- Publishing partial retained sets, stale generations, or completion after key
  removal violates the existing eager-family contract.
- Giving Repo Explorer mutable Bridge/Inbox atoms or importing sibling Features
  violates composition ownership even if tests pass.
- Unit/mocked tests, state files, stale markers, JSONL fallback, or metric
  presence without the completion record cannot satisfy V8.
- Stop with `[BLOCKER-FOR-PARENT]` if restack invalidates authority; a new
  generic primitive/owner/public contract/persistence/trust boundary is needed;
  the eager family cannot express the selected lifecycle; a comparable
  completed baseline is unavailable; thresholds miss; or lint blocking needs a
  weakened/deleted proof gate.

## [BLOCKER-FOR-PARENT] items

None at plan authoring time. T0's mandatory restack reconciliation and the stop
conditions above define the evidence that would create one before or during
implementation.

## Canonical plan record

```text
plan path: docs/specs/2026-08-10-performance-program/plans/2026-08-11-s4-keyed-capture.md
originating planner: plan-implementation
planning result: ready
governing planning basis:
  kind: reviewed-three-artifact-design
  Requirements: docs/specs/2026-08-10-performance-program/requirements.md
  Specification: docs/specs/2026-08-10-performance-program/2026-08-10-performance-program.md
  Program Design: docs/specs/2026-08-10-performance-program/program-design.md
  applicability: perf/s4-repo-explorer@1753666fbc45022ef240951ec22bde1da7e389f4; restack-required-before-implementation onto perf/s3-triggers tip
delivery context:
  requested terminal: pr-ready-unmerged (owner-authorized 2026-08-11)
  delivery grouping: single:s4-keyed-capture
  PR topology: stacked-on:perf/s3-triggers
```
