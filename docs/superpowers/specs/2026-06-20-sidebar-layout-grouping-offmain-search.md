# Sidebar Layout, Repo Grouping, and Off-Main Search Spec

Status: draft for review
Date: 2026-06-20
Scope: repo sidebar header layout, repo sidebar grouping modes, inbox search/list projection performance

## Problem

The repo sidebar should visually align with the inbox sidebar layout without inheriting the inbox header component or inbox-specific behavior. The repo sidebar should add a second-row toolbar with grouping controls, and its grouping modes must be exactly:

- Repo
- Pane
- Tab

Pane and Tab modes must include an Inactive group for worktrees that are not attached to an active-residency tab-owned pane location.

Separately, inbox search/list projection must stop doing expensive list work on the MainActor. This is not just a visual cleanup. Search, grouping, row visibility, collapsed-section rollups, and keyboard navigation are one projection pipeline today, and that pipeline must become Swift-concurrency safe without reintroducing the crash class the repo has been removing from generic timers and nonisolated misuse.

## Current Evidence

- The sidebar host already composes repo and inbox as sibling surfaces in `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`.
- Shared sidebar chrome already exists in `Sources/AgentStudio/SharedComponents/SidebarSurfaceChrome.swift`, `SidebarSearchField.swift`, `SidebarRowShell.swift`, `SidebarRepoGroupHeader.swift`, `SidebarSourceGroupHeader.swift`, and `SidebarSectionHeader.swift`.
- Shared components are required to be render/interaction primitives that do not own product state. They may receive explicitly passed observable view models, but they must not read atoms and must not import `Core`, `Features`, or `App`; this is documented in `docs/architecture/directory_structure.md`.
- `InboxSidebarHeader` is feature-owned. It owns inbox-only controls, menu state, tooltips, and local callbacks in `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`.
- Repo projection already has pure model seams in `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`, `RepoExplorerRowIndex.swift`, and `RepoExplorerSnapshot.swift`, but the view still invokes the projection from `RepoExplorerView`.
- Current repo presentation groups are source-family shaped and can contain multiple repos. The `Repo` grouping mode in this spec is a product correction, not a relabeling of the current source grouping.
- Inbox list/search projection is value-shaped in `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`, but `InboxNotificationSidebarView` builds and caches it from MainActor view state.
- `WorkspaceLookupDerived.paneLocationsByWorktreeId` is the current source of truth for worktree to active pane/tab occupancy. It only counts panes that are active-residency and owned by a tab.
- Command bar already derives `WorktreePresence` from the same lookup, proving a worktree occupancy read model exists, but repo sidebar grouping does not use it yet.
- The strongest current off-main precedent is the filesystem projection offload: MainActor snapshots once, off-main code derives rebuildable state, and MainActor applies compact results with generation guards.
- Swift 6.2 repo guidance requires explicit off-main escape with `@concurrent nonisolated` or an actor boundary. A plain `nonisolated async` helper is not enough when called from MainActor.
- Production delay code must avoid the generic clock sleep path. Current approved production delay seam is `AsyncDelay.taskSleep` / `Task.sleep(nanoseconds:)`, and tests must avoid direct wall-clock sleeps.
- Current debug observability can be run detached, but GUI launch still foregrounds the app today. "No screen interruption" is therefore a requirement to satisfy, not a property already provided by the current runner.

## Design Goals

1. Match the inbox sidebar layout structure where useful while preserving feature ownership.
2. Add repo grouping controls for Repo, Pane, and Tab only.
3. Define Inactive for Pane and Tab modes as a first-class group, not as a vague "other" bucket.
4. Move inbox search/list projection off MainActor using repo-approved Swift 6.2 concurrency patterns.
5. Keep repo grouping/search logic model-owned and testable.
6. Add before/after performance evidence through the existing OTLP/Victoria proof path.
7. Keep IPC/debug proof local, authenticated where possible, and non-disruptive to the user's desktop.

## Non-Goals

