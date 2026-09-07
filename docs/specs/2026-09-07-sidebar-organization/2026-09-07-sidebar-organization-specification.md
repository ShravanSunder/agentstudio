# Sidebar Organization Specification

Basis: [Requirements](2026-09-07-sidebar-organization-requirements.md). Realization: [Program Design](2026-09-07-sidebar-organization-program-design.md).

## Scope of each delivery

The three scopes follow U16. C1–C4 and pin migration are the first sidebar change. The zmx update is a separate preservation contract C7. C5 contains the terminal target completed through the third scope; it is not evidence that PR 1 can already observe all terminal output.

PR 1 must use the existing runtime-only `PaneActivityStatusFact.observedAt` associated with a changed settled output line for activity grouping/subgrouping and sorting. The timestamp is captured when settled-line recording is accepted; publication may be deferred. It is not exact last-byte time, identical lines suppress timestamp-only updates, and surface retirement clears it. These are the accepted current-source limits of PR 1, not permission to omit activity organization or use focus recency. A recent-evidence bucket is not a claim that the terminal process is still running.

## Finding a pane without losing its context

The sidebar separates what is browsed from how it is organized. Repos browses repository/worktree structure. Panes browses existing pane destinations. Grouping changes where rows are placed; sorting changes their order inside that placement.

```text
Person managing parallel work
    → chooses Repos or Panes
    → filters and selects group/subgroup
    → sorts rows without changing the hierarchy
    → identifies and opens the intended destination

Today: mixed object/group controls and long undivided lists
Desired: explicit screens, independent pins and activity organization
Basis: U1–U8, U11
```

```text
Pointer / keyboard user ── sidebar controls ──┐
                                            │ Sidebar organization
Same user ── pane rows / tab indicators ──────┤ (opaque product surface)
                                            │
Restart ── restored choices / activity ages ─┘

Outside: provider-session archive and new agent-completion detection
```

## C1. Two-row controls

**R1 (U1, U2):** The header must use exactly two rows. Row one contains the Repos/Panes selector followed by the filter consuming remaining space. Row two contains group, subgroup, sort field/direction and the current screen's pinned-section visibility control. Organization controls must not be relocated into a catch-all options menu.

```text
Row 1   [ Repos | Panes ] │ Filter…
Row 2   Group │ Subgroup │ Sort field │ Direction │ Show Pinned
```

At the current 250–450 point widths, row two exposes compact icon segments for every option; selected state is visible. It adds selected-option text only when the natural width fits. There are no Group/Subgroup/Sort caption labels, overflow menus, hidden alternatives or third row. Row one keeps Repos/Panes text and gives remaining width to the filter. Tooltips/accessibility names come from the surface-specific command spec. Native fit and accessibility are implementation proof obligations; the conceptual diagram does not claim a captured rendering.

**R2 (U7):** Grouping, subgrouping, sort field and direction must have command-spec-backed, surface-context keyboard actions that produce the same selections and outcomes as the visible controls. Pin visibility likewise uses the command spec system. Labels, icons, help and shortcut display must come from the existing command presentation pipeline. Commands must not steal typing from the filter or unrelated terminal/editor surfaces. The owner explicitly defers exact key chords; no bindings are implied by this diagram, and chord selection is not a blocker to this design.

All sidebar organization commands are surface-specific, including screen selection, grouping, subgrouping, sort field, sort direction and pinned-section visibility. Repos and Panes have separately classified command exposure, targeting and enablement in the existing spec system. A Repos action must not mutate Panes preferences or pins, and vice versa. Pointer controls and later keyboard bindings consume that same classification and dispatcher; a shared icon or chord never supplies authority to affect the other screen.

## C2. Repos sections and independent repository pins

**R3 (U3, U5, U10):** Repos must display repository groups containing their worktrees. When the pinned section is shown, a pinned repository belongs to Pinned Repositories, a remaining repository with an open pane belongs to Open Repositories, and every remaining repository belongs to Other Repositories. Each repository appears in one section. Open denotes pane presence, not output activity or process execution.

