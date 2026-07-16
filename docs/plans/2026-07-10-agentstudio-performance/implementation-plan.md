# AgentStudio Performance Boundaries Implementation Plan

Status: broader plan accepted; S1t strict type-state foundation is committed at
`d099ce32`; performance-first product execution is current under the sequencing
amendment below.

Execution order is amended by
[Performance-First Sequencing Amendment](performance-first-sequencing-amendment.md):
product performance behavior and focused proof now precede S1h/S1i completion,
S5, W11, and final lint expansion.

Accepted source commit: `c9f553e1d143e01b748a3e5aa0f8f6bd4fe0f182`

Focused type-state spec checkpoint:
`4d36c91bde0786c79387d9bb7036c3b40f1e9f0d`

Focused S1 accepted hashes:

```text
6282630cb420956073e279bb65a35189a54fb9bedddf692d2a22a8bc8adeb93a  maintained spec
7b312eaef20411b3d982fd99e0d427fbadbf00430e2ea6f7bf9fd99d901cac81  focused API
```

Focused W1b/W2 accepted hashes:

```text
77e7c671513ee0aa8ccdf039379fe2eef734a639a9652df40b740c478dcc3f88  watched parent
f546f63a6a7608950f8f2ebf4f780d98e3fef7b5282e36393aa089f7ebf19f23  source-admission child
```

Detailed plans:

- [S1 admission correction plan](s1-admission-correction-plan.md)
- [S1t strict type-state correction plan](s1-type-state-correction-plan.md)
- [Watched-folder and shared runtime plan](watched-folder-and-shared-runtime-plan.md)
- [W1b/W2 fixed-slot filesystem lifecycle plan](w1b-fixed-slot-lifecycle-plan.md)
- [Ghostty terminal interaction plan](ghostty-terminal-interaction-plan.md)

## 1. Goal

Implement the accepted performance boundary contracts without asking the executor to choose a different architecture. The implementation must:

1. admit and contract pressure before creating per-sample tasks or global fanout;
2. keep one typed global `RuntimeFactBus` for semantic product facts;
3. move fleet/source/state-machine work off MainActor and retain typed, bounded MainActor apply owners;
4. preserve exact lifecycle, repair, user-intent, persistence, and security semantics under overload and teardown;
5. separate strict composition restore, prioritized terminal activation, and
   non-blocking repository/filesystem/Git/topology derivation so external work cannot gate an
   active pane becoming typing-ready;
6. prove typing, cursor, TUI mouse, focus, reveal, terminal throughput, filesystem recovery, MainActor fairness, and scrollback memory with correlated current-run evidence.

This plan operationalizes the accepted design. It does not reopen mailbox families, bus count, source repair semantics, persistence ownership, terminal signal planes, Ghostty host ownership, screen-capture scope, or Bridge deep-render scope.

## 2. Source Coverage

The planning run read the complete accepted artifacts:

| Source | Lines | Contract used by this plan |
| --- | ---: | --- |
| `docs/specs/2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md` | 2,013 | shared primitives, startup-lane separation, fact transport, MainActor ledger, harness, scope |
| `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md` | 1,999 | WF/WS/FI/TA/EV/BR requirements, strict composition restore, independent topology derivation, and proof |
| `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/filesystem-observation-admission-lifecycle.md` | 958 | fixed fleet slots, callback authority, replacement, FIFO retirement, replay, native release, and shutdown debt |
| `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md` | 1,886 | CB/GT/GA/TS/AI/SC/SF/GV requirements, prioritized terminal activation, and proof |
| `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-action-admission-manifest.md` | 186 | exhaustive action disposition and mechanical coverage |

Live repo anchors were rechecked at `0fd9a080`: the existing global `PaneRuntimeEventBus`, outbound `PaneRuntimeEventChannel`, MainActor `NotificationReducer`, FSEvent callback/source actor, topology/cache/persistence owners, Bridge filesystem refresh path, Ghostty callbacks/action router/surface host, IPC registry/authentication, performance recorder, shared runner, and SwiftSyntax architecture linter.

## 3. Scope And Non-Goals

### In scope

- Shared admission mechanics, typed fact transport, topic filtering/recovery, MainActor work attribution, architecture enforcement, and the shared performance workload.
- Watched-folder callback admission, repair, fair scanning, root indexing, topology projection/apply, persistence handoff, filesystem-to-Git invalidation, and bounded Bridge filesystem refresh/currentness.
- Strict composition restore, independent topology derivation, legacy workspace JSON hard cut, and
  domain-separated steady-state persistence requests.
- Ghostty callback lifetime, tick admission, action/user-intent admission, terminal signal hard cut, activity/notification parity, agent-report IPC, secure input, prioritized startup activation, surface geometry/visibility/lifetime, atomic vendor cutover, and performance proof.

### Out of scope

- Screen-capture product implementation.
- Full Bridge mutation journal, normalized React store, memoization, or list/content virtualization.
- A host-owned VT parser, renderer, or frame loop.
- Actor-per-terminal-pane or several product-global event buses.
- Persistence redesign beyond the accepted forward migration removing legacy
  import state and topology-derived pane facets; no long-lived compatibility pipeline.
- Rewriting already-lazy SwiftUI lists without a measured violation.

## 4. Shared Implementation Rules

1. Behavior changes use RED/GREEN proof. The executor records the failing command and why it failed before implementing the behavior, then the passing command after the change.
2. No test uses wall-clock sleeps. Debounce, lease, quiet, timeout, and retry behavior use injected clocks or exact event/state waits with bounded timeouts.
3. A unit/config/script test is not called smoke. Proof layers use the repo definitions: unit, real-boundary integration, real runnable smoke, native/observability E2E, and PR/release where applicable.
4. All performance evidence records HEAD, worktree identity, app identity/PID, run token, fixture manifest, vendor commit, host revision, probe/adaptation digests, and measurement validity.
5. MainActor queue delay and synchronous service time are separate. A work record never spans `await`.
6. OTLP fields remain content-safe. Raw paths, UUIDs, pointers, terminal text, titles, URLs, errors, payload strings, clipboard data, and screen content are prohibited.
7. A hard cut removes old publication/authority paths in the same integration slice. No task is complete with dual global publication, dual persistence writers, or dual terminal fact authorities.
8. High-conflict files have one integration owner per integration gate. Parallel lanes may add disjoint primitives and focused tests, but they do not independently edit the same composition root.
9. Canonical atoms remain state or pure-derived-state owners. Their narrow methods only assign caller-supplied values, suppress equal writes, perform simple representation-local transforms, and maintain storage indexes/observation invariants. Pure domain types validate and decide; mutation coordinators sequence cross-owner changes; persistence coordinators/adapters reserve preimages and transact assignments. No atom/facade prepares a mutation plan, rejection, semantic effect, persistence descriptor, or cross-owner workflow. W4.5 constructs one long-lived adapter bundle in production, routes every installed persistence-affecting writer through its domain gateway, and proves pre-mutation paging through real front doors. W4.5z hard-cuts durable terminal identity to a non-optional opaque `ZmxSessionID`, UUIDv7 generation for new values, exact existing-value preservation, and mutation-free restore before terminal activation or W5+ resumes.
10. Every workload-producing path is acyclic per checked attempt/generation and proves separate admission, MainActor service, and downstream-expansion bounds. Acknowledgements may close custody; retries/source reconfiguration require a new bounded attempt/generation and cannot synchronously re-enter with payload. Composition and topology install independently inside one persistence runtime, and telemetry remains a bounded fail-open sidecar rather than a correctness edge.

