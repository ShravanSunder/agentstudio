# Sidebar Organization Program Design

Observable contract: [Specification](2026-09-07-sidebar-organization-specification.md). Authorized needs: [Requirements](2026-09-07-sidebar-organization-requirements.md).

## Three bounded changes

```text
PR 1: sidebar organization on current data
    existing runtime activity → existing projection → new organization
    pin/domain/preference migrations and keyboard commands
    no vendor or daemon protocol change
                  ↓
PR 2: zmx baseline update
    preserved session identity and attach/restore contracts
    vendor/toolchain change isolated from new activity protocol
                  ↓
PR 3: internal zmx IPC and terminal enhancements
    actual PTY metadata → existing off-main semantic/projection systems
    historical activity and unseen/animation contracts completed here
```

These are design boundaries, not an implementation plan or new worktree layout. Source reliability and IPC design are not prerequisites for writing the first sidebar scope. Conversely, PR 1 does not claim the third scope's signal coverage. New unseen dots/animation remain in the later terminal-enhancement scope; PR1 keeps current indicators.

| Structural area | First scope | Later scope |
| --- | --- | --- |
| Repos/Panes and independent pins | Complete on existing graph/state owners | Preserved |
| Search/group/subgroup/sort | Existing eager-derived projection with existing settled-line timestamp under R9a | Replace activity input contract without re-owning organization |
| Keyboard routing | Existing command catalog/dispatcher/surface policy | Additional terminal actions only if explicitly designed |
| SQLite | Repository column rename, pane pin column, local preferences | Activity history/acknowledgement schema after source contract |
| zmx version/build | Unchanged | PR 2 update; no protocol extension credited to it |
| zmx IPC | No new client or tags | PR 3 uses the old internal-backend design plus scoped activity contract |
| Active animation / blue dot | Preserve current indicators | PR3 terminal enhancement; acknowledgement details remain later work |

PR 1 uses the existing `PaneActivityStatusAtom` timestamped settled-line fact. App composition changes its current text-only injection to supply the existing fact (or equivalent immutable text/date pair) to RepoExplorer. Keyed observation still reads that same atom slot; no new source/provider/atom is required. Capture copies `observedAt` without calculating age. The existing detached projection evaluates R9a's bucket and sort keys, then returns the next expiry with affected IDs. The timestamp is recorded before optional publication deferral, equal lines are suppressed, attended-pane coverage differs, and it is cleared with the surface. Do not persist it or relabel it as exact last PTY output. Current focus recency remains separate and never fills missing activity.

```text
PR 1 current-to-proposed activity path
UNCHANGED  TerminalActivityProjector → settled line → PaneActivityStatusAtom
CHANGED    App latestPaneMessageSnapshot(text) → immutable existing fact(text,time)
UNCHANGED  keyed pane observation → generation-bound immutable capture
ADDED      existing worker: time buckets + activity leaf sort + next boundary
UNCHANGED  native broker validates generation/baseline → prepared row publication
ABSENT     new IPC, source polling, raw-output parsing, activity-history persistence
```

The worker computes worktree activity as the maximum available timestamp for its current eligible associated pane destinations. Empty evidence stays unknown; retiring a pane removes its contribution through the existing invalidation path. New group/subgroup identities are derived; selected destinations are retained by canonical pane/worktree identity when their materialized row identity changes with the containing group.

This requires changing the current demand gates, not just the injected closure: Repos currently omits pane facts in `captureRequest`, skips pane changes in `capturePaneChanges`, and does not register pane activity observations. Register/capture only the existing keyed pane facts needed when Activity sorting or activity subgrouping is selected in Repos; Name plus no time subgroup needs no additional activity observation. Panes activity inputs cover its existing canonical eligible destinations. The worker returns affected worktree/pane identities and next time boundaries; MainActor does not join pane dictionaries or compute activity maxima. On hidden demand, stop display observation/deadlines through the existing adapter; on resume, recapture the current facts and reference time.

