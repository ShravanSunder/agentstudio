# Drawer, Bridge, and Pane Zoom — System Analysis

Scope: the affected Agent Studio presentation, source-context, command, geometry,
and persistence system before revising Requirements and Specification. Source:
`improvements-viewing` at `85ae48f5e`, inspected on 2026-09-13. The separately
inspected `ipc-improvements` checkout has the same tracked HEAD and additional
untracked design documents. No implementation or native reproduction is claimed.

## Findings that change the design

1. Bridge's **content**, its **source worktree**, its **placement**, and the
   **terminal that initiated navigation** are separate concepts. The existing
   pane model can represent more placements than the product should expose.
2. Normal mode and Pane Zoom share the floating drawer renderer but do not have
   the same geometry: normal leaf frames include their footer; Zoom has a footer
   below its source/companion split. Their shared offset calculation is suspect.
3. Drawer height is currently one shared preference, not a per-pane value.
   Rendering and bootstrap/activation separately calculate drawer geometry.
4. “Create New in Pane → Files/Review” does not create Bridge in that pane. It
   invokes a reuse-or-new-tab command. This is a source-confirmed menu/behavior
   mismatch, distinct from a decision about allowed future Bridge placements.
5. Normal durable Bridge panes can own drawers today, and the owner explicitly
   wants to preserve that useful behavior. This is different from Bridge being
   drawer content. No normal UI route creates Bridge as a drawer child, but
   generic model/restore support is broader.
6. Jitter has a plausible moving-gesture-coordinate hypothesis and possible
   persistence/redraw amplification. Neither is a proven runtime cause yet.
7. The other agent's `file.open`/CodeViewer flow is an unimplemented draft whose
   owning decision record now defers that work. It is not a current product path.

## Current composition

```text
Workspace tab
  ├─ Normal: active arrangement → ordinary pane leaves + their toolbars
  │                              + one floating drawer overlay
  │
  └─ Pane Zoom: terminal source | optional Bridge companion
                                shared toolbar below both
                                + one floating drawer overlay over both

Drawer ownership: source/parent pane → drawer → child panes
Drawer presentation: overlay → existing one/two-row child layout
Bridge source: selected Git worktree → File / continuous Review / annotations
```

The drawer's active child is focus/selection in a grid, not a single displayed
page. All non-minimized children can render concurrently. The rejected
right-hand Bridge/drawer switcher would therefore have changed the presentation
model, not merely moved a control.

Sources: [SingleTabContent](../../Sources/AgentStudio/App/Panes/Hosting/SingleTabContent.swift),
[ZoomPresentationContainer](../../Sources/AgentStudio/App/Panes/Hosting/ZoomPresentationContainer.swift),
[DrawerPanel](../../Sources/AgentStudio/App/Panes/Hosting/DrawerPanel.swift),
[DrawerPanelOverlay](../../Sources/AgentStudio/App/Panes/Hosting/DrawerPanelOverlay.swift).

## State and ownership

| Fact | Current owner / representation | Consequence |
| --- | --- | --- |
| Main pane identity and content | Workspace pane graph; `PaneContent` includes terminal, webview, Bridge, CodeViewer. | Content kind alone does not prescribe where a pane may appear. |
| Drawer parent/child membership | Drawer structure and workspace pane graph. | Moving the full-screen overlay need not move or recreate its children. |
| Drawer layout, minimized children, selected child | Arrangement-level drawer views. | Changing outer overlay geometry is separate from changing child splits. |
| Which drawer is expanded | `WorkspaceDrawerCursorAtom` stores one expanded drawer ID. | Expansion is a cursor, not a height/position preference. |
| Height | `@AppStorage("drawerHeightRatio")`, also read directly through `UserDefaults`. | A resize is shared by overlays using that preference; there is no per-owner or per-mode key. |
| Width | `DrawerLayout.panelWidthRatio = 0.8`. | There is no saved user width or side in the current overlay. |
| Zoom source, companion, visibility, split ratio | `WorkspacePanePresentationAtom`, runtime state. | Per-source split ratios survive runtime retargeting, not through a demonstrated durable preference contract. |
| Bridge root | `BridgePaneState.source.workspace(rootPath:baseline:)` plus runtime repo/worktree metadata. | Root identity outranks incidental CWD in established workspace-source panes. |
| Annotation catalog | Worktree identity. | Changing roots cannot be treated as relabeling the same annotation context. |

