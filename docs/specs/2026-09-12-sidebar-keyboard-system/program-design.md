# Keyboard sidebar program design

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) →
[Specification](specification.md) → this structural design.

## Composition

Reuse the existing App shell, command catalog, feature projection and native
materializer. The table becomes a real keyboard focus target. The hint layer is a
display projection over controls and rows; it never becomes a keyboard owner.

```text
App
├── AppCommandDispatcher + shell handler
│   └── MainSplitViewController: show/hide and request actual table focus
├── Existing pane action/focus path
│   └── shared committed arrangement reveal
└── Preview presentation seam: unresolved, described below

RepoExplorer Feature
├── Existing detached projection worker
│   └── materialization snapshot + navigation indexes
├── Native table/materializer
│   ├── actual list responder
│   ├── selected RowID and local return/focus callbacks
│   └── O(1) index lookup → selection/scroll/dispatch
└── Existing SwiftUI header/row hosts
    └── focused-region values + spec-backed keycap overlays

Core: command identities/specs and derived effective keyboard owner
SharedComponents: stateless keycap/focus-icon paint only
```

No sibling-Feature imports, new atom/store, navigation Boolean, raw-output observer,
event-bus command or app-wide chord engine. Local selection and preview intent are
interaction facts, not competing sources of workspace or keyboard truth.

## Current paths and target deltas

| Current path | Change | Intentionally preserved |
| --- | --- | --- |
| CmdS → showReposSidebar; CmdShiftS → toggleSidebar | Rebind toggleSidebar to CmdS; add focusSidebar at CmdShiftS; remove direct CmdS from Repos | AppCommandDispatcher, exhaustive interactive/IPC classification |
| Shell focusSidebar → invisible focus proxy | Resolve actual table target and make it first responder | Existing shell reveal timing and workspace lifecycle |
| Filter onSubmit defaults to no-op | Wire table-focus request; retain query | Existing SidebarSearchField and live filter pipeline |
| Native table denies/deselects selection | Admit keyboard selection and preserve selected RowID | Row projection, hosted cell identity, existing mouse actions |
| Worker builds materialization rows and indexes | Derive actionable/adjacent/group/first-nine indexes there | Detached execution, cancellation, generation validation |
| Row callback → focusPane/openWorktree | Keyboard activation uses same validated primary-action path | Exact pane/worktree distinction and command authority |

The selected source location for the single focus icon is the leading unused area
of `repoToolbarRow`, before its existing Spacer—not a new row and not the filter
row. All shortcut keycaps are overlays, including first-nine badges.

## Keyboard indexes and fast selection

Add navigation metadata to `RepoExplorerMaterializationSnapshot` during its existing
off-main construction: navigable row IDs, actionable row IDs, next/previous indexes,
group parent/neighbor relationships and at most nine numbered row IDs. Reuse
`rowIndexByID`; do not duplicate row contents in a parallel model. These fields are
immutable Sendable output tied to the existing accepted visible generation.

The MainActor table holds one selected `RepoExplorerRowID?`, never an authoritative
row number. Key handling decodes input, checks actual responder/routing context,
looks up prepared next/numbered target, and applies native selection/scroll. Selection
changes do not request full projection capture or recompute filter/group/sort work.
Only old/new visible row chrome needs update; selection must not change row content
revision or invalidate height caches.

When a new materialization is accepted, remap the selected identity using its index.
The key action and its badge consume that same accepted generation. Before activation,
the existing current-row/command guards validate identity and command availability.
The observable missing-row fallback and digit activation semantics remain upstream
choices; this design reserves an explicit outcome rather than picking arbitrary rows.

## Focus and local commands

The actual table responder publishes list focus. Filter focus remains the existing
SwiftUI field. A feature-local focused-region value distinguishes list/filter/none
and publishes the broad existing sidebar focus fact. It must be a projection of
real focus transitions, not a manually toggled navigation state. The old invisible
proxy no longer impersonates a focused list; retain it only where needed to bridge
filter requests.

Before accepting a list command, check effective `KeyboardRoutingContext` as well
as actual list responder. Management, command-bar/transient surfaces and text input
retain their authority. Returning to a pane removes list hints by changing focus,
not by separately toggling an overlay mode flag.

