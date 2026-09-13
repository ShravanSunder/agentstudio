# Keyboard sidebar and arrangement visibility — review map

**Current core design-review map.** Sidebar source implementation has not started.
Explicit owner choices and implementation defaults are distinguished in the
[decision record](core-design-decisions.md). Preview retains its open boundary.

Authority: [Requirements](requirements.md) → [Specification](../../specs/2026-09-12-sidebar-keyboard-system/specification.md) → [Program Design](../../specs/2026-09-12-sidebar-keyboard-system/program-design.md). Historical discussion and retired traversal drafts are excluded.

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
       +→ Escape ──→ return to A (active-pane fallback if origin is gone)
```

Preview/Enter distinction is owner-requested. Keeping focus in the sidebar and
restoring the prior presentation are the recommended behavior needed to make preview
temporary; hold/release behavior is settled; cold content and its renderer path remain open in section 5.

## 3. Keys by focus location

| Focus | Keys | Meaning | Status |
| --- | --- | --- | --- |
| Pane / app workspace | Command-S | Show/hide sidebar; keep surface | Selected |
| Pane / app workspace | Command-Shift-S | Show sidebar if hidden; focus its navigation list; no-op during Management | Selected |
| Sidebar list | P / R | Panes / Repos | Selected |
| Sidebar list | F | Focus existing current-list filter | Current design |
| Filter | Plain letters/digits | Type query; live results update | Existing text behavior retained |
| Filter | Enter | Keep query/results; focus table, not a result | Selected |
| Sidebar list | Up/Down | Move selection; stop at edges | Implementation default |
| Sidebar list | Left/Right | Expand/collapse or move between group and child | Implementation default |
| Sidebar list | 1–9 | Open the corresponding first-nine result immediately | Selected |
| Sidebar list | Hold Space (proposed key) | Show selected pane temporarily; release cancels | Hold/release selected; renderer boundary open |
| Sidebar list | Enter | Commit selected destination | Selected direction |
| Sidebar list | Escape | Cancel preview if present and return to origin; sidebar stays shown | Core return default; preview pending |
| Filter | Escape / Down | Preserve query and return to list | Implementation default |
| Terminal | Option-Shift-Up/Down | Previous/next pinned pane; Panes order with wrap | Binding selected; ordering is implementation default |

Existing arrangement navigation remains Command-Option-J/L and the
Command-Option-I picker. Existing Option-I/J/K/L spatial navigation and
Command-Shift-I/J/K/L terminal scroll/prompt actions retain their roles.

Plain P/R/F are commands only in the list. In Filter they are text. This deliberately
uses F before typing, rather than unrestricted list type-ahead. Command-Shift-P
already opens Commands and is not a substitute surface shortcut.

## 4. Numbered results and selection

Number the first nine destination rows of the current filtered,
expanded list. Skip headings and diagnostic rows; scrolling alone does not change
numbers. The hint and the action must always refer to the same current row identity.
Do not activate a different row after a stale index survives filtering or regrouping.

Pane rows target existing panes; worktree rows use their existing openWorktree
operation. They are not interchangeable with pinned repositories. A missing or
nonactionable number must not trigger an unrelated command.

The owner selected direct activation: 1–9 opens the corresponding result immediately.
Ordinary row selection and held preview remain separate from this committed action.

Keyboard-selected row, currently active pane, and temporarily previewed pane are
three different facts. Their visual treatments must not imply that preview already
committed navigation. Selection follows its pane/worktree identity even if its group and row ID change.
If the destination vanishes, prefer a surviving successor,
then predecessor, then the new first result; this never activates the fallback.

## 5. Temporary preview, not accidental activation

The owner selected holding a key to preview and releasing it to cancel.

```text
select B → hold Preview key → see B → release → restore
                       |
                       +→ Enter commits B; later release does not undo it
1–9 → open the corresponding result immediately
```

Space remains a proposed key, not an assigned shortcut. Selecting a row alone does
not commit navigation. Numeric activation commits independently of held preview.

Recommended observable boundary:

- Show the existing selected pane while sidebar navigation keeps keyboard focus.
- Preview does not create another terminal/Bridge session or perform openWorktree.
- End uncommitted preview by restoring the prior presentation, not leaving another
  tab selected or a pane/drawer permanently expanded as a side effect.
- Enter converts the chosen target into committed navigation using section 7.
- If the target closes or becomes invalid, remove its preview; never recreate it.
- Text entered while the filter owns focus never goes to a previewed terminal.

Working presentation defaults are full canvas and following selection while held.
The material unanswered question is whether unloaded existing renderer/content may
restore during preview and remain warm. A worktree row does not create a pane for
preview. The renderer/geometry design must preserve the existing session identity.

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

Show hints with effective list focus; suppress them while filtering or another
surface owns input. Cursor's video shows compact pills
replacing trailing metadata; its exact keys, timing and nine-row working-set assumption
are not our contract. First-nine list shortcuts here come from the owner's separate
request. Result keycaps overlay the existing leading identity-icon column, leaving titles
and pin controls readable. Selection uses existing shared row paint. Actual native
fit still requires visual proof.

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

The [arrangement specification](../../specs/2026-09-12-arrangement-visibility/specification.md)
now resolves minimized children, Default fallback and target/parent closing.
The owner explicitly deferred the general [drawer renderer reattachment invariant](drawer-reveal-design-gap.md)
to another PR after the arrangement PR. It is not being repaired here. Arrangement
PR #345 is unmerged; latest main is incorporated and the full local aggregate passed
at `1a467a120`. New CI is being checked separately.

## 8. Review questions and evidence

Review current needs, focus ownership, preview versus commit, numbered results,
visibility rules, and visual restraint. Do not review discarded activity/history
families or require their old questions to be answered.

Management keeps its current precedence. The owner selected Command-Shift-S as a
no-op while Management is active: it does not leave Management or claim sidebar focus.

| Current source | Consequence for the design |
| --- | --- |
| [KeyboardOwner](../../../Sources/AgentStudio/Core/Models/KeyboardOwner.swift) and [routing context](../../../Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift) | Derive command/hint availability from effective focus; transients take precedence |
| [Stable host](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializationHost.swift) / [table materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift) | Host survives empty results and will own focus; table renders selection/scroll |
| [Focus bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift) | Replace invisible list proxy with actual host; retain existing filter focus callback |
| [Sidebar view](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) and [search field](../../../Sources/AgentStudio/SharedComponents/SidebarSearchField.swift) | Live filter exists; sidebar must wire onSubmit for Enter-to-table |
| [Pane focus/reveal](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift) | Committed activation mutates visibility/focus; not a reversible preview API |
| [Arrangement insertion](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift) | Creation-specific current+Default insertion is implemented and locally validated; existing identity placement preserves its original behavior |
| [Row actions](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializedRowView.swift) | Pane focus and worktree open are separate primary actions |

Sidebar proof still needed: real list/filter/pane focus, anchored hints at practical
widths, number-to-row mapping during updates, direct pinned navigation, and preview
hold/release/commit after its design is settled. Arrangement creation/reveal already
has separate native terminal, Bridge and ordinary drawer proof. Core design review
and implementation are next; this map does not claim the whole sidebar is done.