- Do not move `InboxSidebarHeader` into `SharedComponents`.
- Do not merge repo and inbox feature state.
- Do not make command-bar search share sidebar search semantics.
- Do not add a Flat or Source grouping mode for the repo sidebar.
- Do not solve the remaining sidebar issues called out for later work.
- Do not use visual screenshots as the primary proof for search/projection performance.
- Do not use unsafe no-auth IPC as the default verification path.

## Shared Layout Boundary

The shared extraction should be a layout container, not a feature header.

The container owns only geometry:

- search row slot
- toolbar/action row slot
- optional status/filter row slot
- spacing and row alignment consistent with the sidebar style guide

The feature owner supplies everything semantic:

- search binding
- button actions
- menu content
- tooltip render values
- focus behavior
- keyboard behavior
- state persistence decisions
- explicitly passed observable view models when push updates are needed

This preserves the existing rule:

```text
SharedComponents
  receives values, bindings, callbacks, or explicit observable view models
  renders reusable chrome
  does not read atoms or global stores
  does not import Core, Features, or App
```

Observable view models are allowed when they are passed directly by the feature owner and model only the shared control's render/interaction contract. They must not be atom access wrappers, global-state facades, or a way for SharedComponents to reach into feature state on their own.

Repo and inbox may both compose the same layout container:

```text
RepoExplorer header
  -> shared sidebar header layout
     -> SidebarSearchField
     -> repo toolbar slots: sort/group controls

Inbox header
  -> shared sidebar header layout
     -> SidebarSearchField
     -> inbox toolbar slots: sort/filter/content/group controls
     -> optional inbox active-filter row
```

The repo header should look like the inbox layout, but it must not become the inbox header.

## Repo Grouping Modes

Repo sidebar grouping modes are exactly:

```text
Repo
Pane
Tab
```

No `Source` label. No `Flat` mode in this slice.

### Repo Mode

Repo mode groups by repo identity:

- each top-level group maps to one repo id
- worktrees appear under their owning repo
- existing loading repo behavior remains separate from occupancy semantics
- this mode must not preserve source-family aggregation under a new label
- inbox `.byRepo` presentation may continue using the existing inbox contract unless a later spec explicitly changes inbox grouping

### Pane Mode

Pane mode groups resolved worktrees by attached active pane location.

Membership rule:

- A worktree appears under each pane group for which `WorkspaceLookupDerived.paneLocationsByWorktreeId` reports an active-residency tab-owned pane location.
- If a worktree has no active-residency tab-owned pane location, it appears in the Inactive group.
- Backgrounded panes, pending-undo/orphaned panes, and active panes with no owning tab do not make a worktree active for this mode.
- "Active" means active-residency and owned by a tab. It does not require visibility in the tab's current active arrangement for this slice.

This treats Pane mode as an attachment view, not a single-owner view. A worktree with multiple active pane attachments can appear in multiple pane groups, but a single pane tree/group must not render duplicate rows for the same worktree. Row identity must therefore include the group identity as well as the worktree identity.

Pane group stable identity must use pane ids. Mutable display titles must not be storage keys. Pane group display must include a disambiguating ordinal such as `Pane N` or `Tab N / Pane N`; a custom pane title may be appended but must not be the only label.

### Tab Mode

Tab mode groups resolved worktrees by attached active tab membership.

Membership rule:

- A worktree appears under each tab group that contains at least one active-residency tab-owned pane location for that worktree.
- If a worktree has no active-residency tab-owned pane location, it appears in the Inactive group.
- A tab can contain panes for multiple worktrees, and a worktree can appear in multiple tab groups.
- "Active" means active-residency and owned by a tab. It does not require visibility in the tab's current active arrangement for this slice.

Tab mode can render duplicate worktree rows inside one tab group when the tab contains multiple pane attachments for the same worktree. Each duplicate row must include placement information that distinguishes it, following the inbox pattern of primary row text plus secondary source/placement context.

Tab group stable identity must use tab ids. Tab group display must include a disambiguating ordinal such as `Tab N`; a custom tab name may be appended but must not be the only label. Tab ordinals are display details, not storage keys.

