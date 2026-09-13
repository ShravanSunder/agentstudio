# Keyboard sidebar program design

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) → [Specification](specification.md) → this structural design.

## Existing owners, actual focus

The existing App shell moves native focus; the existing RepoExplorer host owns list
interpretation; the detached projection produces navigation metadata. The table renders
selection and scroll, and catalog-derived overlays show the available keys. Committed
pane activation retains the reviewed arrangement path.

    App shell / MainSplitViewController
      owns: sidebar visibility and weak native return target
      calls: stable sidebar host focus; existing active-pane fallback
        |
        v
    RepoExplorerMaterializationHost (full-size, survives empty results)
      owns: native list responder and selected RowID
      consumes: accepted snapshot navigation metadata, local action descriptors
      calls: materializer select/scroll; existing table interaction callbacks
        |                                  |
        v                                  v
    Table / hosted cells               Existing dispatcher / pane focus
      renders selection + hints          owns target authority and reveal
        ^
        |
    Detached projection worker
      owns filter/group/order/navigation-index derivation
      publishes through existing generation/baseline handshake

    Core command catalog -> context-exact shortcut/display projections
    SharedComponents     -> stateless keycap and existing selected-row paint

No new atom/store, event, coordinator, persistent focus mode, or global chord engine.
Local UI interaction state holds selection/focus reporting, not a second KeyboardOwner.

## Responsibility and interface boundaries

MainSplitViewController captures origin on entry from outside the sidebar. It retains
it weakly for the window lifetime and restores it on Escape/hide when still usable.
For a shared field editor, record the owning text control where identifiable rather
than the reusable NSTextView; otherwise fall back to active pane. Repeated sidebar
focus and list/filter switches never replace the origin. The existing bounded focus
request handles host attachment; cancellation/hiding cancels that pending request.

RepoExplorerMaterializationHost accepts first responder while attached and visible.
Its local keyboard state survives content/rowless child replacement. It handles
catalog P/R/F and UI-local arrows/Enter/Escape/digits; content-dependent actions are
no-ops when no accepted content exists. Calls to select/scroll are synchronous and
consume prepared indexes, never a full projection. It rejects ingress unless the
window's actual first responder is itself and effective routing is stable sidebar.
Management, transient surfaces and existing organization popovers suppress ingress.

The feature-local observable interaction value holds a weak host attachment and reports
list/filter/none to the header and existing sidebar-focus publication. Region changes
are tied to real responder/field focus callbacks. A delayed filter resignation clears
only a still-filter-owned region, never newly acquired list focus; actual host focus
wins over a late filter callback. Shell hidden/disposed state clears publication.
The old 1x1 RepoExplorerFocusBridge no longer acts as a list target.

The table materializer owns native selected-row application and scrolling, while its
accepted snapshot is the only data authority. Native selection changes cannot open
rows by themselves. Existing mouse callbacks keep their activation semantics. Hosted
cells receive local selection/hint values separately from row content revisions, so
moving selection does not invalidate content/height caches or force projection work.

## Call-path cutover

    Changed R-S1:
      CmdS -> old showReposSidebar
           -> toggleSidebar -> shell visibility only + actual return if hiding
      CmdShiftS -> old toggleSidebar
                -> new focusSidebar -> Management guard -> reveal -> host responder

    Changed R-S2/R-S3:
      shell focus/filter -> old invisible proxy
                         -> stable materialization host / existing filter callback
      filter onSubmit: old no-op -> preserve query -> make host first responder
      filter Escape: old clear+pane return -> preserve query -> list

    Added R-S4/R-S5:
      host keyDown -> descriptor/context gate -> accepted navigation index
                  -> selected RowID -> table select/scroll
      Enter/digit -> exact accepted row identity -> existing interactions
                  -> worktree AppCommandDispatcher OR targeted pane focus
                  -> authoritative action/reveal operation -> actual native focus
      stale/missing identity -> no operation; no next-row substitution

    Intentionally unchanged:
      pointer row -> existing interaction/dispatcher -> validated target owner
      worker -> candidate/baseline handshake -> accepted materialization generation
      pane focus -> PaneCommittedFocusOperation -> concurrent policy
                 -> select/switch/drawer effects -> revalidate -> exact focus

The table interaction interface already carries onFocusPane/onCommandRequest/
onToggleGroup. Extend it with an explicit desired group-expansion request for
directional keys. Keyboard activation builds the same worktree open request and uses
those callbacks from accepted row data; it does not require a mounted row slot. The
first-nine result may be outside the viewport. Current command authority is checked
by the existing dispatcher; a stale cached row never grants mutation permission.
Mouse cells retain their binding/reuse/command-generation guards.

## Navigation metadata and live changes

