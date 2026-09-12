# Keyboard sidebar and arrangement visibility — review map

**Current discussion-review draft.** This contains the current direction only.
Selected owner decisions and proposed details are distinguished below. It is not
an implementation-ready Specification or a claim of independent design acceptance.

Authority: [Requirements](requirements.md). These two documents are the current
review input; historical discussion and the retired traversal draft are excluded.

## 1. What we are building

```text
Keyboard sidebar system
├── Show/hide or focus sidebar
├── Choose Panes/Repos and filter results
├── Navigate rows/groups and address results 1–9
├── Temporarily preview a pane
├── Commit to a destination or return to work
└── Focus-derived icon and contextual hint layer

Coherent arrangement visibility
├── New pane: current arrangement + Default
├── Other custom arrangements stay undisturbed
├── Commit: current visible → first visible custom → Default
└── Drawer target: reveal parent + expand drawer + reach child

Small direct shortcut
└── Option-Shift-Up/Down from terminal: previous/next pinned pane
```

No activity/history traversal system, app-wide sticky navigation mode, large help
panel, workspace dimming or general chord framework is included. Viewer/annotation
redesign and the activity-grouping bug remain separate work.

## 2. One visible journey

```text
Working in pane A
       |
 Command-Shift-S
       v
Sidebar list owns focus
       |
       +→ P / R ──→ Panes / Repos list
       |
       +→ F ──→ type filter ──→ Enter ──→ filtered list
       |
       +→ move selection to pane B
       |        |
       |        +→ Preview ──→ temporarily see B; sidebar keeps keyboard
       |                              |
       |                        end preview → restore prior presentation
       |
       +→ Enter ──→ reveal B permanently for navigation; focus B
       |
       +→ Escape ──→ return to A (proposed return behavior)
```

Preview/Enter distinction is owner-requested. Keeping focus in the sidebar and
restoring the prior presentation are the recommended behavior needed to make preview
temporary; exact activation and placement remain open in section 5.

## 3. Keys by focus location

| Focus | Keys | Meaning | Status |
| --- | --- | --- | --- |
| Pane / app workspace | Command-S | Show/hide sidebar; keep surface | Selected |
| Pane / app workspace | Command-Shift-S | Show sidebar if hidden; focus its navigation list | Selected |
| Sidebar list | P / R | Panes / Repos | Selected |
| Sidebar list | F | Focus existing current-list filter | Entry selected; filter meaning recommended |
| Filter | Plain letters/digits | Type query; live results update | Existing text behavior retained |
| Filter | Enter | Keep query/results; focus table, not a result | Selected |
| Sidebar list | Up/Down | Move keyboard selection | Proposed |
| Sidebar list | Left/Right | Expand/collapse groups or parent | Proposed |
| Sidebar list | G / Shift-G | Next/previous group | Optional proposal |
| Sidebar list | 1–9 | Address first nine results | Selected capability; select/preview versus activate open |
| Sidebar list | Preview control/key | Show selected pane temporarily | Requested; trigger open |
| Sidebar list | Enter | Commit selected destination | Selected direction |
| Sidebar list | Escape | End preview if needed; return to origin, leave sidebar shown | Proposed |
| Filter | Escape / Down | Return to table | Proposed; preserve/clear policy open |
| Terminal | Option-Shift-Up/Down | Direct previous/next pinned pane | Selected; ordering/reach/wrap open |

Existing arrangement navigation remains Command-Option-J/L and the
Command-Option-I picker. Existing Option-I/J/K/L spatial navigation and
Command-Shift-I/J/K/L terminal scroll/prompt actions retain their roles.

Plain P/R/F are commands only in the list. In Filter they are text. This deliberately
uses F before typing, rather than unrestricted list type-ahead. Command-Shift-P
already opens Commands and is not a substitute surface shortcut.

## 4. Numbered results and selection

Recommended: number the first nine actionable rows of the current filtered,
expanded list. Skip headings and diagnostic rows; scrolling alone does not change
numbers. The hint and the action must always refer to the same current row identity.
Do not activate a different row after a stale index survives filtering or regrouping.

Pane rows target existing panes; worktree rows use their existing openWorktree
operation. They are not interchangeable with pinned repositories. A missing or
nonactionable number must not trigger an unrelated command.

With Preview, the owner is choosing between:

- 1–9 selects the numbered result (and previews it if preview is active); Enter commits.
- 1–9 remains a direct activation shortcut; ordinary selection uses arrows.

Keyboard-selected row, currently active pane, and temporarily previewed pane are
three different facts. Their visual treatments must not imply that preview already
committed navigation. Live-update number/selection fallback rules remain review items.

## 5. Temporary preview, not accidental activation

The owner requested a Preview button that shows a pane only while picked, with
Enter taking the user there. Two concrete triggers are under discussion:

```text
Hold-to-preview:  select B → hold Preview/Space → see B → release → restore
Toggle-preview:  Preview on → select B/C/D → see selected pane → off → restore
Both:            Enter → commit to selected pane; no restoration over that commit
```

