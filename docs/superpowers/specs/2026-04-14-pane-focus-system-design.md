# Pane Focus System Design

**Problem**

Pane focus behavior is currently spread across pane views, tab views, coordinators, management-mode code, and mounted content wrappers. A single user interaction can currently mutate pane selection, AppKit first responder, terminal runtime focus, and web/DOM focus through separate code paths. This makes the behavior hard to reason about, hard to test as scenarios, and easy to regress, as shown by the recent WebView text-input focus bug.

**Goal**

Agent Studio will add a pane-scoped focus system that owns all pane-affecting focus triggers. The system will interpret pane-related triggers through explicit pane focus policies and apply explicit pane focus effects through one `@MainActor` executor. It is not a generic app-wide focus framework.

## Design Principles

```text
1. Pane selection and responder focus are different outputs.
2. Host responder changes are never implicit side effects of selection changes.
3. DOM focus and terminal runtime focus are downstream effects, not primary state.
4. All pane-affecting focus behavior must enter through one typed trigger surface.
5. All pane-affecting focus behavior must leave through one typed decision surface.
6. Compile-time exhaustiveness is required across trigger dispatch and decision execution.
```

## Scope Boundary

The Pane Focus System owns triggers that can affect pane-level focus state or pane-level responder state.

```text
+====================================================================+
| In scope                                                           |
+====================================================================+
| - pane content clicks                                              |
| - pane chrome clicks                                               |
| - tab clicks                                                       |
| - drawer pane clicks                                               |
| - drawer scrim/toggle/add interactions that affect pane focus      |
| - keyboard pane-navigation triggers                                |
| - command/menu-triggered pane or tab activation                    |
| - explicit pane refocus requests                                   |
| - management-mode entry/exit and management pane navigation        |
+====================================================================+
| Out of scope                                                       |
+====================================================================+
| - unrelated text field/popover focus systems                       |
| - generic app-wide focus concepts that never affect panes          |
| - hover-only visuals with no pane focus consequences               |
+====================================================================+
```

## Layer Model

```text
+----------------------+----------------------------------------------+ Owner              +
| Layer                | Responsibility                               |                    |
+----------------------+----------------------------------------------+--------------------+
| Selection            | activeTab / activePane / active drawer pane  | workspace atoms    |
| Host responder       | NSWindow.firstResponder and mounted content   | PaneFocusExecutor  |
| Terminal runtime     | active Ghostty surface                        | PaneFocusExecutor  |
| Web content          | DOM/input ownership                           | WKWebView/page     |
| Mode/navigation      | management mode and drawer navigation scope   | policies + atoms   |
+----------------------+----------------------------------------------+--------------------+
```

Atoms and derived selectors remain the canonical source of input state. They do not perform imperative focus effects.

## Core Architecture

```text
+-------------------+      +---------------------+      +--------------------+
| PaneFocusTrigger  | ---> | PaneFocusOrchestrator| ---> | PaneFocusDecision  |
| exhaustive enum   |      | exhaustive dispatch |      | exhaustive enum    |
+-------------------+      +---------------------+      +--------------------+
                                                               |
                                                               v
                                                        +------------------+
                                                        | PaneFocusExecutor|
                                                        | @MainActor       |
                                                        +------------------+
```

### Canonical Type Strategy

Top-level trigger and decision surfaces must be exhaustive enums. Each case carries a typed child payload struct.

```swift
enum PaneFocusTrigger: Sendable, Equatable {
    case contentClick(PaneContentClickFocusTrigger)
    case tabClick(PaneTabClickFocusTrigger)
    case drawer(PaneDrawerFocusTrigger)
    case keyboard(PaneKeyboardFocusTrigger)
    case mode(PaneModeFocusTrigger)
    case refocusRequest(PaneRefocusRequestTrigger)
    case command(PaneCommandFocusTrigger)
}

enum PaneFocusDecision: Sendable, Equatable {
    case noOp(PaneFocusNoOpDecision)
    case contentClick(PaneContentClickFocusDecision)
    case tabClick(PaneTabClickFocusDecision)
    case drawer(PaneDrawerFocusDecision)
    case keyboard(PaneKeyboardFocusDecision)
    case mode(PaneModeFocusDecision)
    case refocusRequest(PaneRefocusRequestDecision)
    case command(PaneCommandFocusDecision)
}
```

### Exhaustiveness Rules

```text
1. No `default` clauses in switches over PaneFocusTrigger or PaneFocusDecision.
2. Adding a new focus family requires adding a new enum case first.
3. Compiler errors become the migration checklist for orchestrator and executor.
4. Protocols may exist behind the enum boundary, never instead of it.
```

## Policy Interface

Policies stay distributed, not centralized in a god object. The top-level enum boundary stays exhaustive, but family dispatch is done by typed deciders rather than by a broad protocol that forces each implementation to accept unrelated trigger families.

Recommended family deciders:

```text
- PaneContentClickFocusDecider
- PaneTabClickFocusDecider
- PaneDrawerFocusDecider
- PaneKeyboardFocusDecider
- PaneModeFocusDecider
- PaneRefocusRequestFocusDecider
- PaneCommandFocusDecider
```

