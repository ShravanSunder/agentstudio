# DerivedValue Production Adoption Plan

Date: 2026-07-30

Status: reviewed, implementation-ready

Source HEAD: `207cbe3c18bcb9ccbb96dec2eba085a44d402e5f`

Accepted source:
`docs/specs/2026-07-30-derived-value-production-adoption/2026-07-30-derived-value-production-adoption.md`

Companion boundary:
`docs/specs/2026-07-30-state-lifecycle-sqlite-boundaries/2026-07-30-state-lifecycle-sqlite-boundaries.md`

## Outcome

Make the existing revision-keyed `DerivedValue` primitive real through one
small production adoption:

- canonical tab owners expose complete semantic revisions;
- `WorkspaceTabLayoutAtom` owns one long-lived rich-tab snapshot;
- exactly one existing fleet consumer, `TabBarAdapter`, reads that snapshot;
- existing `tabs` compatibility callers remain unchanged; and
- deterministic tests plus the existing debug/performance proof path show
  unchanged behavior and fewer identical rich-tab assemblies.

This is the target-ready precursor. It does not implement pane memoization,
SQLite lifecycle work, a reactive runtime, dependency injection, generalized
transactions, or a new benchmark framework.

## Source Coverage and Current Evidence

The parent read:

- DerivedValue spec: 432/432 lines;
- companion lifecycle spec: 590/590 lines;
- current `DerivedValue`, tab shell, tab graph, arrangement cursor,
  arrangement composition, tab layout, and `TabBarAdapter` sources;
- existing DerivedValue, tab-layout, TabBarAdapter, and architecture-lint
  tests; and
- current atom and tab-bar telemetry plus the existing performance workload.

Verified current facts:

- `DerivedValue` is internal to `AgentStudioInfrastructure`, tested, and has no
  production constructor.
- `WorkspaceTabLayoutAtom.derived` is computed for every read.
- `WorkspaceTabLayoutDerived.tabs` rebuilds the fleet and currently calls the
  arrangement fleet composition once per shell.
- `WorkspaceTabArrangementAtom` already funnels graph/cursor installation
  through `replaceArrangementStates`; graph and cursor revisions can therefore
  be equality-gated at their actual write owners without changing every
  arrangement command.
- `WorkspaceTabShellAtom` is the sole tab-shell write owner.
- `TabBarAdapter` observes and reads `WorkspaceTabLayoutAtom.tabs` as a complete
  fleet in both its observation registration and refresh path.
- `agentstudio_derived_value_declared_inputs` already rejects ambient
  `atom`, `CoreAtoms`, and `CoreAtomScope` reads inside `DerivedValue`
  closures.
- `performance.atom.derived` already reports compute/cache-hit events, and
  `performance.tabbar.refresh` already measures the selected product surface.

Security context: not applicable. The final change adds no authority, secret,
network, filesystem, persistence, subprocess, IPC, or dynamic telemetry field.
Existing fixed telemetry event and attribute allowlists remain authoritative.

## Scope Guard

In scope:

- package visibility for only the `DerivedValue` type, initializer, and
  `value`;
- equality-gated semantic revisions for tab shells, tab graph, active
  arrangement cursors, active pane cursors, and active drawer-child cursors;
- one immutable `WorkspaceRichTabSnapshot` containing only `orderedTabs`;
- one private lazy `DerivedValue<WorkspaceRichTabSnapshot>` in
  `WorkspaceTabLayoutAtom`;
- one package read-only `richTabSnapshot` accessor;
- one consumer cutover in `TabBarAdapter`;
- focused correctness and architecture tests;
- compute duration on the existing `performance.atom.derived` compute event
  using the already-allowed `agentstudio.performance.elapsed_ms` field; and
- existing detached-debug, atom telemetry, and tab-bar performance proof.

Out of scope:

- changes to the existing `tabs` compatibility implementation or its callers;
- active-tab selection in the rich snapshot;
- pane-derived snapshots or keyed indexes;
- persistence, SQLite, hydration, or save-lane changes;
- new DI, resolver, state aggregate, transaction, or reactive mechanisms;
- new benchmark scripts, thresholds, or workflow jobs;
- new telemetry event names, dimensions, runtime selectors, or export
  destinations;
- unrelated Repo Explorer and sidebar-performance working-tree changes.

## Execution DAG