```text
Show Pinned on                  Show Pinned off
Pinned Repositories             Open Repositories
Open Repositories               Other Repositories
Other Repositories
```

**R4 (U5):** Turning Show Pinned off must preserve pin state and return pinned repositories to the ordinary Open Repositories/Other Repositories partition. It must not exclude them. Pane pins must have no effect on this partition.

Open uses the current sidebar's canonical destination population: active-residency panes owned by a tab, traversing that tab's allPaneIds and validating repository/worktree association. A pane need not be in the currently selected arrangement to count. Pending-close undo records and orphan records without a tab destination do not count. Do not add drawer-child traversal beyond the current canonical destination population merely because a drawer is expanded. This preserves existing navigation membership; arrangement visibility and terminal activity do not define Open. Current basis: WorkspaceLookupDerived.paneLocationsByWorktreeId and RepoExplorerProjectionInputCapture.unassociatedPaneLocations.

## C3. Panes sections, grouping and independent pane pins

**R5 (U4, U5):** Panes must partition individually pinned panes into Pinned Panes and remaining panes into Other Panes when Show Pinned is enabled. When disabled, all panes return to Other Panes without clearing pins. Repository pins must not influence this screen, including Repository grouping. Each pane appears once in the selected screen.

**R6 (U4):** Panes must offer Repository, Tab and Terminal activity grouping. Repository grouping must retain a place for panes without a repository. Tab grouping must preserve canonical tab ownership independently of repository association. Changing pin sections or grouping must not change the destination activated by a row.

The subgroup inventory is:

| Screen / group | Subgroup options | Meaning |
| --- | --- | --- |
| Repos / Repository | None, Terminal activity | Divide worktrees within their repository |
| Panes / Repository | None, Terminal activity | Divide panes within their repository |
| Panes / Tab | None, Terminal activity | Divide panes within their tab |
| Panes / Terminal activity | None | Activity buckets already provide the grouping |

These are the complete subgroup choices. Do not add repository-under-tab or tab-under-repository nesting. Defaults and saved-state migration are defined below.

**R6b (U18):** Activity subgroup headings start at the existing row-icon column. Pane/worktree and metadata rows retain their current horizontal alignment; subgrouping does not indent them further. Use the same font, size, weight and casing treatment as the existing top-level section headings, with secondary gray instead of the sections' existing blue. No separate subgroup icon or disclosure arrow is added. Spacing separates subgroups; empty subgroups are omitted and the repository/tab's existing collapse hides its whole content. The display name Just Now replaces the numeric ten-minute label without changing its time predicate.


**R6a (U17):** Restore saved sidebar selections before applying defaults. Panes grouped by Repository or Tab defaults to Activity subgroup only when no saved subgroup choice exists; a saved None remains None. When Activity is the main grouping, no extra activity subgroup is rendered. Retain the saved Repository/Tab subgroup preference across that switch rather than overwriting it with an inapplicable None.

## C4. Sort field and direction

**R7 (U11):** Both screens must offer Name and Terminal activity sort fields and separate ascending/descending direction. Name ascending means A–Z; descending means Z–A. Activity ascending means oldest first; descending means newest first. Arrangement/layout order is not a sort option.

**R8 (U11):** Changing either sort control must only reorder leaf rows within the currently selected section/group/subgroup. It must not change section membership, group membership, group order, activity-bucket order or collapse state. Name ordering acts on worktree names in Repos and pane display names in Panes; secondary displayed terminal output does not become a name key.

```text
Pinned Panes                  unchanged section
  repository                  unchanged group
    Last hour                 unchanged subgroup
      pane B / pane A         only these rows reorder
```

Equal sort keys must have deterministic identity-based tie breaking so arrival order does not cause visible churn. Missing activity must not be fabricated from focus time. Unknown activity sorts after known timestamps in either direction; name and canonical identity break ties. Defaults and migration are defined below.

## C5. Terminal activity and unseen indicators

