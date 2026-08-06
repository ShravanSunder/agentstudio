# Minimized-Run Divider Resize Specification

## The behavior to preserve

Agent Studio users resize horizontal split panes by dragging the boundary between the expanded panes they can see. A minimized pane may remain in the layout between those panes even when its collapsed bar is hidden. Hiding that bar must not remove the resize interaction between the surrounding expanded panes.

This specification is governed by the product-owner decision confirmed on 2026-08-02:

- **U1 — authorized, priority required:** a divider remains draggable whether minimized bars are visible or hidden and regardless of how many consecutive minimized panes lie between the expanded panes; dragging resizes the surrounding expanded panes.

- **P1 — current problem:** the product resizes expanded panes across a visible minimized run while preserving minimized-pane ratios, but removes the resize boundary when the same minimized bars are hidden.
- **O1 — required outcome:** pane-resize availability and mutation targets are independent of minimized-bar presentation.

## Boundary

The change applies to horizontal pane strips that expose pane-resize dragging, including main-pane strips and horizontal drawer rows that use the same behavior.

The existing minimized state, minimized-bar visibility policy, resize limits, command routing, and persistence model remain authoritative.

This change does not:

- move or reorder any pane;
- expand or unminimize a pane;
- make minimized bars permanently visible;
- add a new arrangement, persistence, compatibility, or drag-and-drop model;
- create a resize interaction at an outer edge where there is no expanded pane on both sides.

## Required behavior

### R1 — Resize availability across a minimized run

When two expanded panes are adjacent in the rendered strip, with one or more consecutive minimized panes between them in layout order, their rendered boundary must be draggable.

- If minimized bars are hidden, the strip exposes one resize boundary between the two expanded panes.
- If minimized bars are visible, the existing outer boundaries around the minimized run remain draggable and target the same surrounding expanded-pane pair.
- The number of consecutive minimized panes does not change the target pair.

**C1:** For any rendered boundary with an expanded pane on both sides, pointer acquisition and drag produce a resize of that expanded pair regardless of intervening minimized-bar presentation.

### R2 — Mutation isolation

Dragging a boundary across a minimized run must resize only the nearest expanded pane on each side.

Every pane in the intervening minimized run must retain:

- minimized membership;
- its stored layout ratio; and
- its current bar visibility, as determined independently by the active presentation mode.

The existing minimum-size and overdrag clamping behavior continues to apply to the two resized expanded panes.

**C2:** A successful cross-run resize changes the surrounding expanded-pane ratios and leaves every intervening pane's minimized membership, stored ratio, and current bar presentation unchanged.

### R3 — No invalid edge resize

A minimized run with no expanded pane on one side must not expose a cross-run resize boundary. If the candidate surrounding pair becomes invalid before a resize mutation is accepted, the layout must remain unchanged.

**C3:** An outer-edge or stale invalid cross-run target produces no layout mutation.

## Observable examples

| Layout order | Minimized bars | Required interaction |
| --- | --- | --- |
| `A · C` | none | Compatibility baseline: the ordinary A/C divider continues to resize A and C. |
| `A · [B] · C` | hidden | One A/C divider resizes A and C; B is unchanged. |
| `A · [B] · C` | visible | Both outer edges of B retain the existing A/C resize behavior; B is unchanged. |
| `A · [B1] · [B2] · C` | hidden or visible | Every exposed boundary for the run targets A/C; B1 and B2 are unchanged. |
| `[B] · C` or `A · [B]` | hidden or visible | No cross-run resize is available at the outer edge. |

Square brackets denote minimized panes, not whether their bars are currently rendered.

## Proof obligations

| Trace | Observable obligation | Required evidence |
| --- | --- | --- |
| U1 → P1 → O1 → R1 → C1 → V1 | A resize boundary exists for adjacent expanded panes across one or many minimized panes in both bar-presentation modes; ordinary adjacent-pane resizing remains intact. | Deterministic automated behavior evidence over rendered geometry and resize-target identity. |
| U1 → P1 → O1 → R2 → C2 → V2 | Dragging changes only the surrounding expanded-pane ratios and preserves every intervening pane's minimized membership and stored ratio. | Automated state inspection before and after resize. |
| U1 → P1 → O1 → R3 → C3 → V3 | An edge minimized run or stale invalid pair cannot mutate layout. | Automated negative-case behavior evidence. |
| U1 → P1 → O1 → R1/R2 → C1/C2 → V4 | The user can acquire the resize cursor and drag the boundary while minimized bars are hidden and while they are visible. | Manual interaction proof in the running macOS app. |

Security, privacy, data lifecycle, networking, concurrency, and performance contracts are unchanged because this correction adds no new actor, data, persistence, process, or asynchronous boundary.

Automated proof must not depend on wall-clock sleeps, arbitrary delays, polling intervals, or suite serialization. Most evidence should be pure or synchronous unit behavior, with only the smallest necessary integration evidence. Manual interaction in the running macOS app remains required to prove actual pointer acquisition and dragging in both minimized-bar presentation modes.
