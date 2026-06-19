# Notification Less-Spam Roll-Up Alert Design

Date: 2026-06-14
Status: reviewed and ready for plan creation

## Goal

Reduce notification noise by separating row history from ambient chrome.

The user should be able to tell the difference between:

- something that requires action or safety attention
- ordinary activity that is useful history but should not shout
- rows that have already been read

The product rule is:

- unread action-required rows show a red row dot
- unread safety/failure rows show an amber row dot
- unread activity rows show a blue row dot
- read rows show no row dot
- only action-required and safety rows roll up into numeric badges or tab dots
- activity never contributes to numeric rollups, pane inbox counts, worktree
  chips, global toolbar badges, or tab dots

## Terms

Use "read" only for canonical row state. Use "roll-up alert" for the
action/safety projection that feeds ambient chrome.

Do not use "attention" as the implementation term for this projection. The repo
already uses attended/observed/attention language for focus and visibility. User
facing copy may still say "needs attention"; code should prefer roll-up alert
or alert summary names.

| Term | Meaning |
| --- | --- |
| Read state | Canonical per-row `InboxNotification.isRead`. |
| Lane | Domain classification: `actionNeeded`, `safety`, or `activity`. |
| Row dot | Per-row unread indicator. Red, amber, or blue by lane. |
| Roll-up alert | Derived unread action/safety projection for badges and tab chrome. |
| Activity | History-only lane. Blue row dot only; no roll-up counts. |
| Scope filter | Repo/worktree handoff filter. Runtime-only unless separately requested. |
| Content mode | Mutually exclusive inbox lane mode: roll-up alerts, activity-only, or all lanes. |
| Row-state filter | Whether the surface shows unread rows only or read + unread rows. |

## Current-State Evidence

The repo already has the domain taxonomy this design needs.

- `InboxNotificationClaimLane` has `actionNeeded`, `safety`, and `activity`
  in `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationClaim.swift`.
- `InboxPromoter.lane(for:)` maps approval to `actionNeeded`, secure input /
  progress error / renderer unhealthy / persistence recovery / security event
  to `safety`, and unseen activity / command finished / bell / desktop
  notification / generic `agentRpc` to `activity`.
- `InboxNotificationAtom` currently exposes lane-agnostic unread counts:
  `globalUnreadCount`, `unreadCount(...)`, and
  `visiblePaneInboxUnreadCount(...)`.
- `InboxRow` currently renders one red unread dot for every unread row.
- `PaneInboxPresentation` and `MainSplitViewController` currently feed pane
  inbox chrome from visible unread counts, not lane-aware roll-up alerts.
- `MainWindowController` currently feeds the toolbar badge from
  `globalUnreadCount`.
- `SidebarSurfaceHost` and `WorkspaceNotificationCountProjection` currently
  feed worktree/sidebar chrome from all unread rows.
- `TabBarItem` and `CustomTabBar` currently have no notification dot field.
- `PaneInboxPresentationAtom` currently stores per-parent-pane filter mode in
  runtime memory only, with `.unread` / `.all` semantics.
- `InboxNotificationPrefsAtom` and `WorkspaceSettingsStore` persist grouping,
  sort, and bell preference; sidebar/pane content modes are not persisted
  today.

## Design Decisions

### 1. Canonical Notification Rows Stay Unchanged

`InboxNotification` remains the canonical row record:

- source context
- kind
- activity context
- claim key
- `isRead`
- `isDismissedFromPaneInbox`

No color, SF Symbol, badge text, tab-dot state, or roll-up count should be
stored on the row.

The existing `isRead` flag remains the suppressor for every dot:

- if `isRead == true`, the row has no red, amber, or blue row dot
- if `isRead == true`, the row contributes to no roll-up alert
- if `isRead == false`, dot and roll-up behavior are derived from lane

Marking a row read means "acknowledged/read", not necessarily "resolved". A
safety or action item may still describe a condition that needs external work,
but the notification dot/chrome disappears once the row is read.

### 2. Lane Projection Is Domain, Color Is Presentation

