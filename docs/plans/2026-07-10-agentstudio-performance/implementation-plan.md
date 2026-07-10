# AgentStudio Performance Boundaries Implementation Plan

Status: implementation-ready after plan review; no product code has been changed by this plan.

Accepted source commit: `c9f553e1d143e01b748a3e5aa0f8f6bd4fe0f182`

Detailed plans:

- [Watched-folder and shared runtime plan](watched-folder-and-shared-runtime-plan.md)
- [Ghostty terminal interaction plan](ghostty-terminal-interaction-plan.md)

## 1. Goal

Implement the accepted performance boundary contracts without asking the executor to choose a different architecture. The implementation must:

1. admit and contract pressure before creating per-sample tasks or global fanout;
2. keep one typed global `RuntimeFactBus` for semantic product facts;
3. move fleet/source/state-machine work off MainActor and retain typed, bounded MainActor apply owners;
4. preserve exact lifecycle, repair, user-intent, persistence, and security semantics under overload and teardown;
5. prove typing, cursor, TUI mouse, focus, reveal, terminal throughput, filesystem recovery, MainActor fairness, and scrollback memory with correlated current-run evidence.

This plan operationalizes the accepted design. It does not reopen mailbox families, bus count, source repair semantics, persistence ownership, terminal signal planes, Ghostty host ownership, screen-capture scope, or Bridge deep-render scope.

## 2. Source Coverage

The planning run read the complete accepted artifacts:

| Source | Lines | Contract used by this plan |
| --- | ---: | --- |
| `docs/specs/2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md` | 677 | shared primitives, fact transport, MainActor ledger, harness, scope |
| `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md` | 1,500 | WF/WS/FI/TA/EV/BR requirements and proof |
| `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md` | 1,784 | CB/GT/GA/TS/AI/SC/SF/GV requirements and proof |
| `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-action-admission-manifest.md` | 186 | exhaustive action disposition and mechanical coverage |

Live repo anchors were rechecked at `c9f553e1`: the existing global `PaneRuntimeEventBus`, outbound `PaneRuntimeEventChannel`, MainActor `NotificationReducer`, FSEvent callback/source actor, topology/cache/persistence owners, Bridge filesystem refresh path, Ghostty callbacks/action router/surface host, IPC registry/authentication, performance recorder, shared runner, and SwiftSyntax architecture linter.

## 3. Scope And Non-Goals

### In scope

- Shared admission mechanics, typed fact transport, topic filtering/recovery, MainActor work attribution, architecture enforcement, and the shared performance workload.
- Watched-folder callback admission, repair, fair scanning, root indexing, topology projection/apply, persistence handoff, filesystem-to-Git invalidation, and bounded Bridge filesystem refresh/currentness.
- Ghostty callback lifetime, tick admission, action/user-intent admission, terminal signal hard cut, activity/notification parity, agent-report IPC, secure input, surface geometry/visibility/lifetime, atomic vendor cutover, and performance proof.

### Out of scope

- Screen-capture product implementation.
- Full Bridge mutation journal, normalized React store, memoization, or list/content virtualization.
- A host-owned VT parser, renderer, or frame loop.
- Actor-per-terminal-pane or several product-global event buses.
- New persistence schema or long-lived old/new compatibility pipelines.
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

Implement the normative `AdmissionGeneration`, `AdmissionReceipt`, `AdmissionDiagnostics`, `LatestValueMailbox`, `CoalescingMailbox`, and `OrderedFactJournal` interfaces. Domain policy does not enter this module.

Checkpoint: deterministic state-machine tests prove generation isolation, one pending wake, bounded keys/items/bytes, repair-slot non-eviction, exact fact sequencing/gap semantics, seal/invalidate, and diagnostics.

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
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceProbeSink.swift` (new)
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceRunEvidenceLedger.swift` (new)
- existing performance recorder/OTLP projection/metrics files
- focused diagnostics tests

Implement enqueue/start/synchronous-end attribution, evidence-loss accounting, stage correlation, scrubbing, and invalid-evidence propagation. Wire no product source yet beyond focused test fixtures.

Checkpoint: deterministic ledger tests prove queue/service separation, no span across suspension, loss invalidates a run where required, and content canaries never project to OTLP.

### Domain lanes W and T

After S1 interfaces stabilize, execute the watched and terminal plans in parallel using disjoint files. After S2 stabilizes, domain lanes may build and test cutover-ready `RuntimeFactBus` endpoints in isolated assemblies, but production global wiring stays entirely legacy until IG1. S3 must exist before acceptance-grade measurements.

