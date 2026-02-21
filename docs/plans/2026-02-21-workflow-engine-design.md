# Workflow Engine Design

> Extracted from [Pane Runtime Architecture](../architecture/pane_runtime_architecture.md) Contract 13. This is a deferred design — implementation ships when multi-agent orchestration (JTBD 6) moves from "stay in flow" to "automate cross-agent handoffs."

---

## Problem

When agent A finishes editing files and agent B should start reviewing, the user currently has to manually notice the exit, open a diff, approve it, and signal the next agent. This is the "inverse of Cursor" flow described in the architecture overview — but without temporal coordination, the user is still the message bus.

The workflow engine tracks multi-step cross-pane sequences so the coordinator can advance them automatically when matching events arrive.

---

## Design

### WorkflowTracker

```swift
/// Tracks temporal workflows that span multiple panes and events.
/// "Agent finishes → create diff → user approves → signal next agent"
///
/// Owned by PaneCoordinator. Pure state tracking — no domain logic.
/// The coordinator uses this to know which workflow step to advance
/// when a matching event arrives.
///
/// Restart-safe: on coordinator recovery, replay events from replay
/// buffers to find the current position of each active workflow.
@MainActor
final class WorkflowTracker {

    struct Workflow: Sendable {
        let correlationId: UUID
        let steps: [WorkflowStep]
        var currentStepIndex: Int
        var state: WorkflowState
        let createdAt: ContinuousClock.Instant
    }

    struct WorkflowStep: Sendable {
        let commandId: UUID
        let description: String
        /// What event completes this step. Matched by the tracker.
        let completionPredicate: StepPredicate
        var completed: Bool
    }

    /// How a step is considered complete.
    enum StepPredicate: Sendable {
        /// Any event with this commandId
        case commandCompleted(UUID)
        /// A specific event kind on a specific pane (typed identity)
        case eventMatch(paneId: UUID, eventName: EventIdentifier)
        /// Approval decision on a specific pane
        case approvalDecided(paneId: UUID)
    }

    enum WorkflowState: Sendable {
        case active
        case waitingForEvent(stepIndex: Int)
        case completed
        case failed(reason: String)
        case timedOut
    }

    private var activeWorkflows: [UUID: Workflow] = [:]

    /// Start tracking a new workflow. Returns correlationId.
    func startWorkflow(steps: [WorkflowStep]) -> UUID { ... }

    /// Process an incoming event. If it matches a step predicate,
    /// advance the workflow and return what action to take next.
    func processEvent(_ envelope: PaneEventEnvelope) -> WorkflowAdvance? { ... }

    /// Recovery: replay events to reconstruct workflow positions.
    /// Called on coordinator restart.
    func recover(from events: [PaneEventEnvelope]) { ... }

    /// Expire workflows older than TTL. Returns expired correlationIds.
    func expireStale(ttl: Duration, now: ContinuousClock.Instant) -> [UUID] { ... }
}

enum WorkflowAdvance: Sendable {
    /// Step completed, workflow still active. No action needed.
    case stepCompleted(correlationId: UUID, stepIndex: Int)
    /// Workflow fully completed. Clean up.
    case workflowCompleted(correlationId: UUID)
    /// Step completed, trigger next step's action.
    case triggerNext(correlationId: UUID, action: PaneActionEnvelope)
}
```

---

## Example: Agent Finish → Diff → Approval

```
Workflow correlationId: abc-123
Steps:
  [0] commandFinished on pane-A (terminal)    ← completed by GhosttyEvent
  [1] loadDiff on pane-D (diff viewer)        ← triggered by coordinator
  [2] approvalDecided on pane-D               ← completed by user action
  [3] sendInput on pane-B (next terminal)     ← triggered by coordinator

Event arrives: .terminal(pane-A, .commandFinished(exitCode: 0))
  → WorkflowTracker matches step [0]
  → returns .triggerNext(abc-123, loadDiff action on pane-D)
  → coordinator dispatches DiffAction.loadDiff to pane-D

Event arrives: .diff(pane-D, .diffLoaded(stats))
  → step [1] marked complete (event match)
  → returns .stepCompleted (waiting for approval)

Event arrives: .artifact(.approvalDecided(pane-D, .approved))
  → step [2] matched
  → returns .triggerNext(abc-123, sendInput action on pane-B)
  → coordinator sends TerminalAction.sendInput to next agent
```

---

## Integration Points

- **PaneEventEnvelope.correlationId** links all events in a workflow chain
- **PaneCoordinator** owns the WorkflowTracker instance and feeds it every critical event
- **EventReplayBuffer** provides recovery data — on coordinator restart, replay to find current workflow positions
- **StepPredicate.eventMatch** uses `PaneKindEvent.eventName` for stable string matching across event enum versions

---

## Open Questions

1. **Workflow definition source** — Are workflows defined in code, in a config file, or dynamically via the command bar? Likely all three eventually, but the first implementation should pick one.
2. **Failure policy** — When a step times out, should the whole workflow fail or just pause? Should the user be notified immediately or only on final failure?
3. **Branching** — The current model is linear (step 0 → 1 → 2 → 3). Real workflows may branch ("if tests pass, deploy; if tests fail, notify"). DAG workflows are significantly more complex to track and recover.
4. **User override** — Can the user manually advance or skip a workflow step? What happens to the tracker state?

---

## Relationship to Architecture

This design depends on:
- [PaneRuntimeEvent](../architecture/pane_runtime_architecture.md) — Contract 2 (event stream)
- [PaneActionEnvelope](../architecture/pane_runtime_architecture.md) — Contract 10 (inbound actions)
- [EventReplayBuffer](../architecture/pane_runtime_architecture.md) — Contract 14 (recovery)
- [PaneKindEvent.eventName](../architecture/pane_runtime_architecture.md) — step predicate matching