The existing `InboxNotificationClaimLane` is the lane vocabulary. Do not add a
second semantic lane enum. `InboxNotificationAtom` owns the public roll-up read
APIs used by app chrome; implementation may use a pure feature-local helper, but
consumers must not scan raw notification rows and re-derive lane semantics.

Projection should derive lane from canonical notification data:

1. Prefer `notification.claimKey?.lane`.
2. Fall back to an exhaustive mapping from `InboxNotificationKind` for legacy
   or global rows without claim keys.
3. Treat unknown future rows conservatively as roll-up alerts only after an
   explicit lane decision. Do not silently map unknowns to activity.

The projection may expose names such as:

- `InboxNotificationRollupAlertSummary`
- `InboxNotificationRollupAlertScope`

Views map the lane to color:

| Lane | Row dot | Roll-up alert |
| --- | --- | --- |
| `actionNeeded` | red | yes |
| `safety` | amber | yes |
| `activity` | blue | no |

Colors and icon choices stay in presentation code or `AppStyles`. Domain code
should not contain "red", "amber", or "blue".

### 3. Row Dots Are Not Row Colors

Rows should not receive lane-tinted backgrounds. The indicator is a small dot
near the timestamp cluster, matching the existing row rhythm.

Rules:

- unread action row: red dot
- unread safety row: amber dot
- unread activity row: blue dot
- read row: no dot

Rows stay dot-only visually: no row background tint and no row replacement icon.
The non-color cue is accessibility/help text, tooltips, and existing row text
context. Accessibility labels and tooltips should include lane and read state
where the surface exposes them, for example "Unread action required", "Unread
safety", "Unread activity", or "Read".

### 4. Roll-Up Alerts Drive Counts And Chrome

All numeric badges and ambient chrome that currently mean "something needs
attention" should consume roll-up alert summaries, not all unread rows.

Roll-up alert predicate:

```text
!notification.isRead
AND lane in { actionNeeded, safety }
AND scope matches the surface
AND pane inbox dismissal state allows the surface, when applicable
```

Activity rows never count.

Roll-up surfaces:

- global toolbar inbox badge
- repo/worktree row notification chip
- pane inbox badge/count
- pane management status surfaces that currently reuse worktree notification
  counts
- tab dot

Generic unread history may still be useful inside the full inbox list model,
but it must not feed chrome.

### 5. Pane Inbox Is Roll-Up Alert Count By Default

Pane Inbox chrome shows a roll-up alert count, not an all-unread count.

The Pane Inbox popover default content mode is roll-up alerts:

- action-needed
- safety

The Pane Inbox also needs an activity-only control. Unread activity rows shown
there use blue row dots. Activity-only mode is a discovery/log view; it still
does not contribute to the Pane Inbox badge and does not show an activity count.

The Pane Inbox also needs an all-lanes escape hatch so a user can see mixed
context without changing the meaning of badges. All-lanes mode may show action,
safety, and activity rows together, but activity still contributes no count.

The existing `.unread` / `.all` pane filter does not match the new product
model. Replace it with a content mode and a row-state filter:

- content mode: roll-up alerts by default, activity-only and all-lanes available
- row-state filter: unread-only by default, with read + unread available

`markAllRead` and any "read all" command must clear every dot in the active
scope: red action dots, amber safety dots, blue activity dots, pane badges,
global/worktree badges, and tab dots. Read-all does not dismiss rows from
history; it only changes canonical read state.

Read-all scope rule:

- repo/worktree scope filters narrow global inbox read-all writes
- pane read-all uses the pane-owner scope, including drawer children that belong
  to that Pane Inbox owner
- content mode and row-state filters are view filters only; they do not narrow
  read-all writes
- unscoped app-level "mark all read" acts on the whole workspace inbox
- "Clear Pane Inbox" may remain a separate pane-scope dismiss action that sets
  rows read and dismissed from Pane Inbox, but it must not be treated or labeled
  as read-all

When a user manually toggles a pane-dismissed row back to unread,
`isDismissedFromPaneInbox` must clear too. An unread row that remains dismissed
from the pane inbox creates invisible debt: it can be unread without being
discoverable from the pane surface that owns it.

### 6. Global Inbox Uses The Same Content Model