- Watched pre-IG1 preparation/cuts: W1a, W2a, dormant W1b, W3–W10, atomic W2b, and atomic W7d. W11/W12 are post-IG1.
- Terminal pre-IG1 preparation/cuts: T1–T11. T12 is post-IG1 and post-CG1.

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

### Shared lane S5 — Architecture Enforcement

Depends on: stable post-cut APIs from S1/S2 and domain owners.

Split the rule work so each checkpoint has a narrow RED fixture and can pass independently:

#### S5a — Transport/admission rules

- raw/UI/diagnostic sample admission to `RuntimeFactBus`;
- mixed critical/lossy queues or default-unbounded production streams;
- production subscriber without topics/recovery declaration;
- `AppEventBus` or another global product `EventBus` construction;
- same-bus repost without a named contraction budget.

#### S5b — MainActor/persistence/render rules

- forbidden filesystem/serialization/fleet work in typed MainActor appliers;
- `WorkspacePersistenceCoordinator` queue/drain/retry/checkpoint arbitration isolated to MainActor or any canonical atom/facade minting a revision outside its outer transaction owner;
- direct product datastore mutations outside `WorkspacePersistenceCoordinator` after W7 migration;
- closure-backed, repository-handle-bearing, undeclared-family, or non-inventoried local persistence mutations;
- large fleet transforms in SwiftUI body-derived code.

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
- `scripts/agentstudio-performance/task-dependencies.json`
- `scripts/verify-agentstudio-performance-task-dependencies.sh`
- `scripts/stop-debug-observability.sh`
- a `.mise.toml` task for the verifier
- `Tests/AgentStudioTests/Scripts/AgentStudioPerformanceWorkloadScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/AgentStudioPerformanceTaskDependencyScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/StopDebugObservabilityScriptTests.swift`
- `Tests/AgentStudioTests/Performance/**` fixture/oracle support
- `Sources/AgentStudio/Infrastructure/Diagnostics/PerformanceCalibrationManifest.swift`
- typed `PerformanceRunOutcome` in `PerformanceRunEvidenceLedger.swift`
- `Tests/AgentStudioTests/Performance/PerformanceCalibrationManifestTests.swift`
- `Tests/AgentStudioTests/Performance/PerformanceRunValidityTests.swift`

Implement this as three provable subtasks:

- S6a validity/report core: manifest parsing, minimum independent trials, minimum samples per percentile, stopping rule, independence assumptions, histogram/raw resolution around every ceiling, warmup/exclusion/retry policy, evidence loss, and valid-pass/valid-fail/`invalidEvidence` outcomes. RED fixtures cover early stop, insufficient p99 support, unresolved precision, undeclared trimming/retry, stale identity, and missing stages.
- S6b standard-runner/native driver: reuse `scripts/run-debug-observability.sh`, its deterministic app/data/zmx identity, and the shared Victoria stack. Add exact-PID/identity shutdown through `stop-debug-observability.sh`; it rejects stale/mismatched state and waits for process exit without wall-clock success assumptions. Do not create a second runtime/data identity or silently fall back to JSONL.
- S6c watched/terminal scenario adapters: bind the fixed scenario/matrix manifests and independent final-state oracles to the shared validity/report core.

The checked task-dependency manifest is the execution source for pre-cut/post-cut gates. Its validator rejects unknown tasks, cycles, W11/W12 or T12 before IG1, any T12 performance cell without the immutable CG1 digest, and IG2 without completed W12/T12 contributor receipts.

Every result records the calibration-manifest digest. The optimized candidate cannot choose adequacy, exclusions, or stopping after its results are observed.

### Calibration gate CG1 — Valid baseline/control approval

Depends on S3 and S6a/S6b, and occurs before any candidate measurement or vendor acceptance. Run the pinned/current host baseline and paired controls through the real ledger/validity path. The human owner approves the typed `PerformanceCalibrationManifest` containing capacities, absolute/control-relative ceilings, minimum independent trials, minimum samples per percentile, stopping rule, independence assumptions, histogram/raw precision, warmup/exclusion/retry policy, perturbation allowance, and support counts. The approved digest is immutable for the candidate run. Failure to satisfy adequacy remains `invalidEvidence`; G0 diagnostic values cannot be promoted retroactively.