Primary owners: [Drawer](../../Sources/AgentStudio/Core/Models/Drawer.swift),
[drawer cursor](../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceDrawerCursorAtom.swift),
[Zoom state](../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePanePresentationAtom.swift),
[workspace snapshot](../../Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift),
[annotation catalog](../../Sources/AgentStudio/Features/Bridge/State/SQLite/WorktreeAnnotations/WorktreeAnnotationSQLiteRepository+CatalogLoading.swift).

`UIStateStore` is specifically the sidebar-state persistence wrapper despite its
general name. Its current fields are not drawer geometry. A future per-pane
drawer preference needs an explicitly justified home; the name “UI state” is
not evidence that this wrapper is the right owner.

### Persistence and lifetime

Core SQLite keeps pane/drawer membership and arrangement drawer layouts. Local
SQLite keeps expansion and selected-child cursors; missing or stale local
cursors are projected back to safe choices from the core graph. Actual keyboard
focus is a separate runtime fact. The global height preference sits outside
both of these drawer-state paths.

Closing a drawer child through its visible pane close action preserves the
generic `closePane` action and can participate in durable undo. Explicit drawer
discard is a different path with responder handoff and permanent removal.
Collapsing the overlay does neither: it changes visibility while keeping the
owned children. Zoom cancellation removes the presentation, not the underlying
drawer membership. Companion retirement is separate transient view/runtime
cleanup.

Sources: [SQLite cursor composition](../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift),
[drawer close dispatch](../../Sources/AgentStudio/App/Panes/Hosting/DrawerPanel.swift),
[durable close/undo](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+Undo.swift),
[explicit discard](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+PaneDiscard.swift),
[companion retirement](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ZoomCompanion.swift).

## Current opening and movement paths

| Entry | Current effect | Important boundary |
| --- | --- | --- |
| Repo/worktree “Create New in Tab → Files/Review” | Always creates an independent Bridge tab. | The worktree is supplied explicitly. |
| “Create New in Pane → Files/Review” | `showBridgeFiles` / `showBridgeReview`: reuse eligible Bridge for the worktree; otherwise create a tab. | The submenu label promises placement its command does not carry. |
| `showViewer` / Worktree Viewer | Enter/toggle the Zoom-local Bridge companion. | Not a plain CodeViewer action; only a terminal is eligible as a Zoom source. |
| `bridge.fileView.open` / `bridge.diff.load` | Create a Bridge tab from optional registered worktree ID. | No path, line, drawer/split, focus or reuse argument on these open contracts. |
| `bridge.fileTree.revealPath` | Select exact path in an existing Bridge tree/comparison. | A second operation; requires usable surface metadata and does not prove rendered arrival. |
| Move/drag a durable Bridge main pane | Generic pane movement can put it in a main split. | Main-layout planning is not a Bridge-only placement policy. |
| Split a terminal beside a Bridge target | Generic split creation accepts the main-layout target. | Preventing Bridge dragging alone would not make every Bridge tab a sole-pane tab. Whether that broader restriction is intended remains open. |
| Drag main pane into a drawer | Rejected by main drop planning. | Drawer rearrangement admits an existing child of the same drawer parent. |
| Add/toggle drawer on a normal Bridge main pane | Allowed by current generic capability/IPC checks. | A Bridge-owned drawer is different from Bridge being drawer content. |
| Restore/undo generic pane content | Can reconstruct broader model states than current UI creation offers. | Future restrictions need an explicit existing-layout policy; hiding a menu is insufficient. |

Sources: [menu](../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerContextMenuPresenter.swift),
[Bridge action execution](../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift),
[opening](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift),
[reuse](../../Sources/AgentStudio/Core/Actions/BridgePaneCommandResolver.swift),
[IPC Bridge adapter](../../Sources/AgentStudio/App/IPCComposition/AgentStudioIPCBridgeAdapter.swift),
[IPC drawer adapter](../../Sources/AgentStudio/App/IPCComposition/AgentStudioIPCLayoutAdapter.swift),
[drop planner](../../Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift),
[drawer drops](../../Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift),
[Zoom eligibility](../../Sources/AgentStudio/Core/Actions/ZoomCommandCapabilityPolicy.swift).

## CWD is not one identity

