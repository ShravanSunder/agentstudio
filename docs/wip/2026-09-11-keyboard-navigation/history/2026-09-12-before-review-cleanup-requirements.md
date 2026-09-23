> Historical archive — not current review or implementation authority. Relative links retain their original document context.

# Keyboard navigation requirements — working discussion

Owner: Shravan. Source: this session's 2026-09-11 request to discuss commands,
reduce navigation effort with carpal tunnel, and keep requirements in WIP docs.
This is an evolving Requirements home, not a Specification or implementation plan.
No implementation is authorized by this discussion. Exact bindings and unresolved
behavior below are not accepted contracts unless included in the owner decisions below.

Start with the [visual keyboard map](keyboard-map.md) for the current/proposed
bindings, activity versus visit diagrams, and the remaining sidebar/arrangement
decisions. This file remains the Requirements home.

## Current design cycle — owner decisions, 2026-09-12

**New owner requests:** Enter from Filter completes filter entry and returns to
the table, retaining results; number shortcuts 1–9 for the first nine list items.
The proposed realization uses the existing live filter and treats Enter as focus
handoff, then digits as direct activation only with table focus. It is not a
pinned-only numeric shortcut feature. The owner's request supersedes earlier
statements that no number shortcuts were in scope. Exact actionable-row counting,
live-update mapping and keycap presentation remain design details to settle.

**Validated architecture constraint:** sidebar keyboard behavior and its hint layer
must follow effective focus/routing; no independently stored sticky navigation bit
is selected. Actual list focus is distinct from filter text focus even though both
publish sidebarHasFocus today. The [critique validation](comment-validation.md)
records verified claims, overstatements and proposed scope changes. The map now
explains the complete focus-based solution and real implementation work.

P/R/F remain the owner's selected local list commands; unrestricted type-ahead
conflicts with that choice. F-to-filter is recommended, not a claim that native
type-ahead already works. Modifier-peek versus focus-visible hints is still a
presentation choice. Nine pinned digit addresses and removing the requested icon
are external proposals, not accepted requirements.

Current scope: sidebar keyboard navigation, direct pinned-pane navigation from
terminal, existing arrangement navigation, and arrangement creation/reveal fixes.
Separate activity-stack and visit-history traversal were explicitly removed by
the owner. Their earlier questions and held-sequence proposals are superseded;
none is an implementation prerequisite for the current design.

| Decision | Selected meaning |
| --- | --- |
| Sidebar visibility | Command-S shows/hides sidebar, retaining its surface |
| Sidebar activation | Command-Shift-S activates keyboard navigation and shows sidebar if hidden |
| Surface selection | P selects Panes; R selects Repos while sidebar navigation owns focus |
| Filter entry | F enters search/filter; current recommendation is filtering the visible list, not a file finder |
| Pinned panes | Option-Shift-Up/Down directly switches previous/next pinned pane from terminal, replacing the discarded activity/history family |
| Mode indication | Owner requests an icon at the marked sidebar-header location and supplies Cursor animation as a reference; large help strip rejected |
| Creation | New pane visible in current arrangement and Default; unrelated custom arrangements do not automatically reveal it |
| Reveal | Stay if visible in current arrangement; otherwise first visible custom arrangement in order; otherwise Default |
| Drawer target | Reveal parent and expand drawer before focusing child |

The selected Shift-Option-Up/Down keys are arrow keys, not letters I/K.
Pinned-pane ordering, wrap behavior and reach must be settled for that direct
shortcut without importing the discarded activity-stack assumptions.

Active needs: U1, U3/U4/U5, U6/U7, navigation portions of U12, and new U14 below.
U2 activity/history traversal is superseded. U8/U9 pin/rename action shortcuts,
U10/U11 viewer/search redesign, and broad chord restructuring stay recorded for
later. Per-item relative priority is unassigned. The owner wants questions grouped
while independent design work continues.

Current proposals still needing selection: exact row/group movement, Enter versus
preview, return/filter behavior, Management interaction, and hint reveal trigger.
Do not treat proposed Escape behavior as established code. Annotation focus/draft
behavior remains a compatibility consideration, not a new annotation project.

The owner invoked orchestrator-design. Reuse this Requirements identity; the
existing Specification draft is explicitly superseded for traversal and is not
implementation authority. Separate final Specification and Program Design must
be authored and independently reviewed after current meaning is settled.
The existing events.jsonl trail is reused and finalized by the outer design owner.

Sidebar activity-group diagnosis is separate: a source-only subagent report found
runtime-only timestamps, nonempty-only buckets, persisted collapse, and existing
deadline refresh. It did not reproduce the running-app symptom or prove a fix.

## Goal and boundary