```text
gate 0: create an isolated native worktree from reviewed plan HEAD
  │
  ▼
slice 1: red tests for revision completeness, cache behavior, and one consumer
  │
  ▼
slice 2: semantic revisions + one rich snapshot + TabBarAdapter cutover
  │
  ▼
focused green gate: Core, Infrastructure, App, and architecture tests
  │
  ▼
terminal proof: lint + build + broader tests + detached debug + minimal A/B
  │
  ▼
one implementation-review-swarm cycle
  │
  ▼
PR wrap-up: exact pushed HEAD checks, threads, mergeability; do not merge
```

The implementation is deliberately serial. The owner revisions, snapshot, and
consumer form one compile-time chain, and parallel edits would create more
integration cost than latency benefit.

## Requirements and Proof Matrix

| Requirement | Owning task | Proof gate and layer | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| DV-01 minimal package access | Slice 2 | Infrastructure/Core build plus access audit | parent-run build and exact diff | implementation HEAD | yes |
| DV-02 one long-lived owner | Slice 1/2 | source-architecture test finds one production constructor and the private lazy owner | focused Swift test and parent `rg` audit | implementation HEAD | yes |
| DV-03 ordered immutable output | Slice 1/2 | direct canonical assembly equals `richTabSnapshot.orderedTabs` in shell order | Core unit test | implementation HEAD | yes |
| DV-04 complete semantic invalidation | Slice 1/2 | shell, graph, active-arrangement, active-pane, and drawer-child mutation matrix; equal/rejected changes do not advance | deterministic Core unit tests | implementation HEAD; no sleeps | yes |
| DV-05 declared pure compute | Slice 2 | existing SwiftSyntax rule plus source inspection; compute reads only captured shell/arrangement owners | architecture lint and parent diff | implementation HEAD | yes |
| DV-06 cheap reads stay cheap | Slice 1/2 | source-architecture test proves `tab(_:)` and other keyed accessors do not reference `richTabSnapshot` | focused static test | implementation HEAD | yes |
| DV-07 exactly one fleet consumer | Slice 1/2 | `TabBarAdapter` reads `richTabSnapshot`; production reference inventory has no second consumer; old `tabs` callers remain | App test, source audit, exact diff | implementation HEAD | yes |
| DV-08 behavior unchanged | Terminal | existing tab mutation/restore and TabBarAdapter suites plus real debug tab interactions | parent-run tests and native app proof | exact candidate PID/worktree identity | yes |
| DV-09 measured reuse | Slice 2/Terminal | existing `performance.atom.derived` reports compute elapsed time; equivalent cache-enabled versus cache-bypassed workload reports evaluations, computes, cache hits, rich-assembly mean/p95/max, and `performance.tabbar.refresh` | focused telemetry tests, existing atom/tab telemetry, and disposable local A/B patch outside the PR | same candidate source, workload, marker shape, trace tags, and fixture | yes + controlled A/B |
| DV-10 no unsupported speed claim | Terminal/review | report fewer assemblies separately from any observed latency; no speed claim without equivalent evidence | parent report and implementation review | final evidence packet | not applicable |
| DV-11 pane gate preserved | Review | no pane snapshot, pane revision, or pane consumer in diff | exact diff review | final PR diff | not applicable |
| PR ready, not merged | Wrap-up | focused/full proof, implementation review disposition, current checks, threads, and mergeability | parent and GitHub state | exact pushed PR HEAD | not applicable |

The performance A/B is intentionally not a new permanent harness. Both runs
use the final candidate wiring and existing workload; the baseline run applies
only a disposable local cache-bypass patch in a separate worktree. This
isolates the cache effect without comparing unrelated commits or adding a
runtime feature flag. `DerivedValue` records compute duration on the existing
fixed `performance.atom.derived` event through the globally allowed
`agentstudio.performance.elapsed_ms` field. No event name, dynamic dimension,
export destination, workload script, or benchmark framework is added.

## Gate 0 — Isolate and Re-anchor

1. Confirm `origin/main`, current dirty paths, and the exact source inventory.
2. Commit this reviewed plan without unrelated files.
3. Confirm the exact reviewed plan commit with:

   ```bash
   git cat-file -e HEAD:docs/specs/2026-07-30-derived-value-production-adoption/plans/2026-07-30-derived-value-production-adoption-plan.md
   git show --stat --oneline HEAD
   git status --short
   ```

