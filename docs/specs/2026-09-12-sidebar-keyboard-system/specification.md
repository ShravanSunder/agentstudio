# Keyboard sidebar system

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) → this Specification → [Program Design](program-design.md).

Users should see where keyboard navigation is operating, inspect the existing list,
choose a destination, and return to their work. The sidebar replaces the discarded
invisible activity/history stack.

    Work in pane ── focus sidebar ── choose Panes/Repos ── select result ── open
                           |                |
                           |                └─ filter ── Enter returns to list
                           └─ Escape returns to prior work

Current pain: visibility shortcuts choose a surface; actual list selection is refused;
filter Enter has no list-focus behavior. Desired change: each action has one predictable
role, selection is visible, and activation uses the shared arrangement-reveal contract.
The direct-user class and goals are U1/U3/U4/U5/U12/U14/U16. U6/U7 remain in the
arrangement specification; U15 preview remains an explicit related contract below.

## Visibility, focus and surface

R-S1. CmdS toggles visibility without changing Repos/Panes selection. CmdShiftS reveals
if hidden and focuses the sidebar list. If Management is active, CmdShiftS has no effect.
Showing the sidebar alone does not choose Repos. Hiding a focused sidebar returns actual
keyboard focus to the recorded prior responder, with current-pane fallback if it no
longer exists. Repeating sidebar focus never replaces that origin with the sidebar.
Basis: U3/U4.

R-S2. While the sidebar list owns keyboard interpretation, P chooses Panes, R chooses
Repos, F enters the existing current-list filter. These commands remain available with
no results. Editable fields receive letters and digits as text. Unmodified list typing
is not unrestricted type-ahead. Surface selection keeps list focus and uses that surface's
existing preferences. Basis: U3/U5.

R-S3. Filter changes update results live. Enter and Down in the filter retain query,
focus the list and do not activate anything. Escape from the filter returns to the list
and preserves query; another Escape from the list restores prior work. The existing clear
control clears query explicitly. Filter/global focus requests record the same return
origin as sidebar-list entry. Basis: U4/U5. Escape/Down use the list-return behavior above.

## Selection and activation

R-S4. Selection is visible and independent of the active pane. Up/Down moves among
valid destinations and expandable group headers, stopping at edges. Left collapses an
expanded group or moves a child to its parent; Right expands a collapsed group or moves
to its first child. Filtering preserves existing non-collapsible groups. Static section
and activity labels, loading rows and fault placeholders are skipped. Enter toggles a
selected group where expansion is available; it does not open an arbitrary child.
Basis: U5.

On initial entry choose the first destination, or first group when no destination exists.
Keep selected identity through regrouping and updates. If removed, use the next surviving
selectable row in the prior order, otherwise the preceding survivor, otherwise the new
first destination/group. Empty results have no selection. Fallback selection never opens
a replacement destination.

R-S5. Digits 1-9 immediately open the corresponding first-nine destination rows in the
current result order; headers do not consume numbers. Offscreen results are still
addressable. The badge and key must identify the same target. Enter opens the selected
destination. Pane destinations use shared current/custom/Default reveal and native pane
focus; worktrees use their existing primary open behavior. Stale/removed targets do not
activate a different result or create a substitute pane. Basis: U5/U7.

## Feedback and protected behavior

R-S6. Hints are compact overlays anchored to existing controls/results. They do not add
rows, shift controls, obscure/dim the workspace or intercept pointer input. One focus
indicator occupies leading unused space of the existing second toolbar row. List hints
are visible only while the list effectively owns keyboard input; filter typing,
Management and transient keyboard owners suppress list-command hints. Selection and
active-pane appearance remain distinguishable. Native visual proof determines fit at
narrow and ordinary sidebar widths. Basis: U1/U16.

R-S7. Preserve existing Option-I/J/K/L spatial navigation, CmdShift-I/J/K/L terminal
scroll/prompt navigation, Commands/Panes search and viewer bindings. Commands, shortcut
glyphs, help and icons have one catalog source. Contextual P/R/F cannot become global menu
key equivalents. No general chord engine or new sticky keyboard-owner state. Basis U12.

R-S8. Row filtering, grouping, ordering and navigation indexes are derived off MainActor.
A selection key does not trigger a full sidebar capture/projection. MainActor applies
focus, prepared values and native selection/layout only. No polling or raw terminal-output
observer for hints. Prove the actual keyboard path with marker-scoped measurements;
unit timing is insufficient. Basis U1 and explicit user performance directive.

## Direct pinned navigation

R-S10. OptionShift-Up/Down from terminal moves to previous/next pinned pane across the
current app's tab-owned active panes, including Bridge and drawer children. Use existing
Panes grouping/subgroup/sort order, ignoring sidebar surface, visibility, filter,
collapsed groups and showsPinned setting. No separate history/activity traversal.
Traversal wraps; when origin is not in the pinned set, Down starts at first
and Up at last. Empty set does nothing; a stale/unpinned candidate does not substitute
another target. Repeated presses execute in order, advancing from the result of the
preceding successful navigation. Basis U14. Default-selection provenance is recorded in the [work record](../../wip/2026-09-11-keyboard-navigation/core-design-decisions.md).

## Temporary preview and its open boundary

R-S9. Holding a preview key temporarily displays the selected existing pane; releasing
cancels uncommitted preview. Enter commits selection, digits commit their target; later
key-up never undoes commitment. Preview cannot mutate durable layout then blindly roll
it back. Proposed presentation defaults are Space, full canvas, and following selection. The owner question still open is whether an unloaded
existing renderer/content may be restored during preview or only loaded content shown.
Do not silently exclude cold panes or create a new shell/session. U15 stays in scope; the cold-content behavior remains unspecified until that boundary is settled.

## Proof coverage

| Need | Contract | Required observation |
| --- | --- | --- |
| U1/U3/U4 | R-S1/R-S2/R-S3 | Native visibility/surface/focus, empty states, return origin, Management and editable exclusions |
| U5/U7 | R-S4/R-S5 | Real list/filter/dispatcher journey; group moves, updates, first-nine identity, stale targets and arrangement reveal |
| U1/U16 | R-S6 | Native overlays and selection at practical widths, no reflow or pointer interception |
| U1/U12 | R-S7/R-S8 | Binding/catalog regressions and marker-scoped MainActor versus detached work |
| U14 | R-S10 | Hidden sidebar, each grouping/sort, mixed pane kinds, wrapping and repeated/stale navigation |
| U15 | R-S9 | Pending renderer decision; later native hold/release/commit/loss-of-focus proof |

U8/U9 broader pin/rename bindings, U10 viewer redesign, U11 repository finder and
broad chord restructuring remain deferred by the owner's prior scope. U2 activity/history
traversal was withdrawn. U13 is advisory, not a required new command family.