Row display in Pane and Tab modes must include enough secondary context to identify the attachment:

- Pane mode rows identify the repo/worktree plus pane placement when needed.
- Tab mode rows identify the repo/worktree plus tab/pane placement for duplicate attachments.
- Duplicate rows must never be visually indistinguishable.

### Inactive

Inactive is a required group in Pane and Tab modes.

Inactive means:

```text
resolved worktree
  AND no active-residency pane location owned by a tab anywhere in the tab ownership graph
```

The same definition applies to Pane and Tab modes. It intentionally aligns with the current `WorktreePresence.notOpen` shape rather than inventing a second occupancy source of truth. The later plan must include a multi-arrangement regression test proving that active-residency tab-owned panes in non-current arrangements are treated as attached, not Inactive.

The Inactive group should be last. It may be hidden only when empty.

Group ids and persisted collapse memory must be mode-scoped. Example group ids:

```text
repo:<repo-id>
pane:<pane-id>
tab:<tab-id>
pane:inactive
tab:inactive
```

The Pane-mode Inactive group and Tab-mode Inactive group must not share the same persisted collapse key.

## Search and Projection Concurrency

The MainActor owns UI state, atom reads, focus state, and application of results. It must not own expensive search/list projection work.

The required shape is:

```text
MainActor
  read atoms and view state once
  build Sendable snapshot
  increment generation
  call explicit off-main projection boundary

off-main projection boundary
  filter
  group
  sort
  build row index / visible ids
  record safe timing values
  return Sendable result

MainActor
  discard stale generations
  apply compact result
  update view state
```

Acceptable off-main boundaries:

- a dedicated actor for rebuildable indexes, or
- `@concurrent nonisolated` pure/static helpers over Sendable snapshots

Not acceptable:

- relying on `Task {}` created from a MainActor view to make heavy work off-main
- using plain `nonisolated async` as an off-main guarantee
- passing SwiftUI views, atoms, AppKit objects, or non-Sendable closures into the worker
- adding timers for debounce behavior
- adding production `Task.sleep(for:)` or generic `Clock.sleep(for:)`
- adding direct `Task.sleep` waits in tests

Inbox search specifically must keep its semantic contract:

- search matches title/body and source display search text
- grouping, filtering, collapsed-section counts, visible ids, and navigation boundaries are produced from the same projection result
- stale projection results are discarded
- cancellation does not leave partially applied UI state

Repo projection should follow the same model-ownership rule where this slice touches repo search/grouping:

- row index generation stays model-owned
- rendering reads a prepared model rather than walking groups repeatedly
- repo/inbox shared chrome must not become the projection owner

Repo off-main projection is not a hard requirement of this slice unless performance evidence shows repo grouping/search remains a MainActor bottleneck after the grouping change. The hard off-main requirement is inbox search/list projection.

## Metrics and Proof Requirements

The implementation plan must require before and after measurements.

Required metric dimensions:

- surface: repo or inbox
- phase: projection, row index, or list model
- query state bucket: empty or nonempty
- group mode: repo, pane, tab, or inbox grouping mode where applicable
- input counts: notifications, repos, worktrees, sections, rows
- stale result count
- MainActor apply duration
- total worker duration

Sidebar telemetry must be controlled-vocabulary only: counts, durations, booleans, enums, and buckets. Metrics must not export raw paths, raw UUIDs, query strings, repo names, worktree names, branch names, pane labels, tab labels, group display labels, notification titles/bodies, notification-derived search text, prompts, terminal buffers, tokens, or tool output over OTLP.

Every new sidebar telemetry field must have an allowlist test or verifier update that proves the exported vocabulary is scrubbed.

The standard proof path should stay marker-scoped through the shared observability stack:

```text
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

For sidebar performance proof, the later plan should either extend the existing Victoria-backed performance workload or define a sidebar-specific marker-scoped verifier. JSONL may be a local debug artifact, not the default proof path.

IPC may be used for semantic control only if the app exposes a sidebar-safe semantic contract. If not, startup diagnostics or future sidebar-specific IPC should be specified rather than screen-driving the app.

Sidebar IPC proof, if added, must be:

- escrow-authenticated
- headless
- app-owned and semantic, not click-coordinate or visual automation
- limited to allowlisted DTOs containing stable ids, enums, booleans, counts, and scrubbed buckets
- free of notification text, search text, query strings, repo/worktree names, pane/tab display labels, raw paths, prompts, terminal buffers, tokens, and tool output
- separated from `ui.*` presentation authority when used for background-safe proof

## Background Launch Constraint

The user's desktop must not be interrupted by proof runs.

Current reality:

- `--detach` avoids blocking the shell.
- The debug GUI path still foregrounds the window today.
- `ipc-terminal-smoke` explicitly activates the app.

Therefore the plan must include one of these proof strategies:

1. add or use a non-activating debug proof mode before visual/sidebar proof, or
2. keep proof to headless/semantic observability paths that do not require GUI activation, or
3. explicitly mark foreground GUI proof as blocked pending user approval.

Do not silently run a foreground debug GUI proof as if it satisfied the no-interruption requirement.

## Security and Trust Model

Assets:

- local repo/worktree topology
- pane/tab layout metadata
- inbox notification content
- IPC bearer/debug token material
- OTLP metrics/logs

Trust boundaries:

- MainActor UI state to off-main projection worker
- app process to IPC clients
- app process to local OTLP collector
- debug proof scripts to the running app

Required constraints:

- off-main snapshots must contain only the data needed for projection
- projection workers must not log or export notification bodies or raw paths
- sidebar IPC proof must use debug-token escrow and fail closed if `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH` is set
- debug-token escrow must preserve single-use token consumption and replay-failure semantics
- unsafe IPC auth bypass remains debug-only, opt-in, and out of scope for sidebar proof
- state handoff files are not proof; Victoria/log queries are proof
- shared UI components cannot gain privileged command or IPC semantics

## Validation Expectations for the Later Plan

The implementation plan must include:

- pure model tests for repo grouping modes and Inactive membership
- inbox list/search tests proving search, filtering, grouping, collapsed-section unread counts, `visibleNotificationIds`, group-boundary navigation, and endpoint navigation are preserved after off-main projection
- tests proving inbox visible ids, collapsed counts, and navigation come from the same generation-checked projection result
- stale generation/cancellation tests for asynchronous projection
- architecture tests preventing atom reads from repo/inbox projection workers
- architecture or lint proof that the inbox worker entrypoint is not MainActor-isolated, uses an allowed actor or `@concurrent nonisolated` seam, and crosses the boundary with Sendable snapshots/results only
- architecture lint coverage for forbidden sleep/timer patterns if new async delay code is added
- focused UI/presentation tests for shared header layout composition
- metrics tests or verifier updates proving sidebar performance events are emitted and scrubbed
- baseline vs post-change Victoria-backed measurement for inbox search/list projection with pass/fail comparator rules
- semantic proof that exercises changed sidebar behavior, or an explicit blocked proof lane if no background-safe sidebar driver exists
- detached/background-safe proof, or an explicit blocker if GUI activation is still required

## Confirmed Product Decisions

1. Shared components may receive explicitly passed observable view models for push updates, but they must not read atoms or bind themselves to global state.
2. Pane mode must not duplicate the same worktree within a single pane tree/group. The same worktree may still appear in multiple pane groups if it has multiple attachments.
3. Tab mode may show duplicate worktree rows when one tab contains multiple pane attachments for the same worktree.
4. Pane and Tab duplicate/attachment rows must include secondary placement context so the user can distinguish them.
5. Repo grouping mode should persist per workspace and must use mode-scoped collapse keys.
6. Inbox search may remain transient while repo search remains persisted for this slice.
7. Visual or GUI proof should use a non-activating debug proof path. If that path does not exist yet, foreground GUI proof is blocked pending user approval.
