# Drawer Navigation And Detach Design

## Problem

Drawer interaction currently stops short of the behavior the product wants.

- Outside drawers, pane focus uses the main-layout focus commands.
- Inside drawers, the state model already supports drawer-local panes and drawer-local mutations, but the keyboard model does not treat the drawer as its own navigation space.
- The shared `Layout` type used today is still a flat strip. `up` and `down` neighbor lookup return `nil`, and insertion ignores split direction in the current implementation. That is sufficient for the main pane row, but it is not sufficient for drawer-local `N x 2` movement and management-mode rearrangement.
- Drawer panes can be reordered and mutated, but there is no explicit “detach this drawer pane into the parent tab” command with validator-backed semantics.

The result is an unclear boundary: drawers already behave like mini pane containers in state, but keyboard navigation, layout legality, and promotion back to the parent tab are not modeled with the same clarity.

## Goal

Agent Studio will treat an open drawer as a first-class local pane container with its own navigation semantics, its own layout legality rules, and an explicit detach command.

The design must preserve these product rules:

- Outside drawers:
  - `⌥J` moves to the main-layout pane on the left
  - `⌥L` moves to the main-layout pane on the right
  - `⌥I` does nothing
  - `⌥K` opens or enters the active pane's drawer
- Inside an open drawer:
  - `⌥IJKL` are all movement keys
  - `⌥I` = up
  - `⌥J` = left
  - `⌥K` = down
  - `⌥L` = right
  - if there is no pane in the requested direction, the command is a no-op
- The same movement semantics must still work while management mode is active.
- Drawers may use richer layout only inside the drawer container, never in the main pane layout.
- Drawer layout editing in management mode may realize an `N x 2` drawer grid.
- A drawer pane can leave a drawer only through an explicit detach command.
- Detach inserts the promoted pane into the parent tab's main layout to the right of the parent pane.
- Empty open drawer creation rules:
  - outside management mode, `d` creates the first drawer pane
  - in management mode, only `p` creates the first drawer pane

## Non-Goals

- No change to the main pane layout model
- No change to tab arrangement semantics
- No implicit detach through keyboard movement
- No terminal-only key interception layer for this feature
- No broad generalization of `N x 2` layout rules to main panes or tab arrangements

## Direct Code Observations

These observations ground the design in the current codebase state.

- `Drawer` already owns `layout`, `activePaneId`, `isExpanded`, and `minimizedPaneIds` in `Sources/AgentStudio/Core/Models/Drawer.swift`.
- `PaneActionCommand` already contains drawer mutations such as `addDrawerPane`, `setActiveDrawerPane`, `insertDrawerPane`, `moveDrawerPane`, `resizeDrawerPane`, and `equalizeDrawerPanes` in `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`.
- `PaneTabViewController` currently resolves keyboard pane focus using main-layout neighbor lookup in `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`.
- `Layout` is still a flat pane strip in `Sources/AgentStudio/Core/Models/Layout.swift`:
  - `neighbor(of:direction:)` returns `nil` for `.up` and `.down`
  - `inserting(... direction: ...)` ignores the direction argument
- `WorkspaceCommandValidator` validates drawer actions only at a coarse level today, mostly by checking that the parent pane is showing. It does not validate drawer membership or drawer-shape legality strongly enough for `N x 2`.

## Boundary Split

This feature earns a structural boundary between main-pane layout and drawer layout.

### Main Pane Boundary

Main-pane layout stays exactly as it works today.

- The existing tab arrangement model remains the source of truth for main panes.
- Outside drawers, `⌥J` and `⌥L` continue to map to the existing main-pane left and right focus behavior.
- `⌥I` remains inert outside drawers.
- `⌥K` outside drawers enters drawer scope by opening or focusing the active pane's drawer.
- Main panes do not gain `N x 2` behavior.

### Drawer Boundary

The drawer becomes a drawer-specific pane container with richer local rules.

- Drawer navigation is directional and local to the open drawer.
- Drawer layout legality is independent from the main-pane arrangement model.
- Drawer mutation commands are validated against drawer-specific invariants.
- `N x 2` capability exists only in drawer scope.

This boundary prevents the main layout system from absorbing drawer-only complexity.

## Interaction Model

### Outside Drawer Scope

When the active focus scope is the main pane row:

- `⌥J` dispatches main-pane focus left
- `⌥L` dispatches main-pane focus right
- `⌥I` is ignored
- `⌥K` dispatches an explicit open-or-enter-drawer command

If the active pane has a drawer:

- opening the drawer makes drawer scope available
- if the drawer has an active drawer pane, focus enters that pane
- if the drawer is open but empty, focus remains on the parent pane and creation commands determine the first drawer pane

### Inside Drawer Scope

When drawer scope is active for a parent pane:

- `⌥I` moves to the drawer pane above the current drawer pane
- `⌥J` moves to the drawer pane to the left
- `⌥K` moves to the drawer pane below
- `⌥L` moves to the drawer pane to the right

If the requested neighbor does not exist, nothing changes.

Movement commands inside the drawer:

- do not create panes
- do not edit layout
- do not detach panes
- do not wrap

### Management Mode

Management mode does not create a separate movement model.

- The same drawer and main-pane movement semantics remain valid while management mode is active.
- Management mode continues to enable layout editing and other explicit management actions.
- Management-mode drawer editing may realize an `N x 2` drawer layout, but movement still uses the same directional rules as normal mode.

### Empty Drawer Creation

For an open drawer with zero panes:

- outside management mode, `d` creates the first drawer pane
- in management mode, only `p` creates the first drawer pane

No other shortcut becomes an implicit create path for the first drawer pane.

## Command Model

All behavior continues to flow through the normal app command system. No terminal-host override path is introduced for this feature.

The command surface should become explicit about drawer-local navigation and detach behavior.

### Main Navigation Commands

Existing main-pane focus commands remain the entry point for main-row navigation:

- `focusPaneLeft`
- `focusPaneRight`

The existing main-pane `up` and `down` commands remain separate from this feature's drawer scope.

### New Drawer Navigation Commands

Add explicit drawer-local movement commands:

- `focusDrawerPaneUp`
- `focusDrawerPaneLeft`
- `focusDrawerPaneDown`
- `focusDrawerPaneRight`

These commands are real application commands, not hidden controller-local actions. They should be available to:

- keyboard shortcut dispatch
- any future menu or management-layer trigger

### Drawer Entry Command

Add an explicit drawer entry command for the `⌥K` outside-drawer behavior. The command's job is:

- locate the active parent pane's drawer
- expand or activate that drawer if needed
- move focus into the drawer when possible

This command should not create the first drawer pane on its own.

### Detach Command

Add an explicit detach command:

- `detachDrawerPane(parentPaneId:, drawerPaneId:)`

Its semantics are:

1. validate the drawer child belongs to the given parent pane
2. remove the drawer pane from the drawer
3. insert the promoted pane into the parent tab's main layout to the right of the parent pane
4. keep view/runtime/focus updates in one coordinated action path

Detach is the only legal path for a drawer pane to leave the drawer.

## Drawer Layout Model

The current shared `Layout` type is too flat for this feature. The drawer needs its own layout semantics.

### Why A Drawer-Specific Layout Model Is Required

The shared `Layout` type is intentionally simple for main-pane strips. That simplicity is useful for the main pane row, but it blocks:

- vertical neighbor lookup
- explicit two-row legality
- drawer-local insertion and movement semantics that differ from the main row

Changing the global `Layout` type to satisfy drawer behavior would spread drawer-only complexity into tab arrangements. That is the wrong tradeoff.

### Drawer Layout Requirements

The drawer layout model must support:

- directional neighbor lookup for up, left, down, right
- insertion and movement within the drawer
- management-mode drag and rearrangement
- at most two rows
- any number of columns needed to represent the active drawer contents
- stable serialization with deterministic legality checks

The precise shape may be implemented as a drawer-specific value type built from two horizontal row layouts plus one vertical split ratio, but the boundary must stay drawer-local.

### Legality Rule

Drawer layout is legal if and only if:

- every referenced drawer pane belongs to the same parent drawer
- every referenced drawer pane exists
- no pane is duplicated
- the layout uses at most two rows
- the layout does not orphan any existing drawer pane during a validated move or insertion

Main layouts do not adopt this legality rule.

## Validation Design

Validation must be designed with drawer-specific invariants in mind from the start.

### Validator Responsibilities

Drawer-related validation must answer all of these questions before execution:

- does the parent pane exist
- is the parent pane in the correct visible or active scope for this action
- does the target drawer pane belong to that parent drawer
- does the source drawer pane belong to that parent drawer
- is the requested movement or insertion legal for this drawer
- does the resulting drawer layout remain within the `N x 2` limit
- is detach targeting a real selected drawer pane

### Validation Split

Use a dedicated drawer-layout validation helper behind `WorkspaceCommandValidator`.

- `WorkspaceCommandValidator` remains the entry point
- drawer-specific legality is delegated to a narrow helper or planner
- main-pane validation remains unchanged except for the new drawer-entry command