List P/R/F dispatch the existing showPanesSidebar/showReposSidebar/filterSidebar
identities. Introduce an exact sidebar-list shortcut context or local binding
projection through the established spec system; never hand-copy labels/icons in the
view. Row navigation/numbering commands need final observable semantics before
their identity and enablement are finalized. The new focusSidebar command is
interactive window-local and receives an explicit IPC classification rather than
accidental generic exposure.

## Overlay rendering

The header and row hosts receive current spec-derived hint descriptors and a
focus eligibility value. Stateless SharedComponents keycaps render through overlays
anchored to current control bounds; no standalone NSWindow, generic overlay manager
or geometry polling is needed. AppKit/SwiftUI layout remains on its required actor;
no list-wide anchor search occurs per frame. Clip within the sidebar and disable
hit testing/accessibility duplication on decorative badges; actual controls retain
their existing accessible names and command semantics.

No control or row height changes when hints appear. The Cursor recording is a
visual reference for compact in-place keycaps, not a threshold specification.
Owner-selected overlay direction is fixed; exact icon art and reveal/dismiss timing
need native visual proof. The focus icon and selected row must distinguish keyboard
ownership, selection and active pane, rather than repeat one ambiguous state.

## Preview: known seam and unresolved realization

Committed focus changes durable tab/arrangement/minimization state. It cannot be
used for temporary preview then blindly rolled back. `ViewRegistry` has one native
host per pane; `PaneViewRepresentable` returns a stable container and does not
repair arbitrary reparenting in update. Therefore a second simultaneous pane-view
overlay is not a viable reuse strategy.

Existing `PersistentTabHostView` instances can change presentation visibility without
changing durable tab selection, and `SingleTabContent` already selects a transient
zoom render branch. A window-local App preview value could choose an existing host
and a distinct preview branch, with sidebar retaining first responder. However
mount/admission and geometry currently use active-tab/visible-set facts, and Bridge
activity has its own presentation eligibility. Merely unhiding an inactive tab host
does not prove an unmounted terminal or Bridge renderer can preview correctly.

`WorkspaceActionExecutor` exposes reattach/detach-for-zoom wrappers through existing
surface coordinator operations. Their eligibility must be checked for all requested
pane kinds and drawer children. Reusing the Zoom state itself is rejected: zoom has
different toolbar/content and child eligibility semantics. Extending an existing atom
or adding coordinator responsibilities requires explicit scope/owner admission; no
such extension is selected here.

The preview branch remains structurally incomplete pending its trigger/placement
contract and verified mount/visibility seam. The rest of this source-grounded design
does not depend on pretending that gap is solved.

## Failure and proof architecture

| Boundary | Required design behavior / seam |
| --- | --- |
| Filter/list focus changes | Real responder events are authority; text must not reach pane or list commands |
| Projection arrives after selection | Accept through existing generation handshake; remap by RowID |
| Row reused before activation | Existing binding/reuse/command generation guards reject stale action |
| Target closes during reveal | Shared arrangement/focus validation; no replacement pane |
| Pane focus becomes unavailable | Preserve honest focus outcome; selected row is not proof of native activation |
| Preview enter/commit/cancel overlap | Single App presentation owner and generation ordering needed once preview is designed; no stale snapshot rollback |

Core indexes/policy can be verified with value inputs. Integration must use the real
materializer, hosted rows, filter and dispatcher boundaries. Native proof must cover
actual first responder, overlays at narrow/wide sidebar widths, text input, row
changes and pane/worktree activation. Performance evidence must distinguish off-main
index derivation from MainActor capture, selection, geometry and cell updates;
unit timing alone cannot prove the user-facing hot path.

## Source anchors

- [Worker](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift) and [snapshot](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerMaterializationSnapshot.swift).
- [Native materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift), [row cells](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableRowCell.swift), [focus bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift).
- [Sidebar view](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift), [toolbar](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift), [split controller](../../../Sources/AgentStudio/App/Windows/MainSplitViewController.swift).
- [Pane content](../../../Sources/AgentStudio/App/Panes/Hosting/SingleTabContent.swift), [stable native container](../../../Sources/AgentStudio/App/Panes/Hosting/PaneViewRepresentable.swift), [workspace executor](../../../Sources/AgentStudio/App/Commands/WorkspaceActionExecutor.swift).