The global Inbox sidebar should use the same lane/content semantics as Pane
Inbox:

- default content mode: roll-up alerts
- activity-only button: shows activity rows with blue row dots
- all-lanes mode: shows action, safety, and activity rows together
- row-state filter: unread-only vs read + unread
- scope filters for repo/worktree remain separate from content modes

The user-facing control set should keep the toolbar compact:

- sort button
- row-state filter control
- roll-up alert content-mode button, default on
- activity-only button, using `dot.circle.viewfinder` or `scope` if it reads
  better in the running app
- all-lanes mode, either as a third segmented option or compact menu item
- grouping menu
- delete menu

The activity-only button must not show an activity count badge. If visual
emphasis is needed, it can use active/inactive styling only. This applies to
group headers and summary labels too: no activity-only numeric rollups.

The global toolbar badge remains a numeric roll-up alert count for this slice.
Presence-only toolbar chrome is a later product experiment, not part of this
design.

Chrome-driven inbox entry must explain the chrome. When entry is triggered by a
global toolbar badge, repo/worktree chip, Pane Inbox badge, or tab dot, the
surface opens with a temporary runtime override:

- content mode: `rollupAlerts`
- row-state filter: `unreadOnly`
- repo/worktree scope: preserved when the source chrome is scoped

This override does not overwrite the persisted browsing mode. If the user then
changes content mode or row-state inside the inbox surface, that explicit user
choice becomes the active persisted preference.

Pane content mode and pane row-state filter are single workspace-scoped
observable values. If more than one Pane Inbox popover is open in the same
workspace, changing the mode in one popover updates the others; there is no
per-parent-pane selection owner after the cutover.

### 7. Tab Dot Is Roll-Up Alert Only

Tabs may show a dot, but only for unread roll-up alerts.

Rules:

- unread action row in tab: red tab dot
- unread safety row in tab: amber tab dot
- both action and safety in tab: red wins
- only activity rows in tab: no tab dot
- all roll-up alert rows in tab are read: no tab dot
- clicking or activating the tab does not mark rows read by itself

The tab dot disappears when the underlying action/safety rows become read. It
does not disappear just because the tab was clicked.

Stale owner rule:

- global toolbar: stale roll-up alert rows still count until read
- repo/worktree sidebar: stale roll-up alert rows still count when the
  denormalized worktree/repo still exists, and clicking routes to the global
  Inbox with that scope filter rather than trying to focus a dead pane
- pane inbox: closed panes own no live pane badge; stale rows remain in global
  history until read
- tab bar: closed tabs own no live tab dot; stale rows remain in global history
  until read
- stale activity never migrates into another tab's chrome and never counts

Live tab-dot projection follows the current pane graph, not only the
notification's denormalized `tabId` captured at emit time. If a pane with unread
roll-up alerts moves to another live tab, the dot moves with the pane. Stored
tab metadata is history fallback only after the live pane owner is gone.

### 8. Sort Button Rotation

The sort button should visually communicate the current ordering.

Rules:

- state is still `InboxNotificationSort.newestFirst` or `.oldestFirst`
- the button icon rotates 180 degrees when the order toggles
- the animation should be short and state-driven, not a one-off side effect
- tooltip and accessibility label should reflect the next action or current
  state clearly
- changing sort should preserve the selected/focused row when possible

This is presentation state. It does not require notification model changes.

### 9. Persistence Scope

Row read state must persist across restart.

This is already the intended model because `isRead` and
`isDismissedFromPaneInbox` are persisted through the notification store and
SQLite repository. This design requires explicit tests proving:

- unread row -> mark read -> save -> reload -> no dot and no roll-up alert
- read row -> toggle unread -> save -> reload -> dot restored by lane
- pane dismissal state still round-trips

Content and row-state filter persistence:

- persist global inbox content mode per workspace
- persist global inbox row-state filter per workspace
- persist pane inbox content mode per workspace, not per parent pane
- persist pane inbox row-state filter per workspace
- do not persist transient repo/worktree pending filters
- do not persist flashing rows, focus, popover open state, or command handoffs