Current anchors for this activity-input path: `RepoExplorerProjectionInputCapture.swift:92-98,489-496`, `RepoExplorerProjectionInputCapture+Observation.swift:59-63,110-135`, and `Models/RepoExplorerObservationRegistration.swift:22-46`. Remove both By Tab sort exemptions: the observation skip and the previous-sort reuse. Verification must exercise a pane's new settled-line fact while Repos uses Activity sort/subgroup, the no-new-event time boundary, and hidden/resumed demand. A passing Panes-only test does not prove the Repos input path.

## Reuse the current projection and command boundaries

The sidebar remains a reader of canonical topology, pane state, preferences and admitted activity facts. Its existing eager-derived projection computes the display model off MainActor. New organization does not justify a second worker, scheduler framework, ambient feature atom, or pane-view subscription.

```text
Pointer controls / surface-context shortcuts
    │ synchronous validated command dispatch
    ▼
Existing AppCommand catalog → dispatcher → execution owner
    ├── sidebar preference mutation
    └── validated repository/pane pin mutation
             │ keyed observation
             ▼
RepoExplorerProjectionInputCapture                 MainActor
    canonical keyed values only
             │ immutable request / generation
             ▼
Existing EagerDerivedAtomFamily → projection work  detached
    search/filter → pin/open sections → groups → subgroups
    → leaf sort → row indexes → next time boundary
             │ candidate
             ▼
Existing adapter generation validation             MainActor
    → materialization broker → native update plan → NSTableView
```

The existing `EagerDerivedAtom.startProjection` owns the detached execution guarantee. `RepoExplorerProjectionAdapter` supplies project/classify/publication callbacks. The active path calls `RepoExplorerProjectionWorker.project(work)` through that primitive; the worker's separate async detached helper must not be assumed to be the only off-main entrypoint.

Current anchors: `Infrastructure/AtomLib/EagerDerivedAtom.swift:260`, `Features/RepoExplorer/RepoExplorerProjectionAdapter.swift:148-194`, `RepoExplorerProjectionAdapter+MaterializationBroker.swift:77-111`, `Models/RepoExplorerProjectionWorker.swift`.

## Owners and reasons to change

All source paths below are under `Sources/AgentStudio/` unless otherwise stated.

| Responsibility | Existing owner / design change | Consumers and reason to change |
| --- | --- | --- |
| Repository pin choice | `RepositoryTopologyAtom`; rename favorite domain/mutation vocabulary to pinned | Repos partition, repository controls; changes when user pins a repository |
| Individual pane pin choice | `WorkspacePaneGraphAtom` through pane metadata and existing canonical mutation path; add independent value | Panes partition and pin controls; changes only for that pane's pin action |
| Header/view preference state | Core `WorkspaceSidebarState` plus feature `RepoExplorerSidebarPrefsAtom` and current persistence wrappers | Sidebar capture/commands; extend per-screen values in their existing scopes |
| Search and organization computation | Existing `RepoExplorerProjectionWorker` and pure projection functions | Materialized row model; changes with admitted query, preferences, topology, pins, activity or time |
| Projection admission/currentness | Existing `RepoExplorerProjectionAdapter`, eager-derived family and materialization broker | Native table; changes with demand and source generation |
| Terminal activity source contraction | Existing Contract 7 accumulator and `TerminalActivityProjector` where the chosen source enters | Activity projection; the PR3 source contract must identify fresh output before adding any semantic interface |
| SQLite effects | Existing actor `WorkspaceSQLiteDatastore` and Core/Local repositories | Existing state persistence; no SQL in atoms or views |
| Tab indicator presentation | Existing App `TabBarProjection`/`CustomTabBar` | Aggregated pane activity display; the PR3 indicator contract decides semantics, not a new Inbox route |
| Paint and animation | Existing shared controls and App-owned row hosts | Resolved values only; no domain lookup or animation-frame callback |

Dependency boundaries remain App → Features/Core, Features → Core/Infrastructure/SharedComponents. RepoExplorer must not import Terminal. App composition supplies values from feature-owned terminal state; any cross-feature fact contract must have its narrow existing Core boundary or an explicitly justified addition after the PR3 source contract. No new atom, store or coordinator responsibility is assumed by this table.

## Current-to-proposed call paths

### Controls and shortcuts — C1, C4

