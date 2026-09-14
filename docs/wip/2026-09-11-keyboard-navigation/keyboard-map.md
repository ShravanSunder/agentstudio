# Keyboard sidebar and arrangement visibility — review map

**Current implementation review map.** Sidebar core and terminal navigation are implemented.
The reviewed MainActor snapshot-capture regression is corrected; focused tests and lint pass.
The corrected-head aggregate, capture correction review and pinned timing proof are complete at `41c427781`; the held-preview S1 input/cancellation slice is implemented and proven with `51` focused tests across `6` suites, `0` issues, and scoped lint `0`. S2 owning-tab presentation/custody, S3 mount/restore/renderer/Bridge integration, and S4 Space overlay/performance/native journey remain pending; the design and plan are ready, so this map does not claim whole-PR readiness.
Explicit owner choices and implementation defaults are distinguished in the
[decision record](core-design-decisions.md). Preview behavior is confirmed; S1 input/cancellation is proven, while the remaining S2–S4 realization and proof remain pending.

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
temporary; hold/release behavior is settled; loading existing content is confirmed; its remaining renderer path is governed by the ready S2–S4 plan in section 5.

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
| Sidebar list | Hold Space | Preview fills pane area and follows selection; release cancels | Selected |
| Sidebar list | Enter | Commit selected destination | Selected direction |
| Sidebar list | Escape | Cancel preview if present and return to origin; sidebar stays shown | Core return default; preview pending |
| Filter | Escape / Down | Preserve query and return to list | Implementation default |
| Terminal | Option-Shift-Up/Down | Previous/next pinned pane; sidebar pinned order with wrap | Selected |

Existing arrangement navigation remains Command-Option-J/L and the
Command-Option-I picker. Option-I/J/K/L retains its spatial shortcut bindings.
The separate [terminal discussion](terminal-navigation-discussion.md) now selects
Command-Shift-I/K for 90% up/down and Command-Shift-J/L for 33% up/down.
Option-Shift-J/L remains previous/next shell prompt; Command-Option-K jumps to
terminal bottom. Option-Shift-I/K is unassigned and reserved for later agent-TUI
navigation. No top jump. Implementation and proof are being updated to this map.
Normal Option-J/L spatial movement must skip hidden/minimized panes, without
switching arrangements or expanding them.

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

Space is the selected preview key. Selecting a row alone does
not commit navigation. Numeric activation commits independently of held preview.

Recommended observable boundary:

- Show the existing selected pane while sidebar navigation keeps keyboard focus.
- Preview keeps the existing target pane and its terminal/Bridge renderer; it does not create a substitute pane or perform openWorktree. If an existing terminal pane's session has ended, normal restore may start a fresh shell in that same existing pane.
- End uncommitted preview by restoring the prior presentation, not leaving another
  tab selected or a pane/drawer permanently expanded as a side effect.
- Enter converts the chosen target into committed navigation using section 7.
- If the target pane closes or becomes invalid, remove its preview; never recreate or substitute the pane.
- Text entered while the filter owns focus never goes to a previewed terminal.

Confirmed: preview fills the pane area and follows selection while Space is held.
Load existing panes as needed, including Bridge content; a renderer may remain warm
after release. A worktree row does not create a pane for preview. The renderer/geometry
design must preserve the existing pane identity; normal restore may start a fresh shell
in that same existing pane when its prior session has ended, without substituting another pane.

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
policy. Explicit pane click, sidebar activation and direct pinned-pane commands share the
committed reveal rule. Normal Option-J/L spatial movement instead stays among visible
panes in the current scope; it does not reveal hidden targets. Preview remains distinct.

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
| [Stable host](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializationHost.swift) / [table materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift) | Host owns actual list focus and selected-row/group/digit behavior; accepted worker indexes drive navigation |
| [Focus entry](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift) | Invisible proxy removed; shell targets the actual stable host |
| [Sidebar view](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) and [search field](../../../Sources/AgentStudio/SharedComponents/SidebarSearchField.swift) | Enter/Down/Escape return to the list; production SwiftUI handoff regression is corrected and natively proven |
| [Pane focus/reveal](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift) | Committed activation mutates visibility/focus; not a reversible preview API |
| [Arrangement insertion](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift) | Creation-specific current+Default insertion is implemented and locally validated; existing identity placement preserves its original behavior |
| [Row actions](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializedRowView.swift) | Pane focus and worktree open are separate primary actions |

Sidebar core design and implementation review are complete for corrected HEAD `41c427781`. Native entry,
P/R/F surface/filter routing and filter-to-list/terminal return have
[current proof](sidebar-focus-native-proof.md). Row/group/digit navigation and anchored hints now have
[native activation and overlay proof](sidebar-overlay-native-proof.md), including Bridge/custom
arrangement, drawer reveal and offscreen result 9. The late-restore focus handshake has regression
and rebuilt native proof. Direct pinned navigation is implemented with [mixed-pane native proof](pinned-navigation-native-proof.md);
its full aggregate and corrected marker-scoped timing proof passed; the independent capture correction review is complete. The timing sample is 28 operations represented by 56 phase records, with capture median/max `0.010500`/`0.017875 ms` and worker median/max `0.123208`/`0.225750 ms`; this is an observed sample only. Held-preview S1 input/cancellation is implemented and proven by 51 focused tests across 6 suites with 0 issues and scoped lint 0; S2 owning-tab presentation/custody, S3 mount/restore/renderer/Bridge integration, and S4 Space overlay/performance/native journey remain pending. No nested Bridge WebKit DOM-focus claim is made.

Arrangement creation/reveal has separate native terminal, Bridge and ordinary drawer
proof. The revised terminal map has [fresh native evidence](terminal-native-v2-proof.md).
The historical arrangement entry above preserves its PR #345/main-alignment context. The current corrected-head full aggregate passed at `41c427781` after the capture correction; the receipt is retained in `tmp/sidebar-keyboard-design/capture-current-head-aggregate.result.json`. This map records the corrected implementation and proof state, while pending S2–S4 slices keep the overall change short of whole-PR readiness.