**R9 (U4, U6, U9, U14):** Terminal-activity organization must use qualifying terminal activity from the product's zmx-backed terminal path, not user focus, scrollbar movement alone, or restoring old display content. Historical activity timestamps must survive restart. A persisted active flag must not establish current activity after restart. A separate direct-Ghostty activity provider is not added by this change.

**R9a (U4,U6,U16), PR 1:** Activity sort uses the existing settled-output timestamp. Time grouping/subgrouping evaluates the bucket table below from this timestamp, with Active meaning an existing runtime fact less than 60 seconds old. It must not read outputBurst.accumulating as current activity. No new source detector, persistence, raw-output observer or vendor change is introduced. After source clear/restart, absence is No activity rather than a focus/creation-time fallback. The current title/latest-line presentation remains unchanged by this data-source wiring.

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

**R10 (U12):** When qualifying activity has stopped and remains unseen, its pane row and owning tab must be able to display a blue dot. The same activity must not acquire independent acknowledgement state in the tab and sidebar. Which pane visits acknowledge the activity, quiet delay, multiple-pane aggregation, behavior on renewed output, and unseen-state persistence remain the later indicator contract.

**R11 (U13, U8):** Active pane animation must not require per-frame domain writes, projection recomputation, or pane-view work. It must stop when its row is offscreen or reused and respect Reduce Motion. A small layer-animated rotating arc is proposed; exact appearance and whether tabs animate remain the later indicator contract. Repository refresh animation retains its existing meaning.

## C6. Persistence, invalidation and proof

**R12 (U10):** Favorite-to-Pinned migration must preserve existing repository selections and introduce independent pane pin values with existing panes initially unpinned. The migration must not copy repository pins into panes. Failure must follow existing database preparation/recovery behavior; no silent data reset or simultaneous old/new write path.

**R13 (U8):** Search, filtering, group/subgroup derivation, sorting, activity classification, time-boundary calculation and row-index work must run through the existing off-MainActor systems. UI state mutation and thin keyed capture/publication may occur on MainActor. Views must consume prepared values; no per-row polling, sorting, or timers. A stale result must not overwrite a newer query, preference selection, pin mutation or topology change.

**R14 (U1–U13):** Existing selection, keyboard navigation, collapse state and row identity must remain coherent across section moves and asynchronous publication. Changing a view preference must not mutate topology or terminal execution. Missing local activity data must not be represented as recent activity or completion.

## C7. zmx update and staged preservation

**R15 (U16):** PR 1 must not require a zmx version/toolchain update or a new daemon protocol. Its output detection remains limited to admitted current evidence; improving that evidence belongs to PR 3.

**R16 (U16):** PR 2 must preserve existing stored zmx session identities, attach/restore behavior and the fork's prompt-redraw fix. New-client/old-daemon operation and any supported rollback direction require explicit proof; a successful build alone does not establish compatibility with live sessions. The update must not silently kill or recreate existing sessions. A zmx upgrade alone must not be described as delivering activity metadata or blue-dot acknowledgement.

**R17 (U9,U14–U16):** PR 3 must keep the selected zmx IPC boundary internal and reuse the existing runtime owners. The metadata source must distinguish live PTY reads from attach replay, and provide sufficient identity/currentness to reject stale observations after session replacement. No public zmx methods or raw terminal payload export is introduced for sidebar activity.

