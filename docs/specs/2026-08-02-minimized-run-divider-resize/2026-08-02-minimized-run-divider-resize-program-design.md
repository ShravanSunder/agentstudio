# Minimized-Run Divider Resize Program Design

Governing specification: [Minimized-Run Divider Resize Specification](2026-08-02-minimized-run-divider-resize.md)

## Integrated design

The fix remains inside the existing flat-strip geometry projection. Minimized state and minimized-bar presentation stay separate:

- `minimizedPaneIds` remains the durable authority for which panes are minimized;
- `collapsedPaneWidth` remains the presentation input that makes minimized bars visible or hidden; and
- `FlatTabStripMetrics` remains the owner of rendered pane and divider segments.

When `collapsedPaneWidth` is zero, `FlatTabStripMetrics` will emit exactly one divider after each expanded pane that has a later expanded pane. If one or more minimized panes lie between those expanded panes, the divider carries the existing `visiblePanePair(leftPaneId:rightPaneId:)` intent. The existing gesture and mutation path then resizes that pair without changing the intervening minimized panes.

No new component, state, command, persistence path, or compatibility layer is introduced.

## Current system and structural crux

`FlatTabStripContainer` and `DrawerPanel` independently decide whether minimized bars occupy `CollapsedPaneBar.barWidth` or zero width, then pass that presentation width to `FlatTabStripMetrics`.

The current metrics implementation treats zero-width minimized bars as a reason to discard every structural divider touching them. For `A · [B] · C`, both structural dividers touch B, so no rendered divider survives even though A and C are adjacent on screen. The downstream visible-pair resize path is already present but never receives a gesture.

The crux is therefore projection ownership: hiding a minimized bar may remove its visual segment width, but must not remove the rendered boundary between the expanded panes that become visually adjacent.

### Alternatives

| Direction | Gain | Cost and rejection basis |
| --- | --- | --- |
| Project expanded adjacency in `FlatTabStripMetrics` | Reuses the geometry owner and the complete existing resize path; one local policy change serves main and drawer strips. | Selected. The metrics projection must explicitly avoid duplicate dividers across a hidden run. |
| Add a container-level overlay divider | Avoids changing metrics iteration. | Rejected: creates a second geometry owner and duplicates frame, hit-area, identity, and resize-intent policy. |
| Change minimized panes into ordinary zero-width panes | Appears mechanically small. | Rejected: conflates minimized state with presentation and risks structural resize commands mutating minimized-pane ratios. |

Revisit the selected direction only if flat-strip geometry ceases to be the shared authority for rendered pane and divider frames.

## Ownership and interfaces

| Owner | Responsibility after this change | Interface contract |
| --- | --- | --- |
| `FlatTabStripContainer` / `DrawerPanel` | Select minimized-bar presentation width. | Zero means bars are hidden; it does not disable resizing between expanded panes. |
| `FlatTabStripMetrics` | Project pane frames, visible divider count, divider frames, and resize intents. | Emit one hidden-run divider per adjacent expanded-pane pair and preserve current visible-bar projection. |
| `PaneResizeVisibilityResolver` | Resolve and validate the expanded pair surrounding a minimized run. | A valid pair has expanded endpoints and only minimized panes between them. |
| `FlatPaneDivider` | Convert pointer translation and resize intent into an existing workspace action. | `visiblePanePair` dispatches `resizeVisiblePanePair`; `noResize` dispatches nothing. |
| `ActionValidator` and `WorkspaceTabArrangementAtom` | Reject stale/invalid pairs and mutate the authoritative layout. | Only the selected expanded pair's ratios change; minimized membership and intervening ratios remain unchanged. |

Forbidden edges:

- presentation owners must not mutate minimized state to make a divider available;
- the divider view must not infer surrounding panes independently of metrics;
- the state owner must not accept a visible pair whose intervening panes are not all minimized.

## Call-path delta

