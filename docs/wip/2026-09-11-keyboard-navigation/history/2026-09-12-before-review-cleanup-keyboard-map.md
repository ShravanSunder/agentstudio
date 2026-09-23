> Historical archive — not current review or implementation authority. Relative links retain their original document context.

# Sidebar keyboard navigation — current design map

[Requirements](requirements.md) · [Critique validation](comment-validation.md) · [Decision trail](summary.md)

The owner selected the existing visual sidebar as the navigation surface.
**Separate last/next-pane activity and history traversal is removed from scope.**
The earlier Shift-Option traversal proposal is not part of this map.

## Scope tree — what we are designing now

```text
Keyboard navigation with a visible, predictable destination
│
├── IN THIS DESIGN
│   ├── Sidebar navigation
│   │   ├── Command-S: show/hide; preserve selected surface
│   │   ├── Command-Shift-S: activate; reveal if hidden
│   │   ├── P: Panes; R: Repos; F: search/filter entry
│   │   ├── Navigate rows and groups, activate, return to work
│   │   └── Visible mode icon and contextual hints in existing UI
│   ├── Direct pinned-pane navigation from terminal
│   │   └── Option-Shift-Up/Down: previous/next pinned pane
│   └── Arrangements
│       ├── Keep existing arrangement navigation
│       ├── New pane visible in current arrangement + Default
│       ├── Other custom arrangements stay undisturbed
│       └── Reveal current → visible custom → Default; expand drawer
│
├── DESIGN DETAILS STILL OPEN
│   ├── Row/group keys, activation and return behavior
│   ├── F: list filtering versus a separate file-finding action
│   ├── Exact icon treatment and inline-hint reveal/dismiss trigger
│   ├── Pinned-pane order, reach and boundary behavior
│   └── Closed targets, text focus and Management interaction
│
├── REMOVED
│   ├── Separate activity-ranked traversal stack
│   ├── Visit-history back/forward navigation
│   ├── Their Shift-Option-I/J/K/L and held-snapshot machinery
│   ├── Big keyboard-help panel / additional header rows
│   └── Workspace dimming or hiding to indicate navigation
│
└── SEPARATE / DEFERRED
    ├── Activity-grouping bug: investigate; no fix established yet
    ├── Finished/waiting-agent attention queue: not this feature
    ├── Pin/unpin and rename action shortcuts
    ├── Viewer / Review file-finder and annotation redesign
    └── Broad app-wide chord / shortcut restructuring
```

Selected capabilities do not make every detail below accepted. Row movement,
G/Shift-G, Enter/Escape, and the reveal trigger remain proposals. Do not transplant
discarded traversal semantics into pinned-pane or sidebar navigation.

Design standard: reuse the existing controls and visual hierarchy; place feedback
at the control or row it describes; clearly distinguish keyboard-selected row from
active pane; never turn a navigation key into text while the wrong surface owns it.
The icon, selected row and hints must each have a distinct purpose. No decorative
mode chrome is needed merely to make the state look different.

## Selected entry shortcuts

Latest additions under discussion: Enter from the filter keeps the query and
returns real focus to the table; digits 1–9 activate the first nine list results.
Filtering already updates as text changes, so Enter is a focus handoff, not the
start of filtering. Current host does not wire `SidebarSearchField.onSubmit`.

```text
List → F → type query → results update → Enter → filtered list
                                                   |
                                  1–9 or Enter → activate result
```

Recommended number contract: number the first nine actionable rows of the current
filtered, expanded list, excluding headings and diagnostic rows. Keep numbers tied
to that list order, not viewport position, so scrolling does not renumber them.
Show the keycaps only when the table owns keyboard navigation. In Filter, digits
are text. Numeric activation uses each row's existing primary action: focusPane
for a pane, openWorktree for a worktree. Exact mapping across live reorder and
disabled rows remains a final contract detail, not a reason to stop other work.

This owner request supersedes the previous absence of a digit-address feature.
It is first-nine **list results**, not the peer critique's first-nine pinned-only
destinations, and does not replace the separately selected pinned-pane arrows.

| Keys | Selected job |
| --- | --- |
| Command-S | Show/hide sidebar, retaining its selected surface |
| Command-Shift-S | Activate sidebar for keyboard navigation; show it if hidden |
| P, while navigating sidebar | Show Panes |
| R, while navigating sidebar | Show Repos |
| F, while navigating sidebar | Search/filter entry; exact meaning discussed below |

These change the current assignments: today Command-S opens Repos and
Command-Shift-S toggles visibility. They are selected design changes, not implemented.

```text
                      SIDEBAR VISIBILITY
                  Command-S: hidden ↔ shown

Working in pane A
       |
  Command-Shift-S
       v
Sidebar shown + keyboard navigation active
       |
       +→ P: Panes       R: Repos       F: Filter (proposed)
       |
       +→ move through rows/groups
       |
       +→ activate target → arrangement reveal → focus target
       |
       +→ return/cancel → original pane A
```