Make moving between work, finding panes/files, and acting on panes predictable
and comfortable from the keyboard. The primary users are Shravan and other
keyboard-oriented Agent Studio users, including users who need to reduce hand
strain. No medical benefit is claimed from any proposed binding.

Requested surfaces: panes, arrangements, sidebar Repos/Panes surfaces, viewer /
Bridge / Review, and their file finders. Existing command catalog, pane targeting,
Management mode, sidebar groupings, and arrangements are the foundation to inspect
and reuse. API consumers, operators, and buyers have no separately requested new
outcomes here. Terminal input and text editing conflicts remain a design constraint
to investigate, not permission to redesign those systems.

This cycle permits design documentation and review. Source, configuration,
infrastructure, releases, and implementation plans are outside this cycle. An app-wide
remapping editor or a general chord engine is not yet requested or selected.
Acceptable complexity and final scope need owner confirmation before specification.
Proposed eventual proof: real keyboard journeys across terminal, sidebar, and
viewer, including focus return, hidden/minimized panes, and text input; comfort
needs direct owner feedback. This proof boundary is not yet owner-confirmed.

## Needs inventory

All evidence below is the owner's opening request unless a code anchor is named.
Authorized means the requested need is explicit; it does not settle its proposed
binding or an ambiguous edge case. Priority is unassigned by the owner for every
row; do not infer an ordering from row numbers.

| ID | Need / outcome and reason | Authority | Remaining choice |
| --- | --- | --- | --- |
| U1 | Navigate with less hand movement and strain; keyboard use should be easy for Shravan and others. | authorized | Comfortable modifier holds, reaches, and sequences need owner feedback. |
| U2 | Earlier separate activity/history traversal. | superseded by explicit owner removal | Replaced by sidebar navigation and U14 pinned-pane switching. |
| U3 | Stop Command-S selecting Repos; distinguish sidebar visibility from selecting Repos/Panes. | authorized | Replacement for Command-S; exact surface shortcuts or sequences. The phrase “make mode” is ambiguous. |
| U4 | Move keyboard focus to sidebar and back; reveal sidebar when hidden. | authorized | Return target, selection preservation, and whether return leaves sidebar visible. |
| U5 | Navigate sidebar panes and change grouping from keyboard. | authorized | Row movement versus activation; group traversal; grouping keys. |
| U6 | Creating panes should not expose them in unrelated custom arrangements; Default remains the fallback showing panes. | authorized | Literal “only show in default” versus active custom plus Default. Drawer behavior not settled. |
| U7 | Selecting a pane should reach an arrangement where it is visible, not minimized; otherwise use Default. | authorized | Meaning of “first”; preserve current arrangement if visible; Default ordering; click entry points; keyboard parity. |
| U8 | Pin/unpin pane by keyboard as part of a coherent pane-command family. | authorized | Binding and focused-pane versus selected-sidebar-row target. |
| U9 | Rename by keyboard as part of the same coherent system. | authorized | Pane versus tab/arrangement naming; target and binding. |
| U10 | Reach Review / Bridge easily and search their files with keyboard. | authorized | Exact destinations and local search versus file finder behavior. |
| U11 | Reach the sidebar repository file finder easily. | authorized | Entry, scope, and return behavior. |
| U12 | Inventory existing shortcuts and decide holistically which actions deserve direct bindings or chords. | authorized | Final families, conflicts, discoverability, and priority. |
| U13 | Give infrequent actions visible follow-up choices, a predictable cancel/back route, and optional low-modifier sequences. | advisory — assistant proposal | Whether these improve actual comfort; no timing or modifier-release contract chosen. |

| U14 | Switch directly from terminal to previous/next pinned pane using Option-Shift-Up/Down, revealing its arrangement/drawer. | authorized — owner selected keys and explicitly replaced activity/back-forward idea | Exact ordering, wrap and scope still to settle. |

## Current source evidence

Read on 2026-09-11; these are source observations, not native UI proof.

- [Shortcut catalog](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcut.swift):
  Command-S → Repos; Command-Shift-S → toggle sidebar; Command-F → sidebar filter
  (subject to dispatch context); Command-R → Management; Command-O → viewer;
  Command-P → Everything; Command-Shift-P → Commands; Command-Option-P → Panes.
  Command-J/L → previous/next tab; Command-Option-J/L → previous/next arrangement;
  Command-Option-I → arrangement panel. Management has unmodified arrow and
  action keys. The binding model describes individual triggers with contexts and
  alternates, not a sequence contract. This is not a full conflict audit.
- [Sidebar command catalog](../../../Sources/AgentStudio/Core/Actions/Commands/AppCommand+SidebarCatalog.swift):
  separate Repos/Panes commands, pin/unpin pane, and grouping commands exist;
  Panes and pin/unpin definitions do not assign direct shortcuts.
