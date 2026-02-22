# Pane Runtime Ticket Mapping (Minimal, Single Plan File)

## Canonical Design

- [`docs/architecture/pane_runtime_architecture.md`](../architecture/pane_runtime_architecture.md)

## Design Heading Index (anchor links — no line numbers, they drift)

1. [Design Decisions](../architecture/pane_runtime_architecture.md#design-decisions)
2. [D1: Per-pane-type runtimes](../architecture/pane_runtime_architecture.md#d1-per-pane-type-runtimes-not-actor-per-pane)
3. [D2: Single typed event stream](../architecture/pane_runtime_architecture.md#d2-single-typed-event-stream-not-three-separate-planes)
4. [D3: @Observable for UI, event stream for coordination](../architecture/pane_runtime_architecture.md#d3-observable-for-ui-state-event-stream-for-coordination)
5. [D4: GhosttyEvent FFI enum](../architecture/pane_runtime_architecture.md#d4-ghosttyevent-enum-at-ffi-boundary-for-exhaustive-capture)
6. [D5: Adapter → Runtime → Coordinator](../architecture/pane_runtime_architecture.md#d5-adapter--runtime--coordinator-layering)
7. [D6: Priority-aware event processing](../architecture/pane_runtime_architecture.md#d6-priority-aware-event-processing)
8. [D7: Filesystem observation](../architecture/pane_runtime_architecture.md#d7-filesystem-observation-with-batched-artifact-production)
9. [D8: Execution backend config](../architecture/pane_runtime_architecture.md#d8-execution-backend-as-pane-configuration-not-pane-type-jtbd-7-jtbd-8)
10. [Contract Vocabulary](../architecture/pane_runtime_architecture.md#contract-vocabulary)
11. [Contract 1: PaneRuntime Protocol](../architecture/pane_runtime_architecture.md#contract-1-paneruntime-protocol)
12. [Contract 2: PaneKindEvent + PaneRuntimeEvent](../architecture/pane_runtime_architecture.md#contract-2-panekindevent-protocol--paneruntimeevent-enum)
13. [Contract 3: PaneEventEnvelope](../architecture/pane_runtime_architecture.md#contract-3-paneeventenvelope)
14. [Contract 5: PaneLifecycleStateMachine](../architecture/pane_runtime_architecture.md#contract-5-panelifecyclestatemachine)
15. [Contract 5a: Attach Readiness Policy (LUNA-295)](../architecture/pane_runtime_architecture.md#contract-5a-attach-readiness-policy-luna-295)
16. [Contract 5b: Restart Reconcile Policy (LUNA-324)](../architecture/pane_runtime_architecture.md#contract-5b-restart-reconcile-policy-luna-324)
17. [Contract 7a: Ghostty Action Coverage Policy (LUNA-325)](../architecture/pane_runtime_architecture.md#contract-7a-ghostty-action-coverage-policy-luna-325)
18. [Contract 10: Inbound Runtime Command Dispatch](../architecture/pane_runtime_architecture.md#contract-10-inbound-runtime-command-dispatch)
19. [Contract 11: Runtime Registry](../architecture/pane_runtime_architecture.md#contract-11-runtime-registry)
20. [Contract 12: NotificationReducer](../architecture/pane_runtime_architecture.md#contract-12-notificationreducer)
21. [Contract 12a: Visibility-Tier Scheduling (LUNA-295)](../architecture/pane_runtime_architecture.md#contract-12a-visibility-tier-scheduling-luna-295)
22. [Contract 13: Workflow Engine (deferred)](../architecture/pane_runtime_architecture.md#contract-13-workflow-engine-deferred)
23. [Contract 14: Replay Buffer](../architecture/pane_runtime_architecture.md#contract-14-replay-buffer)
24. [Contract 15: Terminal Process RPC (deferred)](../architecture/pane_runtime_architecture.md#contract-15-terminal-process-requestresponse-channel-deferred)
25. [Contract 16: Pane Filesystem Context (deferred)](../architecture/pane_runtime_architecture.md#contract-16-pane-filesystem-context-stream-deferred)
26. [Migration: NotificationCenter → AsyncStream](../architecture/pane_runtime_architecture.md#migration-notificationcenterdispatchqueue--asyncstreamevent-bus)
27. [Architectural Invariants (A1-A15)](../architecture/pane_runtime_architecture.md#architectural-invariants)
28. [Swift 6 Type and Concurrency Invariants](../architecture/pane_runtime_architecture.md#swift-6-type-and-concurrency-invariants)

## Ticket Links

1. `LUNA-295`: https://linear.app/askluna/issue/LUNA-295/pane-attach-orchestration-priority-scheduling-anti-flicker
2. `LUNA-325`: https://linear.app/askluna/issue/LUNA-325/bridge-pattern-surface-state-runtime-refactor
3. `LUNA-327`: https://linear.app/askluna/issue/LUNA-327/state-ownership-boundaries-observable-migration-coordinator-pattern
4. `LUNA-342`: https://linear.app/askluna/issue/LUNA-342/pane-runtime-contract-freeze-minimal-system-before-luna-325

## Requirement → Contract → Owner → Status Matrix

| Requirement | Contract | Design Section | Owner Ticket | Status |
|-------------|----------|---------------|--------------|--------|
| **Lifecycle state machine** | Contract 5 (PaneLifecycleStateMachine) | `created→ready→draining→terminated` | LUNA-325 | Design frozen |
| **Lifecycle invariants** | Arch Invariants A11, A12 | Forward-only transitions, idempotent shutdown | LUNA-342 (freeze) | Design frozen |
| **Priority classification** | Contract 4 (ActionPolicy) | `critical` / `lossy(consolidationKey)` | LUNA-325 | Design frozen |
| **Visibility-tier scheduling** | Contract 12a (VisibilityTier) | `p0→p1→p2→p3` delivery ordering, tier resolver | LUNA-295 | Design frozen |
| **Event type taxonomy** | Contract 2 (PaneKindEvent + PaneRuntimeEvent) | Per-kind enums, plugin escape hatch | LUNA-325 | Design frozen |
| **Self-classifying events** | Contract 4, Arch Invariant A7 | `PaneKindEvent.actionPolicy` | LUNA-342 (freeze) | Design frozen |
| **Envelope shape** | Contract 3 (PaneEventEnvelope) | `EventSource`, `seq`, `epoch`, `commandId` | LUNA-342 (freeze) | Design frozen |
| **Routing identity** | Arch Invariants A1, A15 | Envelope-only routing, scoping rules | LUNA-342 (freeze) | Design frozen |
| **Per-source ordering** | Arch Invariants A4, A5, A6 | Monotonic seq per source, cross-source best-effort | LUNA-342 (freeze) | Design frozen |
| **Attach readiness policy** | Contract 5a (AttachReadinessPolicy) | Active-visible vs background-prewarm, Ghostty embedding facts | LUNA-295 | Design frozen |
| **Restart reconcile** | Contract 5b (RestartReconcilePolicy) | zmx list, runnable/expired/orphan classification, TTL, health monitoring | LUNA-324 | Design frozen |
| **Attach sequencing** | Contract 5, Existing attach flow | `attachStarted→sizeObserved→sizeStabilized→attachSucceeded` | LUNA-295 | Design frozen |
| **GhosttyEvent FFI enum** | Contract 7 (GhosttyEvent) | Exhaustive C action mapping | LUNA-325 | Design frozen |
| **Ghostty action coverage** | Contract 7a (Action Coverage Policy) | Per-tag handler, routing, priority table | LUNA-325 | Design frozen |
| **GhosttyAdapter singleton** | D5 (Adapter→Runtime→Coordinator) | FFI boundary, `@Sendable` trampolines | LUNA-325 | Design frozen |
| **TerminalRuntime class** | Contract 1 (PaneRuntime protocol) | Per-pane instance, `@MainActor` | LUNA-325 | Design frozen |
| **Runtime registry** | Contract 11 (RuntimeRegistry) | `paneId→runtime` lookup, uniqueness enforcement on register | LUNA-325 | Design frozen |
| **Registry invariants** | Arch Invariants A2, A3 | One runtime per pane, sole lookup, unregister on terminate | LUNA-342 (freeze) | Design frozen |
| **NotificationReducer** | Contract 12 | Critical/lossy queues, injectable clock, frame timer | LUNA-325 | Design frozen |
| **Replay buffer** | Contract 14 (EventReplayBuffer) | Per-source ring buffer, bounded, gap detection | LUNA-325 | Design frozen |
| **Replay invariants** | Arch Invariants A9, A10 | v1 no restart-safe replay, bounded per source | LUNA-342 (freeze) | Design frozen |
| **Inbound command dispatch** | Contract 10 | `RuntimeCommandEnvelope`, capability check, lifecycle guard | LUNA-325 | Design frozen |
| **Filesystem batching** | Contract 6 | 500ms debounce, 2s max latency, per-worktree | LUNA-325 | Design frozen |
| **Execution backend** | D8, Contract 9 | Per-pane config, immutable, security events | LUNA-325 | Design frozen |
| **Execution backend invariant** | Arch Invariant A14 | Immutable after creation, no live migration in v1 | LUNA-342 (freeze) | Design frozen |
| **Metadata & dynamic views** | Contract 1 (PaneMetadata) | Optional fields, dynamic view contract | LUNA-325 | Design frozen |
| **Metadata invariant** | Arch Invariant A13 | All live fields optional, nil = excluded from grouping | LUNA-342 (freeze) | Design frozen |
| **Workflow engine** | Contract 13 (deferred) | WorkflowTracker, StepPredicate, correlationId | LUNA-325 (future) | Deferred |
| **Terminal process RPC** | Contract 15 (deferred) | Request/response channel, processSessionId ordering, idempotent requestId, ProcessOrigin | LUNA-325 (future) | Deferred |
| **Agent harness architecture** | Contract 15 (design intent) | MCP + CLI adapters, plugin-as-adapter model, command gateway, event gateway | LUNA-325 (future) | Deferred |
| **Contract vocabulary** | Contract Vocabulary section | Source/sink/projection role keywords, extensibility notes on Contracts 3/6/15/16 | LUNA-342 (freeze) | Design frozen |
| **Pane filesystem context** | Contract 16 (deferred) | Derived per-pane stream, CWD-scoped filter, shared worktree watcher | LUNA-325 (future) | Deferred |
| **Swift 6 invariants** | Swift 6 section (9 rules) | Sendable, no DispatchQueue, injectable clock, @MainActor | LUNA-342 (freeze) | Partially implemented |
| **Architectural invariants** | Arch Invariants (A1-A15) | Structural guarantees across all contracts | LUNA-342 (freeze) | Design frozen |
| **Migration path** | Migration section | NotificationCenter/DispatchQueue → AsyncStream/event bus, per-action atomic | LUNA-325/327 | Partially implemented |

### Status Legend

| Status | Meaning |
|--------|---------|
| **Design frozen** | Contract shape locked in `pane_runtime_architecture.md`. Implementation not started. |
| **Partially implemented** | Design frozen. Pre-work completed by LUNA-342 (see [Implementation Record](#luna-342-implementation-record)). Remaining work in LUNA-325. |
| **Deferred** | Designed at concept level, implementation deferred to future ticket. |
| **Deferred (additive)** | Can be added later without breaking existing contracts. |

## Ticket → Design Mapping (summary)

1. `LUNA-327` → state ownership and coordinator boundaries:
`D1`, `D5`, `Contract 1`, `Contract 11`, `Swift 6 invariants`, `Migration section` (partial — `DispatchQueue` → `MainActor`).
2. `LUNA-342` → contract freeze gate:
All design decisions (`D1`–`D8`), all contracts (`1`–`16`, `5a`, `5b`, `7a`, `12a`), all invariants (`A1`–`A15`, Swift 6 `1`–`9`).
3. `LUNA-325` → terminal adapter/runtime implementation:
`D4`, `D5`, `Contract 2`, `Contract 7`, `Contract 7a`, `Contract 10`, `Contract 12`, `Migration section` (primary — `NotificationCenter` → event bus).
4. `LUNA-295` → attach orchestration/scheduling:
`Contract 5a` (attach readiness), `Contract 12a` (visibility tiers), attach lifecycle diagram.
5. `LUNA-324` → restart reconcile:
`Contract 5b` (reconcile policy, orphan TTL, health monitoring).

## Deferred: Workflow Engine

1. Workflow scope is deferred and remains design-only until `LUNA-342` freeze and baseline `LUNA-325` transport/runtime foundations are complete.
2. Use `Contract 13` and `Contract 14` as the only canonical workflow references.

## Gate To Start Broad `LUNA-325` Implementation

1. Contract shapes frozen in `pane_runtime_architecture.md`.
2. Swift 6 typing/concurrency invariants explicitly satisfied in design.
3. Envelope/replay/workflow semantics aligned in design references above.

## Directory Placement

Contract types live in `Core/PaneRuntime/` (shared pane-system domain). Feature-specific implementations live in each `Features/X/` directory. See [Directory Structure](../architecture/directory_structure.md) for the full decision process.

```
Core/PaneRuntime/
├── Contracts/       # PaneRuntime protocol, events, envelopes, RuntimeCommand, policies
├── Registry/        # RuntimeRegistry
├── Reduction/       # NotificationReducer, VisibilityTier
└── Replay/          # EventReplayBuffer

Features/Terminal/
├── Ghostty/         # GhosttyAdapter (C FFI boundary)
└── Runtime/         # TerminalRuntime (PaneRuntime conformance)
```

### Naming: PaneAction vs RuntimeCommand

Contract 10's inbound command type is `RuntimeCommand` (not `PaneAction`). Two distinct action layers:

- `PaneAction` (`Core/Actions/`) — workspace structure mutations (selectTab, closePane, etc.)
- `RuntimeCommand` (`Core/PaneRuntime/Contracts/`) — commands to individual runtimes (sendInput, navigate, etc.)

## LUNA-342 Implementation Record

LUNA-342 implemented the Swift 6 language mode migration alongside the contract freeze. This section documents what was completed so LUNA-325 agents know what's already done.

### Completed: Swift 6 Language Mode

- `.swiftLanguageMode(.v5)` → `.swiftLanguageMode(.v6)` on both SPM targets (`Package.swift:34`, `Package.swift:61`)
- Build passes with zero Swift concurrency diagnostics
- Test suite passes in this branch's verification flow (benchmark suite may be skipped where noted)

### Completed: `isolated deinit` Migration

All `@MainActor` classes accessing non-Sendable stored properties in deinit now use `isolated deinit` (SE-0371):

| File | Class | What changed |
|------|-------|-------------|
| `NotificationReducer.swift:37` | `NotificationReducer` | `deinit` → `isolated deinit` |
| `PaneCoordinator.swift:89` | `PaneCoordinator` | `deinit` → `isolated deinit` |
| `SurfaceManager.swift:115` | `SurfaceManager` | `deinit { MainActor.assumeIsolated { ... } }` → `isolated deinit` (wrapper removed) |
| `SessionRuntime.swift:74` | `SessionRuntime` | `@MainActor deinit` → `isolated deinit` |
| `DrawerPanelOverlay.swift:54` | `DrawerDismissMonitor` | `deinit` → `isolated deinit` |
| `DraggableTabBarHostingView.swift:41` | `DraggableTabBarHostingView` | `deinit` → `isolated deinit` (NSView, implicitly @MainActor) |
| `GhosttySurfaceView.swift:235` | `Ghostty.SurfaceView` | `deinit` → `isolated deinit` (NSView) |
| `PaneTabViewController.swift:271` | `PaneTabViewController` | `deinit` → `isolated deinit` (NSTabViewController) |
| `AgentStudioTerminalView.swift:58` | `AgentStudioTerminalView` | `deinit` → `isolated deinit` (NSView) |

### Completed: `MainActor.assumeIsolated` Removal

Zero instances remain in Sources. `SurfaceManager.swift` was the last one — replaced by `isolated deinit`.

### Completed: C Callback Trampoline Migration

| File | What changed |
|------|-------------|
| `Ghostty.swift:110` | `wakeup_cb`: `DispatchQueue.main.async` → `Task { @MainActor in }` with `UInt(bitPattern:)` for Sendable pointer transfer |
| `Ghostty.swift:27` | `initialize()`: removed `DispatchQueue.main.sync` workaround, added `@MainActor` annotation |
| `Ghostty.swift:10,14,19,24` | `@MainActor` on namespace statics (`sharedApp`, `shared`, `isInitialized`, `initialize`) |

### Completed: Swift 6 Type Safety Fixes

| File | What changed |
|------|-------------|
| `PaneRuntimeEvent.swift:9` | `any PaneKindEvent` → `any PaneKindEvent & Sendable` |
| `PaneCommand.swift:24` | `any PaneKindCommand` → `any PaneKindCommand & Sendable` |
| `GhosttySurfaceView.swift:73` | `surface: ghostty_surface_t?` → `nonisolated(unsafe)` (FFI pointer for isolated deinit) |
| `GhosttySurfaceView.swift:854` | `NSTextInputClient` → `@preconcurrency NSTextInputClient` |
| `SessionRuntime.swift:25` | `SessionBackendProtocol: Sendable` → `@MainActor protocol SessionBackendProtocol` |
| `CommandBarPanelController.swift` | Added `@MainActor` annotation; animation completions → `Task { @MainActor in }` |
| `Ghostty.swift:245-290` | `userInfo` values changed from `Any` to `Int` for Sendable compliance |

### Completed: SwiftLint Concurrency Rules

`.swiftlint.yml` includes three concurrency anti-pattern rules (warning severity, strict mode).

**Reality snapshot guidance:**

| Rule | Pattern | Status |
|------|---------|--------|
| `no_dispatch_queue_main` | `DispatchQueue.main.async/sync` | Resolved in this branch |
| `no_notification_center_selector` | `addObserver(_:selector:...)` | Resolved in this branch |
| `no_task_detached` | `Task.detached` | Remaining migration scope |

Plus `unhandled_throwing_task` opt-in rule (0 violations).
Always re-run `mise run lint` before starting LUNA-325 work; counts drift as code moves.

---

## LUNA-325 Agent Implementation Guide

This section is for the agent implementing LUNA-325 on the `luna-325-bridge-pattern-surface-state-runtime-refactor` branch.

### What's already done (do not redo)

All items in the [LUNA-342 Implementation Record](#luna-342-implementation-record) above. Specifically:
- Swift 6 language mode is enforced — do not revert to `.v5`
- All `isolated deinit` migrations are complete
- `MainActor.assumeIsolated` is fully removed from Sources
- `DispatchQueue.main.async` / `DispatchQueue.main.asyncAfter` have been removed from Sources
- C callback trampolines in `Ghostty.swift` now use `Task { @MainActor in ... }` where needed
- Existential Sendable constraints on `PaneKindEvent`/`PaneKindCommand` are in place

### What you must address

Treat lint counts as live data from `mise run lint` output, not fixed numbers in this document.

**`no_dispatch_queue_main` — 0 violations**

This migration is complete in this branch. Do not re-introduce `DispatchQueue.main.async/sync`.

**`no_notification_center_selector` — current state**

Selector-based observers are removed in this branch (`0` current violations).  
Keep new observation code on async streams (`NotificationCenter.default.notifications(named:)`) or typed runtime event streams. Do not reintroduce selector observers.

**`no_task_detached` — outstanding detached task usage:**

`Features/Bridge/Push/Slice.swift` intentionally offloads cold-level JSON encoding to a background executor. Keep `Task.detached` only if profiling still justifies it, and keep inline suppression with explicit justification scoped to the detached call.

### Readiness Tasks (Cross-Ticket)

These tasks are required for LUNA-343 handoff readiness and Swift 6 strictness stability:

1. `Package.swift` language mode guard:
   Keep `.swiftLanguageMode(.v6)` on all active targets. No `.v5` fallback.
2. `isolated deinit` guard:
   Keep `isolated deinit` on actor-isolated classes that access stored state during teardown; no regression to nonisolated deinit workarounds.
3. `RPCMessageHandler.onValidJSON` guard:
   Keep `onValidJSON` `@MainActor`-isolated (no `nonisolated(unsafe)` regression). Any cross-isolation delivery must remain via explicit `Task { @MainActor in ... }` handoff.
4. Compiler-driven sweep:
   Run a full `swift build` + `swift test` + `mise run lint` pass and resolve any newly surfaced Swift 6 concurrency diagnostics before handoff.

### Concurrency Migration Rules (do not regress)

1. `Task {}` vs `Task { @MainActor in }`:
`Task {}` inherits actor isolation **only when the call site is already actor-isolated** (for example, inside `@MainActor` classes like `MainSplitViewController`/`PaneTabViewController`).  
Nonisolated static contexts (for example `Ghostty.App.handleAction` and `postSurfaceNotification`) must use explicit `Task { @MainActor in ... }`.

2. Timing nuance:
`DispatchQueue.main.async` and `Task {}` both defer past the current synchronous frame, but scheduler semantics differ (main dispatch queue vs MainActor executor). Validate each AppKit timing-sensitive replacement in behavior tests.

3. `for await` consumer lifecycle:
Every long-lived event consumption loop must run in a retained `Task` and be canceled on shutdown/deinit to avoid leaks.

```swift
eventConsumptionTask = Task { [weak self] in
    for await envelope in runtime.subscribe() {
        guard let self else { break }
        self.handle(envelope)
    }
}

isolated deinit {
    eventConsumptionTask?.cancel()
}
```

4. Async-stream observer helper trap:
Avoid helper APIs that accept `@Sendable` handler closures for notification migration (for example `observe(_:handler:)`). In Swift 6, that often strips actor isolation and causes `#ActorIsolatedCall` when handlers call `@MainActor` methods. Prefer inline `Task { for await ... }` in actor-isolated context.

5. AsyncStream continuation crossing isolation:
`AsyncStream.Continuation` is `Sendable`. `yield()` and `finish()` are safe from any isolation context, which is required for adapter-to-runtime event bridging.

6. FFI callback closure safety:
C callback trampolines are `@Sendable` entry points from arbitrary threads. Do not capture non-Sendable raw pointers directly across concurrency boundaries. Use `UInt(bitPattern:)` transfer + pointer reconstruction inside the target actor context.

### Architecture references

- [Migration: NotificationCenter/DispatchQueue → AsyncStream/Event Bus](../architecture/pane_runtime_architecture.md#migration-notificationcenterdispatchqueue--asyncstreamevent-bus)
- [D5: Adapter → Runtime → Coordinator](../architecture/pane_runtime_architecture.md#d5-adapter--runtime--coordinator-layering)
- [Swift 6 Concurrency](../architecture/appkit_swiftui_architecture.md#swift-6-concurrency)
- [Contract 7a: Ghostty Action Coverage Policy](../architecture/pane_runtime_architecture.md#contract-7a-ghostty-action-coverage-policy-luna-325)

### Verification

After addressing all violations:
1. `swift build` → zero errors, zero warnings
2. `swift test` → all tests pass (skip `PushPerformanceBenchmarkTests`)
3. `mise run lint` → zero violations

---

## LUNA-336 Structural Closure Checklist (Bridge transport/state/runtime)

- [x] Move bridge transport files to `Features/Bridge/Transport/`: `RPCRouter`, `RPCMethod`, `RPCMessageHandler`, `BridgeBootstrap`, `BridgeSchemeHandler`.
- [x] Move bridge method suites to `Features/Bridge/Transport/Methods/`: `AgentMethods`, `DiffMethods`, `ReviewMethods`, `SystemMethods`.
- [x] Move bridge domain state files to `Features/Bridge/State/`: `BridgeDomainState`, `BridgePaneState`.
- [x] Keep push pipeline under `Features/Bridge/State/Push/` to separate state transport from runtime orchestration.
- [x] Move `BridgePaneController` to `Features/Bridge/Runtime/`.
- [x] Move `PaneContent` to `Core/Models/` per the import/deletion/change-driver/multiplicity decision tests.
- [x] Update `docs/architecture/directory_structure.md` and `CLAUDE.md` component map to reflect `Transport/`, `Runtime/`, `State/`, and `Transport/Methods/`.

## LUNA-327 / LUNA-342 Follow-up Checklist (tracked here, implemented in owning tickets)

- [x] Add docs note for transient UI binding exception (`draggingTabId`, `dropTargetIndex`, `tabFrames`, `isSplitResizing`) in `docs/architecture/component_architecture.md`.
- [x] Add docs note for configuration injection pattern (constructor defaults + `private let`) in `docs/architecture/component_architecture.md`.
- [x] Add docs migration note for remaining production `Task.sleep` call sites in `WorkspaceStore`, `SessionRuntime`, `SurfaceManager`, `MainSplitViewController`, and `AppDelegate`.
- [x] Convert `SurfaceManager` config properties (`undoTTL`, `maxCreationRetries`, `healthCheckInterval`) to constructor-injected immutable config.
- [x] Migrate store-level `Task.sleep` usage to injected clocks in `WorkspaceStore`, `SessionRuntime`, and `SurfaceManager`.
- [ ] Move last-pane escalation domain rule from `PaneCoordinator.executeClosePane` into `WorkspaceStore` return signaling.
- [ ] Land `Core/PaneRuntime/` contract directories (`Contracts/`, `Registry/`, `Reduction/`, `Replay/`) in LUNA-342.

## Notes

This is the single plan file for pane-runtime ticket mapping.
All contract details remain only in the architecture design doc.