`PaneFocusOrchestrator` is the only component allowed to dispatch from the top-level trigger enum to these typed family deciders.

```swift
enum PaneFocusOrchestrator {
    static func decide(
        trigger: PaneFocusTrigger,
        context: PaneFocusContext
    ) -> PaneFocusDecision {
        switch trigger {
        case .contentClick(let trigger):
            return .contentClick(
                PaneContentClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .tabClick(let trigger):
            return .tabClick(
                PaneTabClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .drawer(let trigger):
            return .drawer(
                PaneDrawerFocusDecider.decide(trigger: trigger, context: context)
            )
        case .keyboard(let trigger):
            return .keyboard(
                PaneKeyboardFocusDecider.decide(trigger: trigger, context: context)
            )
        case .mode(let trigger):
            return .mode(
                PaneModeFocusDecider.decide(trigger: trigger, context: context)
            )
        case .refocusRequest(let trigger):
            return .refocusRequest(
                PaneRefocusRequestFocusDecider.decide(trigger: trigger, context: context)
            )
        case .command(let trigger):
            return .command(
                PaneCommandFocusDecider.decide(trigger: trigger, context: context)
            )
        }
    }
}
```

This preserves compile-time exhaustiveness while avoiding seven implementations that each need to reject six unrelated trigger families.

## Context Model

`PaneFocusContext` is one full snapshot struct passed to every policy. Family-specific helpers may derive narrower views, but the public policy contract stays uniform.

```text
+-------------------------- PaneFocusContext --------------------------+
| active tab / pane / drawer selection                                |
| pane kind and mounted-content capabilities                           |
| management mode state and navigation scope                           |
| window focus/key state                                               |
| terminal surface identity where relevant                             |
| whether target is already active                                     |
| whether trigger came from content, chrome, drawer, tab, etc.         |
+----------------------------------------------------------------------+
```

This keeps policy signatures stable, makes tests easy to set up, and avoids a family of near-duplicate context protocols.

### Context Assembly

`PaneFocusOrchestrator` is responsible for assembling `PaneFocusContext` immediately before policy dispatch.

```text
+-------------------------+-------------------------------------------+
| Component               | Responsibility                            |
+-------------------------+-------------------------------------------+
| PaneFocusOrchestrator   | assemble PaneFocusContext                 |
| typed family deciders   | consume already-built context             |
| policy tests            | use hand-built contexts                   |
| orchestrator tests      | verify assembly + dispatch               |
+-------------------------+-------------------------------------------+
```

The orchestrator may read atoms, derived selectors, and injected view/runtime registries as needed to assemble the snapshot. Policies themselves stay free of those dependencies.

## Decision Semantics

Each decision family carries only the outputs relevant to that family. The goal is not to encode every possible output on every case, but to keep each child payload small and explicit.

For example:

```swift
struct PaneContentClickFocusDecision: Sendable, Equatable {
    let selection: PaneContentClickSelectionAction
    let responder: PaneContentClickResponderAction
    let runtime: PaneContentClickRuntimeAction
    let content: PaneContentClickOwnershipAction
    let reason: PaneFocusReason
}
```

The same pattern applies to tab-click, drawer, keyboard, mode, command, and refocus-request families.

## Executor Boundary

`PaneFocusExecutor` is the sole place where imperative focus effects are allowed.

```text
+----------------------+----------------------------------------------+
| Allowed in executor  | Not allowed outside executor                 |
+----------------------+----------------------------------------------+
| update selection     | direct makeFirstResponder                    |
| focus pane host      | direct refocusActivePane                     |
| focus mounted content| direct terminal runtime sync                 |
| clear responder      | ad hoc responder mutation in views/controllers|
| sync terminal focus  |                                              |
+----------------------+----------------------------------------------+
```

This means existing direct calls to `makeFirstResponder(...)`, `refocusActivePane()`, and terminal focus sync helpers must be migrated behind the new executor path.

### Executor Timing Rule

Responder effects execute synchronously on `@MainActor` when the target view/window is ready.

```text
+---------------------------------------------------------------+
| Default behavior                                              |
+---------------------------------------------------------------+
| - run responder effects synchronously on @MainActor           |
| - do not defer with `Task { @MainActor ... }` by default      |
+---------------------------------------------------------------+
| Explicit fallback                                             |
+---------------------------------------------------------------+
| - defer only when target view/window is not yet attachable    |
| - readiness-driven retry is explicit, not implicit            |
+---------------------------------------------------------------+
```

This avoids timing-dependent interleavings in ordinary click and keyboard focus paths.

## Scenario Rules

### Rule 1: Active content click is a host no-op

```text
If:
- trigger = content click
- target pane is already active
- management mode policy does not explicitly override

Then:
- selection stays unchanged
- host responder stays unchanged
- terminal runtime sync stays unchanged
- content ownership stays with the mounted content
```

This is the core rule that prevents the WebView text-input bug.

### Rule 2: Inactive content click may activate the pane

```text
If:
- trigger = content click
- target pane is not already active

Then:
- pane/tab selection may change
- responder changes must be explicit, never implicit
- decision must be pane-kind-aware
```

