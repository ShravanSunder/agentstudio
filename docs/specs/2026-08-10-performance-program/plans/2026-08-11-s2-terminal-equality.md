# Slice 2 Terminal Equality and Targeted Fact Delivery (LUNA-401) Implementation Plan

> Planning result: **ready**. This is a mechanics-only plan record
> authored by `plan-implementation`. It implements the reviewed slice-2 design;
> implementation on `perf/s2-admission` is owner-admitted (2026-08-11).

**Goal:** Stop equal terminal title/CWD/activity projections before MainActor
publication, cut terminal CWD coordination to one exact-fact path, and deliver
runtime facts only to subscribers whose declared fact interest matches, while
preserving R-INV end state, ordering, replay, buffering, diagnostics, and
cancellation behavior.

**Governing authority:**

- `docs/specs/2026-08-10-performance-program/requirements.md`
- `docs/specs/2026-08-10-performance-program/2026-08-10-performance-program.md`
- `docs/specs/2026-08-10-performance-program/program-design.md`
- `docs/specs/2026-08-10-performance-program/doc-drift-inventory.md`
- repository operating contract: `AGENTS.md` / supplied worktree instructions

**Delivery context:** requested terminal `pr-ready-unmerged` (owner-authorized
2026-08-11: implementation admitted on branch `perf/s2-admission`, PR to follow);
delivery grouping `single:s2-terminal-equality`; PR topology
`stacked-on:perf/s1-rails (PR #267)`; existing Linear tracking identity
`LUNA-401` is preserved (state: In Progress).

**Planned snapshot:** branch `perf/s2-admission`, HEAD
`1753666fbc45022ef240951ec22bde1da7e389f4`, stacked on `perf/s1-rails`.
The worktree was clean when planned. Implementation stages only files named by
this plan or files admitted through the scope-expansion record below.

## Scope and design anchors

- R-INV is a suppression gate: sequence-end published state must equal the
  ungated reference, and uncertain equality proceeds
  (`2026-08-10-performance-program.md:161-178`;
  `program-design.md:70-89`).
- R6 owns title/CWD/activity equality at the terminal source before MainActor
  scheduling (`2026-08-10-performance-program.md:233-239`;
  `program-design.md:180-188,565-577`).
- Publication state is per pane/per publication lane and follows exactly
  `unknown`, `pending(value)`, and `committed(value)`. Only successful
  MainActor apply acknowledgement commits; stale lifetime drops pending;
  failed apply remains pending and reschedules
  (`program-design.md:644-666`).
- R7 preserves SurfaceManager-local CWD metadata while removing its stream as
  a coordinator-publication authority. Only the exact runtime `.cwdChanged`
  fact may call `updatePaneCWDAndResolvedContext`, producing one lookup and one
  pane mutation attempt (`program-design.md:190-202,217-230`).
- R8 extends `subscribe(policy:subscriberName:)` with a fact-kind/topic
  interest descriptor. Matching occurs post-side before yield; it is not
  equality, eligibility, command policy, or mutable product policy. Buffering,
  replay, diagnostics, and fact semantics stay unchanged
  (`program-design.md:204-210,222-230,593-598`).
- C1/V2 telemetry reuses the existing trace-tag and OTLP scrub paths. V3 uses
  deterministic behavior tests; V8 uses completed marker-scoped windows and
  `mise run perf:report` (`2026-08-10-performance-program.md:333-399`).
- R18 assigns slice 2 the closed drift items D1, D4, D5, D6, D7, D9, D10,
  D14, M4, M7, M8, and M9. R19 requires any R4 rule that now covers a cleaned
  slice-2 surface to become blocking
  (`doc-drift-inventory.md:19-29,43-49`;
  `2026-08-10-performance-program.md:315-324`).

## Current-source anchor reconciliation

The plan uses current worktree paths and line ranges below. Design anchors are
historical `origin/main` anchors and are not silently treated as current.