| Status | Entry to effect | State/effect and result |
| --- | --- | --- |
| Current | Presentation owner → `FlatTabStripMetrics.compute(collapsedPaneWidth: 0)` → skip both dividers touching a minimized run | No `FlatPaneDivider`; no gesture or mutation is possible. |
| Changed | Presentation owner → `FlatTabStripMetrics.compute(collapsedPaneWidth: 0)` → emit one divider after the left expanded pane with `visiblePanePair(A, C)` | A rendered hit target now exists at the A/C seam. |
| Intentionally unchanged | `FlatPaneDivider` → `PaneTabActionDispatcher` → `PaneTabViewController.dispatchAction` → `WorkspaceCommandValidator` → `WorkspaceActionExecutor` → `WorkspaceSurfaceCoordinator` → `WorkspaceTabLayoutAtom` → `WorkspaceTabArrangementAtom.resizeVisiblePanePair` | Synchronous main-actor validation and mutation change A/C ratios or reject the stale pair; the rendered strip recomputes from authoritative state. Drawer rows first map the same intent to `resizeDrawerVisiblePanePair`, then use the corresponding existing validated path. |
| Intentionally unchanged | `FlatTabStripMetrics.compute(collapsedPaneWidth: barWidth)` | Visible minimized bars keep their current outer-edge dividers and pair targeting. |

The divider identity for a hidden run uses the existing structural divider immediately after the left expanded pane. It remains a valid member of the layout's divider identities, satisfying the current gesture guard without adding synthetic identity state.

## State and failure behavior

| Concern | Design |
| --- | --- |
| Minimized membership | Read-only during resize; remains owned by the active arrangement. |
| Intervening minimized ratios | Read-only during resize; `resizingPanePair` receives only the expanded endpoints. |
| Expanded ratios | Updated together by the existing pair-resize operation and existing clamp policy. |
| Bar visibility | Derived from presentation mode before metrics computation; never written by resize. |
| No expanded pane on one side | Metrics emits no divider because no valid surrounding pair exists. |
| Pair becomes stale before dispatch | Existing validation rejects it and the authoritative layout remains unchanged. |
| Overdrag | Existing minimum-size clamping applies; no new recovery path exists. |

There is no new asynchronous work or shared mutable state. SwiftUI recomputation and the existing main-actor mutation path provide the current consistency model; no retry, lock, migration, or rollback mechanism applies.

## Requirement realization and proof seams

| Requirement | Realization | Proof seam |
| --- | --- | --- |
| R1 | Hidden-bar divider projection in `FlatTabStripMetrics`; existing visible-bar projection remains. | Inspect computed segment count, frame, identity, and `visiblePanePair` intent for one and multiple minimized panes in both presentation widths; retain ordinary adjacent panes as a regression baseline. |
| R2 | Existing `resizeVisiblePanePair` validation and `resizingPanePair` mutation. | Inspect expanded ratios, minimized ratios, and minimized membership before and after a drag-equivalent resize. |
| R3 | Metrics requires a surrounding expanded pair; validator independently revalidates the pair. | Exercise edge runs and stale/invalid pairs and observe no layout mutation. |
| R1/R2 manual boundary | Existing `FlatPaneDivider` hit target and resize cursor rendered from the corrected metrics. | In the real app, drag the seam with minimized bars hidden, then visible, and observe only the surrounding expanded panes resize. |

Proof follows the lowest practical test-pyramid layer:

1. Pure synchronous `FlatTabStripMetrics` unit coverage proves hidden single- and multiple-pane runs, preservation of visible-bar behavior and ordinary adjacent-pane behavior, exactly one hidden-run divider with the expected identity and intent, and negative outer-edge cases.
2. Synchronous state/command unit coverage proves a drag-equivalent resize changes only A/C ratios while every intervening minimized pane retains its identity, minimized membership, and stored ratio; stale invalid pairs produce no mutation.
3. At most one narrow integration seam is added only if direct unit seams cannot prove rendered-divider intent reaches the existing command dispatch. Prefer captured dispatch and immediate state inspection.
4. Manual interaction in the running app proves actual resize-cursor acquisition and dragging with minimized bars hidden and visible.

Automated proof must not use `Task.sleep`, arbitrary delays, wall-clock polling, or suite serialization for synchronization. Use direct pure calls, captured dispatch, and immediate state inspection. If an asynchronous proof is unavoidable, wait for the exact event or state with a bound rather than waiting for elapsed time.