```text
UNCHANGED  control → AppCommand spec/presentation → dispatcher
CHANGED    group commands: old mixed repo/pane/tab selection
                          → explicit screen and group choices
CHANGED    typed sort arguments: direction only → field + direction
ADDED      AppShortcut identities/bindings and sidebar policy cases
UNCHANGED  dispatcher → shell command handling → existing prefs owner
UNCHANGED  prefs observation → keyed input capture → eager projection
REMOVED    By Tab ignores sort preference
RESULT     prepared leaf order; group membership/order unchanged
ERROR      unavailable context/invalid arguments rejected by existing path
```

Current anchors: `Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift`, `App/Windows/SidebarSurfaceHost.swift:64-81`, `App/Boot/AppDelegate+ShellCommandHandling.swift:375-432`, `Core/Actions/Commands/AppShortcutDispatchPolicy.swift:233`, `Features/RepoExplorer/RepoExplorerProjectionInputCapture.swift:130`.

Command identity, labels, SF Symbols, tooltip and shortcut display remain in the spec catalog. Each new identity needs explicit IPC exposure/argument classification; keyboard availability does not grant headless authority. Surface routing consults the actual sidebar screen; old `.inbox` retention is not a Panes screen implementation. The owner deferred exact chords; retain the command identities and routing design without inventing provisional key combinations. Avoid raw-character handlers in the filter and any terminal/pane view.

Every sidebar action uses the existing surface-specific command-spec classification. The presentation query and dispatch preflight resolve Repos versus Panes, including the allowed group/subgroup options, sort values, pin target kind and pinned visibility preference. Grouping Panes by repository never changes its command surface to Repos. Shell execution applies the resolved screen's preference mutation; targeted pin execution validates the corresponding repository or pane identity. Reuse the current catalog/presentation/dispatcher/policy pipeline for this classification, not a parallel surface-command registry or a view-owned switch that bypasses preflight. Exact key combinations remain deferred without blocking these contracts.

#### Proposed keyboard interaction and actual header width

The current split-view owner constrains sidebar width to 250–450 points (`App/Windows/MainSplitViewController.swift:239-240`); the style token's 200-point minimum is not the live split-view minimum. Header proof must target the real 250-point boundary. The existing segmented control renders all segment icons but only the selected text (`SharedComponents/SidebarToolbarSegmentedControl.swift:50-86`). Reuse that established presentation before introducing new controls; long labels for every option cannot be assumed to fit in two rows.

Organization commands operate the same preference values as direct pointer selection. Any cycle action follows visible option order and skips unavailable choices; direction and current-screen pinned visibility are explicit toggles. No-op unavailable transitions must not alter topology or launch terminal work. Actual chord assignment is owner-deferred: when chosen, add bindings through AppShortcut and the existing catalog/dispatcher/surface policy, conflict-check the current catalog, and preserve filter typing. Do not create a parallel view-local key monitor or hardcode shortcut glyphs in controls.

At narrow widths, expose every alternative as a compact icon segment with visible selected state; selected text appears only when it fits. Do not add caption text for each group of controls. Do not raise the minimum width, add a third row, or hide options in a menu. Native fit is a required implementation check, not a claim made by the schematic.

### Pin mutation — C2, C3, C6

Repository pinning cuts over the current `WorkspaceActionCommand.setRepoFavorite`/validation/execution path to pinned terminology. Pane pinning extends the canonical pane mutation path; no current individual-pin command exists. The change is an explicit set value, making duplicate requests idempotent.

```text
Repository target → validate identity → topology owner.isPinned
Pane target       → validate identity → pane graph metadata.isPinned
                           │ equal-write suppression / keyed publication
                           ├── existing persistence snapshot → datastore actor
                           └── existing sidebar projection invalidation

No repository-pin → pane-pin edge exists.
```

Anchors: `Core/Actions/WorkspaceActionCommand.swift:133`, `Core/Actions/ActionValidator.swift:225`, `Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift:479` (existing note mutation pattern), `Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`, `Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift:95`.

Pin state travels with the same pane identity through graph placement and persistence. Hydration, canonical metadata reconstruction and pending-undo snapshots must retain the value. A new pane defaults unpinned; repository pin state is never used as its default. A new pane identity defaults unpinned even if other metadata is copied; undo of the same pane identity restores its pin.