### Final integration gate IG2 — Combined fairness and correctness

After the child plans pass their local gates:

1. Run the watched-pressure matrix with an attended terminal receiving causal typing, cursor, and TUI mouse input.
2. Run the terminal output/version-host factorial matrix with watched folders idle and pressured.
3. Run visible/background Bridge containment cells without claiming deep Bridge render speed.
4. Verify topology final state and SQLite final state using independent oracles.
5. Verify critical/fact/repair gaps are zero or explicitly recovered and evidence is valid.
6. Run native PID-targeted typing, caret, mouse, focus, reveal, and display movement proof.
7. Run scrollback memory fill/idle/quiescence/clear/prune proof for pinned and candidate/control cells.

## 6. Execution DAG

```text
G0 baseline/spec/repo identity
  |
  +-- S1 shared admission primitives --------------------------+
  |                                                            |
  +-- S2 RuntimeFactBus contracts ------------------------+     |
  |                                                       |     |
  +-- S3 MainActor/evidence ledger --------------------+   |     |
                                                      |   |     |
      +-- watched pre-cut: W1a/W2a/W1b, W3-W10, W2b --+---+-----+
      |   including W4.5, W7d, and complete repair owners       |
      +-- terminal pre-cut: T1-T11 -----------------------------+
      |   T11 keeps the complete legacy downstream route        |
      +-- S4a-S4e cutover-ready endpoints ----------------------+
                                                                  |
                   IG1 one atomic global transport hard cut
                                      |
                      +-- S5 + watched W11 enforcement --+
                      +-- S6 shared workload/verifier ----+
                                      |
                       CG1 valid baseline/control approval
                                      |
                      +-- watched W12 acceptance ---------+
                      +-- terminal T12 candidate proof ---+
                                      |
                         IG2 combined cross-pressure proof
                                      |
                         implementation-review-swarm
                                      |
                         lint + full tests + CI/PR gates
```

W12 and T12 are contributors to IG2, not prerequisites that recursively own it. T11 may run candidate callback/app/surface quiescence before CG1 only as build-identity-bound correctness/compatibility proof; it does not measure or accept candidate performance. Every T12 performance cell requires the immutable human-approved CG1 manifest digest.

## 7. Parallel Write Scopes

The executor may allocate these disjoint initial lanes:

| Lane | Exclusive initial scope | Integration owner must later touch |
| --- | --- | --- |
| A | admission module and focused tests | none |
| B | fact contracts/bus and bus tests | event composition roots at IG1 |
| C | diagnostics/evidence ledgers and tests | OTLP projection/metrics |
| D | FSEvent callback/source/mailbox and tests | `FilesystemActor.swift` |
| E | scan scheduler/result/root index and tests | `FilesystemActor.swift`, `RepoScanner.swift` |
| F | persistence types/pager/coordinator and tests | canonical atoms/datastore owners |
| G | Ghostty callback control blocks/tick gate and tests | app/surface lifecycle files |
| H | terminal activity mailbox/projector and tests | terminal/inbox boot and router |
| I | IPC report contracts/contribution and tests | authentication/server/runtime adapter |
| J | Bridge refresh request/coordinator/currentness and tests | coordinator/controller/WebKit surface |
| K | harness/evidence types/verifier tests | `.mise.toml`, shared runner integration |
| L | architecture rules/fixtures | rule registry/allowlists |

High-conflict files are single-owner at each gate: `WorkspaceSurfaceCoordinator.swift`, `AppDelegate.swift`, `AppDelegate+WorkspaceBoot.swift`, `PaneRuntimeEvent.swift`, `EventBus.swift`, `FilesystemActor.swift`, `WorkspaceCacheCoordinator.swift`, `WorkspacePersistenceTransformer.swift`, `GhosttyActionRouter.swift`, `GhosttySurfaceView.swift`, `SurfaceManager.swift`, `BridgePaneController.swift`, `.mise.toml`, and the Ghostty submodule pointer. Performance cells use disposable AgentStudio source/build worktrees at the exact host revision; they do not rewrite the active worktree's `Package.swift`, framework, or resources to select a static Ghostty build.

## 8. Requirements / Proof Matrix

