# Sidebar Organization Program Design

Specification: [Sidebar Organization Specification](2026-09-07-sidebar-organization-specification.md). Requirements: [Sidebar Organization Requirements](2026-09-07-sidebar-organization-requirements.md).

## Structural overview

The design extends existing command, persistence, and detached projection paths. It adds no atom, store, event, coordinator responsibility, activity source, or terminal protocol.

```text
organization-value choice / future shortcut
    → surface-specific AppCommandSpec + preflight
    → dispatcher + existing preference owners
    → keyed RepoExplorer capture
    → existing detached projection worker
        ├── membership and remote-identity grouping
        ├── activity buckets and leaf sorting
        └── materialized row index
    → MainActor binds prepared rows
    → native section / group / subgroup / leaf rendering
```

Selector open/dismiss follows a separate presentation-only path: LocalActionSpec display metadata → local view state → popover. It does not dispatch AppCommand.

MainActor owns UI state and prepared-result publication. It does not own grouping, activity aggregation, sorting, or row derivation.

## Owners

| Responsibility | Existing owner |
| --- | --- |
| Surface/group/subgroup/Show Pinned | `WorkspaceSidebarState` and local-window persistence |
| Sort type/direction | `RepoExplorerSidebarPrefsAtom` and existing settings persistence |
| Repository/pane pins | Existing topology/pane graph owners and migration 017 |
| Labels/icons/help/enablement | Sidebar command catalog, `UIActionPresentation`, presentation query |
| Organization | `RepoExplorerProjection+Organization` in detached worker |
| Identities/conditional subgroups | `RepoExplorerRowIndex` and materialization snapshot |
| Heading/toolbar chrome | `SharedComponents` plus `AppStyles` |
| Native composition | `RepoExplorerView` and materialized row host |

Dependency direction remains App → Feature/Core/SharedComponents, Feature → Core/Infrastructure/SharedComponents, SharedComponents → Infrastructure. Shared controls receive values and callbacks only.

## Toolbar and popovers

`RepoExplorerView+CommandToolbar` resolves surface-specific commands through `RepoExplorerToolbarCommandPresentation`.

```text
Row 1  SidebarEntityToggle | SidebarSearchField
Row 2  Show Pinned | SortDirection + SortField | GroupingSummary

Grouping popover, 16pt padding
┌──────────────────────┬──────────────────────┐
│ [icon] Group         │ [icon] Subgroup      │
│ neutral options      │ neutral options      │
│                      │ or No subgroups      │
└──────────────────────┴──────────────────────┘
       equal 160pt columns, 16pt gap
```

The pin action disables persistent active fill. `SidebarToolbarSortButton` retains stable identity and animated arrow; the adjacent picker owns Name/Activity. The grouping summary shows main or `main → subgroup`.

One `SidebarOrganizationPopover` and keyboard bridge owns navigation. Header/option icons come from action/command specs. The model filters disabled options and selection rechecks enablement. Valid None dispatches normally. Unavailable subgrouping retains the header/icon/column but creates no keyboard item or request.

## Projection

### Repos

`organizedRepositories` computes eligible activity and uses `remoteIdentityGroups` as repository grouping authority.

```text
Repo:     registered repo → pinned/open/available → section-local remote grouping
Activity: whole-remote max activity → registered repo pin/bucket → section-local remote grouping
```

Registrations sharing a remote may remain in distinct pin/open sections; the section-local groups contain disjoint registered repositories. Activity replaces Open/Available. Empty sections are omitted; sections are noncollapsible. Repository groups remain collapsible to checkout leaves. Their header deliberately passes no entity icon.

### Panes

Canonical active-residency destinations partition by individual pane pin, then group by Repo, Tab, or Activity. Repo/Tab preserve expandable identity. When Activity subgrouping is effective, rows order by bucket before leaf sort. `RepoExplorerRowIndex` emits subgroup headings only when a parent contains more than one distinct nonempty bucket. Activity main grouping suppresses the effective subgroup without mutating the stored choice.