## Corrected interaction model — focus owns behavior

Command-Shift-S moves real keyboard focus to the sidebar list and reveals it if
hidden. It does not toggle a sticky navigation flag. The word “mode” describes the
focused sidebar's local key interpretation, not a second stored owner. The proposed
visual layer is a consumer of effective focus; it never captures or assigns focus.

```text
Pane owns focus ── Command-Shift-S ──→ Sidebar list owns focus
      ↑                                     |
      |                              P / R: change surface
      |                              F: focus filter
      |                                     |
      |                              Filter owns typing
      |                                     |
      |                              Escape → list (proposal)
      |                                     |
      +── Escape from list (proposal) ───────+
      +── Enter → chosen destination ───────+  (proposal)
```

Current `KeyboardOwner` distinguishes sidebar(surface), Management and the main
pane chain. `KeyboardRoutingContext` gives command-bar/transient surfaces precedence.
The sidebar focus Boolean also covers the filter, so it is not by itself permission
to consume P/R/F. Actual responder context must distinguish list navigation from
text input, buttons and other controls. Moving focus into an editor or another
surface removes list keyboard authority immediately; no hidden mode remains.

Some transient interaction data is necessary: selected row and an origin for return.
Neither is a navigation-mode Boolean. Selection follows stable row identity across
projection changes, not a retained numeric row index. A removed selected row needs
a deterministic nearby fallback; it must never activate a different row using a
stale index. Exact fallback is still a product choice for the final Specification.

## What the keys do together — recommendation

| Where keyboard focus is | Keys | Proposed behavior |
| --- | --- | --- |
| App pane | Command-S | Show/hide sidebar without switching Repos/Panes |
| App pane | Command-Shift-S | Reveal sidebar and focus its remembered list/row |
| Sidebar list | P / R | Select Panes/Repos, then keep real focus in that list |
| Sidebar list | F or existing Command-F | Focus the existing list filter |
| Sidebar list | Up/Down | Move selection through visible navigable rows; do not activate |
| Sidebar list | Left/Right | Collapse/expand the selected group or parent |
| Sidebar list | Enter | Execute the selected row's existing primary action |
| Sidebar list | Escape | Return to the originating pane; leave sidebar shown |
| Filter | Plain text, including P/R/F | Edit filter normally |
| Filter | Enter | Keep filter and return to table; no automatic result activation |
| Filter | Escape or Down | Return to list; exact Escape behavior still proposed |
| Terminal | Option-Shift-Up/Down | Direct previous/next pinned-pane switch; not pinned repository/worktree open |

On a pane row Enter focuses a pane. On a worktree row Enter performs the existing
openWorktree action; do not pretend these target identities are interchangeable.
Headers expand/collapse. Diagnostic/nonaction rows should not dispatch fake actions.
When the original pane no longer exists, return must choose an existing focusable
pane; final fallback selection remains explicit design work.

The chosen P/R/F means plain typing in the list cannot also be unrestricted
Finder-style type-ahead. Recommended bounded behavior: F then type to filter, retaining
the owner's selected letters. This remains a context-dependent keymap; calling it focus-based does not remove the tradeoff. Switching to
ordinary type-ahead and modified surface keys is an alternative requiring an owner
change. Command-Shift-P is unavailable: it already opens Commands.

For the smallest coherent initial keymap, standard arrows cover row/group movement.
Plain I/J/K/L and G/Shift-G remain optional proposals, not implementation obligations;
they must not silently acquire a second meaning in text fields.

## Hint layer and focus indication — recommendation

The owner rejected a help panel and extra header rows, and requested an icon at the
marked leading toolbar location plus floating contextual hints. Keep that request.

```text
Effective focus: list       → icon + actionable control keycaps + selected row
Effective focus: filter     → actual input focus; navigation-letter hints absent
Effective focus: elsewhere  → sidebar navigation icon/keycaps absent
```

Recommended default: show control hints whenever the list genuinely owns keyboard
navigation, so the owner need not hold another modifier to discover P/R/F. A small
keyboard glyph at the marked toolbar position is derived from the same effective
context. It is not a toggle and does not assert row-address availability. The glyph,
control keycaps and selected-row treatment must not obscure each other.

Place small keycaps in an overlay anchored to the existing Repos/Panes/filter
controls. No new layout row, backdrop, reflow or click interception. Do not draw a
focus ring around the Repos/Panes selector while the table owns focus: the actual
focused control and keyboard-selected row should tell the truth. A selector ring
belongs only to actual selector focus. Active-pane indication remains separate
from the browsed row's selection.

Hints must project available command specs/shortcuts, not copy labels or introduce
new actions. A hint disappears when its action is unavailable. Overlay positions
must follow current control geometry and clipping. The rendering owner is not a
new keyboard owner and may not intercept mouse input or broaden shortcut contexts.