- [Insertion rules](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift):
  main-pane insertion adds to arrangements and removes the pane from each
  minimized set. This differs from U6. Drawer insertion is a separate path.
- [Reveal helper](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift):
  `revealArrangementContainingPane` only switches when the current layout lacks
  the pane, then chooses the first layout containing it. It does not test the
  minimized set. Full click-to-focus call paths still need inspection.
- [Recency model](../../../Sources/AgentStudio/Core/Models/EntityRecency.swift):
  workspace pane recency types exist. This alone does not establish a navigation
  history, frozen switcher list, or exact focus-recording semantics.

## Historical exploration — not current scope

### I/J/K/L shortcut inventory

Current source checked after owner requested the arrow-shaped cluster audit.
These are current assignments, not proposed replacements.

| Modifier | I (up) | J (left) | K (down) | L (right) |
| --- | --- | --- | --- | --- |
| Option | Drawer up; consumed without action in main pane scope | Pane/drawer left | Drawer down; consumed without action in main pane scope | Pane/drawer right |
| Shift-Option | No app assignment found | No app assignment found | No app assignment found | No app assignment found |
| Command | No app assignment found | Previous tab | Explicitly suppressed terminal host binding | Next tab |
| Command-Shift | Terminal page up | Previous terminal prompt | Terminal scroll to bottom | Next terminal prompt |
| Command-Option | Arrangement panel | Previous arrangement | No app assignment found | Next arrangement |

Sources: `AppShortcut.swift`, `PaneTabViewController.scopeAwarePaneCommand`,
`isScopeAwarePaneMovementTrigger`, `handleTerminalRuntimeShortcut`, and
`AppShortcutDispatchPolicy.shouldSuppressTerminalHostTrigger`. “No app assignment
found” is not a claim that OS, keyboard layouts, terminal applications, or all
embedded web content leave the binding free. Owner correction: preserve
Option-I/K for drawer up/down; do not assign Command-I/K to that behavior.
Option-J/L remain spatial left/right. Shift-Option-I/K for activity and
Shift-Option-J/L for visit history are assistant proposals, still unselected.
Command-Shift-I/J/K/L are all used, even though Command-J/L alone are the tab pair.

### Activity versus visits

Reopened meaning: Shravan initially answered “The pane I last focused,” then
questioned visited versus active and explicitly directed inspection of terminal
pane activity. The earlier focus-only conclusion is not a settled navigation
contract. Do not replace it with an assumed activity-only decision either.

Current source distinguishes three facts in `capturePaneFact`:

- `activityAt`: settled terminal output status timestamp; supplies Activity
  sorting/grouping. It does not fall back to focus time.
- `recencyReferenceDate`: workspace pane interaction recency, falling back to
  pane creation time; separate from the Activity sorting field.
- `isActive`: whether this pane is the currently focused pane.

Terminal activity source: `TerminalActivityProjector` settles unattended output
after quiet, and also supports command-finished settles for attended panes and
agent-settled outcomes. `TerminalActivityRouter` sends settled output lines to
`PaneActivityStatusAtom`. That atom timestamps new nonempty lines, suppresses
identical repeats, and defers rapid changes within its ten-second publication
interval. Merely focusing a pane does not write a fresh activity timestamp;
attention can cancel an outstanding unseen-output window. This is runtime-only
settled-output evidence, not every byte of terminal output or a running-process flag.

Evidence: [projection input](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionInputCapture.swift),
[terminal projector](../../../Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityProjector.swift),
[activity status](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/PaneActivityStatusAtom.swift),
and [activity organization](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection+Organization.swift).

Earlier assistant recommendation, now under reconsideration: stable back/forward navigation through
user visits, because repeated separate keypresses can traverse without a held
modifier. Navigation itself should not rewrite the path under the user's feet.
This recommendation is not an accepted behavior contract.

Example: visit A, then B, then C.

```text
Back/forward history:  C -> B -> A; forward returns to B then C
Recent-pane switcher:  hold modifier; traverse fixed C, B, A; release chooses
```

The switcher is a credible alternative: it supports quick last-pane toggling,
but committing on modifier release may be uncomfortable. A latched chooser is
another possible realization if holding is a problem; no mechanism is chosen.
The choice between history and recent-list cycling remains open; confirming
focus as the source of recency does not select either traversal behavior.

## Current discussion queue

1. Mode icon and inline hints, informed by the supplied Cursor video.
2. Row/group keyboard navigation, activation and return; F filter semantics.
3. Direct pinned-pane order/scope and boundary behavior.
4. Arrangement rules at child-minimization and missing-target boundaries.

The old activity/history traversal decision list is removed from the active queue.