4. Create a new native Git worktree and implementation branch from that exact
   reviewed plan commit. Do not move, stash, stage, or edit the unrelated Repo
   Explorer and sidebar-performance files in the current worktree.
5. Run `mise run setup` in the isolated worktree.
6. Run the existing focused DerivedValue and tab-layout tests before changes.
7. Record the pre-change `DerivedValue(` production constructor inventory and
   `WorkspaceTabLayoutAtom.tabs` consumer inventory.

The reviewed-plan commit is a prerequisite for worktree creation, not a later
PR-wrap-up step.

Stop and return to design only if the current owner graph no longer matches the
spec or the selected consumer no longer requires a complete rich tab fleet.

## Slice 1 — Write the Failing Contract

Add the smallest permanent tests that fail for the expected missing behavior:

1. A Core rich-snapshot suite proves:
   - shell, graph, active-arrangement, active-pane, and drawer-child changes
     invalidate;
   - equal/rejected changes do not invalidate;
   - output order and content equal direct canonical assembly; and
   - final output after compound replace/restore is not stale.
2. A serialized opt-in atom-telemetry test proves one first compute, one
   unchanged cache hit, and one recompute after a semantic revision. It uses
   the existing trace runtime and queue drain, not a production debug hook.
3. Extend the existing DerivedValue SwiftSyntax rule and fixtures so:
   - exactly one production `DerivedValue` constructor;
   - it is owned by `WorkspaceTabLayoutAtom`;
   - construction outside the explicit approved owner fails lint;
   - only `TabBarAdapter` reads `richTabSnapshot`;
   - `tab(_:)` and other canonical/keyed accessors do not read the snapshot;
   - persistence paths do not reference the snapshot.
4. Extend the existing `TabBarAdapter` tests only enough to pin observation and
   refresh through the named rich snapshot.

Run the focused tests and retain the expected failures before implementation.
Do not weaken the tests to fit the current code.

## Slice 2 — Implement the One Adoption

### Generic primitive

In `Infrastructure/AtomLib/DerivedValue.swift`, change only:

- `DerivedValue` to `package`;
- its initializer to `package`; and
- `value` to `package`; and
- time only cache-miss compute work with `ContinuousClock`.

Keep `revision`, cache storage, and telemetry internals non-package.

Pass the compute duration to `AtomPerformanceTelemetry` and emit it as the
existing `agentstudio.performance.elapsed_ms` attribute on
`performance.atom.derived` compute events. Cache-hit events do not fabricate a
compute duration. Add focused telemetry/projection coverage for the fixed
field; do not add an event, dimension, tag, or selector.

### Canonical owner revisions

Add `@ObservationIgnored` revision storage and read-only semantic revision
values at the actual owners:

- `WorkspaceTabShellAtom`: one revision for shell identity/order/display
  content;
- `WorkspaceTabGraphAtom`: one revision for graph/membership/layout content;
- `WorkspaceArrangementCursorAtom`: declared revisions for active-arrangement,
  active-pane, and drawer-child cursor collections.

Equality-gate each revision at the owner mutation boundary. An accepted change
to one semantic collection advances its revision exactly once; equal or
rejected input advances zero times. Keep active-tab selection outside the rich
snapshot input vector.

### Rich read model

Add an immutable package `WorkspaceRichTabSnapshot: Equatable` with only:

```text
orderedTabs: [Tab]
```

`WorkspaceTabLayoutAtom` owns one
`@ObservationIgnored private lazy var` of
`DerivedValue<WorkspaceRichTabSnapshot>`. Its input vector reads only the
declared owner revisions. Its compute closure:

- captures only `shellAtom` and `arrangementAtom`;
- composes arrangement state once;
- assembles tabs in shell order;
- performs no ambient atom, persistence, I/O, async, or compatibility-fleet
  read; and
- uses exact snapshot equality.

Expose only:

```text
package var richTabSnapshot: WorkspaceRichTabSnapshot
```

Do not route existing `tabs`, `tab(_:)`, persistence, IPC, or other consumers
through it.

### One consumer

Change only `TabBarAdapter`:

- observation registration reads `richTabSnapshot`;
- refresh reads `richTabSnapshot.orderedTabs`;
- all pane, zoom, notification, and display derivation behavior remains
  unchanged.