### Activity heading rendering — C3

The worker emits the existing activity bucket identity and resolved display label; the ten-minute bucket's label is Just Now and its timing is unchanged. Materialized subgroup headings use the existing section-heading typography and secondary foreground color. Their leading position is the existing row-icon column shared by repository and pane/worktree icons; do not add a nested indentation level, chevron or subgroup icon. Existing leaf and metadata alignment is unchanged. Use existing shared row/header layout constants rather than an unrelated hardcoded inset. Repository/tab collapse controls the subgroup content; no new subgroup-collapse state or preference is introduced. This is rendering of prepared rows, not a new observation or time-calculation path.

### Projection — C2–C6

Retain the current immutable request, source generations, keyed invalidations, pending-intent scope union and native transaction pipeline. Extend request values rather than having views query additional global state.

The off-main computation sequence is explicit:

1. Resolve eligible canonical row identities and filter the requested collection.
2. Partition by the current screen's own pin values; for Repos, partition unhoisted repositories by open-pane presence.
3. Build the selected repository/tab/activity groups and optional time subgroups.
4. Sort leaves within each group/subgroup by the chosen field/direction, with stable identity tie breaks.
5. Produce row indexes, display values, affected scope, and next time-boundary metadata.

Sorting must not call a group comparator whose order changes with the leaf sort selection. Current repository group sorting and fixed recency ordering in `RepoExplorerProjection.swift`/`RepoExplorerProjection+PaneGroups.swift` require separation. Existing scoped update shortcuts must either preserve all new membership/order dependencies or fall back to the full off-main projection; a stale scoped shortcut must never leave a pin/activity move in the wrong section.

### Time boundaries — C5, C6

Current `scheduleRecencyDeadline` maps every pane to its next date and finds due pane IDs on MainActor. The first-scope change has the existing worker compute the next display boundary and affected identities together with the projection, including R9a's one-minute recent-evidence boundary. The existing demand/generation lifecycle consumes that prepared result; it must not rescan rows on MainActor. PR 3 replaces the evidence input and supplies source-currentness, while the existing projection still owns display aging. There is one sidebar display-deadline lifecycle, not separate old/new Active timers.

PR1 has one timestamp representation: the existing `PaneActivityStatusFact.observedAt` wall-clock Date. Each admitted projection request carries a fresh wall-clock reference Date and a captured local calendar/time-zone value. The worker computes age and bucket membership exactly as R9a specifies; missing, non-finite or future facts are No activity. It does not use the atom's private monotonic publication-cadence state or the terminal accumulator's uptime as activity age. Monotonic source time belongs to the later PR3 source contract, not a new PR1 fact field.

The worker returns the earliest next wall-time boundary, its affected canonical IDs, and the generation/baseline it was computed from. Boundaries include 60 seconds, ten minutes, one hour, local midnight and seven days; a valid future timestamp can also supply its next eligibility boundary without being treated as current activity. The existing adapter arms its one delay from that prepared result. When the delay fires, it obtains a fresh reference Date/calendar and submits the due invalidation through the existing queue; it does not assume the sleep duration itself establishes wall-clock age. Newer preferences, facts or topology supersede the result through the existing generation checks.

Add system-clock-change and time-zone-change ingress to the existing `App/Lifecycle/ApplicationLifecycleMonitor.swift`. App composition registers the native notifications once at startup and removes them at shutdown, using the monitor as the ingress owner. The monitor invokes an injected sidebar-time-invalidation callback into the existing projection adapter; it stores no new clock state and emits no new app-domain bus event. This is a thin MainActor ingress only: no pane scan, time classification or sorting occurs there.

The adapter cancels its old display deadline, advances its existing invalidation/generation path and requests a full presentation projection with fresh Date/calendar inputs. It must not reuse `previous.activityReferenceDate` merely because grouping is unchanged. The worker then recalculates ages, keys and the next deadline off-main. If sidebar demand is suspended, no projection starts; the normal demand-resume capture supplies fresh time/calendar before publication. Thus clock changes cannot publish a candidate based on the previous time-zone or leave an old expiry armed. The same source/candidate epoch checks handle a clock notification racing with an activity update.