| Need | Problem → outcome | Contract / requirements | Proof |
| --- | --- | --- | --- |
| U1, U2 | Dense ambiguous header → explicit compact controls | C1 / R1 | V1: real native layout at supported widths; inspect selected values and icon meaning |
| U3, U5, U10 | Mixed membership → independent pins and complete lists | C2,C3,C6 / R3–R6,R12 | V2: partition invariants, navigation, restart and migration with existing data |
| U4, U6, U9, U14 | Focus time masquerades as activity → truthful recency on the zmx path | C3,C5 / R6,R9 | V3: real zmx terminal output versus scrolling, focus, redraw, restore; injected-clock boundaries; restart |
| U7 | Pointer-only organization → contextual keyboard parity | C1 / R2 | V4: actual shortcut routing in sidebar, filter, terminal and other surfaces |
| U8 | Frequent events cause jank → bounded off-main work | C6 / R13,R14 | V5: source isolation, cancellation races, marker-scoped runtime performance under many active panes |
| U11 | Sort changes location model → stable groups with sortable rows | C4 / R7,R8 | V6: each field/direction across each grouping, equal keys, membership invariance |
| U12, U13 | Unseen changes hard to locate → dot and activity feedback | C5 / R10,R11 | V7: real pane/tab interaction, offscreen reuse, Reduce Motion and animation CPU proof; the later indicator contract limits |
| U15,U16 | One large dependency chain → bounded sidebar, update and IPC scopes | C7 / R15–R17 | V8: each delivery's behavior and exclusions, preserved session identities, mixed-version attach/restore; no later-scope proof credited to PR 1 |
| U18 | Extra nesting obscures scanning → aligned heading hierarchy | C3 / R6b | V10: native icon-column alignment, unchanged row positions, shared heading typography and contrasting section/subgroup colors |
| U17 | Repeated setup → restored selections with useful initial pane subgroup | C3 / R6a | V9: saved None/Activity round trip, missing-setting default, Activity main-group round trip without overwriting the saved subgroup |

## C8. Saved settings and defaults

**R18 (U17):** Persist every selected screen/group/subgroup/sort field/direction and each screen's Show Pinned value using the existing owners. Hydration must not rewrite a saved None to Activity or reset choices when the screen changes.

| Setting | Missing-value default | Existing owner scope |
| --- | --- | --- |
| Screen | Repos | Main-window local sidebar memory |
| Panes group | Repository | Main-window local sidebar memory |
| Repos subgroup | None | Main-window local sidebar memory |
| Panes subgroup | Activity | Main-window local sidebar memory |
| Show Pinned | On independently for each screen | Main-window local sidebar memory |
| Sort field | Name independently for each screen | Workspace-local RepoExplorer preferences |
| Sort direction | Ascending independently for each screen | Workspace-local RepoExplorer preferences |

Migrate old repo mode to Repos, pane mode to Panes/Repository, and tab mode to Panes/Tab. Initialize both screen directions from the old saved direction; after migration they are independent. Existing filter text/visibility memory and collapse state are retained. The new always-present filter input ignores the old visibility flag for layout; it does not erase stored filter text. Name/group pin controls use their actual screen identity.

Repository group headers use stable ascending display identity with canonical ID tie-break; tab headers use existing tab-shell order; activity headers use the bucket table. Leaf sorting never changes those orders. A repository pin/open partition is evaluated before remote-identity grouping: the same logical origin may have a header in different sections when distinct registered repositories have different pin/open state, but a registered repository or leaf is never duplicated. Scope collapse keys by screen, section, group and optional subgroup to avoid shared-header collisions. Existing collapse keys are migrated to their equivalent initial placement; new subgroup keys start expanded.

Empty Pinned/Open sections are omitted; the ordinary Other Repositories/Other Panes section remains the standard collection heading. Existing loading/unavailable placeholders and errors remain; no unknown repository origin is reclassified as a terminal activity or new agent state. Filtering preserves existing searchable fields and selection/navigation behavior. Search does not change whether an underlying repository is Open.

## Later-scope and proof boundaries

- Exact keyboard chords remain owner-deferred. The surface-specific command contract is complete without choosing the physical key combinations now.
- PR2's target/update preservation design and PR3's metadata/acknowledgement mechanics remain later scopes. They are not requirements for implementing PR1.
- PR1 retains the current indicator presentation. New blue unseen dots and active animation remain in the later terminal-enhancement scope, with quiet/acknowledgement details to settle there.
- Native two-row fit, keyboard typing safety and measured off-main performance require implementation evidence. No runtime proof is claimed by these documents.
