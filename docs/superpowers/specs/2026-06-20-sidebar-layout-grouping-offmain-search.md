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

Repo metadata is a separate schema-backed requirement for the same sidebar
family. Users need a favorite button that marks repos as favorites and persists
that state across app restarts. Repo notes, worktree notes, repo tags, and color
metadata for tab shells must live in SQLite rather than
workspace settings JSON. Existing `sidebar.checkoutColors` is not part of this
schema migration and must not be modeled as `repo.color_hex` or
`worktree.color_hex` in this slice. Repo/worktree color UX should be removed;
repo rows may keep only the existing automatic generated colors.

## Current Evidence

- The sidebar host already composes repo and inbox as sibling surfaces in `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`.
- Shared sidebar chrome already exists in `Sources/AgentStudio/SharedComponents/SidebarSurfaceChrome.swift`, `SidebarSearchField.swift`, `SidebarRowShell.swift`, `SidebarRepoGroupHeader.swift`, `SidebarSourceGroupHeader.swift`, and `SidebarSectionHeader.swift`.
- Shared components are required to be render/interaction primitives that do not own product state. They may receive explicitly passed observable view models, but they must not read atoms and must not import `Core`, `Features`, or `App`; this is documented in `docs/architecture/directory_structure.md`.
- `InboxSidebarHeader` is feature-owned. It owns inbox-only controls, menu state, tooltips, and local callbacks in `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`.
- Repo projection already has pure model seams in `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`, `RepoExplorerRowIndex.swift`, and `RepoExplorerSnapshot.swift`, but the view still invokes the projection from `RepoExplorerView`.
- Current repo presentation groups are source-family shaped and can contain multiple repos. The `Repo` grouping mode in this spec is a product correction, not a relabeling of the current source grouping.
- Inbox list/search projection already has a Sendable request/result worker in
  `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListProjectionWorker.swift`,
  and `InboxNotificationSidebarView` already records
  `request_build_mainactor`, `projection_worker`, and `mainactor_apply` phases.
  The remaining requirement is to verify that no heavy search/group/sort/list
  calculation remains in MainActor request construction or apply.
- `WorkspaceLookupDerived.paneLocationsByWorktreeId` is the current source of truth for worktree to active pane/tab occupancy. It only counts panes that are active-residency and owned by a tab.
- Command bar already derives `WorktreePresence` from the same lookup, proving a worktree occupancy read model exists, but repo sidebar grouping does not use it yet.
- The strongest current off-main precedent is the filesystem projection offload: MainActor snapshots once, off-main code derives rebuildable state, and MainActor applies compact results with generation guards.
- Swift 6.4 repo guidance requires explicit off-main escape with `@concurrent nonisolated` or an actor boundary. A plain `nonisolated async` helper is not enough when called from MainActor.
- Production delay code must avoid the generic clock sleep path. Current approved production delay seam is `AsyncDelay.taskSleep` / `Task.sleep(nanoseconds:)`, and tests must avoid direct wall-clock sleeps.
- Current debug observability can be run detached, but GUI launch still foregrounds the app today. "No screen interruption" is therefore a requirement to satisfy, not a property already provided by the current runner.
- Current checkout color storage is in `<workspace-id>.settings.json` at
  `sidebar.checkoutColors`, keyed by raw strings that are currently repo ids.
  That storage has no SQLite foreign-key cleanup and is consumed by repo
  explorer, inbox, launcher, and pane display surfaces. This spec does not
  promote that behavior into repo/worktree schema. Manual repo/checkout color
  overrides should stop being a repo UX surface in this slice; automatic color
  derivation may continue.
- Current repo projection has a model-owned placement row path in
  `RepoExplorerProjection.projectedWorktreeRows`. Pane and Tab placement rows
  must not inherit source-family checkout palette colors; those rows use a
  neutral placement row icon color while Repo mode keeps automatic repo/checkout
  colors.
- Repo sidebar already has an async projection worker path from
  `RepoExplorerView` and records `request_build_mainactor`,
  `projection_worker`, `row_index`, and `mainactor_apply` phases. The remaining
  requirement is to ensure the new grouping/sort/filter/favorite work does not
  put heavy scans or sorting back on MainActor.
- `scripts/verify-sidebar-performance-workload.sh` already exists and drives a
  marker-scoped sidebar workload through the debug observability runner. The
  remaining requirement is to align that workload with the final generic
  `command.execute` contract, required metrics, and no-foreground-activation
  proof rule.