```text
ADDED      native clock/time-zone notification → ApplicationLifecycleMonitor
ADDED      thin injected callback → existing adapter invalidation queue
CHANGED    refreshed Date/calendar + new generation → existing detached worker
UNCHANGED  candidate/baseline validation → prepared row publication
UNCHANGED  one demand-owned display deadline, recomputed from worker result
```

The timing proof uses existing timestamp facts and injected clock/calendar values: ordinary expiry with no new output, forward/backward wall-clock changes, time-zone midnight changes, a change while hidden, and a change while a candidate is in flight. Inspect that only the monitor callback and keyed request/publication touch MainActor; bucket calculations and deadline selection remain in the existing worker. No new timer family, activity store, or generic clock service is introduced.

Current anchor: `RepoExplorerProjectionAdapter+InputLifecycle.swift:348-404`. The off-main computation is extended; no per-row timer or replacement scheduling framework is introduced.

## State and SQLite cutover

| Value | Authority / lifetime | SQLite change |
| --- | --- | --- |
| Repository `isPinned` | Existing global repository topology | Rename `repo.is_favorite` to `is_pinned`; preserve values |
| Pane `isPinned` | Existing workspace pane graph metadata | Add `pane.is_pinned` with false default; extend row codecs/upsert/snapshots |
| Screen/group/subgroup/sort/show-pinned | Existing sidebar/feature preference boundaries | Extend existing local preference records as specified in C8; keep per-screen values independent |
| Last qualifying terminal activity | PR 1 existing runtime fact; PR 3 zmx source through existing projector | PR 1 no new activity persistence; PR 3 local activity persistence behind the existing datastore; exact key/schema completed with its source contract |
| Active, section, bucket, sorted order | Derived state | Never persist |
| Unseen activity/acknowledgement | the PR3 indicator contract | Persistence not selected; do not smuggle into the pin field or old notification rows |

Current SQLite anchors: `WorkspaceCoreMigrations+RepoSidebarMetadata.swift`, `WorkspaceCoreRepository+TopologyMutation.swift`, `WorkspaceCoreRepository+PaneGraph.swift`, `WorkspaceCoreRepository+PaneGraphMutation.swift`, `WorkspaceLocalMigrations.swift:228-239,357-362`.

Migrate through the existing ordered Core migration owner. Historical migration definitions remain historical; append a migration instead of rewriting installed schema history. The final readers/writers use only pinned column names. Do not maintain old/new write paths. Existing pin values and pane identities must survive round trip. Database preparation failure follows the existing Core failure path; no catch-and-create-empty-database shortcut. Downgrade compatibility is not added. Application-local activity/preference failure must not corrupt the Core graph; existing local-data recovery governs unavailable history.

Important current scope distinction: grouping is stored on the main window's local row through `UIStateStore`, while sort is workspace-keyed through `WorkspaceSettingsStore`. Do not silently combine or move that state because both controls appear in row two. C8 preserves these scopes.

Preserve those existing lifetimes: extend window-local sidebar memory/codecs for selected Repos/Panes screen, Panes group, each screen's subgroup and pinned-section visibility; extend the existing workspace-local RepoExplorer preferences for each screen's sort field and direction. No new preference store or atom is needed. Migrate old repo/pane/tab grouping values to the corresponding screen/group and retain saved sort direction; initialize only newly introduced settings. This extends existing persistence; it does not unify unrelated preference lifetimes.

Panes' missing subgroup value initializes to Activity (U17); a stored None is an explicit selection, not a missing value. Effective subgroup is None while the main group is Activity, without mutating the stored preference. Switching back to Repository/Tab restores that preference. Extend the existing observe/save/hydrate paths together so selecting a subgroup survives restart; defaults are only for absent settings, never a reset on screen/group selection.

