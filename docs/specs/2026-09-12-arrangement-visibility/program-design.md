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

## Creation delta and existing-identity placement

The current generic insertion methods also serve existing-pane moves, drawer
detach/rollback, reactivation and undo. The creation-only U6 rule must not change
those consumers. Distinguish lifecycle meaning with named entry points, not a
legacy flag or a second version of the behavior.

```text
New terminal identity (Core creation composition)
New webview identity (App creation branch)
           |
           v
creation-specific insertion entry → current + Default
           |
           v
shared private placement mechanics → existing atomic publication/persistence
           ^
           |
existing placement entry → all arrangements (unchanged)
           ^
           |
move / detach rollback / reactivate / restore existing identity
```

Core `TabArrangementMutationRules.insertingNewPane` and `insertingNewDrawerPane`
apply only at current and Default indices, once when equal. The existing
`insertingPane`/`insertingDrawerPane` placement entries retain all-arrangement
behavior for existing identities. Both call shared private placement mechanics;
this is two legitimate operations, not compatibility staging. Keep creation
placement direction/sizing; append Default when different; unrelated custom values
stay untouched. Membership is appended once.

Expose matching narrow creation-specific forwarding entries in the existing
arrangement/tab-layout owners. Do not change old existing-placement callers to
creation merely because their names include “insert.” Physical drawer identity and
child-parent relationship remain with their existing owner.

| Caller | Entry / preserved meaning |
| --- | --- |
| WorkspaceTerminalCreationComposition split/drawer after new UUIDv7 Pane preparation | New-identity placement, current+Default |
| WorkspaceSurfaceCoordinator newWebview split/drawer after successful pane creation | New-identity placement, current+Default |
| PaneSource.existingPane | Existing placement across arrangements, unchanged |
| Drawer detach promotion/rollback | Existing placement, unchanged |
| WorkspaceMutationCoordinator reactivation / restoreFromPaneSnapshot | Existing placement, unchanged |
| WorkspaceUndoRestoreComposition | Existing restoration/recorded drawer views, unchanged |
| Cross-tab pane move / merge dedicated path | Unchanged |

Intentionally unchanged: admission, existing-placement behavior, equal-write
publication, schema, persistence, Default repair, runtime construction, and close/
removal propagation. New custom arrangement creation also keeps its current explicit
behavior. Proof must exercise both new-identity production entries and existing
identity preservation; changing a generic test helper's behavior is not that proof.

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

## Synchronous callers and dependent effects

The async decision must not let existing follow-on effects outrun focus. Use an
inner async `prepareAndApplyTargetFocus` operation accepting the already-admitted
workspace `execute` closure; it does not submit another gesture. An outer wrapper
submits one whole user operation and returns its `Task<Bool, Never>`. Callers already
inside a submitted operation invoke the inner helper directly. Never await a new
submission behind the gesture currently executing; that would await its own tail.

| Existing consumer | Whole-operation ordering after cutover |
| --- | --- |
| Explicit focusPane | Prepare/apply focus, then complete the submitted task |
| editPaneNote | Await exact focus, then present the note; failure presents nothing |
| retained pane-inbox targeted path | Await focus, then its existing presentation; do not reconnect dormant Inbox wiring |
| executeZoomCommand requiring another tab | Resolve capability inside admitted operation, await target focus, then reattach/enter/retarget/reconcile zoom |
| enterZoomAndShowViewer | Await zoom application in the same operation, then inspect presentation and request/show viewer |
| focusMainPaneOrdinal when zoom retargets | Resolve ordinal, await zoom effect when required, then apply exact focus trigger; no immediate post-submit continuation |
| Bridge surface reuse | Set scoped pending attendance event immediately before focus, await successful focus, verify attendance, then request surface; clear scoped intent on failure |
| pane.focus IPC adapter | Await the exact submitted focus task before returning focused:true; failure uses existing layout error cases |

Private synchronous dispatch handlers may report *handled/admitted*, as their
routing purpose requires, but must not report operation completion or inspect
post-focus state until the task finishes. Split pure capability checks from async
effect functions so canExecute remains synchronous and side-effect free. All private
callers of zoom/viewer effect functions follow the same async composition; there is
no legacy synchronous focus fallback.

For IPC, change App-local `PaneFocusAppControlling.focusPane` and the matching
`AppIPCLayoutPort.focusPane` to async throws. The JSON method/parameters/result shape
remain unchanged. `AgentStudioIPCLayoutAdapter` awaits the control result; the
already-async server layout route awaits it just as it awaits split/close. Existing
sync protocol fakes may satisfy an async requirement, but tests invoking the port
must await completion. This preserves the meaning of focused:true instead of
turning it into an unlabelled admission receipt.

Extend the integration proof to cover focus→zoom/viewer, focus→Bridge reuse, and
focus→note ordering with a controlled predecessor/decision suspension. Use the
existing executor submission result/barrier seam; no sleeps or DEBUG-only hooks.

## Threading, state and interleavings

No new persistent or observed state is needed. Pure insertion remains within the
existing atomic workspace mutation transaction; it now visits fewer arrangement
values. This is not a new high-rate projection or a rationale for moving sidebar
derivation onto MainActor. AppKit and atom application remain MainActor-owned.

Core captures the target tab's immutable graph value using the existing keyed
`WorkspaceTabGraphAtom.tabState` access, plus its existing accepted graph revision
and current arrangement ID. Keep graph types internal by exposing one narrow
package snapshot-capture API at the owning Core boundary; raw capture reads existing
atom values only. Visibility decisions live in the separate pure policy, never
in an atom method. The snapshot may wrap
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
payload or runtime ownership boundary is introduced. The focus port becomes async
at source level to preserve completion semantics; its wire schema is unchanged. No migration or dual path is
needed: replace the old insertion/reveal behavior in place.

## Source anchors

- [Mutation](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift), [repair](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementRepairRules.swift), [validation](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift).
- [Persistence graph validation](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraphValidation.swift) and [drawer validation](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraphDrawerValidation.swift).
- [Creation owner](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+PaneInsertion.swift) and [focus owner](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift).
- [Existing focus integration](../../../Tests/AgentStudioTests/App/PaneTabViewControllerTargetedFocusCommandTests.swift) and [arrangement invariants](../../../Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift).