The existing detached snapshot construction adds immutable navigation metadata:
selectable row IDs, first destination, next/previous, parent/first-child relationships,
first-nine destination IDs and row-to-number lookup. Group headers are selectable but
not numbered. Section/activity labels, loading, faults and unresolved rows are omitted.
No row data is duplicated in a parallel store; reuse rowIndexByID and accepted rows.

A native RowID is a presentation coordinate, not stable destination identity: it
includes the group for worktrees and several pane representations. The worker also
indexes destination keys, using existing pane UUIDs and worktree UUIDs, to their row
IDs in current result order. Include associated, tab-owned and unassociated pane rows
under the same pane key. Group headers retain their group identity rather than gaining
a synthetic destination.

The worker's update-plan construction prepares selection reconciliation against the
accepted old and new snapshots. For each prior selectable RowID, first retain that
row when it survives; otherwise resolve its prior pane/worktree destination to the
new RowID. If multiple representations exist, prefer the surviving exact row, then
the first representation of that same destination in new result order. Thus pinning,
regrouping, activity-bucket changes and association changes retain the selected target.
Native RowID equality/hashing and materialization ownership remain unchanged.

Only when the destination is absent does reconciliation apply removal fallback:
the next surviving selectable destination/group in prior order, else predecessor,
else the new first destination/group. Translate surviving destinations to their new
RowIDs before building that successor/predecessor lookup. Section labels never become
selection. This remains detached update-plan work; the host keeps one selected RowID
and applies the prepared reconciliation lookup after candidate acceptance. No second
selection store or per-key list scan is introduced, and no fallback activates.

Membership, content and rowless transitions are admitted by existing lifetime, demand
epoch and visible-generation checks. A key captures the accepted target identity at
its handling point; later projection cannot reinterpret its digit. Badges consume that
same accepted mapping, not requested/published-but-unaccepted rows. Equal projection
must preserve navigation equality; native update validation covers new metadata.

## Local state transitions and failure

    outside -- successful focus --> list -- F --> filter
       ^                             ^             |
       | Escape / hide               +-- Enter/Esc-+
       +-----------------------------+

    list content -- accepted empty --> list rowless
    list rowless -- accepted content --> list with initial selection
    any local state -- detach/window loss --> no list eligibility

Vertical arrows change selected identity only. Directional group expansion uses
an idempotent set-expanded request at the existing sidebar cache owner; mouse and
Enter retain intentional toggle. Repeated Right while a new projection is pending
therefore cannot accidentally collapse the group. Filtering keeps its existing
expansion guard. No pending expansion state or second group-state owner is needed.
A pending projection does not move focus away from the stable host. First responder
failure leaves actual ownership unchanged; the bounded shell retry either succeeds
or ends without claiming focus. Closing origin uses active-pane fallback.

Target removal between key and queued action is rejected by existing dispatcher and
committed-focus validation. A target whose reveal partially changed the workspace is
not blindly rolled back; existing action semantics remain authoritative. The list
does not explicitly return to origin after Enter, which would race successful async
activation. It loses ownership when the actual destination receives focus.

## Catalog and overlays

Add focusSidebar as a shell command with exhaustive interactive and IPC classification;
its interactive window-local focus action has no accidental generic headless exposure.
Rebind toggleSidebar to CmdS and focusSidebar to CmdShiftS. Reuse showPanesSidebar,
showReposSidebar and filterSidebar for P/R/F in sidebarList context. Filter keeps its
existing global binding. Local list navigation has one typed action/shortcut descriptor
for interpretation, accessibility and display; no handwritten duplicate key strings.

Make AppShortcut display selection exact and optional for the requested context.
Menus, command bar and general tooltips request global; sidebar hints request
sidebarList. Do not let current primary-trigger fallback leak P/R into NSMenuItem
key equivalents. Preserve emptyDrawer's existing raw P alternate and all other contexts.

The existing SidebarEntityToggle/segmented-control primitive receives optional resolved
shortcut display per segment. Shared keycaps overlay existing control bounds, never
intercept pointer events and do not duplicate accessibility elements. Numbered row
keycaps overlay the leading identity-icon column, preserving title, pins and chips.
The single catalog-backed focus glyph occupies existing leading space in repoToolbarRow.
It and list hints follow effective list eligibility; no new header or help strip.

Leaf selection uses SidebarRowShell's existing isSelected paint. Group header selection
uses the same style through its existing shared header. Native selection/accessibility
remains accurate without competing native and SwiftUI selection paint. Active-pane
play-chip status remains separate. Old/new visible cell chrome updates only; no layout
poll, list-sized anchor scan or output observer is introduced.

## Direct pinned navigation