Extend the existing window sidebar record with selected screen, pane grouping, Repos/Panes subgroup, and separate Show Pinned booleans. Extend `local_repo_explorer_preferences` with Repos/Panes sort field and direction columns. Column names use the screen prefix; no generic JSON settings bag or new table is needed. The migration uses old repo_grouping_mode to initialize screen/group, copies old sort_order to both directions, sets missing fields according to C8, then removes retired grouping/sort columns from the current schema. Historical migrations are untouched. Extend codecs, typed records, hydrate, observation and save together. Workspace switching preserves window-local organization and restores that workspace's two sort selections. Defaults are applied only to absent new values, not valid saved None/descending/off choices.

`SidebarSurface` gains the actual Panes screen; it must not reuse `.inbox`. Update `WorkspaceSidebarMemoryAtom`'s current force-to-Repos setters/hydration and the SQLite surface codec, plus the existing shell host and keyboard owner. Both screens reuse the same RepoExplorer adapter/materializer with different inputs, not two simultaneously active projection families. Retained Inbox compatibility remains unavailable; there is no Inbox revival or removal in PR1.

Group keys include screen and section; subgroup keys add bucket. Pin movement therefore cannot make two section headers share an identity. Row identity remains distinct from activation identity: preserve selection by canonical pane/worktree ID while rebuilding the new row key. The existing materialization broker still validates baseline/epoch/generation before table mutation. Full off-main rebuilding is allowed when a scoped shortcut cannot prove the new membership dependencies; no unsafe in-place partial move is required for optimization.

Canonical membership stays with existing tab-owned allPaneIds plus active-residency pane facts and validated associations. Capture those keyed canonical facts; any new activity join, grouping or sorting is in the existing worker. Arrangement visibility does not remove a tab-owned pane from Open membership. Drawer expansion does not introduce extra sidebar destinations. The design does not infer a new pane catalog from current rendered views. Source anchors: `Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift:62-108`, `Features/RepoExplorer/RepoExplorerProjectionInputCapture.swift:618-649`, and `Core/Models/Tab.swift:15-19`.

## Concurrency, cancellation and failure

| Interleaving / failure | Required realization |
| --- | --- |
| Query or group changes while projection runs | Existing generation/intent admission rejects obsolete candidate; no publication of older hierarchy |
| Pane pin changes during activity projection | Keyed invalidation includes the pane; candidate currentness covers pin revision, not only activity timestamp |
| Pane moves/closes while activity arrives | Validate source lifetime and pane identity at the owning boundary; removal wins over late output; do not resurrect a row |
| Sidebar hidden or materializer detached | Existing demand suspension stops display work; persisted activity collection must not depend on visible rows |
| Several activity updates arrive together | Preserve per-key latest evidence and required transitions through existing bounded admission; no unbounded event queue |
| Activity source unavailable or restored history only | Do not manufacture Active or completed state; historical grouping remains possible from valid saved time |
| Persistence fails | Existing datastore error/recovery path remains authoritative; no duplicate owner or silent durable-success claim |
| Row reused during animation | Stop old layer animation, assign new prepared indicator state, respect offscreen/Reduce Motion; no source query during frames |

Performance proof must include the actual high-rate path, not only the pure sort function. Source facts that alter sorting can cause semantic updates even while a row stays Active; no promise of zero updates until the next bucket is valid when Activity sort is selected. Publication cadence must preserve the requested order/currentness while bounding work; PR1 retains the current settled-fact admission cadence and existing performance policies; future source cadence belongs to PR3.

## Indicator extension and the source boundary

Existing tab items have a notification-dot slot, but their current `TabBarProjectionRequest.inboxAttentionLane` is not a per-pane unseen terminal-activity model. Do not route new blue dots through dormant Inbox behavior merely because the old view can render a circle.

The proposed consumer shape is one prepared pane indicator state and a tab aggregate over canonical pane ownership, both computed off-main. Tab visibility does not independently acknowledge every pane. Exact acknowledgement, membership across arrangements, renewed-output precedence and persisted unseen state remain the PR3 indicator contract. The existing `AttendedPaneDerived` and ordered `.observed` control are source-backed reuse candidates, not yet a complete acknowledgement policy.

```text
PR3 qualifying activity source
    → existing off-main semantic contraction
    → activity/acknowledgement facts (the PR3 indicator contract)
        ├── sidebar projection → pane indicator
        └── App tab projection → tab indicator
```