## 4.1. Security Context

Assets/privileges: MainActor availability, canonical topology and repair truth, persistence order, callback memory lifetime, pane/runtime identity, user intent, secure-input state, terminal/session content, and trustworthy performance evidence.

Entry points and untrusted inputs: FSEvent paths/flags/IDs, unreadable/replaced/symlinked roots, Git metadata, arbitrary PTY output/OSC/title/URL/notification/action traffic, stale/concurrent C callbacks, clipboard/report payloads, same-user IPC callers, build manifests/patches, and diagnostic pressure.

Trust boundaries and privileged effects:

- a user-authorized canonical root permits traversal/watcher creation only inside that authority; Git metadata cannot expand it;
- complete current-generation scan proof is required for removal;
- terminal metadata/heuristics/agent reports are advisory attribution data, never command, permission, filesystem, or cross-pane authority;
- physical user host-call scope plus one-use intent controls workspace/URL/clipboard effects;
- authenticated server principal plus server-stamped runtime generation controls report attribution;
- `SecureInputOwner` controls OS secure-input state and fails capture closed;
- screen content has no authorized product API in this plan;
- probes export only content-free opaque correlation and aggregate dimensions.

Security invariants: stale generations/revisions cannot mutate replacement state; exact repair/fact/settlement obligations cannot be silently dropped; every accepted clipboard request settles before free; all surfaces quiesce before app free; OTLP excludes paths/raw IDs/text/URLs/errors/payloads; benchmark-only marker/observer behavior is absent from ordinary debug/beta/stable builds.

Security non-goals: no new screen capture, OSC/hook report protocol, general IPC authentication redesign, permission decision from agent state, watcher authority expansion, or relaxed clipboard/notification policy.

Required proof is owned by W1–W4.5/W7–W10 and T1–T5/T8–T12: exhaustive policy/state tables, invalid IO, callback/teardown races, real filesystem/SQLite/Unix-socket/vendor/Carbon boundaries, content canaries, product negative probe scan, and native current-run verification.

## 5. Cross-Plan Task Graph

### Gate G0 — Baseline and branch identity

Before implementation:

1. Confirm `git status --short`, `git submodule status vendor/ghostty`, and accepted spec hashes.
2. Run `mise run lint` and the focused current tests named in both child plans.
3. Start the shared observability stack and collect provisional baseline/control distributions with the existing debug runner. This evidence is diagnostic only and cannot approve ceilings because the evidence-validity/calibration contract does not yet exist.
4. Freeze workload seeds, fixture identities, candidate-independent control definitions, and the values that the later calibration manifest must own. Architecture work does not wait for numeric calibration.

### Shared lane S1 — Admission primitives