```text
Terminal launch directory
        ↓ shell may move
Terminal-reported CWD → association against registered repo/worktree topology
        ↓ contextual opening default
Bridge captures one explicit worktree root
        ↓
File tree / Git comparison / worktree annotation context

An agent can operate on a path in B without changing terminal A's reported CWD.
An explicit registered worktree B can already be opened independently of A.
```

An existing independent Bridge retains its captured root. A Zoom companion is
reconciled against its terminal source's validated association; changing that
association retires/recreates the companion context while retaining supported
visibility/surface continuity. Leaving registered topology can make the
companion unavailable.

Contextual independent opening first resolves the active pane; if that fails,
it can fall back to the only registered worktree. That fallback is not safe
evidence of the destination of an arbitrary agent-supplied path.

Normal pane toolbar location actions can use an active drawer child, whereas
Zoom's shared toolbar explicitly uses the source pane. Caller identity, focused
control target, terminal CWD and Bridge root can therefore differ legitimately.

Source: [context resolution](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift),
[CWD admission](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift),
[Bridge opening](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift),
[root precedence](../../Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewSourceProviderFactory.swift),
[companion lifecycle](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ZoomCompanion.swift),
[normal toolbar targeting](../../Sources/AgentStudio/App/Panes/Hosting/PaneLeafContainer.swift).

The future source-selection contract remains open. “Outside the caller's
worktree” does not mean “outside Git” or justify a plain-text fallback. Git-only
scope still includes another repository or another worktree.

## Geometry has multiple consumers

Current visible drawer panel:

```text
width = 80% of tab width
height = max(100pt, min(tab height × stored ratio, tab height − 60pt))
stored ratio is constrained to 20–80%; default is 80%
complete overlay adds a 40pt connector below the panel
bottom = source leaf bottom − measured toolbar height
horizontal position = centered on source, clamped within tab edges
```

The same broad shape appears in
[`resolvedDrawerContentRect`](../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift)
for bootstrap/activation, using an estimated toolbar height instead of the
measured frame. Child terminal sizing relies on that content rectangle.
Dismissal and drag hit regions use separately published measured frames.
Changing only visible drawing would leave other consumers using old bounds.

### Full-screen gap

**Strong source hypothesis, not native-measured:** normal leaf frames contain
their toolbar, so subtracting toolbar height positions the overlay above it.
Zoom's child toolbars are hidden and its shared toolbar is already below the
split. Subtracting toolbar height again from the source child bottom predicts
an extra gap. The supplied screenshot is consistent with this explanation.

Source: [leaf composition](../../Sources/AgentStudio/App/Panes/Hosting/PaneLeafContainer.swift),
[Zoom composition](../../Sources/AgentStudio/App/Panes/Hosting/ZoomPresentationContainer.swift),
[overlay placement](../../Sources/AgentStudio/App/Panes/Hosting/DrawerPanelOverlay.swift).
Existing [Zoom geometry coverage](../../Tests/AgentStudioTests/App/Panes/Hosting/ZoomPresentationContainerGeometryTests.swift)
does not exercise the drawer overlay's bottom alignment.

### Resize jitter

The handle reads cumulative gesture translation, subtracts its previous sample,
then applies the incremental delta to the current height ratio. Each sample
updates shared persisted state and immediately moves the bottom-anchored panel's
top edge.

The installed Xcode SDK's SwiftUI interface (module 7.5.3, target macOS 26.5,
interface compiler 6.3.2) declares `.local` as the default for both DragGesture
initializer overloads. This confirms the default coordinate-space selection,
not its transform behavior during layout changes. The inspected source is
`SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`,
lines 3518–3521, under the installed Xcode macOS SDK; it is platform evidence,
not proof of the SDK used to build the owner's running application.

| Hypothesis | Supporting evidence | What prevents a proven diagnosis |
| --- | --- | --- |
| Moving gesture coordinate basis feeds back into reported translation. | Gesture uses the default local space on the moving edge; reported symptom begins when pointer/edge separate. | The inspected API evidence does not establish whether SwiftUI freezes that coordinate transform. Translation may remain stable despite view movement. |
| Shared preference writes and geometry/material recomposition amplify lag. | Every drag sample changes `@AppStorage`; all observers can update, and layout/frame preferences change. | This explains work/lag, not by itself reversal or oscillation. No timing trace was captured. |
| Clamping creates dead travel near a size bound. | Ratio bounds and the separate 100pt floor can disagree in a short container. | It explains boundary stickiness, not jitter away from limits. |
| Resize state resets mid-gesture. | Would make incremental deltas jump. | Pane identity and handle position in the view tree are normally stable; no reset was observed. |