The safest persistence owner for user preferences is `InboxNotificationPrefsAtom`
plus `WorkspaceSettingsStore`, because grouping/sort/bell already live there.
Notification history persistence remains in `InboxNotificationStore`.

Add the settings fields with tolerant decoding and defaults, without resetting
existing workspace settings:

- `globalInboxContentMode`, default `rollupAlerts`
- `globalInboxRowStateFilter`, default `unreadOnly`
- `paneInboxContentMode`, default `rollupAlerts`
- `paneInboxRowStateFilter`, default `unreadOnly`

Keep the workspace settings schema at version 1 unless the implementation finds
an existing schema-version migration pattern that is already required for this
file. Missing fields must decode to defaults. Unknown future fields must not
quarantine or reset otherwise-valid settings.

`PaneInboxPresentationAtom` remains a presentation/request owner only after the
cutover. It may track pending popover requests and parent-pane targeting, but it
must not own content mode or row-state selection. `InboxSidebarState.pendingFilter`
remains the runtime repo/worktree handoff only.

### 9a. Phase 0 Producer Correctness

The June 10 inbox correctness work is a phase-0 dependency for this design:
`docs/plans/2026-06-10-inbox-notification-correctness.md` must be folded into
this implementation slice or completed before roll-up projection and chrome work
ship. The roll-up design relies on the producer writing correct canonical
read/dismiss state.

### 9b. Projection Sequencing

Roll-up and dot projection runs after row production has settled canonical read
and dismissal state:

```text
event classification
  -> promoter coalescence / strongest-lane merge
  -> auto-clear and read/dismiss decision
  -> row persisted or updated
  -> row-dot and roll-up alert projection
```

Do not ship roll-up semantics while the producer can still write unintended
unread state for observed/attended activity.

### 10. Coalescence And Upgrade Behavior

Existing promoter behavior lets stronger lanes win display content within a
mergeable pane/session.

Keep that rule:

- row dot follows the strongest current lane
- action-needed is stronger than safety
- safety is stronger than activity for roll-up purposes
- activity upgraded to action-needed in the same session becomes a roll-up alert
  immediately
- no duplicate sibling row is required for an in-session action-needed upgrade
- safety remains outside activity-session coalescence unless a future exact
  semantic guard is explicitly designed; safety events may create separate rows
- filter membership changes immediately when the row lane changes

This means a blue activity row can become red when an action-needed event
coalesces into it. Safety rows are still roll-up alerts, but the no-duplicate
in-session guarantee does not apply to unrelated safety events.

If a stronger roll-up-eligible event coalesces into a row that was already read,
the merge contract must reopen that row to unread and clear pane-inbox
dismissal. The earlier read acknowledged the earlier claim state; the new
stronger event is fresh information and must surface. This is the only case
where a read row regains a dot without the user explicitly toggling it unread.

### 11. Security And Trust Boundaries

This design is not a security boundary.

Do not let web content, bridge callers, plugins, MCP tools, or terminal output
choose lane, color, or roll-up behavior directly. These remain internal product
classifications derived by `InboxNotificationRouter` and `InboxPromoter`.

Relevant trust boundaries:

- Bridge `inbox.post` receives untrusted `title` and `body`; pane identity is
  bound server-side by `BridgePaneController`.
- Runtime and terminal events may carry untrusted titles, output-derived
  activity, command facts, progress payloads, secure-input facts, renderer
  health, and security-event strings.
- Tool/plugin/MCP/subagent approval requests may carry untrusted approval
  summaries. Approval rows may classify as `actionNeeded`, but that lane comes
  from the internal event kind, never from caller-provided summary text.
- Lane/color/count projection must not grant or deny access. It only affects UI
  presentation.
- Existing local inbox history may persist notification text. This design does
  not add a new redaction or at-rest secrecy model.

Input-size and exposure contract:

- notification title/body strings derived from bridge, runtime, terminal,
  approval, tool/plugin/MCP/subagent, or security-event payloads must be bounded
  before promotion and persistence
- oversized payloads should be truncated or summarized at the feature boundary,
  not stored in full and clipped only by the view