- Current IPC code is only partially aligned with the desired command contract.
  `command.list` projects `AppCommandSpec` metadata, and
  `AgentStudioIPCCommandAdapter` validates declared argument schema before
  dispatch, but `command.execute` is still registered as `.debugUnsafe` in
  `AgentStudioIPCRegistryAuthorization`, and the adapter still contains
  feature-specific repo visibility/sort argument decoding. Those two facts are
  current implementation gaps to remove, not desired final architecture.
- Current typed sidebar write IPC methods such as `sidebar.grouping.set` and
  `sidebar.surface.set` exist beside `command.execute`. They are current
  implementation debt for command-shaped state changes, not the final
  authoritative write surface for grouping, surface switching, sort,
  visibility/filter, or favorite commands.

## Design Goals

1. Match the inbox sidebar layout structure where useful while preserving feature ownership.
2. Add repo grouping controls for Repo, Pane, and Tab only.
3. Define Inactive for Pane and Tab modes as a first-class group, not as a vague "other" bucket.
4. Move inbox search/list projection off MainActor using repo-approved Swift 6.4 concurrency patterns.
5. Keep repo grouping/search logic model-owned and testable.
6. Add before/after performance evidence through the existing OTLP/Victoria proof path.
7. Keep IPC/debug proof local, authenticated where possible, and non-disruptive to the user's desktop.
8. Add a repo favorite contract that is persisted on `repo`, testable, and
   usable from all repo grouping modes without adding a fourth grouping mode.
9. Add SQLite-only metadata fields/tables for future repo/worktree notes, repo
   tags, and tab shell colors without adding worktree/pane tags or
   repo/worktree/pane color columns.
10. Remove repo/worktree manual color UX and keep only automatic generated repo
    colors for current repo row presentation.
11. Route sidebar state-changing controls that need programmatic proof through
    app command definitions and generic IPC command execution, with
    command-id-owned surface, typed argument validation, and authorization.
12. Preserve compile-time type safety: IPC may accept public DTOs, but command
    execution must resolve to typed `AppCommand`, `AppCommandSpec`,
    command-owned typed argument values, and typed execution owners before
    mutating app state.

## Non-Goals

- Do not move `InboxSidebarHeader` into `SharedComponents`.
- Do not merge repo and inbox feature state.
- Do not make command-bar search share sidebar search semantics.
- Do not add a Flat or Source grouping mode for the repo sidebar.
- Do not treat Favorite as a repo grouping mode in this slice.
- Do not add global/user-wide repo tags.
- Do not add worktree or pane tags.
- Do not add UX for repo tags in this slice; this is a SQLite migration
  contract only.
- Do not add UX for tab shell colors in this slice; that color field is
  SQLite-only reserved metadata for now.
- Do not add pane color metadata.
- Do not keep user-editable repo or worktree color controls.
- Do not add `repo.color_hex`, `worktree.color_hex`, or `pane.color_hex` in
  this slice.
- Do not migrate `sidebar.checkoutColors` in this slice.
- Do not solve the remaining sidebar issues called out for later work.
- Do not use visual screenshots as the primary proof for search/projection performance.
- Do not use unsafe no-auth IPC as the default verification path.
- Do not add a bespoke `sidebar.filter.*`, `sidebar.sort.*`, or
  feature-specific IPC method when the operation is already an app command.
- Do not add command-specific argument decoding switches to the IPC adapter for
  each new sidebar command.
- Do not replace typed command/state contracts with stringly typed sidebar
  plumbing after public IPC DTO validation.
- Do not treat `command.execute` as one undifferentiated debug-only authority
  once a command advertises explicit required privileges in its command spec.
- Do not add synthetic, random, or test-only product commands just to prove the
  generic IPC command path.
- Do not leave obsolete bespoke IPC routes, duplicate command definitions, or
  feature-specific adapter cruft after a command-shaped sidebar action moves to
  the generic command path.
- Do not keep typed sidebar write IPC methods as independent mutation surfaces
  for command-shaped actions. Read/query methods may remain only when they are
  not command execution.

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

## Repo Metadata SQLite Contract

Repo favorite is active local repo metadata. Repo/worktree notes, repo tags,
and tab shell colors are SQLite schema-backed metadata in this slice, even when
no UX consumes them yet.