The Cursor video demonstrates another valid *reveal trigger*: modifier peek.
Normal trailing timestamps switch to shortcut pills after about half a second of
visible Command indication, then return. The recording does not establish a product
threshold or physical key-up event. We borrow its compact in-place presentation;
using modifier-held peek instead of focus-visible hints remains an owner choice.
It does not require numbered pinned-row shortcuts and does not replace list focus.

## Pinned navigation and arrangements as one journey

Keep the selected Option-Shift-arrow direct pane switch as a separate command
family from sidebar input. It does not require revealing the sidebar. Its targets
are pane pins, including eligible Bridge pane pins, not repository pins. Exact
scope, ordering and wrap must be chosen for this family itself, without reusing
discarded activity/history-stack rules. No Option-Shift-1..9 feature is selected.

Both Enter on a pane row and direct pinned-pane navigation use the agreed target
reveal rules. Keyboard navigation must retain the existing dispatcher/validation
path; it must not bypass authority via a row callback or a guessed window target.

Current creation inserts and unminimizes a new pane in every arrangement; that
must change to current plus Default visibility. Current reveal checks membership,
not minimized status; that must change to the accepted visible-target policy.
Those changes remain part of this design regardless of hint styling.

## Actual implementation boundary — not free native behavior

Existing surface layout, row projection, grouping/filter controls, command catalog,
pane actions and focus derivation are the foundation. Work needed includes:

- Reconcile native row selection and keyboard activation with hosted-row mouse
  actions; the table currently forbids selection and clears it again on change.
- Publish actual list/control/text focus into the existing focus fact without
  conflicting publications from the current filter bridge.
- Preserve selected row identity across regroup/filter/update and scroll it into
  view; preserve return identity and handle destroyed origins.
- Project the icon/hints from effective routing and actual responder context.
- Route selected commands and target reveal through their existing owners.

No independent navigation atom/store, no app-wide mode, no new global chord engine,
no pinned-only numbered working-set assumption, and no claim of a free native focus ring or
automatic text filtering. Native behavior and hint rendering need actual app proof.

## Direct pinned-pane shortcut — selected

Option-Shift-Up / Option-Shift-Down, from terminal, switches to the previous/next
pinned pane using the arrangement/drawer reveal rules. This replaces separate
activity and visit-history navigation. It is a direct action, not sidebar mode.
Exact ordering, wrap and scope remain discussion items.

## Navigation and return — proposed, not yet selected

| Input / event | Proposed result |
| --- | --- |
| Enter navigation | Restore remembered row on the remembered surface; choose a valid fallback if gone |
| Up/down or plain I/K | Move the visible selection without switching panes |
| Left/right or plain J/L | Collapse/expand groups |
| Enter on a pane | Reveal and focus it; leave sidebar navigation |
| F | Focus the existing sidebar filter, scoped to Repos or Panes |
| Typing in filter | Type normally; P/R/F and I/J/K/L are text |
| Escape from filter | Return to list first |
| Escape from list | Return to originating pane; keep sidebar visible |
| Click a pane | Leave sidebar navigation and let the clicked pane own focus |
| Hide sidebar during navigation | Return focus to work; no invisible keyboard mode |

F is recommended as **Filter this list**, not repository file search. Panes should
filter pane rows; Repos should filter repository/worktree rows. A file finder is
a different job whose binding is not selected here. Current filter exit clears
text and refocuses the pane; changing it to the proposed list-first return needs
explicit implementation and proof.

Open decisions: selection-only versus live preview as rows change; exact return
behavior and second activation press; filtering return semantics; Management-mode
interaction; focus return when the origin closes. These stay questions alongside
useful design work, not reasons to stop all progress.

## Arrangement behavior retained

```text
CREATE PANE                        REVEAL TARGET

Current arrangement: visible       Visible in current? → stay
Default:             visible       Else visible custom → first in order
Other custom:        hidden        Else → Default
                                   Drawer → reveal parent + expand
```

The settled creation and reveal rules remain independent of how the user chose
the target. No unrelated arrangement is expanded just to make it eligible.

## Current source versus required work

- `RepoExplorerTableMaterializer.tableView(_:shouldSelectRow:)` returns false;
  selection changes deselect everything. Visible keyboard row selection is new work.
- `executeSidebarScreenCommand` selects Repos/Panes and expands the sidebar but
  does not focus a row.
- `RepoExplorerFocusBridge` exposes filter focus; its neutral cancel operation
  does nothing. It is not a complete list navigation mode.
- `KeyboardOwner.current` already represents a focused sidebar separately from
  Management. This supports the conceptual distinction, not proof of the new UX.

Source anchors: [table selection](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift),
[sidebar commands](../../../Sources/AgentStudio/App/Boot/AppDelegate+ShellCommandHandling.swift),
[focus bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift),
[keyboard owner](../../../Sources/AgentStudio/Core/Models/KeyboardOwner.swift).

The activity-grouping bug investigation remains separate. Settled output and its
age do not by themselves prove that an agent has finished or needs attention.
No code changes or completed keyboard proof are claimed by this map.
