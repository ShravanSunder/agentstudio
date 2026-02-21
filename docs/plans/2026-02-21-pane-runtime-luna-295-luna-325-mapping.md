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
18. [Contract 14: Replay Buffer](../architecture/pane_runtime_architecture.md#contract-14-replay-buffer) (`docs/architecture/pane_runtime_architecture.md:1379`)
19. [Swift 6 Type and Concurrency Invariants](../architecture/pane_runtime_architecture.md#swift-6-type-and-concurrency-invariants) (`docs/architecture/pane_runtime_architecture.md:1579`)

## Ticket Links

1. `LUNA-295`: https://linear.app/askluna/issue/LUNA-295/pane-attach-orchestration-priority-scheduling-anti-flicker
2. `LUNA-325`: https://linear.app/askluna/issue/LUNA-325/bridge-pattern-surface-state-runtime-refactor
3. `LUNA-327`: https://linear.app/askluna/issue/LUNA-327/state-ownership-boundaries-observable-migration-coordinator-pattern
4. `LUNA-342`: https://linear.app/askluna/issue/LUNA-342/pane-runtime-contract-freeze-minimal-system-before-luna-325

## Ticket -> Design Mapping (minimal)

1. `LUNA-327` -> state ownership and coordinator boundaries:
`D1`, `D5`, `Contract 1`, `Contract 11`, `Swift 6 invariants`.
2. `LUNA-342` -> contract freeze gate:
`D1` through `D8`, `Contract 1`, `Contract 2`, `Contract 3`, `Contract 5`, `Contract 10`, `Contract 12`, `Contract 14`, `Swift 6 invariants`.
3. `LUNA-325` -> terminal adapter/runtime implementation:
`D4`, `D5`, `Contract 2`, `Contract 7`, `Contract 10`, `Contract 12`.
4. `LUNA-295` -> attach orchestration/scheduling:
`Architecture Overview` attach flow, `Contract 5`, `Contract 12`.

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