### Sort and activity

The detached stage fixes membership/group order before applying one leaf comparator. Name or valid activity is primary; name and canonical UUID stabilize ties. Unknown activity follows known activity in both directions.

Current input is `PaneActivityStatusFact.observedAt`. The worker validates it, aggregates where required, classifies buckets, and prepares deadlines. Missing/future evidence becomes No Activity. Focus, creation, scrolling, chip recency, and accumulating-burst state never enter as fallbacks. Existing chips and indicators remain separate.

## Heading rendering

| Level | Rendering |
| --- | --- |
| Section | `SidebarEntitySectionHeading`: entity icon, word-initial/lowercase-small-caps label, blue |
| Expandable group | `SidebarRepoGroupHeader`: chevron and title, no entity icon |
| Activity subgroup | `SidebarSubgroupHeading`: word-initial/lowercase-small-caps, secondary, divider |

Shared `AppStyles` owns increased noninitial section/subgroup top spacing. The first section keeps its top-edge treatment. Vertical rhythm changes do not change leaf insets or metadata columns.

## Persistence and migration

Repos reads/writes existing `repoGroupingMode`. `repoSubgroupMode` remains in memory, codecs, and storage for compatibility, but Repos resolves effective subgroup to None and exposes no subgroup command.

Local migration 007 already owns per-surface organization. Core migration 017 already renames repository `is_favorite` to `is_pinned` and adds pane `is_pinned`. This correction adds no migration and does not rewrite history. Existing hydrate/save paths and true Show Pinned defaults remain.

## Concurrency and failure

| Case | Realization |
| --- | --- |
| Query/organization changes in flight | Existing generation/intent admission rejects obsolete result |
| Pin changes in flight | Keyed invalidation rebuilds membership once |
| Invalid command | Presentation/model filtering plus dispatch guard makes no mutation |
| Missing/future activity | No Activity; no focus fallback |
| Hidden/resumed sidebar | Existing demand lifecycle controls projection |
| Row moves | Canonical activation identity survives row-key change |
| Restore failure | UIStateStore clears sidebar memory to defaults and reports resetToDefaults through the existing recovery path |
| Save failure | UIStateStore reports failure and retains current in-memory choices; no new owner or silent database reset |

A full off-main rebuild is allowed when a shortcut cannot prove new membership dependencies. Views and MainActor never patch hierarchy.

## Explicit exclusions

No blue-dot/running-animation state, zmx IPC, vendor update, metadata store, EventBus case, coordinator, focus fallback, schema addition, or replacement projection belongs here. Existing recency/focus chips remain. These exclusions retain U9 and U12–U16 as later needs without prebuilding their How.

## Requirement, realization, and proof

| Specification | Owner / seam | Proof |
| --- | --- | --- |
| R1,R2 | Toolbar, catalog, preflight, dispatcher | Native panel/keyboard and invalid-command checks |
| R3,R4 | Repos organization/remote identity | Section, exclusivity, aggregation, expansion tests |
| R5,R6,R6a,R6b | Panes organization/row index and shared headings | Matrix, conditional headings, independent pins, restoration, native hierarchy |
| R7,R8 | Detached leaf comparator | Field/direction and hierarchy invariants |
| R9,R9a,R10,R11 | Existing activity fact/presentation boundary | Bucket edges, no fallback, unchanged chips/indicators |
| R12,R18 | Persistence/migrations 007 and 017 | Upgrade/restart and no latest schema delta |
| R13,R14 | Capture, worker, admission, broker | Races/currentness and marker-scoped workload |
| R15–R17 | Source/diff boundary | No zmx/vendor/IPC/indicator expansion |

Aggregate tests, native evidence, and the performance workload remain external proof obligations. This design records no review verdict or PR-readiness claim.