Space is a proposed keyboard equivalent, not an assigned shortcut. Review should
settle which trigger “picked” means. Selecting a row alone must not silently become
a committed focus operation just because preview is visible.

Recommended observable boundary:

- Show the existing selected pane while sidebar navigation keeps keyboard focus.
- Preview does not create another terminal/Bridge session or perform openWorktree.
- End uncommitted preview by restoring the prior presentation, not leaving another
  tab selected or a pane/drawer permanently expanded as a side effect.
- Enter converts the chosen target into committed navigation using section 7.
- If the target closes or becomes invalid, remove its preview; never recreate it.
- Text entered while the filter owns focus never goes to a previewed terminal.

Not yet decided: preview location for targets in another window, whether preview
follows selection or lasts only during a press, behavior on a non-pane Repos row,
and exact cancellation/closed-origin behavior. A pane preview is not a worktree
preview or permission to open a new pane merely to fill the preview area.

**Source constraint:** current focusPane changes active tab/arrangement, may expand
minimized panes/drawers, and transfers focus. Calling it for preview then blindly
reversing state is not a validated preview design. Program Design must establish a
safe temporary presentation path after the preview contract is selected.

## 6. Focus-derived icon and hint layer

Real focus/key-window/transient-surface context owns keyboard behavior. No separate
sticky navigation-owner flag. List focus and filter text focus must be distinguished;
sidebarHasFocus alone covers both today and cannot authorize plain-letter commands.

```text
List focus    → selected-row treatment + sidebar keyboard icon + command keycaps
Filter focus  → actual input focus; list-command letters become text
Other surface → sidebar navigation hints stop claiming keyboard authority
```

Selected visual direction: a small icon at the marked leading sidebar-toolbar
location and floating keycaps anchored to their existing controls/rows. No separate
help panel, extra header row, reflow, backdrop or click interception. The icon shows
keyboard ownership; badges show available keys; row selection identifies the target.

Recommended reveal: show hints with effective list focus. Modifier-peek is an
alternative reveal trigger, not a new navigator. Cursor's video shows compact pills
replacing trailing metadata; its exact keys, timing and nine-row working-set assumption
are not our contract. First-nine list shortcuts here come from the owner's separate
request. The final icon/anchor treatment still needs visual review in the actual UI.

## 7. Arrangement creation and committed reveal

### New pane

| Arrangement | Visibility after creation |
| --- | --- |
| Current arrangement | Visible |
| Default in the same tab | Visible |
| Other existing custom arrangements | Do not automatically reveal the new pane |

If creating in Default, it is the sole existing arrangement that newly shows the
pane. Preserve the existing parent/drawer structure; do not flatten children into
main panes. No retroactive rewrite of unrelated existing pane visibility is requested.

### Commit to a pane

```text
Target in owning tab
       |
Visible in current arrangement? ─ yes → keep current
       |
       no
       v
First custom arrangement in order where visible? ─ yes → select it
       |
       no
       v
Default
       |
Reveal parent / expand drawer when needed
       |
Focus actual target pane
```

A minimized pane is not visible. The final result must expose the child, not merely
focus its parent. Preview is temporary and must not silently change this committed
policy. Pane click, keyboard activation and direct pinned-pane commands share the
committed reveal rule; preview is a distinct operation.

Open visibility edges: child minimized while parent visible, target/parent closing,
Default with drawer children, and preview interacting with zoom or another window.
These require explicit resolution, not removal of the agreed fallback behavior.

## 8. Review questions and evidence

Review current needs, focus ownership, preview versus commit, numbered results,
visibility rules, and visual restraint. Do not review discarded activity/history
families or require their old questions to be answered.

One remaining focus decision: Management currently has priority over sidebar
focus. When Command-Shift-S is invoked during Management, should it leave Management
and focus the sidebar, or leave Management unchanged? Neither behavior is selected.

| Current source | Consequence for the design |
| --- | --- |
| [KeyboardOwner](../../../Sources/AgentStudio/Core/Models/KeyboardOwner.swift) and [routing context](../../../Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift) | Derive command/hint availability from effective focus; transients take precedence |
| [Table materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift) | It rejects and clears selection; keyboard selection is actual implementation work |
| [Focus bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift) | Current bridge primarily covers filter focus; cancellation/return not complete |
| [Sidebar view](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) and [search field](../../../Sources/AgentStudio/SharedComponents/SidebarSearchField.swift) | Live filter exists; sidebar must wire onSubmit for Enter-to-table |
| [Pane focus/reveal](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift) | Committed activation mutates visibility/focus; not a reversible preview API |
| [Arrangement insertion](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift) | Currently unminimizes new panes in all arrangements |
| [Row actions](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializedRowView.swift) | Pane focus and worktree open are separate primary actions |

Proof needed later: real list/filter/pane focus, anchored hint rendering, correct
number-to-row mapping during updates, preview dismissal versus Enter commit, and
creation/reveal through terminal, Bridge and drawer targets. No native proof or
complete independent three-artifact review is claimed by this discussion map.