A Core Animation opacity/transform/rotation effect may render the prepared state without per-frame MainActor state changes. Concrete row/host integration requires visual proof and must preserve the existing native table materialization/reuse lifecycle.

The current scrollbar evidence cannot prove all PTY output. The selected provider scope is the existing zmx terminal path (U14); source-owned zmx output metadata is the candidate for completing the signal. The exact metadata transport remains the PR3 source contract. A separate Ghostty output extension is not part of this design. Polling viewport text is not silently accepted as a substitute: it adds read work, misses changes between samples and can confuse replay/resize with new output.

### Later source evidence

Current terminal creation uses zmx. The pinned daemon reads the inner PTY even when Ghostty has no surface; metadata at that read can distinguish fresh output from attach replay. Existing zmx IPC and the prior backend design are the selected later boundary. PR1 does not introduce a Ghostty output API, viewport polling or a passive raw-output client.

The PR2 target is zmx v0.8.1 at `8bab1f0173b07e79835ea372d749af3dbf0d0842`; its source includes the fork's prompt-redraw behavior. zmx requires Zig 0.16.0 while embedded Ghostty remains on its current 0.15.2 build. Current upstream still freezes Info and has no activity timestamp/counter message. These are later-scope constraints, not PR1 implementation dependencies.

### PR 2 build, package and session cutover

```text
CURRENT  setup → existing vendor producer → zmx @ March fork / Zig 0.15.2
CHANGE   zmx task selects mise-managed Zig 0.16.0 → selected v0.8.1 fork base
PRESERVE embedded Ghostty task/version/compiler and vendor-reuse boundary
PRESERVE create-app-bundle → Contents/MacOS/zmx → existing signing lane
PRESERVE pane.zmxSessionID → TerminalRestoreRuntime → bundled zmx attach
PRESERVE running daemon and its socket/PTY; binary update does not kill it
CHANGE   newly created sessions use the new daemon from the bundled executable
RESULT   old sessions continue; future sessions use updated daemon behavior
```

The existing `.mise.toml` zmx build task owns compiler selection for zmx alone. The zmx dependency's ghostty-vt is distinct from AgentStudio's embedded Ghostty vendor; do not update both because they share a project name. Existing `scripts/vendor-worktree.sh` producer/reuse checks and bundle integrity checks remain the build boundary. A compiler/build failure stops PR 2 preparation; it does not trigger vendor hydration bypasses or change PR 1.

Supported upgrade matrix: new bundled client against the March daemon and new bundled client against the new daemon. The upstream client already sends old/new resize encodings; verify that behavior rather than adding a host compatibility shim. Existing opaque session identities and channel-scoped socket directories remain unchanged. New executable packaging never signals, kills, or respawns existing daemons as an upgrade step.

An old client against a new daemon is not declared a supported rollback path. Until its compatibility is proved, rollback must retain a known-compatible client or require an explicit owner-directed session transition; never silently terminate sessions to make rollback work. If an existing session cannot attach after upgrade, retain its identity/socket and surface the existing failed-attach state. Recovery is reattachment with a compatible binary, not allocating a replacement identity. Prove live upgrade using an existing daemon with content/process state before bundling the new client, plus new-session startup, attach/resize, prompt redraw, and failure preservation. Current artifact hashes/signatures and mixed-version runtime observations are required proof, not claims already established by source reading.

### PR 3 activity IPC boundary

PR 3 extends the existing internal zmx IPC boundary behind ZmxBackend. The minimum required behavior is source-owned output metadata, a current snapshot after connection/reconnection, and bounded delivery without terminal content or attach/resize effects. A snapshot-plus-coalesced subscription is the preferred candidate; the exact tags, payload encoding, daemon-instance representation, cadence, observer implementation and local schema are not selected merely because the review identified missing How.

```text
zmx inner PTY read
    → output sequence/time metadata
    → existing per-session IPC boundary
    → existing off-main activity/projection systems
    → historical activity persistence and prepared pane/tab indicators
```

