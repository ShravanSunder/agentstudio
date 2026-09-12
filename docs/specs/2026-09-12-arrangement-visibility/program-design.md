# Arrangement visibility program design

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) →
[Specification](specification.md) → this structural design.

## Ownership and the smallest change

Keep the current workspace mutation and pane-focus owners. Change which arrangements
receive new panes and which existing arrangement an explicit target selects. Do not
add an atom, store, bus event, global coordinator or a preview runtime.

```text
App command / existing sidebar pane action
          |
          v
AppCommandDispatcher                 unchanged authority/validation
          |
          v
PaneTabViewController                committed focus sequencing
          |
          +→ Core arrangement visibility policy   new pure decision
          |
          +→ existing workspace actions           switch/expand/select
          |
          v
PaneFocusOrchestrator → PaneFocusExecutor → existing native host/runtime

Creation action → WorkspaceSurfaceCoordinator → existing arrangement mutation owner
                                                     |
                                  changed TabArrangementMutationRules
                                                     |
                                  current + Default only
```

Core owns the policy because arrangement membership, parent/drawer placement and
minimization are shared domain facts. App owns applying a committed navigation
request to focus and existing action owners. Feature callers continue dispatching
the same focusPane identity. Core does not import App or sibling Features.

The meaningful alternative is inserting each new pane minimized into every custom
layout. Reject it: it changes unrelated layout geometry and creates collapsed-pane
representations. Omitting the pane from unrelated custom arrangements is supported
by existing validation and persistence, whose completeness rule is union-of-all-
arrangements plus Default, not completeness of every custom layout.

## Creation delta

Current: `WorkspaceActionCommand.insertPane` →
`WorkspaceSurfaceCoordinator.executeInsertPane` → existing arrangement atom →
`TabArrangementMutationRules.insertingPane` inserts/appends and unminimizes in every
arrangement. Drawer creation reaches `insertingDrawerPane` for each arrangement
containing the parent.

Changed: both pure value transformations apply placement only to the active and
Default arrangement indices (once when equal). Keep active placement direction and
sizing exactly as requested. Default receives the existing append behavior when
different. Other custom arrangement values are untouched. Append membership once.

For drawers, mutate/install the existing physical drawer's view only at those two
indices, provided its parent belongs there; do not allocate a second drawer or
insert the child into the main layout. Reuse current child placement policy.

Intentionally unchanged: mutation admission, equal-write publication, storage
schema, persistence serialization, Default repair, pane runtime construction,
and close/removal propagation. New custom arrangements retain existing explicit
creation behavior; this change governs insertion into already-existing arrangements.

## Visibility policy interface

Expose a package-level Core pure policy adjacent to arrangement selection rules,
with inputs: ordered `[PaneArrangement]`, active arrangement ID, target pane ID,
and optional parent pane ID plus physical drawer ID. The caller obtains parent/
drawer identity from canonical pane state, never from the sidebar label or row index.

The nonisolated pure policy is invoked through a `@concurrent nonisolated` async
entry so its layout/visibility scan is off MainActor.

Return an optional selected arrangement ID. `nil` means no valid target-bearing
fallback, not permission to choose any pane. The policy does no I/O, mutation,
window lookup, sorting, focus, or persistence. Repeated calls with equal values
return the same result. Main target eligibility is layout membership and absence
from minimized IDs; drawer eligibility adds visible parent, child drawer-view
membership and absence from that drawer view's minimized IDs. Physical drawer
collapse is handled later as an effect.

```text
pure policy
    current passes? ─ yes → current ID
          |
          no
    first custom passes? ─ yes → its ID
          |
          no
    target belongs to Default? ─ yes → Default ID
          |
          no → nil
```

Only current/custom candidates require unminimized child state.
Default fallback requires actual parent/child membership and may require a later
child expansion; it does not use the current/custom visibility predicate.
Default fallback requires actual target membership. The current store normalizes
Default completeness, but the policy must still return nil for stale/inconsistent
input rather than inventing a target.

## Committed focus delta and ordering

Current main path: targeted focusPane → `focusTargetedPane` → command focus trigger →
executor selectPane callback → select tab → membership-only reveal helper → expand
current minimized pane → set active pane and responder/runtime focus.

Changed main path: enter the existing serialized `submitGesture` operation, capture
and resolve the exact target, then execute validated selectTab/switchArrangement
workspace actions before focus orchestration. Remove the direct atom-switch edge
from the membership-only helper. The switch action owns host detach/reattach and
geometry reevaluation; direct atom assignment would omit those effects. Only after
successful actions and current-target validation does the existing focus trigger
select the pane/responder. Do not expand the current custom merely because it
contains the target. All existing committed callers of the helper must be routed
through the same preparation, not given an unvalidated fallback.

