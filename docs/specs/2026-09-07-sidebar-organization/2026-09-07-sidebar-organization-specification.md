# Sidebar Organization Specification

Basis: [Requirements](2026-09-07-sidebar-organization-requirements.md). Realization: [Program Design](2026-09-07-sidebar-organization-program-design.md).

## Scope

This contract covers the current sidebar organization branch. It excludes unseen dots, running animations, zmx IPC, vendor/toolchain updates, and complete or restart-persistent terminal activity. U9 and U12–U15 remain retained later needs. Existing R identities keep their original meaning.

## C1. Two-row controls

**R1 (U1, U2):** The header MUST have exactly two rows. Row one contains Repos/Panes and Filter. Row two contains, in order, pinned visibility, divider, sort direction, sort type, divider, and one grouping summary.

```text
Row 1   [ Repos | Panes ] │ Filter…
Row 2   Pin │ ↑/↓  Name/Activity │ Repo → Activity
```

Show Pinned defaults on. Selected is blue without persistent fill; unselected is neutral. The original animated arrow toggles direction only. The Name/Activity picker changes sort type only. The grouping summary appends `→ Subgroup` only when effective.

The grouping `.popover` MUST use 16-point padding and two equal, top-aligned columns. Group/Subgroup headers use catalog-owned icons; options use compact neutral Arrangement-style rows. When unavailable, the Subgroup column/header/icon/width remain with lighter noninteractive “No subgroups”. Valid None remains selectable.

**R2 (U7):** Every state-changing organization choice MUST use its surface-specific command spec, presentation preflight, and dispatcher. Selector open/dismiss is presentation-only local view state, with display metadata projected from LocalActionSpec; it does not create an AppCommand or IPC action. Option selection and pin/sort toggles recheck command enablement and dispatch. Exact chords are deferred. Unavailable/disabled commands MUST NOT dispatch or steal Filter/terminal/editor typing.

## C2. Repos and independent repository pins

**R3 (U3, U5, U10):** Repos MUST offer exactly Repo and Activity and MUST NOT offer a subgroup. Repo assigns each registered repository once to Pinned Repos, Open Repos, or Available Repos before grouping remote identities within each section. Registrations sharing a remote may therefore have section-local headers in different sections when their pin/open states differ; no registered repository or checkout is duplicated. Activity keeps Pinned Repos first and replaces Open/Available with fixed, noncollapsible activity sections. One remote-identity group uses the newest eligible timestamp among all represented repositories/worktrees. Repository headers remain expandable to checkouts.

**R4 (U5):** Hiding Pinned Repos MUST preserve pins and return items to Open/Available in Repo mode or their activity bucket in Activity mode. Pinned remains first and exclusive when shown. Pane pins have no effect.

## C3. Panes and independent pane pins

**R5 (U4, U5):** Panes MUST partition individual pane pins into Pinned Panes and Other Panes. Hiding Pinned Panes merges all panes into Other Panes without clearing or duplicating pins. Repository pins have no effect.

**R6 (U4):** Panes MUST offer Repo, Tab, and Activity. Repo/Tab headers remain expandable and allow None or Activity subgroups. Activity allows no subgroup.

**R6a (U17):** Saved None/Activity MUST restore for Panes Repo/Tab. Activity main grouping suppresses the effective subgroup without overwriting it. Repos ignores its retained legacy subgroup value.

**R6b (U18):** An activity subgroup heading appears only when its parent contains more than one nonempty bucket. Section headings use entity icons, blue word-initial/lowercase-small-caps labels, and increased noninitial top spacing. Expandable headers use chevron and title without an entity icon. Subgroups use the same casing, secondary color, trailing divider, and increased top spacing without adding leaf indentation.

## C4. Sort field and direction

**R7 (U11):** Both screens must offer Name and Terminal activity sort fields and separate ascending/descending direction. Name ascending means A–Z; descending means Z–A. Activity ascending means oldest first; descending means newest first. Arrangement/layout order is not a sort option.

**R8 (U11):** Changing either sort control must only reorder leaf rows within the currently selected section/group/subgroup. It must not change section membership, group membership, group order, activity-bucket order or collapse state. Name ordering acts on worktree names in Repos. In Panes it uses the trimmed resolved pane title (the title portion after the positional Pane number), with zsh for an empty title; the Pane number, notes, and secondary terminal output are not name keys. Unknown activity sorts after known activity in both directions; deterministic ties prevent churn.

## C5. Terminal activity and retained indicators

**R9 (U4, U6, U9, U14):** Terminal-activity organization must use qualifying terminal activity from the product's zmx-backed terminal path, not user focus, scrollbar movement alone, or restoring old display content. Historical activity timestamps must survive restart. A persisted active flag must not establish current activity after restart. A separate direct-Ghostty activity provider is not added by this change. **Deferred to PR3; not implemented in PR1.**

**R9a (U4, U6, U16):** This branch MUST classify the existing settled-output timestamp into Active, Just Now, Last Hour, Today, Last 7 Days, Older, or No Activity. It MUST NOT use focus, click, creation time, scrolling alone, or accumulating burst state as fallback. Current evidence is runtime-only, may miss output outside admission, and may suppress equal lines; the branch MUST NOT claim complete PTY coverage or restart persistence.