This keeps the validator surface centralized while keeping drawer-shape logic out of generic tab validation.

### Drawer Validation Rules By Action

#### Drawer Focus Movement

For `focusDrawerPaneUp/Left/Down/Right`:

- validate that drawer scope is active or activatable for the parent pane
- validate the current drawer pane belongs to the parent drawer
- if neighbor exists, movement is legal
- if neighbor does not exist, the command is a valid no-op

The no-neighbor case must not be treated as an error state.

#### Drawer Editing

For drawer move/insert/resize/equalize actions:

- validate parent ownership
- validate source and target membership
- validate post-action `N x 2` legality
- reject any action that would create a third row

#### Empty Drawer Create

For “create first drawer pane” behavior:

- outside management mode, validate only `d`
- in management mode, validate only `p`
- reject unsupported key paths even if the drawer is open and empty

#### Detach

For `detachDrawerPane(parentPaneId:, drawerPaneId:)`:

- validate parent pane exists
- validate parent pane owns the drawer pane
- validate the drawer pane is a drawer child, not a main pane
- validate the parent pane belongs to a tab and visible arrangement suitable for insertion
- validate the promotion target to the right of the parent pane is legal in the main layout

## Coordinator And Focus Effects

Execution should preserve the existing architecture: coordinators sequence multi-store operations but do not own domain rules.

### Detach Sequencing

Detach is a multi-store action and should be sequenced atomically:

1. resolve the parent pane's tab and target insertion position
2. remove the drawer pane from the parent drawer model
3. reclassify the pane as a main-layout pane
4. insert it into the parent tab's main layout to the parent's right
5. update active pane and focus state explicitly
6. preserve runtime and view ownership during the promotion

Any domain decision about whether detach is legal belongs in validation or drawer-layout helpers, not in the coordinator.

### Focus Routing

Keyboard movement and drawer entry continue to use the pane focus system.

- Outside drawers, existing main-pane focus triggers remain unchanged.
- Inside drawers, drawer movement should become explicit pane-focus triggers or explicit commands that resolve into pane-focus decisions.
- The focus system must understand drawer scope so the responder and runtime effects stay aligned with selected pane state.

## Testing Strategy

This feature is test-first by default. The implementation plan must preserve strict TDD.

### TDD Rule

Every behavior change starts with a failing test at the narrowest layer that can prove the requirement.

Do not batch implementation first and tests later.

### Required Test Layers

#### 1. Shortcut And Command Resolution Tests

Prove the keymap and scope rules:

- outside drawer:
  - `⌥I` inert
  - `⌥J` main left
  - `⌥L` main right
  - `⌥K` drawer entry
- inside drawer:
  - `⌥IJKL` resolve to drawer movement commands
- management mode:
  - same movement semantics still apply
- empty drawer:
  - outside management mode, `d` creates first drawer pane
  - in management mode, only `p` creates first drawer pane

#### 2. Drawer Layout Unit Tests

Pure tests for drawer-local layout semantics:

- directional neighbor lookup
- no-neighbor movement returns no-op
- legal `N x 2` shapes
- rejection of any operation that would create a third row
- stable movement and insertion within one drawer

#### 3. Validator Tests

Prove legality checks:

- cross-drawer moves rejected
- wrong-parent drawer actions rejected
- invalid detach rejected
- detach accepted only for real drawer-child selection
- empty-drawer create rules enforced by management-mode state

#### 4. Coordinator / Integration Tests

Prove multi-store behavior:

- drawer entry focuses the expected drawer pane
- detach promotes the pane into the parent tab to the right of the parent pane
- drawer editing in management mode can realize legal `N x 2` layouts
- main-pane arrangement behavior remains unchanged

### Test Quality Rules

- No wall-clock sleeps
- No test-only behavior hidden behind production conditionals
- Model math tested as pure value behavior first
- Integration tests only for real seams: command routing, focus scope, detach promotion, coordinator sequencing

## Summary Of Decisions

- Main-pane layout and drawer layout are separate boundaries.
- Main-pane behavior stays simple and unchanged.
- Drawer behavior becomes richer and explicit.
- `⌥IJKL` are universal movement keys only while drawer scope is active.
- `⌥J/⌥L` outside drawers remain main-pane left/right.
- `⌥I` outside drawers is inert.
- `⌥K` outside drawers opens or enters drawer scope.
- Management mode keeps the same movement semantics.
- Drawer-only layout editing may realize `N x 2`.
- Detach is explicit, one-way, and validator-backed.
- TDD is mandatory and must be visible in the plan task structure.