```text
MainActor gesture: capture target-tab values + graph revision + active arrangement
       | immutable Sendable snapshot
       v
Concurrent Core policy: ordered visibility/membership scan
       | decision or nil
       v
MainActor gesture: revalidate snapshot token/target relationship
       | current
       v
validated selectTab / switchArrangement → detach/reattach/geometry owner
       | applied and still current
       v
existing focus orchestrator/executor → exact native target
```

No successful result is reported when the snapshot is superseded or the target is
invalid. Preserve the existing gesture result as false; do not act on a stale plan.
This is a stale-input rejection, not a new automatic retry or debounce mechanism.

Current drawer path opens/expands before parent focus can choose an arrangement.
Changed drawer sequence:

```text
validate target/parent/tab/drawer
    → choose target-child arrangement
    → switch owning tab and chosen arrangement through existing actions
    → re-read live drawer view
    → open physical drawer if collapsed
    → expand child if fallback has it minimized
    → select/focus parent and exact child through existing focus ingress
```

Parent focus must not override the child-selected arrangement: the parent is visible
there, so the main policy retains current. After each awaited mutation, revalidate
that target, parent relationship, tab and selected arrangement still exist. A
failed step stops the remaining sequence; do not restore a stale whole-tab snapshot.
Preserve the existing gesture execution owner and command failure result path.

## Threading, state and interleavings

No new persistent or observed state is needed. Pure insertion remains within the
existing atomic workspace mutation transaction; it now visits fewer arrangement
values. This is not a new high-rate projection or a rationale for moving sidebar
derivation onto MainActor. AppKit and atom application remain MainActor-owned.

Core captures the target tab's immutable graph value using the existing keyed
`WorkspaceTabGraphAtom.tabState` access, plus its existing accepted graph revision
and current arrangement ID. Keep graph types internal by exposing one narrow
package snapshot/resolve API from the owning Core boundary; the snapshot may wrap
internal Sendable graph data without making the entire graph public. Do not rebuild
all tabs or join pane fleets on MainActor for this query.

The concurrent pure resolver runs inside the existing serialized gesture's async
body. Before applying its result, Core/App recheck the captured graph revision,
current arrangement ID, pane/parent/drawer identity and target liveness using keyed
reads. No full-array equality comparison on MainActor substitutes for revision
validation. A superseded decision returns a rejected outcome without mutations.
After each awaited workspace action, revalidate the chosen arrangement and exact
target before the next effect. AppKit/atom publication remains MainActor-owned;
new candidate derivation does not. No cache, timer, bus signal or new atom is added.

| Interleaving / fault | Containment |
| --- | --- |
| Target absent before dispatch | Existing validation rejects; no state mutation |
| Target closes during drawer awaits | Revalidation stops; existing close owner cleans up |
| Arrangement changed/removed during awaits | Do not act on the stale drawer view; stop rather than expanding a different arrangement |
| Repeated focus of already-visible target | Policy retains arrangement; existing focus equal-write/ownership behavior applies |
| Persistence rejects malformed state | Existing error path; no schema bypass or fallback mutation |

The policy does not control preview. A sidebar preview may later consume visibility
facts but cannot call committed focus and blindly undo it. That independent design
question must not cause this capability to introduce temporary snapshots or UI owners.

## Proof and enforcement

| Specification | Realization | Proof seam |
| --- | --- | --- |
| R-A1/R-A2 | active+Default-only pure mutation; unchanged other values | existing store integration and persisted graph round-trip |
| R-A3/R-A4 | Core visibility policy; corrected App focus ordering | pure policy tests plus targeted focus harness and native visible-host/focus readback |
| R-A5 | existing dispatch authority plus live revalidation after awaits | stale UUID, removed arrangement/child and controlled close interleavings |

Tests should use existing store/action/focus paths for integration; fake native focus
cannot establish real responder ownership. Policy-only inputs may use constructed
value layouts. Native proof should select hidden/minimized main and drawer panes,
including a Bridge destination, and inspect both visible content and focus. Never
treat a broad pane-count snapshot as proof of arrangement visibility.

Architecture boundaries are enforced by package imports, narrow visibility, existing
architecture lint, and behavior tests. No new permission, secret, network, telemetry
payload or runtime ownership boundary is introduced. No migration or dual path is
needed: replace the old insertion/reveal behavior in place.

## Source anchors

- [Mutation](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift), [repair](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementRepairRules.swift), [validation](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift).
- [Persistence graph validation](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraphValidation.swift) and [drawer validation](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraphDrawerValidation.swift).
- [Creation owner](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+PaneInsertion.swift) and [focus owner](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift).
- [Existing focus integration](../../../Tests/AgentStudioTests/App/PaneTabViewControllerTargetedFocusCommandTests.swift) and [arrangement invariants](../../../Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift).