For stable translation and no clamping, the incremental deltas telescope to the
total displacement. It would be incorrect to claim this code necessarily has
the same cumulative-delta double-application bug as a different divider.

The [existing divider](../../Sources/AgentStudio/Core/Views/Panes/FlatPaneDivider.swift)
captures drag-start geometry and uses cumulative translation; its
[regression test](../../Tests/AgentStudioTests/Core/Views/FlatPaneDividerResizeTests.swift)
is a useful precedent, not proof of this drawer's runtime cause.

Smallest decisive runtime observation: compare pointer Y in a fixed tab/window
coordinate space, reported gesture translation, panel-top Y, and ratio during
one monotonic drag and reversal. Oscillating local deltas with monotonic pointer
motion would support coordinate feedback; stable values plus delayed paint would
point toward lag instead. No drawer gesture trace or equivalent behavioral test
was found or run in this investigation.

### Connector

The current broad S-curve is constructed from source-pane and overlay bounds;
it assumes substantial horizontal overlap. Its unclamped lower endpoints can
become reversed/outside the panel if arbitrary narrow side placement is added.
The latest owner direction avoids arbitrary side resizing and permits a visual
anchor centered with the selected full-screen position. Moving that visual
anchor need not change the drawer's owning pane.

## Current owner decisions to carry into Requirements

The following are from the 2026-09-13 conversation, not inferred from code:

- Git repos/worktrees only; no non-Git viewer fallback is selected.
- Bridge does not open as drawer content and cannot be dragged into ordinary
  pane layouts.
- A Bridge tab may own and open its own drawer in normal mode; the owner
  explicitly confirmed that this is useful. The earlier blanket interpretation
  that no normal drawer could cover Bridge is superseded.
- Moving a terminal's drawer over the terminal or Bridge region is a
  full-screen-only placement feature. It does not change drawer ownership.
- Keep floating drawers; the proposed right-hand content switcher is dropped.
- Normal mode retains top-edge resizing; fix the jitter and save normal height
  independently per owning pane.
- Full-screen uses fixed drawer geometry with no resize handles and commands
  to move it over the terminal or Bridge region.
- Width follows the actual selected region, including a 70/30 split; the earlier
  50% minimum is dropped.
- The full-screen drawer is 2–5% narrower than that region so its shadow reads
  as an overlay. The current interpretation is total width reduction, centered.
- Approximately 15% remains exposed at the top as visual context. This is a
  visual starting point, not an empirically validated dimension.
- The full-screen visual connector may move with the overlay. The drawer keeps
  its owning pane. Remember the full-screen side independently from normal height.

## Meaning still needed before a complete specification

1. For a file in worktree B requested from terminal A, which reusable Bridge
   surface receives B, and when does it resume following A? The earlier
   separate-tab default was challenged and is not selected.
2. Is the restriction specifically on dragging Bridge into ordinary layouts,
   or on every route that produces a mixed Bridge layout, including splitting a
   terminal beside Bridge and restoring an existing arrangement? Existing
   Bridge-owned drawers are now expressly allowed and are not part of this gap.
   The restriction does not itself authorize deleting any saved child content.
3. What is the initial full-screen drawer side, and what happens when Bridge is
   hidden/unavailable while its side is selected? A command should not silently
   create a new source policy to make space exist.
4. Exact file-navigation/agent focus and undiscovered-repo intake remain the
   earlier navigation proposal's open decisions. Current IPC identity does not
   settle future authority or user-visible placement.

These gaps should remain explicit in Requirements. They are not reasons to
reopen the selected width rule or reintroduce side resizing/CodeViewer.

## Proof coverage and limits

Source inspection covers the menu-to-owner path, normal/Zoom render composition,
gesture-to-height update, duplicate bootstrap geometry, drawer membership and
focus, Bridge opening/root selection, generic movement, and the sibling draft
boundary. Existing tests were read for intent; no suite pass is claimed.

Before implementation completion, evidence must cover actual normal dragging,
full-screen overlay bounds/shadow/context strip at unequal split ratios, mode
switching and per-owner retention, child terminal bounds and hit testing,
existing-layout behavior, and the eventual real human/agent file navigation.
Static documents or pane-creation receipts cannot establish those outcomes.