Terminology for this slice:

```text
source repo / source group
  normalized remote/local identity used for grouping; not a table today

repo table row
  local checkout family/root; can own multiple worktree rows

worktree table row
  concrete checkout path under a repo row, including git worktrees
```

Required behavior:

- A repo can be toggled favorite/unfavorite from the repo sidebar.
- Favorite state is keyed by stable repo id, not repo name, path, branch, group
  label, pane id, or tab id.
- Favorite state persists across app restart and workspace reload.
- Favorite state follows the repo wherever it appears in the sidebar. In Repo
  mode the primary affordance belongs on the repo group/header row. In Pane and
  Tab modes, rows that identify a repo must carry enough favorite presentation
  state to show and toggle the same repo tag without creating per-attachment
  favorite state.
- Favorite must not create a fourth grouping mode. The grouping modes remain
  exactly Repo, Pane, and Tab.
- Favorite state must not reorder the normal all-repos list. Bookmarking or
  unbookmarking a repo must not make rows jump in the default visibility mode.
  The explicit favorite visibility/filter mode is the way to show favorites
  only.
- Empty/loading repos may show disabled favorite affordances until they have a
  stable repo id.
- Existing manual repo icon/checkout color UX must be removed or disabled in
  this slice. Current automatic repo color derivation may remain.
- Repo automatic checkout colors are visible only in Repo grouping mode. Pane
  and Tab grouping rows use a neutral placement row icon color so attachment
  grouping does not show multi-colored repo/source accents.
- Do not add repo or worktree color columns as part of this plan.
- Tab shell color is migration-only in this slice and must not change current
  UI behavior.
- Pane color metadata is not part of this schema.
- Repo tags are migration-only in this slice and must not add tag UI, grouping,
  or filtering.
- Worktree and pane tags are not part of this schema.

Required persistence shape:

```text
repo
  add is_favorite INTEGER NOT NULL DEFAULT 0
  add note TEXT

worktree
  add note TEXT

tab_shell
  add color_hex TEXT

repo_tag
  repo_id TEXT NOT NULL REFERENCES repo(id) ON DELETE CASCADE
  tag     TEXT NOT NULL
  PRIMARY KEY(repo_id, tag)
```

These changes belong in core SQLite because they are metadata on durable repo,
worktree, and tab identities. They must not be added to workspace-local SQLite
or the workspace settings JSON lane.

The word "checkout" in the current `checkoutColors` code means the local
checkout family represented by a `repo` table row. It does not mean the
normalized remote/source group, and it does not mean each individual
`worktree` row. The existing color key is repo id, not worktree id, but this
spec does not turn that historical storage into `repo.color_hex`. The repo
sidebar should stop exposing user-editable checkout/repo colors and should use
only the existing automatic generated colors.

Required state boundary:

```text
MainActor repo/topology state
  owns repo favorite, note, and tag render inputs

repo projection snapshot
  receives repo metadata values from the MainActor snapshot

off-main projection
  filters by explicit visibility mode and sorts by selected sort order without
  reading atoms or stores
```

SharedComponents may render a passed favorite value and invoke a callback, but
must not read favorite atoms or storage directly. SharedComponents may also
render a passed tab shell color value, note affordance state, or tag count in
later UI slices, but must not read SQLite, atoms, or global stores directly.

## Command and IPC Contract

Sidebar controls are UI entry points into the app command system when they
change app state and need to be testable through programmatic control. The
command system owns command identity, presentation metadata, argument schema,
command-id-owned surface semantics, and execution owner routing. IPC owns transport,
authentication, authorization, public DTO validation, and forwarding to the
command system.

The steady-state command path is:

```text
sidebar UI control / keyboard / command bar / IPC command.execute
  -> AppCommand identity
  -> AppCommandSpec
       declares execution mode, argument schema, command-owned target/surface
       constraints,
       required privileges, and presentation metadata
  -> generic command execution request
       validates headless execution, argument schema, command-specific
       command-id-owned surface rules, and command-specific required privileges
  -> ShellCommandHandling or WorkspaceCommandHandling owner
  -> feature/app state owner
```

The type-safety rule is explicit: public IPC payloads are untrusted DTOs at the
transport boundary, but the app must not carry raw string dictionaries into
feature mutation. After generic DTO/schema validation, execution must resolve
through typed command identities and command-owned typed arguments. The typed
argument construction point is part of the command system contract, so new
sidebar commands must add typed command cases/decoders where needed instead of
adding feature-specific switches to the IPC adapter.

