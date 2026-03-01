# Pane Validation Spec

## TL;DR

This document is the canonical validation contract for pane drag/drop behavior in management mode. It defines:

1. Which validator owns which decision.
2. The required parity between preview visibility and drop commit eligibility.
3. Drawer modal interaction constraints.
4. Target ownership boundaries between tab-level and drawer-level drop capture.

It complements, and does not replace:

- [Component Architecture](component_architecture.md)
- [AppKit + SwiftUI Hybrid Architecture](appkit_swiftui_architecture.md)

---

## Scope

This spec governs:

1. Split/drop targeting (`PaneDragCoordinator`, `SplitContainerDropCaptureOverlay`)
2. Drop planning (`PaneDropPlanner`)
3. Action validation (`ActionValidator`)
4. Tab-bar pane insertion semantics
5. Drawer-modal interaction gating in management mode

This spec does not define session backend lifecycle behavior (zmx/surface internals), except where validator contracts explicitly constrain UI actions.

---

## Swift 6.2 Constraints

Validation logic must remain deterministic and side-effect free under Swift 6.2 concurrency:

1. Validator and planner layers are pure-value decision engines.
2. UI drop-capture layers must run on `@MainActor` for UI event and drop-capture handling, and must not mutate domain state during preview.
3. Preview and drop commit must both invoke the same planner function against an `ActionStateSnapshot` captured at evaluation time (no cached eligibility reuse across events).
4. Commit execution occurs only after planner eligibility, then flows through `PaneAction` -> `ActionExecutor` -> `PaneCoordinator` -> store mutation APIs.

---

## Validator Ownership Table

| Layer | Owner | Input | Output | Reject Surface |
|---|---|---|---|---|
| Target resolution | `PaneDragCoordinator` + drop-capture overlay | pointer location + pane frames + optional container bounds | `PaneDropTarget?` | no marker shown |
| Planning | `PaneDropPlanner` | `SplitDropPayload` + `PaneDropDestination` + `ActionStateSnapshot` | `PaneDropPreviewDecision` + `DropCommitPlan` | ineligible decision |
| Action validation | `ActionValidator` | `PaneAction` + `ActionStateSnapshot` | `Result<ValidatedAction, ActionValidationError>` | rejected action, no commit |

Contract: lower layers never bypass higher layers for eligibility-sensitive behavior.

---

## Management-Mode Drawer Modal State Machine

```text
Normal
  | Cmd+E / toggle
  v
ManageIdle
  | expand drawer
  v
ManageDrawerModal
  | valid drag candidate
  v
DragPreview
  | drop accepted
  v
DragCommit
  | teardown (drop end / mouse up / blur / mode off)
  v
ManageDrawerModal or ManageIdle
```

### State semantics

1. `Normal`: no management drag affordances, no management-only drop targets.
2. `ManageIdle`: management affordances enabled, no drawer modal overlay.
3. `ManageDrawerModal`: expanded drawer behaves as modal focus surface.
4. `DragPreview`: visible target exists only if planner says eligible.
5. `DragCommit`: execute exactly the planned commit action.

---

## Interaction Gating Contract

When `ManageDrawerModal` is active:

1. Background pane content is non-interactive.
2. Background pane management affordance visuals do not activate.
3. Outside click dismisses drawer first.
4. Drawer interactions remain active inside drawer exclusion zone.

This ensures “click-away to dismiss” has deterministic priority over background pane interaction.

---

## Target Ownership Contract

Only one drop-capture owner should be active for a pointer context:

| Context | Active owner | Inactive owner |
|---|---|---|
| tab split drag (no drawer modal) | tab-level split drop capture | drawer-level capture |
| drawer drag (drawer modal active) | drawer-level drop capture | tab-level split capture |
| tab-bar insertion drag | tab-bar host insertion resolver | split/drop capture overlays |

---

## Movement Matrix

| Source | Destination | Preview | Commit | Validator Path |
|---|---|---|---|---|
| layout pane (single-pane tab) | tab bar insertion | visible if eligible | `moveTab` | planner -> action validator |
| layout pane (multi-pane tab) | tab bar insertion | visible if eligible | `extractPaneToTab` then tab move | planner -> action validator |
| drawer child pane | tab bar insertion | hidden | rejected | planner (ineligible) |
| drawer child pane | drawer pane (same parent) | visible if eligible | `moveDrawerPane` | planner -> action validator |
| drawer child pane | drawer pane (different parent) | hidden | rejected | planner (ineligible) |
| layout pane/tab/new terminal payload | split target in layout | visible if eligible | resolved `PaneAction` | target -> planner -> action validator |
| any payload | management mode off | hidden | rejected | planner (mode gate) |

---

## Preview Commit Parity Contract

Rule 1: A preview marker must never render for an ineligible commit.  
Rule 2: A commit path must not execute unless preview would have been eligible for the same snapshot and destination.  
Rule 3: Tab-bar insertion and split/drop must both use planner-backed eligibility semantics, not parallel ad-hoc logic.  
Rule 4: Drawer child constraints are evaluated from snapshot state, not payload-only hints.

---

## Sequence Reference

```text
Pointer update
  -> Target resolver (frames + bounds)
  -> Planner (payload + destination + snapshot)
  -> ActionValidator (candidate action)
  -> Marker visible (eligible only)

Drop
  -> Target resolver
  -> Planner
  -> ActionValidator
  -> Execute DropCommitPlan
  -> Teardown target state
```

---

## Test Mapping

Validation coverage is organized across three unit-test layers:

1. Action validator tests: action-level constraints and canonicalization.
2. Planner matrix tests: payload/destination eligibility matrix.
3. Target ownership tests: drop-capture owner exclusivity + modal gating behavior.

Visual checks are tracked separately in guide docs and should verify the modal and marker contracts in a live UI.

