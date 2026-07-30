# Pane Toolbar MainActor Saturation Hotfix

Date: 2026-07-29
Status: implementation plan
Implementation baseline: `origin/main` at `ad975f98c4bc75f021b651269fdbdb03d10c2c81`

## Outcome

Restore responsive terminal typing and display by removing fleet-wide pane
derivation and repository-topology enrichment from pane-toolbar rendering.

The hotfix preserves Pane Zoom, Viewer, toolbar, command, target, and lifecycle
semantics. It does not roll back SwiftPM modularization or create a new state,
cache, dependency-injection, observation, or performance framework.

## Why this is the fix

The `v0.0.67` production sample records one 3.1-second SwiftUI transaction with
the dominant MainActor path:

```text
PaneSegmentSlotView.body
  -> normalPaneSurfaceToolbarPresentation
  -> canExecutePaneSurfaceViewerCommand
  -> zoomCommandCapability
  -> mainPaneTabIdByPaneId
  -> WorkspacePaneAtom.pane
  -> WorkspacePaneDerived.displayFacets
  -> RepositoryTopologyAtom.repoAndWorktree
```

The toolbar needs facts about one pane: content eligibility, drawer-child
status, owning tab, Zoom presentation, and Viewer worktree availability. It
does not need rich display metadata or a map of every pane.

## Source coverage

The plan is grounded in:

- all 396 lines of the accepted Pane Zoom UI contract;
- all 219 lines of the accepted AgentStudio performance-boundaries contract;
- the complete production sample at
  `/tmp/AgentStudio_2026-07-29_184913_9j1o.sample.txt`;
- the released toolbar/capability call path in
  `PaneTabViewController.swift`, `FlatPaneStripContent.swift`,
  `ZoomCommandCapabilityPolicy.swift`, `WorkspacePaneAtom.swift`,
  `WorkspacePaneGraphAtom.swift`, `WorkspacePaneDerived.swift`, and
  `WorkspaceTabLayoutAtom.swift`; and
- the existing Pane Zoom controller, toolbar-presentation, and tab-layout
  tests.

Planning used two focused lanes: the completed high-reasoning history/code-path
investigation and a parent-owned high-reasoning validation/proof pass. No new
planning swarm is needed for this bounded hotfix.

## Requirements

### H1 — Render work is candidate-local

Normal and Zoom toolbar presentation must inspect only the source pane and its
owning tab. It must not enumerate all tabs/panes or construct rich `Pane`
display models.

### H2 — Capability API cannot request the pane fleet

`ZoomCommandCapabilityPolicy` must accept one candidate pane's narrow facts
rather than `mainPaneTabIdByPaneId` and `zoomEligiblePaneIds` fleet
collections.

### H3 — Viewer resolution avoids rich pane derivation

Viewer availability must read durable pane-graph facets directly, then perform
only the already-required worktree-id validation, CWD topology lookup, and sole
worktree fallback.

### H4 — Product behavior is unchanged

Explicit and untargeted Zoom must retain enter, cancel, retarget, and resume
behavior. Drawer children and nonterminal panes remain ineligible. Viewer
availability and fallback behavior remain unchanged.

### H5 — The production hot stack is absent

Under terminal output and typing, a fresh debug-process sample must not contain
`mainPaneTabIdByPaneId` and must not reach `WorkspacePaneDerived`,
`displayFacets`, or `repoAndWorktree` from pane-toolbar capability evaluation.

## PR 1 — Surgical runtime hotfix

### Task 0 — Isolated baseline

1. Create a fresh hotfix worktree from exact current `origin/main`.
2. Confirm the worktree is clean and record the baseline SHA.
3. Preserve the production sample as the before evidence.
4. Do not copy production workspace state into the debug data root.

Checkpoint: exact baseline and sample path are recorded before edits.

### Task 1 — Make capability input candidate-local

Change `ZoomCommandCapabilityPolicy` to consume one optional candidate record:

```text
pane id
owning tab id
is eligible
```

The controller selects the candidate:

- explicit pane when the command has a pane target;
- active pane when the command is untargeted; or
- no candidate when there is no relevant pane.

Keep active-tab identity and per-tab Zoom-source state as separate inputs.
Delete the fleet-shaped `mainPaneTabIdByPaneId` and
`zoomEligiblePaneIds` inputs.

Add focused policy tests before implementation and observe the expected
compile/test failure against the old fleet-shaped contract. Cover explicit and
untargeted enter/cancel/retarget/resume, wrong-tab activation, drawer-child
rejection, and ineligible content.

Checkpoint: the policy test suite passes and its API cannot accept pane-fleet
collections.

### Task 2 — Cut rich derivation from toolbar and Viewer reads

In `PaneTabViewController`:

1. Resolve toolbar content and parent/main-pane status from
   `paneAtom.graphAtom.paneState(paneId)`.
2. Resolve the owning tab ID through the existing indexed
   `WorkspaceTabGraphAtom.tabID(containingPane:)` lookup exposed by the
   read-only tab-layout facade.
3. Use the same direct graph-state content check for targeted Viewer
   availability and active Zoom Viewer availability.
4. Reimplement `resolvedViewerWorktreeId(forPane:)` from graph-state facets:
   validate an existing worktree id, otherwise resolve the stored CWD, then
   preserve the existing sole-worktree fallback.
5. Use the indexed pane-owner lookup for normal and Zoom toolbar presentation
   instead of reconstructing tabs or scanning `tabs`.
6. Delete `mainPaneTabIdByPaneId`.

Do not cache toolbar presentations. Do not add a new observable projection.
The direct candidate-local path is measured first.

Checkpoint: source tracing from `PaneSegmentSlotView.body` reaches no rich
`WorkspacePaneDerived` call and performs no fleet enumeration.

### Task 3 — Behavioral regression proof

Run the existing Zoom/controller tests plus new narrow-policy tests. Add or
extend cases only where the refactor could change behavior:

- terminal versus every nonterminal content type;
- main pane versus drawer child;
- active versus inactive tab;
- explicit versus untargeted command;
- enter/cancel/retarget/resume;
- valid stored worktree id;
- stale stored worktree id with CWD resolution;
- sole-worktree fallback; and
- no available worktree.

Do not add wall-clock unit tests or production test hooks.

Checkpoint: behavior parity is green before runtime claims.

### Task 4 — Runtime performance proof

1. Run `mise run setup`, the focused Swift tests, `mise run lint`,
   `mise run test-fast`, and `mise run build`.
2. Start the shared observability stack.
3. Launch the isolated debug app through
   `mise run run-debug-observability -- --detach`.
4. Exercise a multi-pane terminal workspace with sustained terminal output
   while typing and switching panes.
5. Capture a fresh five-second process sample during the workload.
6. Run `mise run verify-debug-observability`.
7. Compare the sample and marker-scoped performance metrics with the
   production evidence.

The runtime gate passes only when:

- typing/display are responsive during the workload;
- the toolbar stack contains no fleet map or rich pane derivation;
- no single pane-toolbar SwiftUI transaction dominates the sample as it did in
  production; and
- the debug verifier confirms the live candidate process and marker.

If candidate-local reads still dominate the sample, stop. That is evidence for
a separate narrow keyed-observation design; it is not permission to add one
inside this hotfix.

### Task 5 — Review and release readiness

Run one bounded implementation review against exact `origin/main...HEAD`.
Verify the diff contains only the policy input, controller read path, tests, and
this plan. Push a hotfix PR only after exact-head tests, lint, build, runtime
sample, and observability receipts are recorded.

## Requirements and proof matrix