Required behavior:

- `command.list` projects all command specs that are IPC-visible, including
  execution modes, target handle kinds, argument schema, and required
  privileges.
- `command.execute` is the generic IPC execution surface for commands marked
  headless-executable by `AppCommandSpec`.
- For this slice, sidebar command surface specificity is encoded in the command
  identity and typed command arguments, not in a new public
  `IPCCommandExecuteParams.surface` or `IPCCommandExecuteParams.specifier`
  field. A repo command id is repo-scoped, an inbox command id is inbox-scoped,
  and surface-switch commands are explicit command ids. Adding a future public
  surface selector would require a separate spec that changes `AppCommandSpec`,
  `IPCCommandListEntry`, and `IPCCommandExecuteParams` together.
- `command.execute` must not mutate atoms, stores, sidebar state, or feature
  state directly. It forwards a validated command execution request to the same
  command owner used by keyboard shortcuts, command-bar execution, and UI
  controls.
- `command.execute` validation is generic and data-driven from the resolved
  `AppCommandSpec`. It validates command existence, headless executability,
  target handle kind, required arguments, unexpected arguments, enum values,
  command-id-owned surface shape, and required privileges before dispatch.
- Public raw IPC arguments are validated against the command's declared
  `argumentSchema` before any typed command arguments are constructed.
- Typed argument construction belongs with the command/request contract, not in
  `AgentStudioIPCCommandAdapter` feature switches. Adding a new
  argument-bearing command may require adding a command-owned typed argument
  case or decoder, but it must not require adding feature-specific decoding
  logic to the IPC adapter.
- `command.execute` must not be reachable only through the unsafe-debug method
  gate. The registry/authorization path must add a neutral method-gate
  privilege such as `appCommandExecute`. That privilege lets an
  escrow-authenticated automation principal reach generic command validation,
  but it grants no command mutation authority by itself.
- Command execution authorization is a two-phase `AgentStudioAppIPC` concern,
  not an `AgentStudioIPCCommandAdapter` concern. Phase 1 replaces the current
  `.debugUnsafe` method gate with a neutral authenticated app-command invocation
  privilege such as `appCommandExecute`; that privilege allows a caller to ask
  for command execution but grants no command mutation authority by itself.
  Phase 2 resolves the `AppCommandSpec` through an injected command-spec
  resolver before adapter dispatch, then reuses the centralized
  `AuthorizationService`/grant-ledger path to authorize the resolved
  `requiredPrivileges` and declared command identity/target. The adapter
  remains DTO validation plus forwarding only.
- Sidebar state-changing commands in this slice must not require broad
  `.layoutMutate` just to make headless automation possible. They must use a
  narrower grantable command privilege such as `sidebarStateMutate`, scoped to
  sidebar state commands and target `.workspace`. That privilege covers repo
  grouping, inbox grouping, repo sort, repo favorite visibility, programmatic
  repo favorite toggle if added, and headless surface ensure-visible commands.
  Broad layout mutation remains reserved for pane/tab/window layout commands.
- Surface-specific sidebar commands must carry an unambiguous surface through
  command identity in this slice. IPC validation must reject missing/extra
  arguments, invalid enum values, and commands that are not declared
  headless-executable before mutation.
- UI presentation remains separate. Commands that open interactive pickers,
  require user input, or only present the command bar must use explicit UI
  presentation authority such as `ui.commandBar.open`, not `command.execute`.
- Existing typed sidebar read/query IPC methods may remain when they are not
  command execution. Existing typed sidebar write methods for command-shaped
  state changes must not remain as independent product mutation paths. The
  product write path is `command.execute`.

Generic validation shape:

```text
IPCCommandExecuteParams
  -> parse command id
  -> load AppCommandSpec
  -> authorize neutral appCommandExecute privilege at the method gate
  -> require .headless execution mode
  -> validate target handle kind / command-id-owned surface
  -> validate argument names and values from argumentSchema
  -> AgentStudioAppIPC authorizes requiredPrivileges such as sidebarStateMutate
  -> build command-owned typed AppCommandExecutionArguments
  -> dispatch AppCommandExecutionRequest with typed executionContext to owner
```