| Design citation | Current worktree observation | Planning consequence |
|---|---|---|
| `TerminalLocalActionAccumulator.swift:202-282,319-367` | Offer/drain mechanics are now roughly `252-476`; only `.immediate` and `.title` drain lanes exist. CWD is not an accumulator action. | Keep drain lanes unchanged; add separate per-surface publication state for title/CWD/activity rather than pretending CWD is a current drain lane. |
| `TerminalLocalActionDrainScheduler.swift:26-136` | Current scheduler is `1-153`; claimed drain completes after the async MainActor drain returns. | Thread explicit apply outcome/ack through the current claimed-drain completion edge; do not add a second scheduler. |
| `GhosttyActionRouter.swift:268-282` | Current `.pwd` split is exactly `268-282`; title/exact barrier routing is now `698-785`. | Preserve local `pwdDidChange`; admit/ack the exact runtime CWD publication at the existing exact-fact route. |
| `Features/Terminal/SurfaceManager.swift` | Requested path is absent; current path is `Features/Terminal/Ghostty/SurfaceManager.swift`. CWD stream emission remains `631-702`. | Use the current path; remove only upstream coordinator publication, not local metadata maintenance. |
| `WorkspaceSurfaceCoordinator.swift:309-357,563-571` | Current duplicate owners remain at `309-363` and `567-571`. | Delete coordinator subscription/handler/task ownership; retain only runtime exact-fact call. |
| `EventBus.swift:182-260` | Single-post fan-out is `182-263`; batch post `267-303` and subscription replay `186-215` also yield envelopes. | Apply the same descriptor to replay, single post, and batch post; otherwise tests could pass while batch/replay still fan out. |
| Structural resolution says lanes `title`, `cwd`, `activity` | Current accumulator drain lanes are `.title` and `.immediate`; activity is embedded in immediate scrollbar batches. | Model publication kinds separately from scheduling lanes; no new CWD deadline or drain lane is authorized. |

## Explicit non-goals

- No change to terminal visible end state, exact-fact ordering, title deadline,
  search semantics, activity derivation, command routing, or runtime fact
  schema.
- No EventBus domain equality, command filtering, eligibility policy, mutable
  predicate closure, second event plane, or product-aware transport owner.
- No persistence/schema migration, compatibility shim, feature flag, vendor
  change, new service, new trust boundary, or stable trace-default/OTLP scrub
  change.
- No slice-3 git/forge cadence, coalescing, eligibility, or filesystem ingress
  work, even where those components subscribe to the bus.
- No claim that reduced targeted delivery alone proves UI latency improvement.

## Numeric V1/V2/V8 gates

These thresholds are fixed plan meaning, as required by R6/R20 and V8
(`requirements.md:66-74`; `2026-08-10-performance-program.md:325-331,401-404`).

| Gate | Required result on current-HEAD completed candidate window |
|---|---|
| Title/CWD/activity equal-publication waste | MainActor schedules/applies caused by a projection equal to `committed` = 0; reported equal-after-hop waste ratio = 0%. |
| Terminal accumulator contraction | `scheduled_drain_count / offered_count` and MainActor task count improve versus the immediately preceding completed baseline; title-lane scheduled-drain count drops by at least 90% in the equal-title workload. |
| CWD authority | One distinct `.pwd` produces exactly one coordinator topology lookup and one pane mutation attempt; an equal committed CWD produces zero additional coordinator lookup/mutation. |
| EventBus targeting | Every unmatched subscriber has zero live, batch, and replay yields/consumes for the posted fact; every matched subscriber receives the same ordered sequence as the ungated reference. |
| Priority interactions | Command bar open/close, tab move, and Cmd+R remain p95 <= 2 frames and p99 <= 4 frames; divider remains <= 1 frame per admitted sample; each is at-or-better than the preceding completed baseline. |

A missing completed baseline, absent slice-2 lane, threshold miss, or incomplete
marker window fails V8. It does not authorize changing the threshold or a
different hotspot.

## Scope-expansion record convention

If implementation discovers a required file not listed by a task, stop before
editing it and append one record to the implementation handoff:

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

An expansion is admissible only when it is a reversible mechanical dependency
of an already-decided edge and changes no owner, public contract, persistence,
trust boundary, proof gate, delivery grouping, or numeric threshold. Otherwise
record `[BLOCKER-FOR-PARENT]` and return to the parent without editing.

## Task DAG