| Requirement | Owning task | Proof | Layer | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| H1 candidate-local render work | 1, 2 | source trace and policy API shape | static/unit | exact hotfix HEAD | yes |
| H2 no fleet-shaped capability API | 1 | focused policy compilation/tests | unit | exact hotfix HEAD | yes |
| H3 no rich Viewer pane derivation | 2, 3 | worktree-resolution behavior cases and source trace | unit/static | exact hotfix HEAD | yes |
| H4 unchanged Zoom/Viewer behavior | 3 | existing controller and toolbar suites | unit/integration | exact hotfix HEAD | yes |
| H5 production hot stack absent | 4 | PID-bound sample, live interaction, Victoria verifier | runtime/manual/observability | fresh PID and marker from exact HEAD | baseline/candidate |

## Execution DAG

The hotfix is serial because the policy API and controller call site change
together:

```text
gate 0: fresh origin/main worktree + baseline receipt
  -> task 1: candidate-local policy contract + failing tests
  -> task 2: controller cutover + delete global scan
  -> task 3: focused behavior parity
  -> task 4: lint + test-fast + build + debug workload sample
  -> task 5: one exact-head implementation review
  -> hotfix PR
```

## Write surfaces

Expected:

- `Sources/AgentStudio/Core/Actions/ZoomCommandCapabilityPolicy.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- one focused Core policy test file or the nearest existing policy test file
- `Tests/AgentStudioTests/App/PaneTabViewControllerZoomCommandTests.swift`
  only if behavior coverage is missing

Not expected:

- `Package.swift`
- atom ownership or registry files
- terminal accumulation/runtime files
- `FlatPaneStripContent.swift`
- CI, benchmark, release, resource, IPC, or persistence files

An unexpected write outside the expected set triggers a scope check before it
lands.

## Rollback and risk

The source fix is a pure read-path and policy-input cutover. It writes no
durable state and adds no migration. Rollback is reverting the hotfix commit.

Primary risk: raw pane-graph facts might accidentally differ from the current
rich `Pane` behavior for Viewer worktree resolution. Task 3 explicitly proves
the existing stored-id, CWD, stale-id, sole-worktree, and unavailable cases.

Secondary risk: candidate-local reads may remain broadly observable and still
recompute frequently. Runtime sampling decides that question. A keyed
observation slice is deferred unless the candidate sample proves it necessary.

Security context: not applicable. The hotfix changes no auth, IPC authority,
filesystem authority, secrets, network protocol, or subprocess behavior.

## PR 2 — Benchmark hardening follow-up

PR 2 starts only after the runtime hotfix is proven. It has two non-negotiable
outcomes:

1. remove hidden display enrichment from the foundational pane accessor; and
2. make performance regression evidence repeatable and CI-enforced.

PR 2 is incomplete unless both outcomes land. Benchmark hardening must not
preserve the ambiguous `WorkspacePaneAtom.pane(_:)` behavior that made the
regression easy to introduce.

### Required canonical-pane hard cut

`WorkspacePaneAtom.pane(_:)` was originally a direct lookup into stored
`[UUID: Pane]`. The SQLite pane-graph cutover preserved that signature while
changing it into an uncached rich projection through `WorkspacePaneDerived`.
The projection resolves repository topology and applies repository enrichment
on every read. The cheap-looking compatibility API now has 153 static
product-source references spanning legitimate display consumers and structural
hot-path consumers.

PR 2 must:

1. Inventory every production and test consumer of `paneAtom.pane(...)`,
   `paneAtom.panes`, and `WorkspacePaneDerived`.
2. Restore a canonical pane read that composes only pane graph state and the
   drawer cursor. It must not depend on `RepositoryTopologyAtom`,
   `RepoEnrichmentCacheAtom`, CWD containment lookup, or display-facet
   enrichment.
3. Route consumers that genuinely need enriched labels, repository context, or
   search metadata through an explicitly named display projection such as
   `PaneDisplayDerived`.
4. Route structural predicates, command availability, focus, drawer, lifecycle,
   and hot render consumers through canonical graph facts or another
   explicitly cheap structural read.
5. Remove the ambiguous rich compatibility behavior completely. Do not retain
   parallel old/new pane lookup paths, a compatibility shim, or a hidden cache.
6. Preserve behavior with focused tests for command-bar/search presentation,
   notifications, IPC snapshots, restore/persistence, worktree resolution, and
   pane display labels.
7. Add an architecture/source gate proving the foundational pane accessor
   cannot import or retain repository-topology and enrichment dependencies.

The hard cut may use multiple reviewable commits inside PR 2, but it remains an
absolute acceptance requirement for that PR.

### Required hidden-cost audit

The pane accessor is one confirmed instance of a broader failure mode: an API
whose name and type imply a cheap local read while its implementation performs
fleet enumeration, rich reconstruction, or cross-atom resolution on the
MainActor.

PR 2 must inspect the current product source for:

- `@MainActor` and `@Observable` accessors backed by `Derived` construction;
- singular lookup names such as `pane`, `tab`, `state`, `value`, `current`, or
  `presentation` whose implementation enumerates a collection;
- computed properties that reconstruct full dictionaries or arrays on every
  access;
- SwiftUI `body` expressions and callbacks that synchronously invoke command
  availability, topology, URL normalization, enrichment, or fleet lookup;
- derived projections that depend on atoms outside their canonical ownership
  slice; and
- compatibility facades whose implementation cost changed while their old
  signature and name remained stable.

The audit must trace in both directions:

1. start from suspicious accessor implementations and identify every
   synchronous product caller; and
2. start from hot SwiftUI render, command-availability, focus, lifecycle, IPC,
   and notification paths and trace their reads back to the implementation.

Name-based search is only candidate discovery. A cheap-looking symbol is not
cleared until its implementation and relevant callers have been inspected.

For each finding, PR 2 must record and enforce one disposition:

```text
structural-safe
  cheap candidate/key-local read; no action

