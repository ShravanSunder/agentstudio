# Terminal Scrollbar Convergence Implementation Plan

Status: Reviewed; ready for implementation

Spec:
`docs/specs/2026-07-26-terminal-scrollbar-convergence/2026-07-26-terminal-scrollbar-convergence.md`

Goal ID: `2026-07-26-terminal-scrollbar-convergence`

## Outcome

Restore terminal thumb/viewport and scroll-to-bottom convergence while
preserving PR #202's fixed-key callback contraction, one-drain-per-surface
admission, and off-MainActor activity projection.

This plan implements only two source-owned slices:

1. valid detached batches deliver mounted host presentation and activity even
   when `TerminalRuntime` is temporarily absent;
2. live scrollbar gestures express authoritative bottom intent and reconcile
   only Ghostty state received for that gesture.

Scrollbar styling, `AppleShowScrollBars`, Ghostty vendor work, EventBus,
mailboxes, generic schedulers, and projector redesign remain out of scope.

## Source Coverage And Live Re-anchor

- The reviewed spec was read in full: 461/461 lines.
- Source HEAD is
  `5a7bd64690a3566dcb57fdf4d5a6dd34f9ed056c`.
- Current source confirms:
  - `GhosttyActionRouter+LocalActions.swift` validates mounted lifetime and
    begins a batch before runtime lookup, but runtime absence currently retires
    the surface before host-cache delivery and activity submission.
  - `TerminalLocalActionAccumulator.finishDrain` is the existing sole
    convergent follow-up scheduler.
  - `TerminalSurfaceScrollView` stores only a row-shaped persistent dedup value,
    suppresses programmatic position writes during live scrolling, and performs
    no drag-end reconciliation.
  - `TerminalSurfaceActionPerforming` already exposes both `.scrollToRow` and
    `.scrollToBottom`; no action API change is required.

Security context: not applicable. No trust boundary, secret, network,
filesystem, persistence, IPC, or privileged operation changes. Operational
safety remains mandatory: production Agent Studio processes and databases are
never touched.

## Write Scope

Expected:

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+LocalActions.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`

Conditional only when the smallest drain seam cannot remain in the local
actions file:

- one adjacent internal terminal-local-action drain support file;
- one adjacent focused drain test file.

Forbidden:

- `TerminalLocalActionAccumulator` or `TerminalLocalActionDrainScheduler`
  contract changes;
- `SurfaceManager`, `Ghostty.SurfaceView`, `TerminalSurfaceActionPerforming`,
  Ghostty vendor, EventBus, persistence, or release configuration changes;
- public APIs, `#if DEBUG` hooks, generic routing frameworks, polling, timers,
  request IDs, or cross-command arbitration.

## Vertical Slice A — Runtime-Independent Detached-Batch Delivery

### Task 1 — Implement and prove runtime-independent detached-batch delivery

Source requirements: R1-R4 and R8.

Behavior:

- validate mounted surface lifetime before beginning delivery;
- apply a changed detached scrollbar state to the mounted host cache first;
- submit a detached activity aggregate when pane/context/sink exist;
- apply runtime-owned batch state only when a matching runtime exists;
- keep the batch/follow-up lifecycle valid when runtime is absent;
- retire only invalid/replaced surface lifetimes.

Likely source/test owners:

- `GhosttyActionRouter+LocalActions.swift`
- `GhosttyActionRouterTests.swift`
- existing `TerminalLocalActionAccumulatorTests.swift` as preservation proof

#### Step A0 — Extract the smallest internal drain test seam

This is a behavior-preserving refactor performed while the existing focused
tests are green.

- Keep production `drainLocalActions(for:)` as the scheduler entry point.
- Extract only mounted-host-target resolution (surface lifetime plus pane
  identity) and host scrollbar cache read/write. This is the only current
  dependency that cannot be faked.
- Reuse the existing `setRuntimeRegistry` / `runtimeRegistryForActionRouting`
  and `bindTerminalActivityInput` / `unbindTerminalActivityInput` seams. Do not
  re-abstract runtime lookup, activity context, or activity submission.
- Keep the seam local to terminal local-action draining and internal to the
  module. Prefer a single small dependency value over many positional closure
  parameters. It must not generalize action routing or alter source ownership.
- Preserve current behavior in this task, including the runtime-miss failure,
  so the next tests can prove red for the right reason.
- Land one green test through the new seam proving the runtime-present path
  still writes host cache, applies the runtime batch, and submits activity.
  This new test is Step A0's behavior-preservation gate because no existing test
  reaches `drainLocalActions(for:)`.

Checkpoint:

- existing router/accumulator tests remain green;
- the new runtime-present drain test is green;
- diff proves no scheduling, accumulator, vendor, or public API change.

Split/replan trigger:

- testing requires a public abstraction, real Ghostty process, SurfaceManager
  mutation, vendor work, or `#if DEBUG`.

#### Step A1 — Add failing drain integration proof

Using a serialized fixture and unique surface/pane IDs, add tests that:

- offer a scrollbar callback into a real accumulator;
- resolve a valid mounted target while runtime lookup returns `nil`;
- observe that current code fails to update host cache;
- observe that current code fails to preserve a newer callback offered during
  the drain;
- bind a real test activity context/sink and observe that current code fails to
  submit the detached aggregate without runtime;
- preserve existing invalid/replaced lifetime retirement coverage.

Pane IDs must be freshly generated with `UUIDv7.generate()` and asserted
absent from `RuntimeRegistry.shared`, because the production drain falls back
to the shared registry when the test override registry differs.

Every global binding/registry override must reset in `defer`; accumulator
surface state must be removed after each test. No sleeps.

Red gate:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test -- \
  --filter 'GhosttyActionRouterTests|TerminalLocalActionAccumulatorTests'
```

The new no-runtime host/activity/follow-up cases must fail for the runtime
guard/retirement reason, not fixture construction.

#### Step A2 — Implement the minimal drain reorder

- After a valid batch begins, apply changed host scrollbar state before
  optional runtime lookup.
- Resolve runtime optionally; do not retire a valid batch when it is absent.
- Keep surface-title and runtime batch/title routing inside the runtime-present
  path.
- Submit detached activity outside the runtime-present path when aggregate,
  latest scrollbar state, context, and sink exist.
- Leave `defer finishDrain` as the sole follow-up transition.
- Preserve performance tracing truthfully for both runtime-present and
  runtime-absent paths.
- On the runtime-absent path, record `equalWriteSuppressedCount: 0` and still
  emit both compact-apply and accumulator-drain snapshots so P8 measures that
  path rather than silently skipping it.

Green/integration gate:

- all Step A1 cases pass;
- existing accumulator boundedness and one-follow-up cases pass;
- no accumulator or scheduler source change appears in the diff.

## Vertical Slice B — Authoritative Gesture Intent And Reconciliation

### Task 2 — Implement and prove authoritative gesture convergence

Source requirements: R5-R8.

Behavior:

- interior thumb position sends `.scrollToRow(row)`;
- host maximum sends `.scrollToBottom`;
- repeated semantic row/bottom commands deduplicate across gestures;
- programmatic pinned synchronization records bottom identity;
- drag end applies only gesture-relevant state that satisfies R6;
- drag end never sends a second Ghostty command.

Likely source/test owners:

- `TerminalSurfaceScrollView.swift`
- `TerminalSurfaceScrollViewTests.swift`

#### Step B1 — Add failing AppKit behavior proof

Split the test-only full-gesture helper into explicit start/live/end helpers so
a fake host scrollbar update can arrive between live-scroll and drag-end.

Add red tests for:

- host maximum sends `.scrollToBottom`, never `.scrollToRow(maximum)`;
- repeated bottom intent deduplicates;
- programmatic pinned state plus zero-movement gesture emits nothing;
- matching row state received during the gesture applies at drag end;
- pinned-bottom state received during the gesture applies at drag end;
- a no-command gesture may apply state received during the gesture;
- unrelated pinned growth does not acknowledge an interior row;
- no received state causes no drag-end position write;
- drag-end reconciliation adds no Ghostty action.

Retain existing interior-row, row-dedup, sticky-bottom, history anchoring,
document range, and pinned offset tests.

Red gate:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test -- --filter 'TerminalSurfaceScrollViewTests'
```

#### Step B2 — Implement bounded semantic gesture state

In `TerminalSurfaceScrollView`:

- replace row-only persistent dedup with semantic command identity:
  no command, interior row, or bottom;
- keep that persistent dedup record distinct from gesture acknowledgement
  state;
- at gesture start, clear only:
  - latest command actually sent in this gesture;
  - whether host scrollbar state arrived during this gesture;
- while live scrolling, mark receipt when host state arrives but retain current
  suppression of programmatic clip-position writes;
- send bottom intent at the host maximum, otherwise the interior row;
- at gesture end:
  - end suppression;
  - apply a no-command received state;
  - apply a row acknowledgement only when a state arrived and
    `cached.top == requestedRow`;
  - apply bottom acknowledgement only when a state arrived and cached state is
    pinned;
  - otherwise perform no position write;
  - never send another action.
- clear gesture-local state after reconciliation.
- refresh the persistent semantic-command dedup record when drag-end
  reconciliation applies a received state, including bottom identity for a
  pinned state.

Keep the state local to the wrapper. Do not add timers, request IDs, polling,
mailboxes, or a persistent intent state machine.

Green gate:

- all Step B1 cases pass;
- all existing scroll-wrapper tests pass;
- no external API or Ghostty vendor change.

## Requirements / Proof Matrix