### Rule 3: Selection does not imply responder reassignment

Selection changes and responder changes are separate outputs. Policies may select a pane/tab without moving AppKit first responder.

### Rule 4: Mode transitions are policy-driven

Management-mode entry/exit and management navigation become trigger families. They must not directly call responder mutation helpers.

### Rule 5: Refocus requests are first-class triggers

Any existing “restore focus to active pane” flows become `PaneFocusTrigger.refocusRequest(...)`. They are no longer allowed to call direct refocus helpers on their own.

## Pane-Kind Behavior

The same trigger family may produce different decisions by pane kind.

```text
+------------+--------------------------------------+----------------------+
| Pane kind  | Inactive content click               | Active content click |
+------------+--------------------------------------+----------------------+
| Terminal   | may activate + host/runtime focus    | host no-op           |
| Webview    | may activate, preserve DOM focus     | host no-op           |
| Bridge     | same family as webview by default    | host no-op           |
| CodeViewer | may activate + responder policy      | likely host no-op    |
+------------+--------------------------------------+----------------------+
```

This “same contract, different family payload” approach is the reason the system uses typed child payloads instead of a single bag-of-fields struct.

## Migration Rules

The branch goal is a full clean-cut focus-system migration. The implementation order can still be staged inside the branch, but the architecture does not support long-lived coexistence between old and new pane focus paths.

```text
1. Click triggers
   pane content, pane chrome, tabs, drawer interactions

2. Keyboard triggers
   pane navigation and focus-changing shortcuts

3. Mode triggers
   management-mode entry/exit/navigation

4. Command/refocus triggers
   command bar, menu, sidebar/filter-close, explicit refocus requests

5. Remove old direct focus paths
   ad hoc makeFirstResponder/refocus/syncFocus helpers
```

Architecturally this is one system. The staging is implementation order only.

### Hard Cutover From PaneActionCommand Focus

Pane-affecting focus stops being modeled as `PaneActionCommand.focusPane(...)`.

```text
+------------------------------------------------------------------+
| Hard cutover decision                                            |
+------------------------------------------------------------------+
| - pane focus selection/responder/runtime behavior moves into     |
|   PaneFocusTrigger -> PaneFocusDecision -> PaneFocusExecutor     |
| - `PaneActionCommand.focusPane` no longer owns pane focus flows  |
| - command/menu shortcuts that affect pane focus emit triggers    |
|   into the Pane Focus System instead                             |
+------------------------------------------------------------------+
```

## Existing Seams To Migrate

The following seams currently perform pane-affecting focus work and should be migrated into triggers or executor actions:

```text
- pane content tap selection in PaneLeafContainer
- active-pane host focus in PaneTabViewController.focusActivePane()
- explicit refocus in PaneTabViewController.refocusActivePane()
- pane-host responder forwarding in PaneHostView.becomeFirstResponder()
- management-mode first-responder clearing
- drawer pane activation / drawer open-close focus paths
- tab click selection paths
- sidebar-filter-close refocus path
- command/menu pane activation paths
```

## Testing Model

The Pane Focus System is validated with scenario-driven tests, not implementation-driven tests.

Each family should be testable as:

```text
given trigger + PaneFocusContext
when policy decides
then decision matches expected outputs
and no unrelated outputs are present
```

Representative scenarios:

```text
- click active webview text input -> no-op, preserve content focus
- click inactive webview text input -> select pane, preserve content focus
- click active terminal content -> no-op
- click inactive terminal content -> select pane, host/runtime focus
- click tab -> selection change, responder action explicit
- click drawer pane -> drawer selection explicit
- enter management mode -> mode policy decides responder/content behavior
- sidebar filter closes -> refocus request trigger, not direct helper call
- app/window becomes key -> refocus request trigger, not direct helper call
- pane creation/split/drawer add -> command-origin trigger with explicit focus policy
- terminal surface repair/recreation -> refocus request trigger with explicit executor path
```

## Reentrancy Rule

Pane focus execution is reentrant only through new external inputs. Executor side effects must not directly recurse into the orchestrator as part of the same application step.

```text
+---------------------------------------------------------------+
| Reentrancy rule                                               |
+---------------------------------------------------------------+
| - executor applies decision effects                           |
| - any AppKit/lifecycle callbacks caused by those effects are  |
|   treated as new external triggers                            |
| - executor does not synchronously emit fresh PaneFocusTrigger |
|   values during the same application step                     |
+---------------------------------------------------------------+
```

## Non-Goals

```text
- building a generic app-wide focus framework
- replacing unrelated text field/popover focus systems
- moving all app state into a new focus atom
- using callbacks or AsyncStream as the primary trigger/decision contract
```

## Concurrency Guidance

Swift 6.2 best practice for this system:

```text
- top-level trigger and decision surfaces are Sendable enums
- child payloads are Sendable structs/enums
- policies are pure or near-pure decision builders
- PaneFocusExecutor is @MainActor and owns side effects
- AsyncStream remains appropriate for true event streams, not click-policy contracts
```

This keeps the model explicit, testable, and compiler-enforced while fitting AppKit and the existing actor-bound state architecture.