intentional-display
  rich work is required and the API/call site names it explicitly

cutover-required
  hidden or hot work is replaced with a canonical/key-local read
```

PR 2 must carry a compact audit ledger with one row per candidate:

```text
symbol | hidden work | synchronous callers | disposition | action/proof
```

The acceptance gate is zero unclassified candidates and zero unresolved
`cutover-required` findings. `intentional-display` findings must use names and
call sites that make the rich work explicit; the disposition cannot merely
document a misleading API and leave it unchanged.

The audit is not permission to introduce a general performance framework,
cache every derived value, or rewrite unrelated state. It is complete only
when every identified hot or misleading accessor has an explicit disposition,
all `cutover-required` findings are fixed, and the runtime workload confirms
that no replacement hidden-cost stack dominates the MainActor.

### Required benchmark hardening

Bounded scope:

1. Add a deterministic pane-toolbar/terminal-pressure workload that fails when
   one pane invalidation performs fleet-wide work or exceeds an accepted
   distribution budget.
2. Run the same workload locally and in the post-merge benchmark workflow.
3. Repair the known benchmark workflow defects:
   - permit the CI-only `.build-benchmark` slot while local runs use normal
     `.build-agent-*` slots;
   - replace deleted `PushBenchmarkSupportTests` and
     `PushPerformanceBenchmarkTests` references;
   - fail when required benchmark output is missing;
   - run the existing `bridge-viewer-benchmark`;
   - align benchmark Swift cache keys with the build inputs used by CI; and
   - raise the documented clean prebuild timeout from 90 to 240 seconds where
     that prebuild lane owns the timeout.
4. Emit an artifact containing workload identity, release/debug SHA,
   distributions, thresholds, and pass/fail—not merely event presence.

Do not add test sharding, a custom cache system, compiler tuning, or a generic
MainActor telemetry framework.

PR 2 gets its own focused implementation plan after PR 1 records the corrected
runtime stack and measurements. Those measurements define the benchmark budget;
the hotfix plan must not invent a threshold before the corrected workload is
observed.
