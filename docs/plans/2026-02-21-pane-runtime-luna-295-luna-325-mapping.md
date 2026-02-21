# Pane Runtime Ticket Mapping (Minimal, Single Plan File)

## Canonical Design

- [`docs/architecture/pane_runtime_architecture.md`](../architecture/pane_runtime_architecture.md)

## Design Heading Index (numbered references)

1. [Design Decisions](../architecture/pane_runtime_architecture.md#design-decisions) (`docs/architecture/pane_runtime_architecture.md:24`)
2. [D1: Per-pane-type runtimes, not actor-per-pane](../architecture/pane_runtime_architecture.md#d1-per-pane-type-runtimes-not-actor-per-pane) (`docs/architecture/pane_runtime_architecture.md:28`)
3. [D2: Single typed event stream, not three separate planes](../architecture/pane_runtime_architecture.md#d2-single-typed-event-stream-not-three-separate-planes) (`docs/architecture/pane_runtime_architecture.md:62`)
4. [D3: @Observable for UI state, event stream for coordination](../architecture/pane_runtime_architecture.md#d3-observable-for-ui-state-event-stream-for-coordination) (`docs/architecture/pane_runtime_architecture.md:72`)
5. [D4: GhosttyEvent enum at FFI boundary for exhaustive capture](../architecture/pane_runtime_architecture.md#d4-ghosttyevent-enum-at-ffi-boundary-for-exhaustive-capture) (`docs/architecture/pane_runtime_architecture.md:82`)
6. [D5: Adapter -> Runtime -> Coordinator layering](../architecture/pane_runtime_architecture.md#d5-adapter--runtime--coordinator-layering) (`docs/architecture/pane_runtime_architecture.md:90`)
7. [D6: Priority-aware event processing](../architecture/pane_runtime_architecture.md#d6-priority-aware-event-processing) (`docs/architecture/pane_runtime_architecture.md:99`)
8. [D7: Filesystem observation with batched artifact production](../architecture/pane_runtime_architecture.md#d7-filesystem-observation-with-batched-artifact-production) (`docs/architecture/pane_runtime_architecture.md:105`)
9. [D8: Execution backend as pane configuration, not pane type](../architecture/pane_runtime_architecture.md#d8-execution-backend-as-pane-configuration-not-pane-type-jtbd-7-jtbd-8) (`docs/architecture/pane_runtime_architecture.md:111`)
10. [Contract 1: PaneRuntime Protocol](../architecture/pane_runtime_architecture.md#contract-1-paneruntime-protocol) (`docs/architecture/pane_runtime_architecture.md:276`)
11. [Contract 2: PaneKindEvent Protocol + PaneRuntimeEvent Enum](../architecture/pane_runtime_architecture.md#contract-2-panekindevent-protocol--paneruntimeevent-enum) (`docs/architecture/pane_runtime_architecture.md:434`)
12. [Contract 3: PaneEventEnvelope](../architecture/pane_runtime_architecture.md#contract-3-paneeventenvelope) (`docs/architecture/pane_runtime_architecture.md:615`)
13. [Contract 5: PaneLifecycleStateMachine](../architecture/pane_runtime_architecture.md#contract-5-panelifecyclestatemachine) (`docs/architecture/pane_runtime_architecture.md:684`)
14. [Contract 10: Inbound Action Dispatch](../architecture/pane_runtime_architecture.md#contract-10-inbound-action-dispatch) (`docs/architecture/pane_runtime_architecture.md:991`)
15. [Contract 11: Runtime Registry](../architecture/pane_runtime_architecture.md#contract-11-runtime-registry) (`docs/architecture/pane_runtime_architecture.md:1126`)
16. [Contract 12: NotificationReducer](../architecture/pane_runtime_architecture.md#contract-12-notificationreducer) (`docs/architecture/pane_runtime_architecture.md:1187`)
17. [Contract 13: Workflow Engine (deferred)](../architecture/pane_runtime_architecture.md#contract-13-workflow-engine-deferred) (`docs/architecture/pane_runtime_architecture.md:1371`)
18. [Contract 14: Replay Buffer](../architecture/pane_runtime_architecture.md#contract-14-replay-buffer)
19. [Contract 15: Terminal Process Request/Response Channel (deferred)](../architecture/pane_runtime_architecture.md#contract-15-terminal-process-requestresponse-channel-deferred)
20. [Contract 16: Pane Filesystem Context Stream (deferred)](../architecture/pane_runtime_architecture.md#contract-16-pane-filesystem-context-stream-deferred)
21. [Architectural Invariants (A1-A15)](../architecture/pane_runtime_architecture.md#architectural-invariants)
22. [Swift 6 Type and Concurrency Invariants](../architecture/pane_runtime_architecture.md#swift-6-type-and-concurrency-invariants)

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
| **Visibility-tier scheduling** | D6 (deferred addendum) | `p0→p1→p2→p3` delivery ordering | LUNA-295 | Deferred (additive) |
| **Event type taxonomy** | Contract 2 (PaneKindEvent + PaneRuntimeEvent) | Per-kind enums, plugin escape hatch | LUNA-325 | Design frozen |
| **Self-classifying events** | Contract 4, Arch Invariant A7 | `PaneKindEvent.actionPolicy` | LUNA-342 (freeze) | Design frozen |
| **Envelope shape** | Contract 3 (PaneEventEnvelope) | `EventSource`, `seq`, `epoch`, `commandId` | LUNA-342 (freeze) | Design frozen |
| **Routing identity** | Arch Invariants A1, A15 | Envelope-only routing, scoping rules | LUNA-342 (freeze) | Design frozen |
| **Per-source ordering** | Arch Invariants A4, A5, A6 | Monotonic seq per source, cross-source best-effort | LUNA-342 (freeze) | Design frozen |
| **Attach sequencing** | Contract 5, Existing attach flow | `attachStarted→sizeObserved→sizeStabilized→attachSucceeded` | LUNA-295 | Design exists (in architecture doc) |
| **GhosttyEvent FFI enum** | Contract 7 (GhosttyEvent) | Exhaustive C action mapping | LUNA-325 | Design frozen |
| **GhosttyAdapter singleton** | D5 (Adapter→Runtime→Coordinator) | FFI boundary, `@Sendable` trampolines | LUNA-325 | Design frozen |
| **TerminalRuntime class** | Contract 1 (PaneRuntime protocol) | Per-pane instance, `@MainActor` | LUNA-325 | Design frozen |
| **Runtime registry** | Contract 11 (RuntimeRegistry) | `paneId→runtime` lookup, precondition on register | LUNA-325 | Design frozen |
| **Registry invariants** | Arch Invariants A2, A3 | One runtime per pane, sole lookup, unregister on terminate | LUNA-342 (freeze) | Design frozen |
| **NotificationReducer** | Contract 12 | Critical/lossy queues, injectable clock, frame timer | LUNA-325 | Design frozen |
| **Replay buffer** | Contract 14 (EventReplayBuffer) | Per-source ring buffer, bounded, gap detection | LUNA-325 | Design frozen |
| **Replay invariants** | Arch Invariants A9, A10 | v1 no restart-safe replay, bounded per source | LUNA-342 (freeze) | Design frozen |
| **Inbound action dispatch** | Contract 10 | `PaneActionEnvelope`, capability check, lifecycle guard | LUNA-325 | Design frozen |
| **Filesystem batching** | Contract 6 | 500ms debounce, 2s max latency, per-worktree | LUNA-325 | Design frozen |
| **Execution backend** | D8, Contract 8 | Per-pane config, immutable, security events | LUNA-325 | Design frozen |
| **Execution backend invariant** | Arch Invariant A14 | Immutable after creation, no live migration in v1 | LUNA-342 (freeze) | Design frozen |
| **Metadata & dynamic views** | Contract 1 (PaneMetadata) | Optional fields, dynamic view contract | LUNA-325 | Design frozen |
| **Metadata invariant** | Arch Invariant A13 | All live fields optional, nil = excluded from grouping | LUNA-342 (freeze) | Design frozen |
| **Workflow engine** | Contract 13 (deferred) | WorkflowTracker, StepPredicate, correlationId | LUNA-325 (future) | Deferred |
| **Terminal process RPC** | Contract 15 (deferred) | Request/response channel, processSessionId ordering, idempotent requestId | LUNA-325 (future) | Deferred |
| **Agent harness architecture** | Contract 15 (design intent) | MCP + CLI adapters, command gateway, event gateway | LUNA-325 (future) | Deferred |
| **Pane filesystem context** | Contract 16 (deferred) | Derived per-pane stream, CWD-scoped filter, shared worktree watcher | LUNA-325 (future) | Deferred |
| **Swift 6 invariants** | Swift 6 section (9 rules) | Sendable, no DispatchQueue, injectable clock, @MainActor | LUNA-342 (freeze) | Design frozen |
| **Architectural invariants** | Arch Invariants (A1-A15) | Structural guarantees across all contracts | LUNA-342 (freeze) | Design frozen |

### Status Legend

| Status | Meaning |
|--------|---------|
| **Design frozen** | Contract shape locked in `pane_runtime_architecture.md`. Implementation not started. |
| **Deferred** | Designed at concept level, implementation deferred to future ticket. |
| **Deferred (additive)** | Can be added later without breaking existing contracts. |

## Ticket → Design Mapping (summary)

1. `LUNA-327` → state ownership and coordinator boundaries:
`D1`, `D5`, `Contract 1`, `Contract 11`, `Swift 6 invariants`.
2. `LUNA-342` → contract freeze gate:
All design decisions (`D1`–`D8`), all contracts (`1`–`14`), all invariants (`A1`–`A15`, Swift 6 `1`–`9`).
3. `LUNA-325` → terminal adapter/runtime implementation:
`D4`, `D5`, `Contract 2`, `Contract 7`, `Contract 10`, `Contract 12`.
4. `LUNA-295` → attach orchestration/scheduling:
Architecture overview attach flow, `Contract 5`, `Contract 12`, `D6` visibility tiers.

## Deferred: Workflow Engine

1. Workflow scope is deferred and remains design-only until `LUNA-342` freeze and baseline `LUNA-325` transport/runtime foundations are complete.
2. Use `Contract 13` and `Contract 14` as the only canonical workflow references.

## Gate To Start Broad `LUNA-325` Implementation

1. Contract shapes frozen in `pane_runtime_architecture.md`.
2. Swift 6 typing/concurrency invariants explicitly satisfied in design.
3. Envelope/replay/workflow semantics aligned in design references above.

## Notes

This is the single plan file for pane-runtime ticket mapping.
All contract details remain only in the architecture design doc.