App command ingress runs previous/next pinned actions through the existing gesture
sequence. At operation start capture the current origin and raw COW pane/tab/activity
state, repository topology snapshot, stored tab order, Panes preference scalars and
reference time. MainActor performs no location enumeration, pin filtering, dictionary
join, title normalization or sort. Add narrow read accessors over existing raw storage,
not new atoms or stored properties. This follows CoreTabBarProjection's capture/derive
separation without reusing its unnecessarily broad snapshot.

RepoExplorer owns the focused detached projector and shared pane organization policy.
Factor that policy from organizedContent so both full sidebar and pinned navigation
consume the same grouping/subgroup/leaf comparator. The focused path stops before
rows, enrichment and materialization. It ignores query, collapse, surface and showsPinned.
All active tab-owned content kinds and drawer members remain eligible.

    terminal shortcut -> App gesture sequence -> raw capture (MainActor)
                      -> focused projector (detached)
                      -> candidate pinned ID
                      -> fresh pin/ownership check (MainActor scalar reads)
                      -> existing non-enqueuing committed-focus operation
                      -> success/failure -> next queued navigation

Do not enqueue and await another gesture from inside the gesture queue. Fresh target
checks reject stale/unpinned candidates without substitute. Sequential keys resolve
from the preceding successful result rather than concurrently from the same old origin.
Empty set is no-op; wrap and absent-origin first/last behavior follow the Specification.
No hidden sidebar adapter demand, activity/history stack or extra persistent cache.

## Quality and proof boundaries

All input is local keyboard/UI identity; no new external transport or persisted format.
AppCommandDispatcher and current focus action retain authorization. IPC classification
must be exhaustive, not inherited from UI visibility. Text fields remain text owners.
No typed text or pane content is newly logged; performance markers carry counts/durations
and existing bounded identifiers under the current scrub rules.

| Contract | Owner and proof seam |
| --- | --- |
| R-S1/R-S2/R-S3 | Real MainSplitViewController window + stable host + shared field; observe actual responder through empty/filter/hidden/Management transitions and origin-control reuse |
| R-S4/R-S5 | Pure snapshot/update policy plus real host/materializer/dispatcher integration; accepted-generation digits, destination continuity across regroup/pin/activity/association changes, true removal fallback, offscreen ninth result, group moves and exact pane/worktree actions |
| R-S6 | Native shared controls/hosted rows at narrow and ordinary widths; inspect selection, icon-column overlays, no reflow/click interception, accessible selected row |
| R-S7 | Exhaustive catalog/context/menu/display tests and existing terminal/empty-drawer regressions |
| R-S8 | Existing performance probe: separate raw capture, detached navigation projection, native selection/apply; demonstrate no full-capture increment on row motion |
| R-S10 | Pure focused/full ordering equivalence and real gesture/reveal integration with hidden sidebar, mixed panes, stale pins and sequential commands; capture/derive timing proof |

Mocks may replace external filesystem/runtime dependencies in pure policy tests, not
native responder transitions or the interaction under test. Native journey proof must
exercise the actual app after source passes, including editor text isolation and the
marked overlay placement. Existing architecture lint enforces module boundaries;
Sendable DTOs and concurrent worker entry enforce derivation separation.

## Preview boundary

R-S9 is still in the delivery scope but not structurally ready. Working direction is a
window-local transient presentation in the existing tab host, with one selected pane
branch and sidebar retaining first responder. Never mount the same stable container
twice or use durable focus-and-rollback. Hold state needs generation-bound cancellation;
Enter/digits invalidate preview before committing so late key-up cannot undo commit.
Renderer preparation must preserve existing custody and exact zmx sessions, bound pending
work, and share the authoritative geometry/visibility path. Cold content restoration
and live full-canvas resize effects remain the open owner/design boundary. No general
detached-drawer invariant repair is introduced through preview.

## Source map

- [Stable host](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializationHost.swift) and [native materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift): lifetime, accepted generation and native row rendering.
- [Shell focus](../../../Sources/AgentStudio/App/Windows/MainSplitViewController.swift) and [current filter/proxy bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift).
- [Snapshot construction](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerMaterializationSnapshot.swift), [update planning](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerNativeUpdatePlan.swift) and [pane organization](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection+Organization.swift).
- [Shortcut context/display](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcut.swift) and [dispatch policy](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcutDispatchPolicy.swift).
- [Row shell](../../../Sources/AgentStudio/SharedComponents/SidebarRowShell.swift), [surface toggle](../../../Sources/AgentStudio/SharedComponents/SidebarEntityToggle.swift) and [toolbar](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift).
- [Committed focus](../../../Sources/AgentStudio/App/Panes/PaneCommittedFocusOperation.swift) remains the arrangement effect owner.
