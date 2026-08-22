# Inbox Retirement — Program Design

Requirements: [requirements.md](requirements.md)
Specification: [specification.md](specification.md)

## Structural Decision

Inbox becomes dormant retained code and data, not a hidden runtime feature. App stops composing Inbox presentation and runtime ingestion while the feature module, atom/store types, SQLite schema, and existing rows remain unchanged for a later removal.

```text
TARGET APP COMPOSITION

Workspace state + Repo facts
          │
          ▼
RepoExplorerProjectionAdapter
          │
          ▼
RepoExplorerView  ──► sole SidebarSurfaceHost content

Inbox source/schema
          │
          └── retained but not composed, loaded, started, or presented
```

The crux is whether dormant code is allowed to perform work. “Hide only” is rejected because `SidebarSurfaceHost` currently mounts Inbox under opacity and runtime boot independently starts Inbox routing/persistence. Deleting Inbox is rejected because the owner explicitly preserves source and data. The selected hard disconnection removes App edges while retaining the disconnected owners.

## Owners And Boundaries

### SidebarSurfaceHost

- Owns Repo Explorer composition only.
- Does not import or construct `InboxNotificationSidebarView`.
- Does not accept Inbox atoms, preferences, sidebar state, callbacks, counts, or switch telemetry.
- Repo Explorer projection demand is always tied to sidebar visibility rather than an Inbox/Repo surface choice.

### WorkspaceSidebarState and legacy surface token

- Repo Explorer is the only live sidebar surface.
- The legacy `.inbox` Codable token may remain solely to decode existing settings until later source/data removal.
- Restore and every live mutation normalize `.inbox` to `.repos`; no App caller can make Inbox current.
- This is a decode boundary, not a compatibility presentation path or rollout flag.

### Command ownership

- Inbox `AppCommand` identities remain temporarily so exhaustive catalogs and stale callers compile, but their interactive surface policy is empty and `canDispatch`/execution fail closed.
- `AppCommand+IPCProjection` marks global and pane-local Inbox commands unexposed.
- The separate `sidebar.grouping.get(surface: inbox)` transport is removed from discovery and rejected before reading feature state. `AgentStudioIPCSidebarAdapter` becomes repo-only and App IPC composition no longer accepts `InboxNotificationPrefsAtom`.
- `AppShortcut` identities may remain dormant, but dispatch policy admits none of them.
- App and pane toolbars omit Inbox item identifiers and never construct Inbox items or badges.
- Command-bar composition receives no Inbox command provider.

### Inbox runtime and persistence

- `bootLoadUIStore` does not call `bootLoadInboxNotificationStore`.
- runtime-bus establishment does not call `bootStartInboxNotificationRouter`.
- no persistence observation or notification promotion begins because neither retained owner is activated.
- termination remains nil-safe for a router that was never created.
- the SQLite schema and dormant repository/store implementations remain unchanged; no Inbox write is performed.
- `WorkspaceSettingsStore` no longer imports, hydrates, observes, snapshots, or serializes Inbox preferences. `WorkspaceSQLiteDatastore` workspace-settings load/save omits Inbox preference replacement entirely, so unrelated editor/Repo preference saves and termination cannot touch the dormant row.

### Terminal activity and persistence recovery

- Live `bootStartTerminalActivityRouter` and its attendance helper move from the mixed Inbox boot extension to a terminal/runtime App boot owner. Their event-to-`PaneActivityStatusAtom` path remains unchanged.
- Persistence recovery remains owned by the active persistence layer, but retired operation records diagnostics without creating Inbox notifications or retaining `pendingPersistenceRecoveryEvents`. The dormant Inbox-specific conversion helper remains disconnected with the rest of Inbox boot.
- Termination stops the terminal router normally and treats the Inbox router/store as intentionally absent.

### Pane and Repo presentation

- `MainSplitViewController` passes no `PaneInboxPresentation` into `PaneTabViewController`.
- pane and terminal-zoom toolbar surfaces receive no Inbox actions or counts.
- Repo Explorer removes notification-count reads and the worktree action that dispatched the global Inbox command.
- terminal activity continues writing `PaneActivityStatusAtom`; Inbox attendance/promotion is not required for that path.
- `TabBarAdapter` drops Inbox attention-lane reads and notification-dot projection.
- `WorkspaceLauncherProjector`, `PaneManagementContext`, normal pane/drawer hosting, and Zoom drop Inbox notification-count inputs while retaining branch, Git/PR, focus, and terminal-status facets.
- `AppDelegate+MainWindowCreation` and `MainSplitViewController` no longer inject `InboxNotificationAtom`, Inbox sidebar state/preferences, or `PaneInboxPresentation` into window/pane composition.

## Current-To-Target Call Paths

```text
GLOBAL PRESENTATION

CURRENT
App toolbar / command / worktree badge
  -> showInboxNotifications
  -> WorkspaceSidebarState(.inbox)
  -> mounted InboxNotificationSidebarView
  -> MainActor repo presentation + SwiftUI List work

TARGET
Inbox entry point
  -> not presented or exposed
  -> stale dispatch rejected unavailable
  -> no sidebar mutation, view, projection, or list work

sidebar.grouping.get(surface: inbox)
  -> rejected by repo-only IPC surface validation
  -> no Inbox preference read
```