| Row | Requirement | Owning task | Proof modality and layer | Evidence / freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| P1 | R1 callback contraction | 1 | deterministic unit + translated-admission integration | existing 100k mixed pressure, 10-surface bounded burst, one-follow-up tests at final HEAD | preservation |
| P2 | R2 lifetime validation | 1 | focused drain integration | invalid, replaced, and missing-pane fixtures with unique IDs and cleanup | preservation |
| P3 | R3 no-runtime host cache | 1 | callback-to-accumulator-to-drain integration | latest cache write and newer during-drain callback survive at final HEAD | required |
| P4 | R4 no-runtime activity | 1 | drain integration + projector unit preservation | bound context/sink receives one expected aggregate; binding reset in `defer` | required |
| P5 | R5 bottom intent/dedup | 2 | synchronous AppKit unit | fresh wrapper/fake performer; exact action list asserted | required |
| P6 | R6 acknowledgement | 2 | interleaved AppKit notification/state unit | explicit start/live/update/end; bounds and action count asserted immediately | required |
| P7 | R7 follow bottom/history | 2 | existing AppKit regression unit | sticky buffer in/out, history anchor, pinned offset, range at final HEAD | preservation |
| P8 | R8 MainActor/bounds | 1/2 | deterministic structural/performance preservation | one scheduled drain per surface, one coalesced follow-up, fixed retained entries, immediate snapshot `mainActorTaskCount == 1` | preservation |
| P9 | quality | final | build, format/lint, full relevant suite | fresh commands and exit codes from final HEAD | n/a |
| P10 | native behavior | final | isolated manual native interaction | recorded debug identity/PID/marker and PID-targeted observations/screenshots | n/a |

No proof row may be waived by the executor. If a required row cannot pass
inside its slice, split or return to planning.

## Execution DAG

```text
gate 0: verify branch, spec/plan coverage, worktree diff, shared vendor inputs
  |
  +--> Task 1: runtime-independent detached-batch delivery
  |      |
  |      +--> A0 green seam --> A1 red integration --> A2 green delivery
  |
  +--> Task 2: B1 red gesture tests --> B2 green gesture behavior
          (may run after gate 0; source write set is disjoint from A)
  |
integration gate: parent inspects both diffs and requirement rows P1-P8
  |
focused combined tests
  |
build + lint + full relevant test suite
  |
isolated per-worktree native manual proof
  |
implementation-review-swarm
  |
address accepted findings and rerun affected proof
  |
implementation-pr-wrapup: PR ready, not merged
```

Execution lane reasoning:

- Task 1: high effort because async drain lifetime, global binding cleanup, and
  performance accounting are correctness-sensitive.
- Task 2: medium effort because the state is bounded and synchronous but AppKit
  coordinate direction and gesture ordering require care.
- Parent integration and review: high effort.

## Validation Gates

Focused:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test -- --filter 'TerminalSurfaceScrollViewTests'
SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test -- \
  --filter 'GhosttyActionRouterTests|TerminalLocalActionAccumulatorTests|TerminalActivityProjectorTests|TerminalActivityRouterTests'
SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 \
  mise run test -- \
  --filter 'TerminalSurfaceScrollViewTests|GhosttyActionRouterTests|TerminalLocalActionAccumulatorTests|TerminalActivityProjectorTests|TerminalActivityRouterTests'
```

Repository:

```bash
mise run build
mise run lint
mise run test
```

Manual native proof:

```bash
mise run observability:up
scripts/run-debug-observability.sh --print-identity
mise run run-debug-observability -- --detach
AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1 mise run verify-debug-observability
```

Use Peekaboo only against the PID recorded for this worktree's deterministic
debug identity:

1. use a disposable debug workspace;
2. generate known scrollback;
3. drag to a recognizable history position;
4. generate bounded sustained output;
5. while totals advance, drag to bottom, leave bottom, and return;
6. capture thumb, rendered viewport, and bottom-indicator convergence;
7. quit only the verified debug PID.

This is native interaction proof, not a replacement for automated tests.
`verify-debug-observability` proves fresh isolated identity/telemetry, not the
scrollbar behavior itself.

## Risks And Recovery

- A fakeable drain seam can drift into a generic router. Stop if it needs more
  than the local batch delivery dependencies.
- Static router bindings can leak between tests. Serialized tests, unique IDs,
  `defer` reset, and accumulator cleanup are mandatory.
- Ghostty applies row synchronously and bottom through its IO mailbox. The spec
  accepts normal callback convergence for a bottom-then-interior race; do not
  add command correlation.
- AppKit global scroller preferences are not part of this fix or proof.
- If LaunchServices proof cannot launch the isolated debug bundle, report the
  manual gate blocked; do not substitute production or an historical app.
- Reverting the scoped source/test diff is sufficient recovery. No schema,
  migration, vendor, or persistent-state rollback exists.

## Completion Contract

Implementation is not complete until:

- P1-P10 have fresh evidence or a named external blocker;
- red/green evidence is recorded for P3-P6;
- build, lint, focused, and full relevant tests pass;
- isolated native manual proof passes without production interaction;
- implementation review findings are addressed or rejected with evidence;
- PR checks/review threads/mergeability are freshly reported;
- the PR is ready but not merged.