```text
T0 baseline/applicability freeze
 └─requires─► T1 title committed-value defect and publication-state core
                ├─requires─► T2 lossless ack/cancellation/activity sequences
                └─requires─► T3 CWD exact-fact publication admission

T0 ─requires─► T4 single-authority CWD coordinator cutover
T0 ─requires─► T5 EventBus fact-interest contract
                  └─requires─► T6 production subscriber cutover

T3 + T4 + T6 ─requires─► T7 integrated V2/V3/V8 telemetry proof
T2 + T4 + T6 ─requires─► T8 docs ride-along and R19 lint-flip check
T7 + T8 ─requires─► T9 aggregate current-HEAD proof

Serial write collisions:
  T1 <-> T2 <-> T3  accumulator/router tests and publication state
  T4 <-> T6         WorkspaceSurfaceCoordinator subscription/CWD ownership
  T5 <-> T6         EventBus API and call-site compilation
  T7 <-> T9         current-HEAD marker proof artifacts

Integration gates:
  T3 joins publication state to the exact CWD route.
  T6 joins generic matching to real subscribers.
  T7 first proves accumulator, CWD authority, targeting, and telemetry together.
```

## Standard task table

| Task | Outcome | Depends on | Primary proof |
|---|---|---|---|
| T0 | Freeze current anchors, baseline, subscribers, and lint/doc inventory | — | read-only inventory + completed baseline identity |
| T1 | Fix repeated equal-title post-drain scheduling first | T0 | failing then passing committed-title test |
| T2 | Prove ack/failure/cancellation/activity state is lossless | T1 | deterministic reference-vs-gated sequence matrix |
| T3 | Apply publication state to exact CWD admission | T1 | equal/changed/unknown CWD scheduling tests |
| T4 | Remove SurfaceManager as coordinator CWD authority | T0 | one CWD / one lookup / one mutation observation |
| T5 | Add generic fact-interest descriptor and post-side match | T0 | live/batch/replay targeted-delivery counts |
| T6 | Declare interests at production subscribers | T5 | subscriber contract + integration sequence tests |
| T7 | Prove combined behavior and Victoria deltas | T3,T4,T6 | V2/V3/V8 marker-scoped transcript |
| T8 | Resolve slice-2 docs and decide each R19 flip from evidence | T2,T4,T6 | V5/V7 diff and lint output |
| T9 | Run complete quality/test/manual proof gate | T7,T8 | focused tests, lint, `mise run test`, current marker |

## T0 — Freeze applicability, baseline, and exact write inventory

**Files:** no product edits; proof notes remain under repo `tmp/`.

**Mechanics:** verify the planned HEAD/stack, clean status, slice-1 rails
(`scripts/perf-report.sh`, interaction probes, report-only lint channel), all
production `EventBus<RuntimeEnvelope>` subscriber call sites, current terminal
performance metric names, and D/M inventory ownership. Capture one completed
pre-change title-pane workload marker and resolve it explicitly as the V8
baseline. Cite `program-design.md:176-230,565-589` and
`2026-08-10-performance-program.md:233-246,388-404`.

**Proof recipe:**

```bash
git status --short --branch
git rev-parse HEAD
rg -n "subscribe\(|surfaceCWDChanges|cwdChanged|accumulator_drain" Sources Tests
mise run observability:up
mise run verify-title-pane-performance-workload
mise run perf:report -- --channel debug --lane performance.terminal
mise run lint
```

**Acceptance evidence:** exact baseline marker/completion identity, current
lane counts/waste ratios/p95, all subscriber owners, all report-only rule ids,
and slice-2 D/M items are recorded. A missing slice-1 rail or unresolved
baseline is `[BLOCKER-FOR-PARENT]`; do not fabricate a substitute.

## T1 — First RED/GREEN: retain and suppress the committed title

**Files:**

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionAccumulator.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionDrainScheduler.swift` only if the existing async drain return cannot carry the required ack outcome without changing ownership
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/TerminalLocalActionAccumulatorTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterLocalDrainTests.swift`

**Mechanics:** this is the earliest implementation task and its first test is
the owner-confirmed defect. Introduce the design-decided per-surface
publication state with `unknown`, `pending(value)`, and `committed(value)` for
title projection. First offer from unknown proceeds; successful MainActor apply
ack commits the exact applied projection; a subsequent identical title is
suppressed before title-deadline scheduling; a changed title becomes pending
and schedules normally. Preserve `.title` deadline and `.immediate` claims.
Cite `program-design.md:180-188,226-230,644-666`.