The full PR3 design must answer session replacement, disconnect/reconnect, slow readers, source unavailability and restart without inventing process completion. Existing Info remains frozen, raw attach replay is not fresh output, and a metadata observer must not become a terminal leader or resize the session. These are necessary source constraints, not permission to build a new transport service or generic event framework.

Reuse the previous backend IPC design's internal helper boundary. Do not add speculative subscription state to PR1, extend an unrelated atom, or prebuild a storage adapter for a future protocol. The current sidebar projection should consume the existing fact now; PR3 later changes that input behind the same presentation ownership. Concrete protocol and persistence realization is required before PR3 planning, but it does not block PR1 organization.

### Prior backend IPC design to reuse

The existing [2026-06-13 zmx Backend IPC Design](/Users/shravansunder/Documents/dev/project-dev/agent-studio.sessions-in-sidebar/docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md) is a future backend track, not a shipped client. It refreshes an older March IPC design and proposes replacing probe/list/kill shell-outs with one-shot Unix-socket operations behind ZmxBackend. Preserve its internal/public boundary: no public zmx namespace, socket paths or output payloads in AgentStudio app IPC. Preserve pane identity and backend encapsulation.

That design deliberately defers protocol extensions, persistent control connections and output streaming; it warns that ordinary connected clients receive PTY broadcasts. The requested activity feature goes beyond that first transport-only slice. Reuse its client/protocol boundary rather than assuming a persistent metadata subscription already exists. Any activity observer must explicitly prevent attach/resize/input effects and unwanted output buffering. Current source's durable stored zmx identity supersedes the old document's claim that session names are derived from pane identity. The old document's transport details were unverified then; the pinned-source research supplies current evidence without upgrading it to implementation authority.

For PR3, metadata at zmx's inner PTY read is the stronger source because it precedes replay and survives loss of the Ghostty surface. A separate Ghostty extension remains outside the selected scope. PTY output can include shell echo and terminal protocol traffic: it proves bytes arrived, not semantic task progress or a changed final screen. The eventual PR3 source contract must retain that distinction.

## How the design is proved

| Specification | Owner / structural seam | Real boundary and proof |
| --- | --- | --- |
| R1,R2 | Shared controls, command catalog, surface dispatch | Native header width and actual key events; pure catalog tests alone cannot prove typing safety |
| R3–R6 | Canonical topology/pane state → existing projection | Real graph membership, pinned/unpinned moves, no association and changing arrangements; identity/duplicate checks |
| R7,R8 | Off-main projection sort stage | Matrix of field/direction/group/subgroup; assert unchanged group order and deterministic equal keys |
| R9a | Existing settled-line fact, lifecycle time ingress, adapter and detached worker | PR1 normal expiry, clock/time-zone change, hidden/resumed demand, future/missing evidence, and stale-candidate rejection |
| R9 | PR3 source + time projection + local persistence | Real PTY/redraw versus focus/scroll/restore, injected-clock edges and restart; later source design |
| R10,R11 | PR3 pane state + App tab projection + layer rendering | Individual acknowledgement, tab aggregation, renewed activity, reused rows, Reduce Motion and CPU traces |
| R12 | Existing Core migration/repository codecs | Upgrade a pre-pin database, preserve repo pins, default pane pins, restart round trip and failure containment |
| R13,R14 | Eager-derived admission/currentness + native broker | Overlapping input/removal/deadline races, demand suspend/resume, marker-scoped real sidebar performance |
| R15–R17 | Three scope boundaries and existing backend owners | PR 1 has no vendor dependency; PR 2 preserves real sessions under mixed versions; PR 3 provides metadata through internal IPC with source/reconnect proof |
| R6b | Existing shared header typography and row-layout alignment | Subgroup label begins at icon column; same font as sections, secondary gray; leaf rows unchanged |
| R6a,R18 | Existing window-sidebar and workspace-settings persistence owners | Saved None/Activity/off/descending survive restart and screen/group changes; absent-only defaults and old-mode migration |

No mock can establish Ghostty/zmx output coverage. In-process clock and sorting tests are appropriate for timing/ordering semantics; real terminal and native UI proof establish the cross-process and visual paths. The existing aggregate repository gate and architecture rules remain mandatory for subsequent implementation.
