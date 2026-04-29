# Last Drawer Pane Crash Debug Note

## Problem

Closing the last pane in an expanded drawer crashed the app.

Expected behavior:

```text
drawer has 1 pane
  -> user closes it
  -> close animation starts
  -> drawer pane is removed
  -> drawer stays open
  -> drawer becomes empty
  -> focus lands in emptyDrawer context
```

## What We First Thought Was Wrong

At first, the suspected bug was a focus bug:

```text
close last drawer pane
  -> app refocuses parent pane host
  -> terminal responder churn
  -> crash
```

That older bug shape was addressed by changing the last-drawer-pane path so it now:

```text
close last drawer pane
  -> prerefocus empty drawer
  -> clear first responder to window content
  -> detach surface
  -> refocus empty drawer
  -> controller replay also stays in empty drawer
```

So the drawer state machine and focus ownership path became correct.

## What The Logs Proved

The important trace looked like this:

```text
PaneLeafContainer.performClose ... drawerChild=true
PaneCoordinator.removeDrawerPane ... willBecomeEmptyDrawer=true
PaneCoordinator.removeDrawerPane prerefocus emptyDrawer ...
PaneCoordinator.clearFirstResponderToWindowContent ... didClear=true
PaneCoordinator.teardownView start ...
SurfaceManager.detach begin/end ...
PaneCoordinator.teardownView unregisterView ...
PaneCoordinator.teardownView unregisterRuntime ...
PaneCoordinator.teardownView removeSession ...
PaneCoordinator.teardownView finish ...
PaneCoordinator.removeDrawerPane refocus emptyDrawer ...
PaneTabViewController.syncFocusOwnerAfterValidatedAction ...
PaneTabViewController.syncFocusOwnerAfterDrawerMutation ...
PaneTabViewController.clearFirstResponderToWindowContentForDrawer ... didClear=true
```

That ruled out:

- wrong drawer state
- parent-pane refocus
- surface detach failure
- view unregister failure
- runtime unregister failure
- session removal failure

## The Actual Crash

The real failure ended with:

```text
Fatal error: ViewRegistry.slot(for:) lazy fallback paneId=...
```

So the actual crash site was:

```text
ViewRegistry.slot(for:)
```

not:

- `SurfaceManager.detach`
- `TerminalPaneMountView.becomeFirstResponder`
- drawer focus routing

## What Was Happening

The real race was:

```text
MODEL LAYER
  drawer pane removed from store
        │
        ▼
REGISTRY LAYER
  slot removed for that pane id
        │
        ▼
VIEW LAYER
  SwiftUI still performs one stale transition render
  using the old paneSegments
        │
        ▼
FlatPaneStripContent asks:
  viewRegistry.slot(for: removedPaneId)
        │
        ▼
slot is gone
        │
        ▼
assertion / crash
```

## Why Main-Pane Last Close Does Not Hit The Same Problem

Main-pane last close is different:

```text
single main pane in tab
  -> canonicalized to closeTab
  -> whole tab subtree goes away
```

Drawer last-pane close is different:

```text
last drawer pane
  -> remove drawer child in place
  -> parent pane remains
  -> tab remains
  -> drawer remains
  -> one stale child render is possible
```

So the drawer case is more transition-sensitive because the parent UI survives while the child disappears.

## Grounding In Code

The stale slot lookup happens in:

- `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`

The drawer child close/removal flow goes through:

- `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`

The failing invariant lives in:

- `Sources/AgentStudio/App/Panes/ViewRegistry.swift`

## Clean Summary

The crash was not primarily about focus anymore.

The app was already:

- transitioning to `emptyDrawer`
- clearing first responder correctly
- detaching the Ghostty surface correctly
- unregistering view/runtime/session correctly

The remaining crash was a stale `ViewRegistry` slot read during the drawer close transition after the pane had already been removed.

## One-Line Takeaway

```text
The drawer close path became correct semantically, but the slot lifecycle was still too eager for SwiftUI's transition frame.
```