**Red-first proof:** add a test that offers title `A`, begins/drains it,
acknowledges successful apply, then offers title `A` again and observes the
current defect: a second scheduler/MainActor claim is created. The expected
post-fix result is `.equalSuppressed`, no second claim, and committed `A`
retained. Run RED before implementation, then GREEN:

```bash
mise run test:swift -- --filter "TerminalLocalActionAccumulatorTests"
mise run test:swift -- --filter "GhosttyActionRouterLocalDrainTests"
```

**Acceptance evidence:** captured RED names the extra schedule; GREEN proves
first unknown proceeds, successful ack commits, equal repeat schedules zero,
and changed repeat schedules one. No equality assertion after MainActor apply
counts as this gate.

## T2 — Complete lossless publication ack and activity sequences

**Files:**

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionAccumulator.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionDrainScheduler.swift` if admitted by T1
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/TerminalLocalActionAccumulatorTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterLocalDrainTests.swift`

**Mechanics:** apply the same publication state to the activity projection
already retained in the immediate scrollbar batch. Acknowledge only values
successfully applied by the MainActor drain. Pending replacement stays
latest-wins within the existing contraction contract; ack commits the value
actually applied, not a newer pending value. Failed apply keeps pending and
reschedules. Surface close/detach and stale lifetime remove pending/committed
runtime state; shutdown clears without publishing. Cite
`program-design.md:226-230,644-666` and R-INV
`2026-08-10-performance-program.md:163-178,235-239`.

**Red-first proof:** before mechanics, add a table-driven deterministic
reference-vs-gated sequence suite covering unknown, pending equal, pending
replacement, committed equal, committed change, ack racing newer pending,
failed apply/retry, stale generation, close, scheduler cancellation before
MainActor admission, and cancellation after admission. No sleeps; use captured
scheduler operations and explicit apply acknowledgements.

```bash
mise run test:swift -- --filter "TerminalLocalActionAccumulatorTests"
mise run test:swift -- --filter "GhosttyActionRouterLocalDrainTests"
```

**Acceptance evidence:** every gated sequence has the same terminal published
state as its ungated reference. Cancellation never makes unacknowledged work
committed and never converts uncertain work into suppression.

## T3 — Admit and acknowledge exact CWD publication