The IPC adapter may contain the generic schema validator and the bridge to the
command owner. It must not know that repo visibility uses
`RepoExplorerVisibilityMode`, repo sort uses `RepoExplorerSortOrder`, or inbox
grouping uses `InboxNotificationGrouping`; those are command-system concerns.

Implementation proof must use real app commands from the sidebar surfaces, not
throwaway product commands. If a generic helper needs isolated coverage, test
the helper directly with local test fixtures or command-owned test doubles that
do not enter the product command catalog.

Current-code delta to close before this contract is satisfied:

```text
current
  command.execute method privilege: debugUnsafe
  typed sidebar write methods exist for grouping/surface switching
  adapter: validates schema, then switches on repo visibility/sort commands
  command system: receives typed arguments after adapter-specific decoding

required
  command.execute method: uses a neutral authenticated app-command invocation
    privilege instead of debugUnsafe; escrow-authenticated callers can reach
    command-spec validation without unsafe auth bypass
  AgentStudioAppIPC command authorization: resolves command spec through an
    injected resolver, then enforces command-specific requiredPrivileges and
    command identity/target before adapter dispatch
  adapter: owns generic public DTO/schema validation and forwarding only
  command system: owns typed argument construction for command-specific enums
  command request: carries a typed execution context that distinguishes
    interactive execution from headless IPC automation
  sidebar command privilege: uses a narrow grantable sidebar-state privilege,
    not broad layoutMutate and not unsafeDebug
  sidebar typed write methods: absent from the final product registry for
    command-shaped actions
```

The implementation plan must treat this as a refactor of the command execution
boundary. It must not add another repo/sidebar command just to prove the
generic path, and it must remove the repo-specific adapter decoding once the
command-owned decoder exists. It must also remove typed sidebar write routes
for command-shaped actions after their command specs are headless-executable.

Repo sidebar requirements for this slice:

- Repo grouping controls use headless command specs for Repo, Pane, and Tab
  grouping and are programmatically executed through generic `command.execute`.
- Repo sort order uses a command spec with a typed order argument.
- Repo favorite visibility/filter mode uses a command spec with a typed mode
  argument; Favorite remains a filter/view mode, not a grouping mode.
- Bookmark/favorite row toggles may remain direct feature callbacks for pointer
  interaction, but any programmatic toggle surface must be modeled as an app
  command before it is exposed through IPC.

Inbox sidebar requirements for this slice:

- Inbox grouping controls use headless command specs for the inbox surface and
  are programmatically executed through generic `command.execute`.
- If inbox sort or filter controls become programmatically drivable,
  they must use the same command-spec and generic `command.execute` contract
  rather than a parallel inbox-specific IPC command family.

Command-shaped sidebar action matrix for this slice:

```text
Action                         Final programmatic write surface
Repo grouping                  AppCommandSpec + command.execute
Inbox grouping                 AppCommandSpec + command.execute
Repo sort order                AppCommandSpec + command.execute
Repo favorite visibility       AppCommandSpec + command.execute
Repo favorite toggle           direct callback for pointer UI; command required before IPC
Sidebar surface switching      existing per-surface AppCommand identities + command.execute + typed headless context
Existing sidebar read/get APIs may remain query/read methods only.
Existing sidebar write/set APIs are not retained as independent product writes.
```

Surface switching uses the existing surface-specific command identities
`showWorktreeSidebar` and `showInboxNotifications` once they are made
headless-executable. The typed discriminator is an execution context on
`AppCommandExecutionRequest`, for example:

```text
AppCommandExecutionContext
  interactive
  headlessIPC
```

The IPC adapter does not invent this behavior. It builds a typed
`AppCommandExecutionRequest(command: ..., arguments: ..., executionContext:
.headlessIPC)` only after command-spec validation and authorization. Shell
command owners use that typed context to choose ensure-visible semantics for
headless automation while preserving existing pointer, keyboard, and menu
toggle/collapse semantics for interactive execution.

Headless surface-switch execution is idempotent. Executing
`showWorktreeSidebar` through `command.execute` with `.headlessIPC` must ensure
the repo surface is visible, and executing `showInboxNotifications` through
`command.execute` with `.headlessIPC` must ensure the inbox surface is visible.
A second headless invocation on the already visible surface must not collapse
the sidebar.

Repo sidebar state persistence matrix:

```text
Field                    Persistence owner
groupingMode             WorkspaceSettingsStore repoExplorer
sortOrder                WorkspaceSettingsStore repoExplorer
repoVisibilityMode       WorkspaceSettingsStore repoExplorer
repo search query        WorkspaceSidebarMemoryAtom / UIStateStore sidebar memory
active sidebar surface   WorkspaceSidebarMemoryAtom / UIStateStore sidebar memory
repo.is_favorite         core SQLite repo table
```

The repo favorite visibility control lives in the repo sidebar second-row
toolbar as a filter control. The default visibility mode is `all`; selecting
the favorites-only filter shows favorited repos without changing the default
all-repos ordering contract.

Spec boundary / separability map:

```text
AppCommand / AppCommandSpec
  owns: command identity, command-id-owned surface vocabulary, argument schema,
        required privileges, command presentation metadata
  exposes: command definition and typed execution request contract

AgentStudioAppIPC
  owns: IPC method registry, transport auth, grant/authorization checks,
        public DTO decoding, method dispatch
  exposes: command.list and command.execute

AgentStudio/App/IPCComposition
  owns: concrete adapter from IPC command DTOs to app command execution
  must not own: feature-specific command semantics or atom mutation

ShellCommandHandling / WorkspaceCommandHandling
  owns: command execution against app/window/sidebar/workspace owners
  exposes: typed execution outcome

Feature state owners
  own: repo sidebar state, inbox sidebar state, persistence, projections
  expose: callbacks/actions invoked by command owners
```

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
- hiding heavy search, grouping, sorting, row-index, or metric-prep work behind
  a `@MainActor` helper just because the caller is already on the MainActor
- adding timers for debounce behavior
- adding production `Task.sleep(for:)` or generic `Clock.sleep(for:)`
- adding direct `Task.sleep` waits in tests

Inbox search specifically must keep its semantic contract:

- search matches title/body and source display search text
- grouping, filtering, collapsed-section counts, visible ids, and navigation boundaries are produced from the same projection result
- stale projection results are discarded
- cancellation does not leave partially applied UI state

Repo projection should follow the same model-ownership and concurrency rule
where this slice touches repo search/grouping:

- row index generation stays model-owned
- rendering reads a prepared model rather than walking groups repeatedly
- repo/inbox shared chrome must not become the projection owner
- heavy repo grouping, sorting, filtering, row-index, and metric-prep work must
  run through an off-main actor or `@concurrent nonisolated` Sendable worker
- MainActor may read atoms and build the minimal Sendable snapshot, but it must
  not perform repeated repo/worktree/pane/tab scans or list sorting itself
- if a step remains on MainActor, the implementation must prove it is only
  compact snapshot/apply work and not the slow calculation path

The hard off-main requirement applies to inbox search/list projection and to
any heavy repo sidebar grouping, sorting, search/filtering, row-index, or
metric-prep calculation introduced or touched by this slice. Performance
evidence decides what to optimize first; it does not permit known-heavy work to
stay on MainActor.

## Metrics and Proof Requirements

The implementation plan must require before and after measurements.

Required metric dimensions:

- surface: repo or inbox
- phase values: `request_build_mainactor`, `projection_worker`, `row_index`,
  `mainactor_apply`
- query state bucket: empty or nonempty
- group mode: repo, pane, tab, or inbox grouping mode where applicable
- visibility/favorite filter mode where applicable: all, favorites_only, or
  not_applicable. Do not use a per-row favorite bucket for a mixed all-repos
  projection.
- sort order where applicable: ascending, descending, or not_applicable
- input counts where applicable: notifications, repos, worktrees, sections,
  groups, rows, loading repos, expanded groups
- stale result count
- MainActor apply duration
- total worker duration

Repo sidebar telemetry contract for this slice:

```text
Event bodies
  performance.sidebar.projection
  performance.sidebar.row_index

Required repo phases
  request_build_mainactor
  projection_worker
  row_index
  mainactor_apply

Required repo attributes
  agentstudio.performance.sidebar.surface = repo
  agentstudio.performance.sidebar.phase
  agentstudio.performance.sidebar.trigger
  agentstudio.performance.sidebar.query_state
  agentstudio.performance.sidebar.group_mode
  agentstudio.performance.sidebar.sort_order
  agentstudio.performance.sidebar.visibility_mode = all | favorites_only
  agentstudio.performance.sidebar.repo.count
  agentstudio.performance.sidebar.query_character.count
  agentstudio.performance.sidebar.expanded_group.count
  agentstudio.performance.sidebar.is_filtering

Phase-specific repo attributes
  request_build_mainactor -> request_build_mainactor_elapsed_ms
  projection_worker      -> total_worker_elapsed_ms, group.count, loading_repo.count
  row_index              -> row_index_elapsed_ms
  mainactor_apply        -> mainactor_apply_elapsed_ms, group.count, loading_repo.count
  stale mainactor_apply  -> stale_discard.count
```