- approval and security-event rows may still describe the condition, but they
  should not persist raw unbounded payload text as the row body
- approval/security/tool-derived text must also be bounded or summarized before
  diagnostic emission
- lane/color/count projection must never depend on caller-provided text content

Retention contract:

- activity-only rows must not evict unread action/safety rows while read rows or
  unread activity rows are available to evict
- retention order is: oldest read rows first, then oldest unread activity rows,
  then unread roll-up alerts only as a last resort when the cap is otherwise
  impossible to maintain
- one shared feature-owned retention-priority policy must be reused by
  `InboxNotificationAtom` and `InboxNotificationSQLiteRepository`
- the same retention order must cover append, upsert, snapshot replace, and
  legacy-import materialization paths
- if the store must evict unread roll-up alerts because every retained row is an
  unread roll-up alert and the cap is exceeded, emit a diagnostic event/log so
  this is visible during testing
- retention diagnostics must be aggregate-only and OTLP-safe: counts, lane mix,
  and source category are allowed; row title/body, raw UUID, path, command,
  secret id, consumer id, tool output, and payload text are not allowed
- this design accepts the residual availability risk that a flood consisting
  entirely of unread roll-up alerts can still force oldest unread roll-up alert
  eviction as a last resort

Security non-goals:

- no change to bridge auth or RPC routing
- no new caller-provided notification severity API
- no terminal-output content parsing
- no attempt to classify generic `agentRpc` as action-required without a typed
  payload
- no change to local persisted notification body secrecy

## Ownership Boundaries

### Feature Domain

Owned by `Features/InboxNotification`:

- lane projection from canonical rows, using existing `InboxNotificationClaimLane`
- public roll-up alert summary APIs on `InboxNotificationAtom`
- content mode enums
- row-dot semantics
- inbox list filtering by lane/read state
- persisted inbox preference model

### App Shell

Owned by `App/Windows` and `App/Panes`:

- toolbar badge consumes global roll-up alert summary
- worktree/sidebar chip consumes worktree roll-up alert summary
- tab bar consumes tab roll-up alert summary
- Pane Inbox presentation closure consumes pane roll-up alert summary

The app shell should not re-derive notification lane semantics. It asks the
feature-owned projection for a summary.

Tab notification chrome stays App-local at the tab rendering seam. App
composition resolves the feature-owned roll-up candidates against the current
pane graph before `TabBarAdapter.refresh`, then injects an App-local render token
into `TabBarItem`, for example `none`, `safety`, or `actionNeeded`.
`CustomTabBar` renders the dot only; it does not import inbox feature types,
query inbox state, or decide whether activity counts. Core tab layout/state
models stay notification-free.

### Core

Core UI seams receive primitive counts, callbacks, and type-erased popover
content. They do not import inbox feature types.

If Core pane-inbox names still say "unread" for badges, use a hard cutover to
"roll-up alert" naming rather than keeping a compatibility shim. The
post-cutover Core pane-inbox contract should not expose
`pruneFilterModes`-style filter ownership; filter selection belongs to
workspace-scoped inbox preferences.

`WorkspaceSettingsStore` is the only persistence owner for inbox preferences.
`InboxNotificationStore` owns row history and collapsed groups. Any legacy
notification preference payload should be import-only or removed in the same
cutover, not kept as a second write path.

`WorkspaceSettingsStore` is the existing sanctioned settings-persistence
composition exception for inbox preferences. Do not use this as permission to
add new Core UI or domain dependencies on inbox feature types. If implementation
needs new persisted preference value types, keep them aligned with the existing
settings-store pattern or introduce one shared contract before widening the
boundary.

### Shared Components

Keep the colored dot primitive feature-local first. Move it to
`SharedComponents` only if another feature uses the same semantic contract, not
just because it draws a circle.

## API / Naming Direction

Hard cut over roll-up naming rather than layering compatibility names.

Suggested names:

- `InboxNotificationRollupAlertSummary`
- `InboxNotificationRollupAlertScope`
- `rollupAlertCount(...)`
- `globalRollupAlertCount`
- `visiblePaneInboxRollupAlertCount(...)`
- `WorkspaceNotificationRollupProjection`
- `PaneInboxRollupBadge`