**Files:**

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/TerminalLocalActionAccumulator.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/TerminalLocalActionAccumulatorTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`

**Mechanics:** add CWD as a publication kind on the accumulator's per-surface
state, not as a third timed drain lane. At the existing exact `.pwd` route,
compare the normalized candidate with pending/committed CWD before enqueuing
MainActor exact-fact publication. Preserve title-before-exact barrier ordering.
Ack only after the exact runtime fact was successfully handed to its existing
runtime publication owner. Unknown/failed/stale cases follow the state machine;
equal committed CWD still updates no coordinator because local SurfaceManager
metadata is maintained independently. Cite `program-design.md:185-202,
217-230,644-666`.

**Red-first proof:** tests first demonstrate repeated equal exact CWD currently
creates a second MainActor exact-fact task. Then prove unknown proceeds, changed
pending replaces, successful ack commits, equal committed schedules zero,
failure retries, and an intervening title remains ordered before changed CWD.

```bash
mise run test:swift -- --filter "GhosttyActionRouterTests"
mise run test:swift -- --filter "TerminalLocalActionAccumulatorTests"
```

**Acceptance evidence:** equal CWD is stopped before MainActor admission;
changed CWD preserves exact-fact sequence and title barrier; no new CWD drain
deadline or coordinator path exists.

## T4 — Hard-cut coordinator CWD publication to the runtime fact

**Files:**

- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift`
- Modify: `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorCWDIdentityTests.swift`
- Modify current SurfaceManager test support implementing `WorkspaceSurfaceManaging`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`

**Mechanics:** remove `surfaceCWDChanges` from
`WorkspaceSurfaceManaging`, the coordinator's `cwdChangesTask`, subscription,
handler, cancellation, and await. Keep
`SurfaceManager.onWorkingDirectoryChanged` normalization/equality/local
metadata update; its stream may be removed if no remaining consumer exists,
but do not remove local callbacks. Retain the single
`handleTerminalRuntimeEvent(.cwdChanged)` call to
`updatePaneCWDAndResolvedContext`. Cite `program-design.md:190-202,217-230`.

**Red-first proof:** replace the surface-stream behavioral expectation with an
observation test that drives one Ghostty `.pwd` through both local metadata and
runtime publication and counts coordinator topology lookup plus pane mutation
attempt. It must fail pre-cutover with two and pass with one. Add equal CWD
proof showing zero second lookup after T3.

```bash
mise run test:swift -- --filter "WorkspaceSurfaceCoordinatorCWDIdentityTests"
mise run test:swift -- --filter "GhosttyActionRouterTests"
```

**Acceptance evidence:** one distinct CWD produces local SurfaceManager
metadata update, one coordinator lookup, and one pane mutation attempt; an
equal committed repeat produces no additional coordinator work.

## T5 — Add the generic fact-interest descriptor to EventBus

**Files:**

- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift` or create one adjacent fact-interest contract file if needed to keep EventBus generic
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus+WaitForFirst.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift`
- Modify: `Tests/AgentStudioTests/TestSupport/EventBusHarness.swift`

**Mechanics:** extend subscription with one immutable, Sendable fact-interest
descriptor and a transport-generic matcher supplied at bus construction or
descriptor boundary. Runtime-envelope interest vocabulary may name only stable
fact kind/topic identity derived from envelope cases; it cannot contain command
semantics, mutable product state, or arbitrary consumer closures. Store the
descriptor in `SubscriberRecord`. Filter replay, `post(_:)`, and
`post(contentsOf:)` before `yield`; unmatched facts do not increment yielded,
consumed, lag, or drop diagnostics. Preserve subscriber count semantics,
buffering, replay source storage/truncation, termination, and matched ordering.
Cite `program-design.md:204-210,226-230,593-598`.

**Red-first proof:** add targeted-delivery count tests with two disjoint and one
overlapping subscriber for live single post, batch post, and replay. Add an
ambiguous/all-facts descriptor test proving uncertainty proceeds. Existing
buffer/drop/recovery tests must remain unchanged for matching facts.

```bash
mise run test:swift -- --filter "EventBusRuntimeEnvelopeTests"
mise run test:swift -- --filter "EventBusWaitForFirstTests"
```

**Acceptance evidence:** unmatched subscribers receive/count zero work;
matching subscribers receive exact ordered sequences; replay status, drop
classes, and diagnostics are unchanged for matched delivery.

## T6 — Declare production RuntimeEnvelope subscriber interests

**Files:**

- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityRouter.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Forge/ForgeActor.swift`
- Modify corresponding focused subscriber/integration tests and direct runtime-bus test call sites mechanically required by the hard API cutover

**Mechanics:** derive each descriptor from the subscriber's existing exhaustive
switch/guard behavior; do not broaden or reinterpret what it consumes.
WorkspaceSurfaceCoordinator declares the fact families its reducer/handlers
currently accept, including terminal CWD. Cache, inbox, activity, git, and
forge owners declare only their existing fact topics. Use an explicit
all-facts descriptor only for test probes or a production consumer proven by
its current code to consume every fact. Hard-cut all call sites; no overload
with implicit fan-out remains. Cite `program-design.md:204-210,222-230`.

**Red-first proof:** before each production call-site change, add/extend a
focused integration test posting one matching and one unrelated envelope and
counting consumer work. Compile failures after T5 are expected RED for
undeclared interests; migrate owner by owner to GREEN.

```bash
mise run test:swift -- --filter "EventBus"
mise run test:swift -- --filter "WorkspaceSurfaceCoordinatorRuntimeDispatch"
mise run test:swift -- --filter "TerminalActivityRouter"
mise run test:swift -- --filter "WorkspaceCacheCoordinator"
```

**Acceptance evidence:** every production subscription declares inspectable
fact-only interest; unrelated posts cause zero consumer work; matched behavior
and ordering remain identical.

## T7 — Integrated telemetry and marker-scoped V2/V3/V8 proof