```text
PANE PRESENTATION

CURRENT
pane command / toolbar count
  -> PaneInboxPresentation.toggle
  -> pane Inbox popover

TARGET
Inbox entry point
  -> not presented or exposed
  -> no PaneInboxPresentation injected
  -> no popover or count read
```

```text
INGESTION AND PERSISTENCE

CURRENT
workspace boot
  -> load Inbox rows into atom
  -> observe atom for debounced saves
  -> start InboxNotificationRouter
  -> runtime/focus events -> promoter -> new notification -> SQLite save

TARGET
workspace boot
  -> leave Inbox store/router unconstructed
  -> active WorkspaceSettingsStore omits Inbox preferences
  -> live terminal router starts from terminal/runtime boot owner
  -> recovery diagnostics do not buffer/create Inbox notifications
  -> no Inbox load, observation, promotion, append, or save
  -> existing SQLite rows remain unchanged
```

```text
NOTIFICATION PROJECTIONS

CURRENT
InboxNotificationAtom
  -> TabBar attention dot
  -> WorkspaceLauncher recent-worktree chip
  -> PaneManagementContext / pane / drawer / Zoom counts
  -> Repo Explorer worktree badge and global-Inbox action

TARGET
App/window/pane/Repo composition
  -> no Inbox atom/count/action inputs
  -> branch, Git/PR, focus, activity, and terminal status unchanged
```

Preservation-critical unchanged paths are Repo Explorer projection, terminal activity routing and `PaneActivityStatusAtom`, Forge/cache projection, workspace SQLite schema creation, and ordinary shutdown.

## Failure, Recovery, And Cutover

- Legacy `.inbox` state normalizes deterministically to `.repos` before presentation.
- Stale command/shortcut/IPC requests return unavailable through existing validation/dispatch failure; they do not mutate state or delete rows.
- Missing Inbox router/store instances are an expected retired state. Shutdown and recovery-notification plumbing must tolerate absence without fabricating Inbox data.
- Active settings autosave and shutdown never call Inbox preference replacement. Before/after equality includes timestamps and every Inbox preference/history row.
- If runtime proof detects any Inbox row write, presentation construction, or command exposure, the retirement gate fails; there is no hidden fallback.
- Cutover is one binary hard disconnection. Rollback to the checkpointed predecessor can reuse the unchanged schema/rows. No dual active path or feature flag exists.

## Explicit Source Boundary

The surviving dormant Inbox boot, persistence, and presentation owners carry one concise contract comment:

> Inbox presentation and ingestion are intentionally retired. Source and persisted rows remain only for a later data-safe removal. Do not reconnect these owners to App, command, toolbar, shortcut, IPC, or runtime-bus composition without a new product decision.

The comment documents why retained code exists; disabled calls are removed rather than commented out.

Authoritative documentation cutover updates the command contract, IPC contract, AppKit/SwiftUI hosting and keyboard-surface contract, workspace-data sidebar flow, component/persistence ownership, and architecture index. Each describes active Repo/terminal behavior separately from the dormant retained Inbox source/schema boundary; none instructs a maintainer to reconnect live Inbox edges.

## Requirement And Proof Trace

| Requirement | Structural realization | Proof seam |
| --- | --- | --- |
| R1 | Repo-only `SidebarSurfaceHost`; legacy state normalization | host/state behavior plus native sidebar proof |
| R2 | empty command surfaces, rejected dispatch, repo-only non-command IPC | catalog/dispatch/registry/adapter exhaustive tests |
| R3 | no Inbox toolbar/count/action/TabBar/launcher/pane composition | source architecture tests plus native surface proof |
| R4 | no history/settings load/write/router/promotion; terminal/recovery split | boot/settings/recovery behavior tests and marker absence |
| R5 | unchanged history/preferences/schema including timestamps | before/after SQLite inspection across autosave/termination |
| R6 | retirement comments, all authoritative contract cutovers, static enforcement | architecture navigation and source-scan tests |

The real-size sidebar verifier changes its workload contract from alternating Repo/Inbox surfaces to exercising Repo grouping/search/sort and pane activity only. Removing the retired surface is not permission to reduce the load or proof threshold.

| Gate | Disposition |
| --- | --- |
| 150 repos / 180 worktrees / 12 tabs / 36 panes / 1 active PTY | retained exactly |
| 100 authenticated workload cycles and retained stage/readback floors | retained; replacement Repo sequence produces the same load duration/class |
| interval CPU p95 `<30%` | retained exactly |
| Repo capture/worker/apply/row-index metrics and stage ratios | retained exactly |
| keyed-wake relevant/irrelevant isolation and zero trace/runtime/collector drops | retained exactly |
| Inbox grouping/projection/surface-switch metrics and notification mutations | owner-authorized supersession; absent, never replaced with zero-valued fake series |
| workload/baseline identity | versioned to the Repo-only sequence; stale Inbox-era baselines rejected |

## Tradeoffs And Revisit Signal

- Retaining dormant source leaves temporary maintenance surface. The payer is maintainers; explicit static enforcement and the later removal decision bound that debt.
- Stopping new ingestion means rollback sees preserved historical rows but no notifications from the retirement interval. The owner accepts this because Inbox is unused and should perform no hidden work.
- Keeping the legacy decode token avoids restore failure without preserving runtime Inbox behavior. Remove it only with the later data/source disposition change.