| Claim | Source | Owner | Public seam and independent oracle | Layer and freshness | RED/GREEN / fit |
| --- | --- | --- | --- | --- | --- |
| admission is bounded before per-sample task allocation | parent shared interfaces | S1; W1–W2; T3/T6/T7 | typed `offer/takeDrain`; literal state-machine histories and diagnostics | unit, then pressure integration; current HEAD/run | required; tasks split by primitive/domain |
| one global semantic fact bus filters before queue/replay | parent fact taxonomy; EV1–EV11 | S2/S4/IG1 | `RuntimeFactBus.subscribe/post`; independent topic/replay table and structural source inventory | unit + integration + architecture lint; current source tree | required; IG1 atomic |
| MainActor attribution is causal and bounded | parent MainActor last mile; TA8 | S3 and every applier | `MainActorWorkLedger`; independent responsiveness probe plus stage IDs | unit + observability E2E; current PID/run token | required for behavior; ceilings calibrated separately |
| watched loss never authorizes false removal | WF/WS/FI | W1–W5 | callback/source-gate/scheduler/topology applier; literal filesystem manifest | unit + real filesystem/Git integration + workload | required; split callback, scan, apply |
| stale persistence cannot overwrite newer topology | TA10–TA11 | W7/W8 | coordinator/datastore receipts; repository reads compared to literal final map | unit + real SQLite integration + workload | required; sole-writer cut atomic |
| filesystem-to-Git and Bridge work is contracted | EV12; BR1–BR6 | W9/W10 | typed internal mailbox and bounded refresh owner; provider counters/currentness state | unit + integration + WebKit/native currentness | required; deep render out of scope |
| Ghostty callbacks are generation/lifetime safe | CB/GT/SF9–10 | T2–T4/T11 | control-block/gate/lifecycle APIs; vendor completion recorder and lease counts | unit + foreign-thread integration + pinned/candidate stress | required; candidate quiescence is a blocking gate |
| privileged actions require one event-scoped user intent | GA manifest | T5 | action router/host scope; literal manifest plus side-effect/fallback counters | unit + integration + native input | required; action cut atomic |
| terminal samples cannot evict exact facts or reach global bus | TS/AI | T6/T7/IG1 | presentation/activity mailboxes and fact owner; semantic parity oracle | unit + bounded flood + inbox integration | required; no dual terminal pipeline |
| pane agent reports cannot outlive runtime authority | AI3–AI10 | T8 | authenticated Unix socket and server generation registry; accepted receipts/current generation | unit + real IPC integration | required; runtime generation first |
| secure input is app-global and capture fails closed | SC1–SC8 | T9 | `SecureInputOwner`; injected error table plus OS secure-input query | unit + native integration + export canaries | required; screen capture remains absent |
| input/geometry/visibility/reveal remain correct | SF1–SF11 | T10–T12 | AppKit/Ghostty host seams; causal layer/cursor marks plus PID-targeted visible behavior | unit + integration + native E2E | required; callback and host edits serialize |
| vendor benefit is independently attributable | GV1–GV8 | T1/T12 | immutable build/probe/adaptation manifests; factorial controls | build integration + native/perf E2E | required; exact candidate only |
| combined pressure no longer stalls typing/cursor | parent scenario matrix | S6/IG2 | standard debug runner + Victoria metrics + PID-targeted UI; correlated stage ledger | observability/native E2E; exact app PID/run/vendor | required; final acceptance gate |

Each detailed child task expands these rows with the test boundary, invalid states, IO cases, and exact files.

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
| `verify-agentstudio-agent-report-smoke`, `verify-git-refresh-performance-workload`, `verify-agentstudio-performance-workload` | launch owner; preflight idle, launch one standard debug identity, and guarantee exact-PID cleanup before returning |
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
```

The new workload and stop tasks are added by S6. Each launch-owning verifier must confirm no same-worktree debug identity is running before launch, record its PID/run marker, clean up that exact PID on success/failure/cancellation, and confirm the identity is idle before the next launch owner. An `already_running` state is failure, never reusable proof. The workload task must launch through the standard debug runner and query the shared Victoria stack. JSONL is diagnostic only unless a test plan explicitly authorizes it.

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

## 12. Completion Definition

Implementation is not complete until every child task and IG1/IG2 is checked, the requirements/proof matrix has current-run evidence, all critical drops/gaps/repair debts have valid dispositions, `mise run lint` and required tests pass, native/observability proof is current, the exact vendor/probe/adaptation manifests are recorded, and an `implementation-review-swarm` verifies the code and proof chain.

The next workflow is `implementation-execute-plan`; it must first revalidate this plan against the live branch and must not implement if the accepted specs or high-conflict files have materially drifted.