**Files:**

- Modify existing terminal accumulator telemetry/projection tests only if new
  outcome counters require coverage; no new telemetry lifecycle.
- Modify: `scripts/verify-title-pane-performance-workload.sh` only to exercise
  and assert slice-2 lanes using its existing marker/completion identity.
- Proof artifacts remain under repo `tmp/`.

**Mechanics:** expose admission outcomes needed to distinguish
`equal`, `changed`, and `uncertain_proceeded` through the existing terminal
accumulator metric family and OTLP allowlist. Add no raw title/CWD/path/UUID.
Extend the existing title-pane workload to emit repeated equal titles/CWD and
mixed changed sequences, plus targeted bus facts, then complete its existing
marker normally. Cite `program-design.md:81-89,226-230` and C1 privacy
`2026-08-10-performance-program.md:335-339,372-386`.

**Red-first proof:** metric projection tests first fail for missing outcome
fields/counts; workload assertions first fail because equal post-drain titles,
duplicate CWD coordination, and unrelated delivery remain observable.

```bash
mise run test:swift -- --filter "AgentStudioOTLPPerformance"
mise run observability:up
mise run verify-title-pane-performance-workload
mise run perf:report -- --channel debug --lane performance.terminal
mise run perf:report -- --channel debug --lane performance.runtime_delivery
```

**Acceptance evidence:** current marker is completed and explicitly compared
with T0 baseline; all numeric gates pass; report shows zero equal-after-hop
waste, >=90% title schedule reduction, one-CWD counts, zero unmatched delivery,
safe labels only, and no interaction regression. JSONL is not fallback proof.

## T8 — Docs ride-along and R19 lint-flip check

**Files:**

- Modify: `docs/architecture/state/workspace_data_architecture.md` (D1)
- Modify: `docs/architecture/runtime/pane_runtime_architecture.md` (D4-D7, M4, M7, M9)
- Modify: `docs/architecture/runtime/pane_runtime_eventbus_design.md` (D9-D10, M8)
- Modify: `docs/architecture/structure/component_architecture.md` (D14)
- Modify: `docs/specs/2026-08-10-performance-program/doc-drift-inventory.md`
- Modify: `docs/architecture/structure/architecture_lint_inventory.md` only if a rule flips
- Modify the owning architecture rule/fixture only when the evidence below requires a flip

**Mechanics:** update only the closed inventory items assigned to slice 2 and
mark each resolved once with current paths/behavior. Document independent
terminal drain lanes plus publication ack state, single CWD authority, and
fact-interest matching without presenting EventBus as a domain-policy owner.
For R19, inspect all four R4 rules against the changed surfaces. Flip a rule
from `report` to blocking only if its documented lexical surface actually
covers the cleaned slice-2 code and all findings on that surface are resolved;
record the surface and fixtures. If none covers these mechanics, record
`checked—no slice-2-owned flip` in the inventory; do not broaden a rule merely
to force a flip. Cite `2026-08-10-performance-program.md:315-324,365-368`.

**Red-first proof:** capture stale claims and current report diagnostics before
editing; architecture fixture tests must fail first for any required severity
change.

```bash
rg -n "dumb fan-out|unbounded subscribe|generic accumulator|surfaceCWDChanges" docs/architecture
mise run test:architecture
mise run lint
```

**Acceptance evidence:** D1, D4-D7, D9-D10, D14, M4, M7-M9 each has exactly
one truthful resolution; V5 output proves every applicable cleaned-surface
rule is blocking or proves with inventory evidence that no existing R4 rule
covers this slice.

## T9 — Aggregate proof and handoff gate

Run from repository root in this order:

```bash
mise run format
mise run test:swift -- --filter "TerminalLocalActionAccumulatorTests"
mise run test:swift -- --filter "GhosttyActionRouterLocalDrainTests"
mise run test:swift -- --filter "GhosttyActionRouterTests"
mise run test:swift -- --filter "WorkspaceSurfaceCoordinatorCWDIdentityTests"
mise run test:swift -- --filter "EventBusRuntimeEnvelopeTests"
mise run test:swift -- --filter "EventBusWaitForFirstTests"
mise run test:swift -- --filter "TerminalActivityRouter"
mise run test:architecture
mise run lint
mise run test
git diff --check
```