Keep row-local names:

- `isRead`
- `markRead`
- `markAllRead`
- `toggleReadState`
- `dismissFromPaneInbox`

Do not rename row read state to attention.

## Alternatives Considered

### Reuse `globalUnreadCount` And Filter At Call Sites

Rejected.

This keeps old names with new meaning and makes it too easy for activity to leak
back into badges.

### Store Roll-Up Alert Counts

Rejected.

Counts are derived from canonical rows. Storing them creates a second source of
truth and repeats the unread/count drift risk this change is meant to remove.

### Add Activity Dots To Tabs

Rejected by product decision.

Blue activity is a row dot only. Tabs show red/amber roll-up alert dots only.

### Persist Pane Inbox Mode Per Parent Pane

Rejected for the first design slice.

Per-pane persistence adds state churn and makes temporary drawer behavior feel
sticky. Persist one pane inbox content mode and row-state preference per
workspace instead.

### Treat Generic `agentRpc` As Action-Required

Rejected.

Generic bridge inbox posts remain activity until a typed payload or event
actually carries action-required intent.

## Validation Strategy

The implementation plan should use red/green proof. Current tests that assert
activity increments generic unread rollups should fail before the semantic
cutover.

### Unit Proof

- lane projection derives action/safety/activity from claim lane
- fallback mapping covers rows without claim keys
- roll-up summary includes action/safety and excludes activity
- read rows produce no row dot and no roll-up contribution
- mark-all-read/read-all clears action, safety, and activity dots
- row-dot presentation maps unread lanes to red/amber/blue
- tab summary chooses red over amber when both exist
- tab summary produces no dot for activity-only rows
- content mode default is roll-up alerts
- activity-only mode shows activity rows without any activity count
- all-lanes mode shows action, safety, and activity together without changing
  roll-up counts
- sort state drives rotated icon state
- stronger action/safety coalescence into a read row reopens that row to unread
- retention evicts read rows before unread activity rows, and unread activity
  rows before unread roll-up alerts
- title/body bounding applies before promotion and persistence

### Persistence Proof

- read/dismiss flags round-trip through SQLite
- toggled unread/read state round-trips
- global inbox content mode and row-state filter round-trip through workspace
  settings
- pane inbox content mode and row-state filter round-trip through workspace
  settings
- old settings payloads without the new fields decode with defaults and do not
  reset existing grouping/sort/bell preferences
- `WorkspaceSettingsStoreTests` prove positive preference ownership while
  `InboxNotificationStoreTests` prove notification history persistence does not
  grow a second preference write path
- transient pending repo/worktree scope filters do not persist

### Integration Proof

- bridge `inbox.post` remains sanitized, rate-limited, and pane-bound
- runtime activity rows still append/coalesce as activity
- activity rows do not affect global, worktree, pane, or tab roll-up chrome
- explicit action/safety events still roll up
- activity upgraded to action-needed changes dot and roll-up membership
- activity upgraded to action-needed after a row was read reopens the row
- safety rows remain roll-up alerts without relying on activity-session
  coalescence
- Pane Inbox default view excludes activity and counts only roll-up alerts
- pane-dismissed unread roll-up rows stop counting for that Pane Inbox but still
  count for global/worktree/tab summaries while their owner is live
- stale tab/pane owners do not render live dots, while stale global/worktree
  roll-up history remains visible until read
- chrome-driven navigation opens roll-up alert rows in `rollupAlerts` +
  `unreadOnly` even when persisted browsing mode is activity-only or all-lanes
- tab-dot projection follows live pane ownership after a pane moves between tabs

### UI / Mounted Proof

- global Inbox rows show red/amber/blue dots by lane
- read/toggled rows lose every dot
- Pane Inbox badge ignores activity-only rows
- tab dot appears only for action/safety and never for blue activity
- sort button rotates 180 degrees on toggle
- accessibility labels/tooltips expose lane and read state, so dots do not rely
  on color alone
- automated tab-dot proof is mandatory: either adapter-level `TabBarItem` render
  token assertions plus Peekaboo visual proof, or mounted `CustomTabBar` render
  checks if the existing test seam supports them without broad harness changes