PR 3 improves qualifying evidence: immediate Active on admitted source output, refreshed for a sliding one-minute interval. At 60 seconds without another qualifying event the row leaves Active. No inference of command or agent completion follows from either scope's bucket transition.

Mutually exclusive time predicates, evaluated in order:

| Bucket | Predicate |
| --- | --- |
| Active | Current-runtime evidence with age >= 0 and < 60 seconds; PR 1 uses the existing settled-output fact, PR 3 source-owned activity |
| Just Now | Historical activity age less than ten minutes, not Active |
| Last hour | Age less than one hour, not above |
| Today | Activity on the current local calendar day, not above |
| Last 7 days | Age less than seven days, not above |
| Older | Older known activity |
| No activity | No usable evidence |

The first-match rule avoids duplicates across midnight. Exactly 60 seconds leaves Active; exactly ten minutes enters Last hour; exactly one hour uses Today/Last 7 days/Older as appropriate. A missing, invalid or future wall timestamp is unknown, not recent. PR 1 worktree activity is the newest available timestamp among that worktree's existing eligible pane destinations; no remaining evidence means No activity. Closing/retiring the last source does not retain synthetic worktree history. PR3 durable aggregation/lifecycle remains later work. The tail categories keep every destination visible.

**R10 (U12):** When qualifying activity has stopped and remains unseen, its pane row and owning tab must be able to display a blue dot. The same activity must not acquire independent acknowledgement state in the tab and sidebar. Which pane visits acknowledge the activity, quiet delay, multiple-pane aggregation, behavior on renewed output, and unseen-state persistence remain the later indicator contract. **Deferred to PR3; not implemented in PR1.**

**R11 (U13, U8):** Active pane animation must not require per-frame domain writes, projection recomputation, or pane-view work. It must stop when its row is offscreen or reused and respect Reduce Motion. A small layer-animated rotating arc is proposed; exact appearance and whether tabs animate remain the later indicator contract. Repository refresh animation retains its existing meaning. **Deferred to PR3; not implemented in PR1.**

## C6. Persistence, invalidation, and proof

**R12 (U10):** Favorite-to-Pinned migration must preserve existing repository selections and introduce independent pane pin values with existing panes initially unpinned. The migration must not copy repository pins into panes. Failure must follow existing database preparation/recovery behavior; no silent data reset or simultaneous old/new write path.

**R13 (U8):** Search, filtering, membership, grouping, activity classification/deadlines, sorting, and row-index derivation MUST execute in the detached projection. MainActor is limited to keyed capture, command state, and binding/rendering prepared results.

**R14 (U1–U13):** Organization and asynchronous publication MUST preserve canonical activation identity, avoid duplicates, reject stale candidates, and leave existing selection/navigation/collapse/chips coherent. Preferences MUST NOT mutate topology or terminal execution.

## C7. Staged preservation boundary

**R15 (U16):** This branch MUST NOT require a zmx version/toolchain update, new daemon protocol, dot, or running animation.

**R16 (U16):** PR 2 must preserve existing stored zmx session identities, attach/restore behavior and the fork's prompt-redraw fix. New-client/old-daemon operation and any supported rollback direction require explicit proof; a successful build alone does not establish compatibility with live sessions. The update must not silently kill or recreate existing sessions. A zmx upgrade alone must not be described as delivering activity metadata or blue-dot acknowledgement. **Deferred to PR2; not implemented in PR1.**

**R17 (U9,U14–U16):** PR 3 must keep the selected zmx IPC boundary internal and reuse the existing runtime owners. The metadata source must distinguish live PTY reads from attach replay, and provide sufficient identity/currentness to reject stale observations after session replacement. No public zmx methods or raw terminal payload export is introduced for sidebar activity. **Deferred to PR3; not implemented in PR1.**

## C8. Saved settings and defaults

**R18 (U17):** Existing settings restore before defaults. Without saved values, Repos defaults to Repo grouping, Panes defaults to Repo grouping with Activity subgrouping, and both surfaces default to Name ascending. Repos reuses `repoGroupingMode`; legacy Repos subgroup storage remains compatible but unused. Valid Panes None remains None. Both Show Pinned values default on. Exact shortcut chords remain deferred and unavailable subgroup selection produces no command.

## Coverage and proof

| Needs | Contract | Evidence obligation |
| --- | --- | --- |
| U1,U2,U7 | R1,R2 | Native layout/popover and pointer/keyboard/invalid-command routing |
| U3,U5,U10 | R3,R4,R12 | Partitions, pin merge-back, remote-identity aggregation, migration |
| U4,U5,U17,U18 | R5,R6,R6a,R6b,R18 | Panes matrix, independent pins, conditional headings, restoration, visual hierarchy |
| U11 | R7,R8 | Sort independence and hierarchy invariants |
| U4,U6,U9,U12,U13,U16 | R9,R9a,R10,R11 | Current-source limit, no focus fallback, unchanged indicators |
| U8 | R13,R14 | Off-main workload, currentness, identity, preserved presentation |
| U14–U16 | R15–R17 | No zmx/vendor/IPC expansion |

The aggregate gate, native evidence, and marker-scoped performance workload remain required. This specification records obligations; it claims no current pass, review, or PR readiness.