Then repeat T7 against current HEAD. Prior markers are baseline/history, not
candidate proof.

**Manual proof:** through the authenticated standard debug-observability
product path, drive repeated equal title and CWD updates plus distinct changes;
observe final pane title/CWD and SurfaceManager local CWD metadata; query the
completed marker with `perf:report`. This is operational telemetry proof, not a
replacement for deterministic tests.

**Acceptance evidence:** report every command's exit code and pass/fail count;
attach RED/GREEN transcripts for T1-T6, current-HEAD completed marker ids,
baseline/candidate identities, numeric gate results, and the manual final
title/CWD observation. Any missing focused, aggregate, lint, manual, or live
telemetry gate means the slice is not done.

## Obligation and proof map

| Obligation | Task(s) | Proof |
|---|---|---|
| R-INV title/activity | T1,T2,T7 | reference-vs-gated sequences + V2 outcome/waste |
| R6 title defect | T1,T7 | post-drain equal title creates zero schedule/MainActor task |
| R6 CWD equality | T3,T4,T7 | equal committed CWD creates zero lookup/mutation |
| R6 activity equality | T2,T7 | equal committed activity creates zero MainActor apply |
| R7 single CWD authority | T4,T7 | one `.pwd`, one lookup, one mutation, local metadata retained |
| R8 targeted delivery | T5,T6,T7 | live/batch/replay counts + production subscriber isolation |
| C1 privacy/telemetry | T7 | safe OTLP projection + completed marker report |
| R18 slice-2 inventory | T8 | V7 owning-doc/inventory diff |
| R19 applicable guards | T8,T9 | V5 fixture/severity and `mise run lint` output |
| R20 no regression | T7,T9 | slice-1 V1 interaction gates versus preceding baseline |

## False-green risks and stop/replan conditions

- Equality checked in `SurfaceView`, coordinator, atom mutation, or after a
  MainActor task is already enqueued is too late and does not satisfy R6.
- Treating `beginDrain` or scheduler return as successful publication can
  suppress changed work after cancellation/failure; only successful apply ack
  may commit.
- Committing the newest pending value when an older detached batch was applied
  loses facts; ack must identify the applied projection/generation.
- Removing `pwdDidChange` or SurfaceManager metadata maintenance breaks the
  selected CWD design; only coordinator publication is cut.
- Filtering only `post(_:)` while batch or replay still fans out is a false
  green. Unmatched facts must affect no delivery diagnostics.
- A descriptor carrying a predicate closure, command meaning, visibility,
  demand, or mutable product policy violates EventBus ownership.
- Unit/mocked tests are not V8; state files, stale markers, JSONL fallback, or
  metric presence without completion cannot pass telemetry proof.
- Tests using `Task.sleep`, suite serialization to hide leaked tasks, or new
  production `#if DEBUG` hooks violate the proof contract.
- Stop and return `[BLOCKER-FOR-PARENT]` if the current runtime cannot provide a
  successful publication ack without moving ownership; exact CWD ordering
  cannot coexist with source admission; interest vocabulary requires domain or
  command policy in EventBus; a persistence/vendor/trust-boundary change
  appears; an R4 flip requires weakening/deleting a gate; or a numeric threshold
  lacks a completed comparable baseline.

## [BLOCKER-FOR-PARENT] items

None at plan authoring time. The stop conditions above define the evidence that
would create one during implementation.

## Canonical plan record

```text
plan path: docs/specs/2026-08-10-performance-program/plans/2026-08-11-s2-terminal-equality.md
originating planner: plan-implementation
planning result: ready
governing planning basis:
  kind: reviewed-three-artifact-design
  Requirements: docs/specs/2026-08-10-performance-program/requirements.md
  Specification: docs/specs/2026-08-10-performance-program/2026-08-10-performance-program.md
  Program Design: docs/specs/2026-08-10-performance-program/program-design.md
  applicability: perf/s2-admission@1753666fbc45022ef240951ec22bde1da7e389f4
delivery context:
  requested terminal: pr-ready-unmerged
  delivery grouping: single:s2-terminal-equality
  PR topology: stacked-on:perf/s1-rails (PR #267)
```