### Visual Proof

Use PID-targeted Peekaboo on a debug build, following the repo's native UI
verification policy.

Visual acceptance:

- red, amber, and blue row dots are visible but do not tint row backgrounds
- blue activity rows are discoverable in activity-only mode
- no activity count appears in roll-up badges, group headers, or activity-only
  controls
- tab dot is absent for activity-only tabs
- all dots disappear after rows are marked read
- sort icon flip is visible and does not cause layout jump

Victoria/Peekaboo proof must target the same debug run:

```text
mise run observability:up
  -> mise run run-debug-observability -- --detach
  -> mise run verify-debug-observability
  -> read tmp/debug-observability/latest-observability.env
  -> extract AGENTSTUDIO_OBSERVABILITY_PID
  -> peekaboo see --app "PID:$AGENTSTUDIO_OBSERVABILITY_PID" --json
```

If the state file reports `already_running`, quit or reuse only the confirmed
current debug PID after rerunning verification. If launch or Peekaboo capture
fails for environment reasons, record that as a visual-proof blocker unless
automated mounted coverage proves the same UI behavior and the blocker is
clearly outside the changed code path.

Suggested local proof commands for the implementation plan:

```bash
mise run test -- --filter "InboxNotification"
mise run test -- --filter "PaneInboxPresentation|DerivedTerminalActivityNotificationRegression"
mise run test -- --filter "WorkspaceNotificationCountOwnership|MainWindowControllerInboxToolbarButton|WorkspaceSettingsStore|InboxNotificationStore|TabBar|PaneInboxPresentation"
mise run test
mise run lint
```

UI verification should then use `mise run build` and PID-targeted Peekaboo, per
the repo's visual verification policy.

## Known Test Updates

Existing tests likely need semantic updates:

- `InboxNotificationDerivedActivityTests`
- `DerivedTerminalActivityNotificationIntegrationTests`
- `DerivedTerminalActivityNotificationRegressionTests`
- `InboxPromoterTests`
- `InboxNotificationAtomTests`
- `WorkspaceNotificationCountOwnershipTests`
- `PaneInboxPresentationTests`
- `PaneInboxNotificationPopoverTests`
- `PaneInboxPresentationAtomTests`
- `InboxNotificationSidebarViewTests`
- `MainWindowControllerInboxToolbarButtonTests`

New tests should be added near:

- `InboxNotificationAtomTests` for roll-up summaries
- `InboxRowTests` for lane dot mapping
- `InboxNotificationListModelTests` for content modes
- `WorkspaceSettingsStoreTests` for persisted filters
- `InboxNotificationStoreTests` for negative preference non-ownership
- `TabBarAdapterTests` for tab roll-up dot data flow
- `CustomTabBar`/mounted tab tests for tab dot rendering, if the existing test
  seam can mount it without broad AppKit harness changes

Red tests to expect before the cutover:

- `WorkspaceNotificationCountOwnershipTests`: activity worktree counts should
  change from `1` to `0`.
- `MainWindowControllerInboxToolbarButtonTests`: toolbar badge should stay
  hidden for activity-only rows.
- `PaneInboxNotificationPopoverTests`: `.unread` / `.all` behavior should be
  replaced by content-mode plus row-state cases.
- `InboxNotificationAtomTests`: `markAllRead` should clear blue activity dots as
  well as red/amber roll-up dots.

## Open Questions For Plan Creation

These are planning inputs, not blockers for the design direction:

1. Exact SF Symbol for activity-only control: start with
   `dot.circle.viewfinder`; use `scope` only if it reads better visually.
2. Exact tab-dot placement in `CustomTabBar`, given the existing title mask,
   close button, and shortcut label.

## Non-Goals

- No new notification ingestion path.
- No bridge API change.
- No content parsing of terminal output.
- No activity roll-up count.
- No tab blue activity dot.
- No row background tinting by lane.
- No compatibility shim keeping old unread-count names for roll-up chrome.
- No broad redesign of notification source text or row hierarchy.

## Next Step

Create an implementation plan from this reviewed spec.