Owned write scope:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/**` (new)
- `Tests/AgentStudioTests/Core/PaneRuntime/Admission/**` (new)
- initial creation/registration, Admission protected-state clause, inventory,
  parity test, and fixtures for `RuntimeSignalPlaneRule` under
  `Tools/AgentStudioArchitectureLint/**`; S5 owns the remaining rule clauses and
  post-cut inventory

Implement the closed `PressureStreamID` manifest, `AdmissionGeneration`,
domain-free admission results, capability-separated producer/consumer and
doorbell ports, binding-scoped drain tokens, base/primitive diagnostics,
`LatestValueMailbox`, value-only `BoundedGatherMailbox`, and the typed
offer/replay/gap results for `OrderedFactJournal`. The gather primitive stores
opaque contributions and checked footprints only; domain merge, repair
evidence, routing, dedupe, and projection do not enter this module.

Checkpoint: deterministic state-machine tests prove fixed-generation isolation,
explicit undeclared-key rejection, one pending wake plus one
acknowledgement-released follow-up wake, O(1) fixed-shape offers across
1/100/300 declared keys, pending-plus-leased retained limits globally/per key,
one-key lease quanta, discriminated retained/retained-with-recovery/contracted-
to-recovery receipts, and exact per-key
recovery revisions. Cancellation/rebind re-presents identical custody under a
new binding token; retries rotate behind already-ready unrelated keys while
remaining ahead of newer same-key work. Tests also prove graceful seal,
post-transfer invalidation, stale/double/foreign/old-binding rejection,
non-aliasing exhaustion, truthful retained/pending/leased diagnostics, and no
task, payload queue, stored domain closure, fleet scan, or payload-derived
telemetry dimension.

The ordered-journal RED/GREEN matrix separately proves exact fact sequencing,
persistent versus query-local gaps, immediate post-recovery replay with empty
retained history, oversized snapshot atomic rejection before sequence
assignment, persistent-gap precedence over future/invalid cursors, invalidated
non-current diagnostics, gap widening, and near-maximum non-aliasing authority.
Independent literal state tables—not production helpers—own every oracle.

The focused implementation-review correction is operationalized in
[S1 Admission Correction Plan](s1-admission-correction-plan.md). It is normative
for S1a–S1i plus focused S1t file edits, RED/GREEN order, and the corrected S1
checkpoint. It hard-cuts strict public/private result, nonempty custody,
recovery, cleanup, replay, drain-age, and snapshot-footprint types; implements latest
`D/R/C` component pressure, finalization reservation/final-batch wake, per-value
retry, and wrapper-currentness proof; bounds gather metadata and journal
snapshot/replay custody; makes journal raw state lexical-private; and replaces
manual protected-region manifests with a fail-closed wrapper/token helper graph.
It does not wire a product caller or reopen later domain lanes.

### Shared lane S2 — Runtime fact contracts and bus

Depends on: S1 for journal semantics.

Owned write scope:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeFactContracts.swift` (new)
- `Sources/AgentStudio/Core/RuntimeEventSystem/Events/RuntimeFactBus.swift` (new)
- `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Events/**`

Implement exhaustive `RuntimeTopic`, `RuntimeDomainFact.topic`, `RuntimeFactEnvelope`, typed replay requests, topic-interest subscription, pre-admission filtering, recovery policies, and lag/recovery diagnostics. Keep `EventBus` transport-only.

Checkpoint: exact topic/replay table tests, irrelevant-topic no-admission tests, and gap/current-snapshot recovery in an isolated `RuntimeFactBus` assembly. Pre-IG1 structural proof must show that production has not wired this as a second global bus; the exactly-one-global-product-bus proof belongs to IG1.

### Shared lane S3 — MainActor work and evidence ledger

Can run in parallel with S1/S2.

Owned write scope:

- `Sources/AgentStudio/Infrastructure/Diagnostics/MainActorWorkLedger.swift` (new)
- `Sources/AgentStudio/Infrastructure/Diagnostics/MainActorResponsivenessHeartbeat.swift` (new)
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceProbeSink.swift` (new)
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceRunEvidenceLedger.swift` (new)
- existing performance recorder/OTLP projection/metrics files
- focused diagnostics tests, including `MainActorResponsivenessHeartbeatTests.swift`

Implement enqueue/start/synchronous-end attribution, evidence-loss accounting, stage correlation, scrubbing, and invalid-evidence propagation. Wire no product source yet beyond focused test fixtures.

The acceptance metric contract is explicit:

- `performance.mainactor.work` exports separate `queue_age_ms` and synchronous `service_ms` distributions keyed only by bounded `domain`, `operation`, and `outcome` dimensions;
- `performance.mainactor.heartbeat` exports run-loop heartbeat gap and consecutive-overdue counts without attributing a gap to an operation by proximity alone;
- `performance.pipeline.contraction` exports source/admitted/coalesced/fact/delivery/MainActor-apply/render counts for expansion-ratio proof;
- terminal interaction records AppKit dispatch-to-handler, host-call service, and `inputToFrameLayerPublished` separately;
- source/fact/repair diagnostics export queue depth/typed oldest-age measurement
  plus bounded precision (`exact` or `pressure_conservative`), high-water,
  coalesced/dropped count, exact gap/debt state, and quiescence outcome.

`AgentStudioOTLPTraceProjection.swift` and `AgentStudioOTLPPerformanceMetrics.swift` must project these into VictoriaMetrics histograms/counters/gauges and marker-scoped VictoriaLogs records. Raw watched paths, pane IDs, terminal content, errors, and payloads remain forbidden; real roots use stable aliases plus `dev.worktree.hash`/run correlation only.

`MainActorResponsivenessHeartbeat` is the sole producer of `performance.mainactor.heartbeat`. It uses an injected monotonic clock and independently scheduled run-loop observations; it does not inspect adjacent `MainActorWorkLedger` operations or infer causality from temporal proximity.

Checkpoint: deterministic ledger, injected-clock heartbeat, and OTLP projection
tests prove queue/service/liveness separation, no span across suspension,
bounded metric dimensions, loss invalidates a run where required, and
raw-path/content canaries never project to logs or metric labels. The projection
oracle covers both age precision cases: `exact` and `pressure_conservative`
remain distinguishable, and a pressure-conservative sample can never enter an
exact-latency series or exact-valued log field.

### Domain lanes W and T

After S1 interfaces stabilize, execute the watched and terminal plans in parallel using disjoint files. After S2 stabilizes, domain lanes may build and test cutover-ready `RuntimeFactBus` endpoints in isolated assemblies, but production global wiring stays entirely legacy until IG1. S3 must exist before acceptance-grade measurements.

- Watched pre-IG1 preparation/cuts: W1a, W2a, dormant W1b, W3–W10, split-domain W4.5 strict composition restore, W4.5z durable terminal identity, atomic W2b, and atomic W7d including the legacy JSON/schema hard cut. W1b's native observation adapter remains isolated from the complete legacy `FSEventStreamClient -> FSEventBatch -> FilesystemActor` production path; W2b replaces that protocol/composition and deletes the legacy batch path atomically. W11/W12 are post-IG1.
- The focused W1b/W2 child plan supersedes the older registration-keyed/raw-
  port/per-generation-seal task vocabulary. W1b dormant readiness includes the
  isolated actor/SourceGate transfer and real native lifetime proof; W2a
  mechanics completion includes fixed-slot replacement/currentness and repair-
  participant protocol mechanics. W2b remains the sole production cut.
- Terminal pre-IG1 preparation/cuts: W4.5z then T1–T11 including T10.5
  prioritized startup activation. T12 is post-IG1 and post-CG1.

### Shared lane S3.5 — Visible-First View Composition Restore

Depends on accepted W4.5 composition and coordinates with T10.5 without owning
terminal runtime activation. Add `ViewCompositionRestoreOwner` as the bounded
visible-first owner for webview, code-viewer, Bridge, and other nonterminal pane
content. Replace the generic serial `restoreAllViews` loop with an exhaustive
prepared-content dispatch: terminal cases go only to T10.5; nonterminal cases go
only to this owner; the empty-workspace case installs the shell empty state.
Expanded-drawer panes are visible priority, and each pane may mount exactly once
per composition generation.

Modify `WorkspaceSurfaceCoordinator+ViewLifecycle.swift`, launch restore call
sites, `ViewRegistry`, and focused launch-restore tests. Prove active
nonterminal, active terminal, mixed terminal/nonterminal, empty workspace, and
expanded-drawer behavior. `activeContentReady` gates only the active pane;
`visibleContentSettled` reports all visible content-specific outcomes without
delaying active readiness. Use bounded fleet scheduling and bounded MainActor
mount quanta; no task-per-pane fanout.

### Shared lane S4 — Nonterminal And App Event Migration

Depends on: S2. These are separately provable subtasks; they may overlap domain migration, but one integration owner later changes composition roots.

S4 builds cutover-ready endpoints, disposition tables, and focused target assemblies. It does not land a second production global bus. Edits that change current global composition, remove old delivery, or wire new product effects are held for the single IG1 integration diff.

#### S4a — Exhaustive producer/consumer inventory

Create `Tests/AgentStudioTests/Architecture/RuntimeFactTransportArchitectureTests.swift` with a checked disposition table covering every `PaneRuntimeEvent`, `AppEvent`, global publisher, global subscriber, direct acknowledgement, and IPC wait/status path. The table names source, current consumers, target local/fact/direct-command disposition, topic/replay/recovery when global, and deletion gate. Its source-inventory test fails on an unclassified new case.

#### S4b — Nonterminal pane-local runtime and IPC migration

Modify `Core/RuntimeEventSystem/Runtime/SwiftPaneRuntime.swift`, `Features/Bridge/Runtime/BridgeRuntime.swift`, `Features/Webview/Runtime/WebviewRuntime.swift`, and browser/diff/editor/plugin runtimes represented by `PaneRuntimeEvent`. Local presentation/console samples stay in local runtime channels; semantic cross-feature output becomes an exhaustive typed fact; nonterminal IPC attaches directly to the selected runtime.

#### S4c — System-domain producers

Migrate `Core/RuntimeEventSystem/Forge/ForgeActor.swift` and artifact/security/runtime-error producers. Each receives a literal fact/recovery/consumer table and focused zero-legacy-post proof.

#### S4d — Global consumers and boot composition

Modify `App/Boot/AppDelegate.swift`, `App/Boot/AppDelegate+WorkspaceBoot.swift`, `App/Coordination/WorkspaceCacheCoordinator.swift`, and other boot/composition subscribers to request nonempty topics and explicit delivery/replay/recovery. Any critical MainActor delivery uses a synchronous `MainActorWorkLedger` span.

#### S4e — Remove `AppEventBus` as a second global product bus

Modify:

- `Sources/AgentStudio/App/Events/AppEvent.swift`
- `Sources/AgentStudio/App/Events/AppEventBus.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift`
- `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewExitBehaviorTests.swift`

Disposition the three current cases explicitly without creating a second semantic producer. Terminal-origin authority remains exclusively with T5/T6 and the terminal/pane lifecycle owner: `terminalProcessTerminated` is committed once by that generation-bearing lifecycle owner; `terminalProcessTerminationHandled` becomes a targeted typed acknowledgement to the same owner rather than global fanout; and the existing coordinator `worktreeBellRang` relay is deleted. Bell admission remains exclusively in T5/T6's manifest-selected inbox/notification owner, which may publish one accepted content-free occurrence only when the inventory confirms a named consumer. S4e removes/rewires the second transport; it never converts an AppEvent relay into an additional fact producer. Delete the unkeyed `Task`-per-post façade. RED/GREEN plus the cross-plan producer inventory proves one authority and at most one publication for each terminal lifecycle/bell fact.

S4 completion: every former global producer/consumer has one disposition, every production fact subscriber declares topics, and no subtask publishes the same product effect through legacy and new global transport.

### Integration gate IG1 — Runtime transport hard cut

Depends on: S2, S4a–S4e, watched fact migration, terminal fact/snapshot migration, IPC terminal migration, and all named global consumers.

Single integration owner modifies:

- `Core/RuntimeEventSystem/Events/EventChannels.swift`
- `Core/RuntimeEventSystem/Runtime/PaneRuntimeEventChannel.swift`
- `Core/RuntimeEventSystem/Contracts/PaneRuntime.swift`
- `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
- `Core/RuntimeEventSystem/Contracts/RuntimeEnvelope*.swift`
- `Core/RuntimeEventSystem/Reduction/NotificationReducer.swift`
- `App/Coordination/WorkspaceSurfaceCoordinator.swift`
- `App/IPCComposition/AgentStudioIPCRuntimeAdapter.swift`
- `App/Events/AppEvent.swift`
- `App/Events/AppEventBus.swift`
- `App/Panes/PaneTabViewController.swift`
- `Features/Terminal/Hosting/TerminalPaneMountView.swift`
- boot/composition roots

Hard-cut rules:

1. Remove `PaneRuntimeEventBus` as a global transport, delete the global `EventBus<RuntimeEnvelope>` instance, and remove `AppEventBus`/`EventBus<AppEvent>`.
2. Remove the outbound stream and global-bus constructor dependency from `PaneRuntimeEventChannel`; retain it only for nonterminal pane-local subscribe/replay contracts.
3. Remove `BusPostingPaneRuntime` and terminal participation in `PaneRuntimeEventChannel`.
4. Remove `NotificationReducer` from terminal/filesystem paths; delete it if no valid nonterminal owner remains.
5. Nonterminal IPC attaches directly to the selected runtime. Terminal IPC uses `TerminalStateSnapshot` and `TerminalFactOwner.facts(after:)`.
6. Structural proof finds exactly one global product `EventBus` instance—the `RuntimeFactBus` backing transport—and no production construction/post of `EventBus<RuntimeEnvelope>` or `EventBus<AppEvent>`.
7. Every remaining correctness-critical `RuntimeFactBus` delivery that executes a MainActor applier has a named synchronous `MainActorWorkLedger` operation with enqueue/start/end, generation/revision, input/changed-key count, and outcome; no span crosses subscriber `await` work.

No intermediate commit after IG1 may contain dual publication. If all consumers cannot cut together, split work before IG1 and keep the old global transport until the final atomic integration diff.

Before landing the IG1 integration commit, the single integration owner assembles the complete hard-cut diff in an isolated branch/worktree and runs `mise run lint`, `mise run test`, and `mise run test-webkit`. Any failure attributable to the hard-cut composition blocks IG1; there is no mixed-state or ignored-failure allowlist. Unrelated infrastructure failures remain governed by the repo validation scope guard and are reported separately rather than edited through this plan.

### Shared lane S5 — Architecture Enforcement

Depends on: stable post-cut APIs from S1/S2 and domain owners.

The type system is the first guard: `RuntimeFactBus.post` accepts only `RuntimeDomainFact`; local UI/activity/diagnostic signal types cannot conform to that protocol. `MainActorMutationApplier` accepts a bounded `Sendable` mutation and exposes a synchronous non-`async` apply region, so an applier cannot hide suspension inside its acceptance span.

Own two named SwiftSyntax rules in the existing registry, inventory, good/bad
fixtures, and parity tests. S1h creates and registers the initial Admission
protected-state clause of `RuntimeSignalPlaneRule`; S5 extends that same rule
and creates/registers `MainActorBlockingWorkRule`. S5 writable work waits for
the completed S1i handoff; read-only fixture preparation may occur earlier.
Each new clause starts with a narrow RED fixture and must pass independently:

1. `MainActorBlockingWorkRule` (`agentstudio_mainactor_blocking_work`, error): in `@MainActor` declarations, `State/MainActor/**`, `MainActorMutationApplier` implementations, and `withMainActorWork` regions, reject filesystem enumeration/canonicalization, Git/process/network calls, JSON encode/decode, regex construction or fleet collection transforms, persistence queue/retry/checkpoint arbitration, and spans crossing `await`. Allowlist entries require an operation name, calibrated service budget, and expiry/owner comment.
2. Extend `RuntimeSignalPlaneRule` (`agentstudio_runtime_signal_plane`, error): preserve S1h's settled structural Admission wrapper/token protected-helper graph, then reject `LocalUISample`/`ActivitySample`/diagnostic values posted or replayed through `RuntimeFactBus`, exact facts placed in lossy/latest mailboxes, terminal publication through legacy `PaneRuntimeEventChannel`, mixed fact/sample dropping queues, and unkeyed `Task { @MainActor }` scheduling from C callback routers. Its checked owner/route manifest enumerates direct input, Ghostty action, filesystem/Git, composition install, topology install, durable mutation, fact transport, and diagnostic export edges; a focused static test rejects same-attempt back-edges, observation-driven mutation, cross-domain preinstall authority, and undeclared routes without attempting a whole-program call-graph solver. S5 does not restore a helper-name manifest or rescan contract. Runtime flood/race/count tests remain the behavioral oracle.

The following subgroups define the broader fixtures covered by those two rules and adjacent existing rules:

#### S5a — Transport/admission rules

- raw/UI/diagnostic sample admission to `RuntimeFactBus`;
- mixed critical/lossy queues or default-unbounded production streams;
- production subscriber without topics/recovery declaration;
- `AppEventBus` or another global product `EventBus` construction;
- same-bus repost without a named contraction budget.
- missing owner/route declaration or a same-attempt workload-producing back-edge.

#### S5b — MainActor/persistence/render rules

- forbidden filesystem/serialization/fleet work in typed MainActor appliers;
- `WorkspacePersistenceCoordinator` queue/drain/retry/checkpoint arbitration isolated to MainActor or any canonical atom/facade minting a revision outside its outer transaction owner;
- direct product datastore mutations outside `WorkspacePersistenceCoordinator` after W7 migration;
- closure-backed, repository-handle-bearing, undeclared-family, or non-inventoried local persistence mutations;
- large fleet transforms in SwiftUI body-derived code.
- new/touched atom methods that accept commands/plans or produce validation,
  rejection, semantic-effect, persistence, async, I/O, or cross-atom workflow state.

#### S5c — Ghostty/security/content rules

- per-callback unkeyed `Task { @MainActor }`;
- delayed unretained callback-pointer reconstruction;
- terminal runtime publication through the legacy channel;
- lifecycle frees outside explicit Ghostty owners;
- caller-supplied pane/runtime generation authority;
- screen/terminal content in OTLP/replay;

Files:

- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/**`
- `ArchitectureLintCommand.swift`
- `Paths/ArchitectureAllowlists.swift`
- `Tools/AgentStudioArchitectureLint/Tests/**`

These rules are approximation guards and never replace runtime, race, native, or performance proof.

### Shared lane S6 — Fixed Workload And Evidence Verifier

Depends on: S3 and domain stage instrumentation. May be developed earlier against fixture seams, but acceptance runs occur after IG1 and domain gates.

Add:

- `scripts/verify-agentstudio-performance-workload.sh`
- `scripts/verify-agentstudio-real-root-qualification.sh`
- `scripts/agentstudio-performance/compare-runs.sh`
- `scripts/agentstudio-performance/query-victoria-run.sh`
- `scripts/agentstudio-performance/task-dependencies.json`
- `scripts/verify-agentstudio-performance-task-dependencies.sh`
- `scripts/stop-debug-observability.sh`
- a `.mise.toml` task for the verifier
- `Tests/AgentStudioTests/Scripts/AgentStudioPerformanceWorkloadScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/AgentStudioRealRootQualificationScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/AgentStudioPerformanceComparisonScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/AgentStudioPerformanceTaskDependencyScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/StopDebugObservabilityScriptTests.swift`
- `Tests/AgentStudioTests/Performance/**` fixture/oracle support
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceCalibrationManifest.swift`
- typed `PerformanceRunOutcome` in `PerformanceRunEvidenceLedger.swift`
- `Tests/AgentStudioTests/Performance/PerformanceCalibrationManifestTests.swift`
- `Tests/AgentStudioTests/Performance/PerformanceRunValidityTests.swift`
- `docs/guides/performance_proof_runbook.md`
- `AGENTS.md` routing and proof obligations; `CLAUDE.md` remains its existing symlink

Implement this as six provable subtasks:

- S6a validity/report core: manifest parsing, minimum independent trials, minimum samples per percentile, stopping rule, independence assumptions, histogram/raw resolution around every ceiling, warmup/exclusion/retry policy, evidence loss, and valid-pass/valid-fail/`invalidEvidence` outcomes. Write one fixed-length, non-evictable local run-summary receipt outside the high-rate OTLP queue; it records expected/admitted/completed stage counts, evidence loss, final outcome, run/build/calibration identity, and a digest of the marker-scoped query contract. The verifier compares this receipt with VictoriaMetrics/VictoriaLogs and returns `invalidEvidence` on disagreement. RED fixtures cover early stop, insufficient p99 support, unresolved precision, undeclared trimming/retry, stale identity, missing stages, summary loss, and summary/Victoria disagreement.
- S6b standard-runner/native driver: reuse `scripts/run-debug-observability.sh`, its deterministic app/data/zmx identity, and the shared Victoria stack. Add exact-PID/identity shutdown through `stop-debug-observability.sh`; it rejects stale/mismatched state and waits for process exit without wall-clock success assumptions. Do not create a second runtime/data identity or silently fall back to JSONL.
- S6c watched/terminal scenario adapters: bind the fixed scenario/matrix manifests and independent final-state oracles to the shared validity/report core.
- S6d baseline-to-candidate comparison: build verified baseline and candidate manifests, run identical scenario cells with unique markers, query VictoriaMetrics for p50/p95/p99/max and counts plus VictoriaLogs for required-stage/validity records, then emit machine-readable JSON and a human summary. Comparison rows show absolute value, absolute delta, percentage delta, control-relative delta, sample support, confidence/adequacy, and pass/fail/`invalidEvidence`. No candidate result may select its own query window, retry, trimming, or threshold.
- S6e real-root qualification: run the local read-only/controlled-sentinel profile defined by DQ1 below. The tracked plan names the two authorized roots, but OTLP and portable reports contain only `open_source`/`project_dev` aliases, root hashes, safe aggregate counts, volume class, and run/build identity. Script tests prove raw paths never enter VictoriaLogs, VictoriaMetrics labels, or committed artifacts.
- S6f durable operator guidance: `performance_proof_runbook.md` documents the exact stack/start/run/query/compare/cleanup loop, result interpretation, invalid-evidence states, and which gates are fixture-blocking versus developer-environment qualification. `AGENTS.md` routes performance, watched-folder, Ghostty-host, MainActor, EventBus, persistence, and Bridge-refresh work to this runbook and requires baseline capture before optimization, explicit admission contracts for high-rate sources, `MainActorWorkLedger` coverage for new MainActor boundaries, and current marker-scoped Victoria proof. Each hard-cut owner updates the `AGENTS.md` component-ownership table in the same integration commit so `RuntimeFactBus`, admission/source gates, persistence, terminal lifetime/fact/activity/security owners, and performance evidence owners do not exist only in the plan. Do not copy the shared stack's generic lifecycle/query cookbook into AgentStudio.

The checked task-dependency manifest is the execution source for pre-cut/post-cut gates. Its validator rejects unknown tasks, cycles, W11/W12 or T12 before IG1, any T12 performance cell without the immutable CG1 digest, DQ1 without completed W12/T12 contributor receipts, and IG2 without a completed DQ1 receipt.

Every result records the calibration-manifest digest. The optimized candidate cannot choose adequacy, exclusions, or stopping after its results are observed.

The comparison loop is fixed:

```text
shared stack healthy
  -> verify immutable baseline/candidate build manifests
  -> preflight one debug identity idle
  -> run identical cell with fresh marker
  -> drain evidence and stop exact PID
  -> query marker-scoped VictoriaMetrics + VictoriaLogs
  -> validate stages/support/no-loss/final-state oracle
  -> alternate build order and repeat to manifest minimum trials
  -> compare distributions and control-relative deltas
  -> validPass | validFail | invalidEvidence
```

AgentStudio currently treats VictoriaMetrics and VictoriaLogs as acceptance sources; VictoriaTraces may corroborate only after the producer exports accepted spans and is never assumed by this plan.

### Calibration gate CG1 — Valid baseline/control approval

Depends on S3 and S6a/S6b, and occurs before any candidate measurement or vendor acceptance. Run the pinned/current host baseline and paired controls through the real ledger/validity path. The human owner approves the typed `PerformanceCalibrationManifest` containing capacities, absolute/control-relative ceilings, minimum independent trials, minimum samples per percentile, stopping rule, independence assumptions, histogram/raw precision, warmup/exclusion/retry policy, perturbation allowance, and support counts. The approved digest is immutable for the candidate run. Failure to satisfy adequacy remains `invalidEvidence`; G0 diagnostic values cannot be promoted retroactively.

### Developer qualification gate DQ1 — Real watched roots and MainActor stability

Depends on CG1 plus completed deterministic W12/T12 candidate cells. This is a required local qualification on the primary development machine, not a portable CI oracle. The authorized watched roots are:

- `open_source` → `/Users/shravansunder/Documents/dev/open-source`
- `project_dev` → `/Users/shravansunder/Documents/dev/project-dev`

The verifier never writes existing repositories. Controlled churn is confined to a newly created, run-token-owned `.agentstudio-performance-soak/<run-token>` sentinel directory under each authorized root; cleanup verifies the sentinel token/canonical containment before removing only that generated directory. Preflight detects older orphan sentinels and fails closed with their aliases/tokens; it never deletes a prior run directory automatically. Initial add, cold boot, and settled observation exercise the actual root shapes read-only. Run baseline and candidate in alternating order with identical settings and record pre/post aggregate root manifests so unrelated environmental churn cannot be mistaken for product improvement.

DQ1 runs each root alone and both together with one attended deterministic terminal, then applies idle, controlled sentinel churn, terminal output pressure, cursor/caret, TUI mouse, focus/reveal, Bridge background/visible, and clean shutdown phases. The qualification duration, minimum trials, heartbeat cadence, sample support, and absolute/control-relative ceilings come from the immutable CG1 manifest; a short manual launch is not stability proof.

“MainActor is clear” means all of these pass together:

| Dimension | Blocking evidence |
| --- | --- |
| queue availability | `performance.mainactor.work` queue-age p50/p95/p99/max within approved limits for every named operation |
| synchronous occupancy | service p50/p95/p99/max and fixed-changed-key 10/100/300 scaling within each operation budget; no unapproved long span |
| independent liveness | heartbeat-gap p95/p99/max and consecutive-overdue counts within limits; no missing heartbeat interval while the process is expected runnable |
| user interaction | dispatch-to-handler, host-call service, input-to-layer publication, cursor/TUI mouse/focus/reveal tails within limits under watch/output pressure |
| pressure contraction | bounded mailbox/bus depths and oldest age; zero critical drops, unresolved exact-fact gaps, or unacknowledged repair debt at quiescence |
| correctness/currentness | source gates healthy, topology/SQLite/content oracles current, no stale generation accepted, clean close/reopen/shutdown |
| memory stability | bounded scrollback/watcher/ledger memory after fill, idle, clear/prune, and soak; no positive retained-memory slope beyond the approved envelope |

A crash, hang, marker loss, missing required stage, stale build/root manifest, raw-path export, unsupported p99, failed cleanup, non-quiescent source, or any violated MainActor/interaction/correctness ceiling yields `invalidEvidence` or `validFail`, never pass.

### Final integration gate IG2 — Combined fairness and correctness

After the child plans and DQ1 pass their local gates:

1. Run the watched-pressure matrix with an attended terminal receiving causal typing, cursor, and TUI mouse input.
2. Run the terminal output/version-host factorial matrix with watched folders idle and pressured.
3. Run visible/background Bridge containment cells without claiming deep Bridge render speed.
4. Verify topology final state and SQLite final state using independent oracles.
5. Verify critical/fact/repair gaps are zero or explicitly recovered and evidence is valid.
6. Run native PID-targeted typing, caret, mouse, focus, reveal, and display movement proof.
7. Run scrollback memory fill/idle/quiescence/clear/prune proof for pinned and candidate/control cells.

## 6. Execution DAG

The performance-first amendment supersedes only the ordering of guardrail
work. All dependency and atomic-cut requirements below remain normative.

```text
G0 baseline/spec/repo identity
  |
  +-- S1t strict admission foundation -------------------------+
  |                                                            |
  +-- S2 RuntimeFactBus contracts ------------------------+     |
  |                                                       |     |
  +-- S3 MainActor/evidence ledger --------------------+   |     |
                                                      |   |     |
      +-- watched pre-cut: W1a/W2a/W1b, W3-W10, W2b --+---+-----+
      |   W4.5p pure atoms/live bundle/front-door proof precedes |
      |   W4.5a-d/z strict restore, W5+, and W7d                 |
      +-- terminal pre-cut: T1-T11 incl. T10.5 activation -----+
      |   T11 keeps the complete legacy downstream route        |
      +-- S3.5 nonterminal visible-first view restore ----------+
      +-- S4a-S4e cutover-ready endpoints ----------------------+
                                                                  |
                   IG1 one atomic global transport hard cut
                                      |
                      +-- product-focused runtime proof ---+
                      +-- S1h/S1i + S5 + W11 cleanup/lint -+
                      +-- S6 shared workload/verifier -----+
                                      |
                       CG1 valid baseline/control approval
                                      |
                      +-- watched W12 acceptance ---------+
                      +-- terminal T12 candidate proof ---+
                                      |
                      DQ1 real-root/MainActor qualification
                                      |
                         IG2 combined cross-pressure proof
                                      |
                         implementation-review-swarm
                                      |
                         lint + full tests + CI/PR gates
```

W4.5p is a blocking architectural correction, not a reorderable implementation
detail. One persistence-owned `WorkspacePersistenceRuntime` retains the shared
revision owner and adapter bundle, but composition and topology have independent
strict lifecycles and distinct non-copyable preinstall tokens. For each domain,
the required order is: off-main prepare/validate; atomic initial apply with that
domain token; hard-cut every same-domain production writer through the bound
adapters/coordinator; install that domain participant inventory; then expose its
installed mutation gateway. Composition may unlock window and terminal
readiness while topology is still preparing. The complete pager is assembled
only after both domains install. No later S1, prepared-composition,
terminal-activation, W5, or performance lane resumes until W4.5p production
reachability, real-front-door pager proof, and full validation pass. Terminal
activation additionally requires W4.5z.

W12 and T12 are contributors to DQ1/IG2, not prerequisites that recursively own them. T11 may run candidate callback/app/surface quiescence before CG1 only as build-identity-bound correctness/compatibility proof; it does not measure or accept candidate performance. Every T12 and DQ1 performance cell requires the immutable human-approved CG1 manifest digest.

## 7. Parallel Write Scopes

The executor may allocate these disjoint initial lanes:

| Lane | Exclusive initial scope | Integration owner must later touch |
| --- | --- | --- |
| A | admission module, focused tests, and the Admission clause/fixtures of `RuntimeSignalPlaneRule` through S1i | none |
| B | fact contracts/bus and bus tests | event composition roots at IG1 |
| C | diagnostics/evidence ledgers and tests | OTLP projection/metrics |
| D | FSEvent callback/source/mailbox and tests | `FilesystemActor.swift` |
| E | scan scheduler/result/root index and tests | `FilesystemActor.swift`, `RepoScanner.swift` |
| F | persistence types/pager/coordinator and tests | canonical atoms/datastore owners |
| F2 | strict composition validation/apply and independent topology-lane tests | boot composition roots and persistence hard cut |
| G | Ghostty callback control blocks/tick gate and tests | app/surface lifecycle files |
| H | terminal activity mailbox/projector and tests | terminal/inbox boot and router |
| H2 | terminal activation scheduler/readiness tests | AppDelegate launch restore, view lifecycle, SurfaceManager |
| H3 | nonterminal view-composition restore owner/readiness tests | launch restore, view lifecycle, ViewRegistry |
| I | IPC report contracts/contribution and tests | authentication/server/runtime adapter |
| J | Bridge refresh request/coordinator/currentness and tests | coordinator/controller/WebKit surface |
| K | harness/evidence types/verifier tests | `.mise.toml`, shared runner integration |
| L | non-Admission architecture rules/fixtures; Admission fixture preparation is read-only until S1i | rule registry/allowlists and post-S1i `RuntimeSignalPlaneRule` extensions |

Writable dependency edge: `S1i completed handoff → lane L / S5 writable
RuntimeSignalPlaneRule work`. Before that edge, lane A is the only writer for the
Admission clause and fixtures; lane L may only prepare read-only fixture designs.

High-conflict files are single-owner at each gate: `WorkspaceSurfaceCoordinator.swift`, `AppDelegate.swift`, `AppDelegate+WorkspaceBoot.swift`, `PaneRuntimeEvent.swift`, `EventBus.swift`, `FilesystemActor.swift`, `WorkspaceCacheCoordinator.swift`, `WorkspacePersistenceTransformer.swift`, `GhosttyActionRouter.swift`, `GhosttySurfaceView.swift`, `SurfaceManager.swift`, `BridgePaneController.swift`, `.mise.toml`, and the Ghostty submodule pointer. Performance cells use disposable AgentStudio source/build worktrees at the exact host revision; they do not rewrite the active worktree's `Package.swift`, framework, or resources to select a static Ghostty build.

## 8. Requirements / Proof Matrix

| Claim | Source | Owner | Public seam and independent oracle | Layer and freshness | RED/GREEN / fit |
| --- | --- | --- | --- | --- | --- |
| admission is bounded before per-sample task allocation | parent shared interfaces | S1; W1–W2; T3/T6/T7 | strict discriminated public/private type states; typed producer/consumer ports, nonempty gather/latest/fact drains, latest `D/R/C` offer/take/cleanup, journal physical snapshots/readers; compiler-negative former-construction fixtures plus literal custody/counter/currentness histories | compile/static, unit, and in-process integration, then product pressure integration in later lanes; current source manifest/HEAD/run | required; S1 fails type-state, component-pressure, final-batch wake, retry/currentness, metadata-root, snapshot-reader, private-owner, and graph-lint REDs before GREEN |
| workload flow has no same-attempt cascade | parent acyclic-workload contract | S5/S6; every domain cut | checked owner/route manifest plus literal correlation/generation count ledger; independent negative back-edge/observation fixtures | compile/static + deterministic unit/integration counts + Victoria runtime evidence; current source/HEAD/run | required; acknowledgements are payload-free and every retry/reconfiguration advances a checked attempt/generation |
| one global semantic fact bus filters before queue/replay | parent fact taxonomy; EV1–EV11 | S2/S4/IG1 | `RuntimeFactBus.subscribe/post`; independent topic/replay table and structural source inventory | unit + integration + architecture lint; current source tree | required; IG1 atomic |
| MainActor attribution and availability are causal and bounded | parent MainActor last mile; TA8 | S3, every applier, DQ1 | `MainActorWorkLedger`; independent heartbeat plus interaction stages | unit + Victoria observability + native E2E; current PID/run/build/root manifest | required; queue/service/liveness/interaction gates all pass |
| composition, content mounting, terminal activation, and repository startup are independent | parent startup-lane contract; SF12–SF17 | W4.5/W4.5z/W5/W7; S3.5/T10.5 | invalid composition with zero mutation/activation; accepted immutable composition with one bounded apply; UUIDv7 new creation; exact historical-ID round-trip; zero startup writes/list calls; exact stored-ID activation ledger; delayed topology control | unit + SQLite/runtime integration + Victoria/native E2E; current PID/run/build | required; active terminal/nonterminal readiness and empty shell precede delayed external lanes; each pane mounts once and external lanes cannot alter composition/residency/session identity |
| UI-memory persistence is settled/coalesced, never callback-rate | parent UI-memory checkpoint contract | W4.5p/W7/W8 | explicit end-gesture or injected-clock latest settle gate plus revision/pump counters; literal N-callback oracle | unit + AppKit-boundary integration + Victoria MainActor/persistence counts; current source/run | required; N continuous callbacks yield one settled atom assignment/revision/request, zero fact posts, and no Observation feedback revision |
| watched loss never authorizes false removal | WF/WS/FI | W1–W5 | callback/source-gate/scheduler/topology applier; literal filesystem manifest | unit + real filesystem/Git integration + workload | required; split callback, scan, apply |
| watched roots never falsely present last-known state as current | watched currentness contract | W5b/W11/DQ1 | `WatchedFolderCurrentnessAtom` + Repo Explorer currentness read model | unit + integration + PID-targeted native visibility; current source/run/root generation | required; last-known content remains usable but visibly non-current |
| stale persistence cannot overwrite newer topology | TA10–TA11 | W7/W8 | coordinator/datastore receipts; repository reads compared to literal final map | unit + real SQLite integration + workload | required; sole-writer cut atomic |
| filesystem-to-Git and Bridge work is contracted | EV12; BR1–BR6 | W9/W10 | typed internal mailbox and bounded refresh owner; provider counters/currentness state | unit + integration + WebKit/native currentness | required; deep render out of scope |
| Ghostty callbacks are generation/lifetime safe | CB/GT/SF9–10 | T2–T4/T11 | control-block/gate/lifecycle APIs; vendor completion recorder and lease counts | unit + foreign-thread integration + pinned/candidate stress | required; candidate quiescence is a blocking gate |
| privileged actions require one event-scoped user intent | GA manifest | T5 | action router/host scope; literal manifest plus side-effect/fallback counters | unit + integration + native input | required; action cut atomic |
| terminal samples cannot evict exact facts or reach global bus | TS/AI | T6/T7/IG1 | presentation/activity mailboxes and fact owner; semantic parity oracle | unit + bounded flood + inbox integration | required; no dual terminal pipeline |
| pane agent reports cannot outlive runtime authority | AI3–AI10 | T8 | authenticated Unix socket and server generation registry; accepted receipts/current generation | unit + real IPC integration | required; runtime generation first |
| secure input is app-global and capture fails closed | SC1–SC8 | T9 | `SecureInputOwner`; injected error table plus OS secure-input query | unit + native integration + export canaries | required; screen capture remains absent |
| input/startup/geometry/visibility/reveal remain correct | SF1–SF17 | T10–T12 | AppKit/Ghostty host seams, activation ledger, and readiness milestones; causal layer/cursor marks plus PID-targeted visible behavior | unit + integration + native E2E | required; callback and host edits serialize |
| vendor benefit is independently attributable | GV1–GV8 | T1/T12 | immutable build/probe/adaptation manifests; factorial controls | build integration + native/perf E2E | required; exact candidate only |
| combined pressure no longer stalls typing/cursor | parent scenario matrix | S6/IG2 | standard debug runner + Victoria metrics + PID-targeted UI; correlated stage ledger | observability/native E2E; exact app PID/run/vendor | required; final acceptance gate |
| actual development roots remain usable and stable | user environment qualification; PF/interaction contracts | S6e/DQ1 | authorized-root aliases + sentinel-contained churn; Victoria comparison plus source/topology/SQLite/currentness oracle | local qualification E2E; current root/build/run manifests | required locally; not a portable CI oracle |
| performance boundaries remain mechanically visible to future agents | parent enforcement/maintainability contract | S5/S6f | two SwiftSyntax rules, rule inventory, good/bad fixtures, AGENTS-linked runbook | compile/static + docs link checks; current source tree | required; runtime proof still mandatory |

Each detailed child task expands these rows with the test boundary, invalid states, IO cases, and exact files.

Accepted specification SHA256 values for this implementation-plan revision:

| Artifact | SHA256 |
| --- | --- |
| `agentstudio-performance-boundaries.md` | `bc7a065d7b4c518a82923520e68da116eaf8cdb92dfa1bc4bb05f455cf38a801` |
| `watched-folder-admission-mainactor-fairness.md` | `ad5081fee1f1e9ba726beec33681b2b767430bed97c2b21af87e998b9b8d3122` |
| `ghostty-terminal-interaction-fairness.md` | `7bfdbf98f59ca5fa84ceff85deb05d7dd1ea69e62d03d3c4b1ef7fc6406bccdb` |
| `ghostty-action-admission-manifest.md` | `68f81a879119f331291f2fa66dd1442a07a20494caa70b4b80c702c69169c5fa` |

## 9. Validation Gates

### Per-task implementation receipt

Every task/subtask records:

- starting and ending HEAD;
- the four accepted spec SHA256 values;
- affected public seam and owned write scope;
- exact RED command/exit code and intended failure;
- exact GREEN command/exit code;
- proof layer and independent-oracle result;
- current fixture/app/PID/run/vendor/calibration identity when applicable;
- higher required layer not run, with blocker or explicit not-applicable reason;
- remaining repair debt, fact gap, durability-currentness, or evidence-validity state.

Broad filters shown in the child plans are planning selectors only. The receipt records the actual discovered suite/test name and demonstrates that the selected cases protect the named requirement; a broad substring match is not proof by itself.

### Per-slice unit and integration

Use the focused `mise run test -- --filter <SuiteOrTest>` commands listed in the child plans. Record RED and GREEN exit codes. Do not combine unrelated failures into the slice.

### Shared static gate

```bash
mise run lint
```

This includes swift-format lint, strict SwiftLint, AgentStudio architecture lint, and release script checks.

### Full repo test gate

```bash
mise run test
```

Run `mise run test-webkit`, `mise run test-large`, and any opt-in E2E lane explicitly required by the changed slice when not already included by the default task. Report each layer separately.

### Observability and performance gates

Every native verifier declares one launch contract:

| Task | Launch contract |
| --- | --- |
| `run-debug-observability -- --detach` | launch owner for one manual attached-verifier group |
| `verify-debug-observability`, `verify-agentstudio-ipc-phase-a-smoke`, `verify-secure-input-native`, `verify-ghostty-terminal-native` | attach to the exact current PID/run marker; never launch |
| `verify-agentstudio-agent-report-smoke`, `verify-git-refresh-performance-workload`, `verify-agentstudio-performance-workload`, `verify-agentstudio-real-root-qualification` | launch owner; preflight idle, launch one standard debug identity per cell, and guarantee exact-PID cleanup before returning |
| `verify-ghostty-vendor-manifest` | offline/build artifact verifier; no app |

Run the attach group, explicitly stop it, then run launch owners serially:

```bash
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-agentstudio-ipc-phase-a-smoke
mise run verify-secure-input-native
mise run verify-ghostty-terminal-native
mise run stop-debug-observability
mise run verify-agentstudio-agent-report-smoke
mise run verify-git-refresh-performance-workload
mise run verify-agentstudio-performance-workload
AGENTSTUDIO_PERF_REAL_ROOT_OPEN_SOURCE=/Users/shravansunder/Documents/dev/open-source \
AGENTSTUDIO_PERF_REAL_ROOT_PROJECT_DEV=/Users/shravansunder/Documents/dev/project-dev \
  mise run verify-agentstudio-real-root-qualification
```

The new workload, qualification, comparison, and stop tasks are added by S6. Each launch-owning verifier must confirm no same-worktree debug identity is running before launch, record its PID/run marker, clean up that exact PID on success/failure/cancellation, and confirm the identity is idle before the next launch owner. An `already_running` state is failure, never reusable proof. Workload tasks launch through the standard debug runner, query the shared Victoria stack, and write a comparison receipt containing every marker/query/build/calibration/root-manifest digest. JSONL is diagnostic only unless a test plan explicitly authorizes it.

### Native gate

Within the manual attach group above, target the exact already-launched debug PID with Peekaboo. Verify typing echo, caret movement/publication, TUI mouse selection/drag, focus transfer, hidden-to-visible reveal, display move, secure-input transitions, and native Bridge currentness overlay, then stop that PID before any self-launching workload. Visual proof supplements rather than replaces lower layers.

## 10. Rollback And Recovery

Rollback is task-local before a hard cut: remove an unintegrated primitive/owner and leave the old product path untouched. After IG1 or the persistence/terminal hard cuts, rollback must revert the complete integration commit; it may not restore a mixed state.

Allowed runtime recovery:

- keep last-known topology/content marked non-current and preserve repair debt;
- reject stale generations/revisions and request authoritative reprojection;
- retain ordered fact gaps and require snapshot resynchronization;
- keep Bridge last-known content under `refreshing`, `retrying`, or `failed-last-known` currentness;
- close/revoke stale terminal/IPC generations;
- invalidate performance evidence when diagnostics/probes are incomplete.

Forbidden rollback states:

- two persistence writers;
- old plus new global terminal publication;
- global filesystem-to-Git intermediate traffic;
- unretained callback userdata;
- pane-local secure-input authority;
- screen capture;
- permanent pinned/candidate runtime selection.

## 11. Split / Replan Triggers

Return to plan/spec work before continuing when:

1. a slice cannot make its required unit/integration proof pass without editing outside its owned boundary;
2. the selected Ghostty candidate cannot satisfy callback/app/surface quiescence;
3. one full `ghostty_app_tick` remains above the approved unpreemptible maximum under overlapping refill;
4. Bridge containment still violates the terminal/MainActor SLO because deep package/React work is dominant—route to the maintained Bridge render spec;
5. a screen-content consumer is requested—requires a new product/spec decision;
6. several physical product buses appear necessary—requires measured evidence and spec revision;
7. a non-local/removable root needs destructive disappearance semantics—requires explicit product support;
8. a required proof is too large or flaky at the task boundary—split the task before implementation rather than waiving proof.
9. the real-root qualification cannot avoid mutation outside its run-owned sentinel or cannot prove raw-path scrubbing—stop DQ1 and redesign the harness;
10. the proposed SwiftSyntax rules require broad permanent allowlists or cannot distinguish typed boundaries—narrow the rule contract rather than normalizing waivers.

## 12. Completion Definition

Implementation is not complete until every child task and IG1/DQ1/IG2 is checked, the requirements/proof matrix has current-run evidence, the baseline-to-candidate comparison report is adequate, all critical drops/gaps/repair debts have valid dispositions, `mise run lint` and required tests pass, both named SwiftSyntax rules and inventories are green, native/observability proof is current, the exact vendor/probe/adaptation/root/calibration manifests are recorded, `AGENTS.md` routes to the verified performance runbook, and an `implementation-review-swarm` verifies the code and proof chain.

The next workflow is `implementation-execute-plan`; it must first revalidate this plan against the live branch and must not implement if the accepted specs or high-conflict files have materially drifted.