## Focused Green Gate

Run from the isolated worktree:

```bash
mise run test -- --filter DerivedValueMemoizationTests
mise run test -- --filter WorkspaceRichTabSnapshotTests
mise run test -- --filter WorkspaceTabLayoutDerivedTests
mise run test -- --filter WorkspaceTabBoundaryTests
mise run test -- --filter TabBarAdapterTests
mise run test -- --filter ArchitectureLintCommandTests
mise run test -- --filter RuleParityTests
```

Then audit:

```bash
rg -n "DerivedValue<|DerivedValue\\(" Sources/AgentStudio
rg -n "richTabSnapshot" Sources/AgentStudio
rg -n "\\.tabs\\b" Sources/AgentStudio Tests/AgentStudioTests
git diff --check
```

The expected production inventory is one constructor and one consumer type.
Existing `tabs` callers are expected to remain and are not migration failures.

## Terminal Proof

### Automated and quality

```bash
mise run lint
mise run build
mise run test
```

Report command, pass/fail count when available, and exit code. If repo-wide
tests expose an unrelated failure, preserve the focused result separately and
apply the scope gate before editing anything outside this plan.

### Detached debug product proof

Use the repo-owned background path:

```bash
mise run observability:up
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
  mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Against the exact candidate PID and isolated worktree identity, exercise real
tab create, rename, reorder, select, arrangement switch, pane movement, drawer
selection, remove, and restart/restore behavior through PID-targeted Peekaboo.
The launcher remains detached; target only the candidate PID and never stable
or beta. Capture before/after screenshots for tab labels/order/selection and
drawer state, plus a post-restart restored-state screenshot. Correlate those
screenshots with `verify-debug-observability` process/worktree identity.
Generic startup verification alone is not product proof.

### Minimal performance evidence

Use the existing representative workload and existing telemetry only:

- candidate: cache enabled at exact final source;
- controlled baseline: the same source and workload with a disposable local
  cache-bypass patch in a separate worktree;
- trace selection explicitly includes `atoms`;
- query `performance.atom.derived` explicitly from Victoria because the
  existing workload summary does not include that event;
- report evaluation count, compute count, cache-hit count, and rich-assembly
  elapsed mean/p95/max from the existing event and elapsed field;
- report `performance.tabbar.refresh` count and elapsed distribution;
- identify source commit, patch difference, fixture/workload identity, markers,
  sample counts, and commands.

The required conclusion is only that unchanged evaluations perform fewer rich
tab assemblies while behavior remains correct. Treat latency as observation,
not a claimed improvement, unless equivalent evidence supports it.

## Review, Commit, and PR Boundary

1. Commit the green implementation slice after focused proof.
2. Run exactly one `implementation-review-swarm` cycle against
   `origin/main...HEAD`, with correctness/architecture and proof/scope lanes.
3. Address accepted findings in one follow-up commit; do not cycle reviews
   unless a reviewer identifies a genuine source-truth break.
4. Push and create/update the PR.
5. Use `implementation-pr-wrapup` to report exact pushed HEAD, current checks,
   unresolved comments/threads, mergeability, and proof links.
6. Do not merge.

## Risks and Recovery

- Missing revision advancement can return stale UI. The mutation-family matrix
  is the blocking proof; do not compensate with immutable fleet comparison on
  every read.
- Swift Observation wakeups and DerivedValue memoization are separate. The
  consumer continues observing canonical owners; this PR does not promise a
  new reactive runtime.
- A cross-owner command may expose an intermediate generation during its
  synchronous sequence. The final revision vector must invalidate that
  intermediate result; no transaction framework is added.
- If the new snapshot changes behavior, revert the single consumer to `tabs`
  and remove the snapshot/revisions as one bounded commit. No stored data or
  migration requires rollback.

## Split or Replan Triggers

Return to design instead of expanding when:

- `TabBarAdapter` no longer needs a complete rich fleet;
- complete invalidation requires an owner not named by the accepted spec;
- a required mutation bypasses the canonical graph/cursor replacement boundary;
- the compute needs persistence, ambient atom access, async work, pane
  enrichment, or a new cross-owner transaction; or
- required proof can pass only by adding a generalized benchmark or telemetry
  framework.

## Open Questions

None before implementation. The reviewed spec and current source resolve the
owner, consumer, output shape, and proof boundary.