`trigger = visibility_mode` is not a substitute for
`agentstudio.performance.sidebar.visibility_mode`; the trigger says why a
projection ran, while the visibility attribute says which filter mode was
applied.

Sidebar telemetry must be controlled-vocabulary only: counts, durations, booleans, enums, and buckets. Metrics must not export raw paths, raw UUIDs, query strings, repo names, worktree names, branch names, pane labels, tab labels, group display labels, notification titles/bodies, notification-derived search text, prompts, terminal buffers, tokens, or tool output over OTLP.

Every new sidebar telemetry field must have an allowlist test or verifier update that proves the exported vocabulary is scrubbed.

The standard proof path should stay marker-scoped through the shared observability stack:

```text
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

For sidebar performance proof, the later plan should either extend the existing
Victoria-backed performance workload or define a sidebar-specific marker-scoped
verifier. JSONL may be a local debug artifact, not the default proof path.
Inbox search/list projection requires baseline and post-change comparator proof.
Repo grouping/sort/visibility proof must at minimum verify scrubbed event
presence for `request_build_mainactor`, `projection_worker`, `row_index`, and
`mainactor_apply`, including the dedicated `visibility_mode` attribute. If repo
performance is changed beyond the existing projection worker path, the plan
must add repo baseline and post-change comparator rules too.

Comparator policy is a hard gate, not report-only. The verifier may own exact
numeric thresholds, but it must use one shared policy for every required p95/max
series. The current acceptable policy family is "fail if compare exceeds
max(baseline * multiplier, baseline + absolute allowance)" with both multiplier
and allowance declared in the verifier. Missing required series, unsafe
attributes, unsafe no-auth, foreground activation, or absent authenticated mode
are immediate failures independent of numeric thresholds.

IPC may be used for semantic control only through sidebar-safe contracts. For
command-shaped sidebar actions, the preferred contract is `AppCommandSpec`
discovery through `command.list` and execution through generic
`command.execute`. Startup diagnostics or future semantic IPC methods are
reserved for non-command behavior, query/read APIs, or app operations that do
not fit the command system. They must not become alternate mutation paths for
sort, grouping, favorite visibility, favorite toggle, or surface-switch
commands.

Sidebar IPC proof, if added, must be:

- escrow-authenticated
- headless
- app-owned and semantic, not click-coordinate or visual automation
- command-spec driven for command-shaped actions, including declared argument
  schema, command-id-owned surface validation, and command-specific required
  privileges
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

Visual proof routing:

- Pure model, command, persistence, and metrics behavior is proven by unit,
  integration, IPC, and Victoria-backed gates.
- User-visible layout/icon/row-distinguishability changes require native visual
  proof with Peekaboo against the launched debug app PID when a non-activating
  or user-approved foreground path is available.
- If native visual proof would foreground the app without approval, mark that
  visual lane blocked and keep IPC/Victoria proof separate; do not replace the
  visual lane with lower-layer tests.

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
- generic IPC command execution to command-specific app owners

Required constraints:

- off-main snapshots must contain only the data needed for projection
- projection workers must not log or export notification bodies or raw paths
- sidebar IPC proof must use debug-token escrow and fail closed if `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH` is set
- debug-token escrow must preserve single-use token consumption and replay-failure semantics
- unsafe IPC auth bypass remains debug-only, opt-in, and out of scope for sidebar proof
- `command.execute` must enforce the resolved command spec's required
  privileges and command-id-owned surface/target rules before dispatch
- `command.execute` method access uses a neutral `appCommandExecute` privilege;
  sidebar state-changing commands use a narrower `sidebarStateMutate`
  command-required privilege, not broad `.layoutMutate`
- IPC command adapters must not become privileged feature controllers; they
  validate public DTOs and forward to app command owners
- state handoff files are not proof; Victoria/log queries are proof
- shared UI components cannot gain privileged command or IPC semantics

## Validation Expectations for the Later Plan

The implementation plan must include:

- pure model tests for repo grouping modes and Inactive membership
- pure model tests proving both halves of the color contract: Repo mode keeps
  automatic repo checkout colors, and Pane/Tab placement rows do not use
  source-family checkout colors
- inbox list/search tests proving search, filtering, grouping, collapsed-section unread counts, `visibleNotificationIds`, group-boundary navigation, and endpoint navigation are preserved after off-main projection
- tests proving inbox visible ids, collapsed counts, and navigation come from the same generation-checked projection result
- stale generation/cancellation tests for asynchronous projection
- architecture tests preventing atom reads from repo/inbox projection workers
- architecture or lint proof that the inbox worker entrypoint is not MainActor-isolated, uses an allowed actor or `@concurrent nonisolated` seam, and crosses the boundary with Sendable snapshots/results only
- compile-time type-safety proof for command execution: tests or architecture
  checks proving sidebar command execution resolves from public DTOs into typed
  `AppCommandExecutionArguments` / typed command-owner calls before state
  mutation, without feature-specific IPC adapter switches
- architecture lint coverage for forbidden sleep/timer patterns if new async delay code is added
- focused UI/presentation tests for shared header layout composition
- core SQLite metadata migration, repo favorite toggle persistence, and
  no-row-jump favorite toggling inside normal Repo, Pane, and Tab views
- command catalog tests proving sidebar command specs expose correct execution
  modes, argument schema, command-id-owned surface vocabulary, and required
  privileges such as `sidebarStateMutate`
- IPC command execution tests proving `command.execute` forwards through the
  generic command system, rejects invalid arguments and command-owned surface
  shape before mutation,
  enforces command-specific authorization, and does not require
  feature-specific adapter switches for new argument-bearing sidebar commands
- IPC authorization tests proving `command.execute` is not debugUnsafe-only:
  escrow-authenticated automation can execute an allowed sidebar command, and a
  caller lacking the command's required privilege or using the wrong declared
  command identity/argument shape is rejected before mutation.
- cleanup/architecture tests proving obsolete bespoke sidebar IPC routes,
  duplicate command definitions, and test-only product commands are absent from
  the final product surface
- cleanup/architecture tests proving typed sidebar write/set IPC methods do not
  remain as independent product mutation paths for command-shaped actions
- command execution tests proving headless `showWorktreeSidebar` and
  `showInboxNotifications` are idempotent ensure-visible actions and do not
  collapse the sidebar when invoked twice through `command.execute`, while
  interactive command execution keeps existing toggle semantics
- metrics tests or verifier updates proving sidebar performance events are emitted and scrubbed
- baseline vs post-change Victoria-backed measurement for inbox search/list projection with pass/fail comparator rules
- repo sidebar performance proof covering scrubbed event presence for
  request-build, projection worker, row index, and MainActor apply phases,
  including the dedicated repo visibility-mode attribute, plus comparator rules
  if implementation changes repo performance behavior beyond the existing
  projection worker path
- native visual proof with Peekaboo for user-visible layout/icon/row
  distinguishability changes, or an explicit blocked visual lane if that proof
  would require unapproved foreground activation
- PR-ready proof is inherited from repo Definition of Done and this goal:
  focused tests, lint, runtime/performance proof, implementation review,
  current PR checks, review-thread state, and mergeability before any
  ready-to-merge claim
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
8. Repo favorites are core SQLite repo metadata keyed by repo id, persisted on
   `repo.is_favorite`, and rendered/toggled through feature-owned callbacks.
9. Repo/worktree manual color UX is removed from this slice; keep only existing
   automatic generated repo colors and do not add `repo.color_hex`,
   `worktree.color_hex`, or `pane.color_hex`.
10. Pane and Tab grouped repo rows use neutral placement row icon color; only
    Repo grouping mode shows automatic repo/checkout row accent colors.
11. Sidebar commands that need programmatic control use `AppCommandSpec` plus
    generic `command.execute`; feature-specific IPC routes are not added for
    command-shaped sort, grouping, favorite, or visibility controls.
12. Repo sidebar grouping, sort order, and favorite visibility mode are
    workspace-persisted repo explorer preferences. Repo search remains persisted
    in sidebar memory, and the favorite tag itself persists on `repo.is_favorite`
    in core SQLite.
