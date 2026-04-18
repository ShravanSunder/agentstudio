# Notification Inbox — Design Spec

**Status:** Draft · Design Mode
**Linear:** [LUNA-361](https://linear.app/askluna/issue/LUNA-361/show-agent-and-cli-notifications-in-notification-center)
**Related:** LUNA-355 (Ghostty host event consumers)
**Date:** 2026-04-17
**Owner:** Shravan Sunder

---

## 1. Problem

Agent and CLI work (Claude Code, Codex, other agents, terminal processes) finishes asynchronously while the user is focused elsewhere — a different tab, a different pane, a different drawer. Today those completions are invisible: the pane updates, but nothing surfaces the fact that *something now wants your attention*.

We need a notification system that:

- Surfaces notification-worthy events without being a transient distraction. **No toasts, no banners, no auto-dismissing popups.** The user consults notifications on their own schedule.
- Provides a durable log (Inbox) that can be revisited, searched, and navigated.
- Has an explicit routing contract in code and docs so the set of events that produce notifications is legible, not implicit.
- Integrates with the existing sidebar per-worktree bell badge (already rendering `🔔 0`) as the per-worktree unread count.

## 2. Non-goals

- **macOS Notification Center (UNUserNotificationCenter)** — out of scope for v1. Everything is in-app. System-level notifications may follow in a later ticket.
- **Push to remote devices.**
- **Email/Slack fan-out** of notifications.
- **Configurable per-event routing UI.** The routing contract is code-level in v1; settings come later if needed.

## 3. Surfaces

Three persistent surfaces. None transient.

```
┌──────────────────────────────────────────────────────────────────┐
│ Existing sidebar toolbar:                                        │
│   [show/hide sidebar]  [🔔 3]                                    │
│                         ^ new inbox icon, next to the existing  │
│                           show/hide sidebar button                │
│                           • red dot or count when unread > 0     │
│                           • click toggles Inbox Layer (same ⌘I)  │
│                                                                  │
│  Sidebar (worktrees, default):                                   │
│   agent-studio · drawer-improvements  +447 -103 ↑0 ↓0 🔔 3       │
│   agent-studio · zmx-ipc              +0   -0  ↑0 ↓0 🔔 0       │
│                                                 ^ per-worktree    │
│                                                   unread count   │
│                                                                  │
│  Sidebar (inbox, ⌘I active):                                     │
│   replaces worktree list — see §6                                │
│                                                                  │
│                                                                  │
│  Drawer strip (per drawer, at bottom of each drawer):            │
│   [finder] [other] [other]   │   [🔔 3]                          │
│                           divider   ^ rightmost slot,            │
│                                     count = unread in this       │
│                                     drawer's panes               │
└──────────────────────────────────────────────────────────────────┘
```

### 3.1 Global Inbox (sidebar, ⌘I)

- **Scope:** all notifications across all tabs/panes/drawers in the workspace.
- **Surface:** replaces the worktree list in the sidebar. Sidebar is one view at a time; ⌘I and ⌘S switch between them.
- **Toolbar entry point:** a new bell icon in the existing sidebar toolbar, next to the show/hide sidebar button. Shows a red dot (v1 default) or optional count when unread > 0. Clicking it toggles the Inbox Layer (same effect as ⌘I).
- **Dismissal model:** read-state only — nothing is removed when you act on it. Inbox is the log of record.

### 3.2 Drawer Inbox (popover, ⌘⇧I)

- **Scope:** notifications for panes attached to **the drawer of the currently focused pane**. If focus is not on a layout pane with a drawer (e.g., focus is on a non-drawer pane, or no drawer exists), ⌘⇧I is a no-op.
- **Surface:** popover anchored on a bell icon placed as the rightmost icon in the drawer's icon strip, after a divider that separates it from the existing icons (finder, editor, etc.).
- **Indicator:** numeric unread count on the bell icon.
- **Dismissal model:** true dismiss — acting on an item removes it from the drawer popover. Same item remains visible in the global Inbox (marked read).

### 3.3 Per-worktree bell badge

- Already rendering in the sidebar row (`🔔 N`). Continues to show `0` when there are no unread notifications (existing behavior).
- Reads `NotificationInboxAtom.unreadCount(forWorktreeId:)` off the same underlying data.
- Stretch (deferred): click the pill opens global Inbox with search pre-filled to the worktree name.

## 4. Data model

### 4.1 `Notification` record

```swift
struct Notification: Identifiable, Sendable, Codable {
    let id: UUID                       // stable, assigned at emit
    let timestamp: Date                // emit time (wall clock)
    let kind: NotificationKind
    let title: String                  // one-line, required
    let body: String?                  // optional detail line
    // Denormalized source context (frozen at emit time so history
    // reads correctly if pane/worktree is later closed):
    let paneId: UUID?                  // for click-through routing
    let tabId: UUID?
    let repoId: UUID?
    let repoName: String?              // for display
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
    // State:
    var isRead: Bool                   // global inbox read state
    var isDismissedFromDrawer: Bool    // drawer popover state
}

enum NotificationKind: String, Sendable, Codable {
    case agentDesktopNotification     // Ghostty OSC 9/777
    case bellRang                     // Ghostty bell
    case commandFinished              // Ghostty command completion, gated
    case agentRpc                     // Bridge RPC inbox.post
    case approvalRequested            // ArtifactEvent.approvalRequested
    case securityEvent                // filtered SecurityEvent subset (see §7)
}
```

**Design note: denormalized context.** We freeze repo/worktree/branch names at emit time rather than looking them up on render. A notification from a pane that was later closed still displays coherent information. Reconciliation on click-through uses `paneId` and degrades gracefully if the pane is gone.

### 4.2 Dismissal states — two independent flags

| Action | `isRead` | `isDismissedFromDrawer` |
|---|---|---|
| Focus source pane (any means) | `true` | `true` |
| Click in global inbox / Enter | `true` | `true` (consistent) |
| Click in drawer popover | `true` | `true` |
| Space in global inbox (toggle) | flips | unchanged |
| Explicit "dismiss" in drawer | unchanged | `true` |
| "Mark all as read" in inbox | `true` | unchanged |

**Rule:** focusing the source pane clears both because "I've dealt with it" is a stronger signal than either UI surface's local dismissal.

### 4.3 Atoms and persistence

Feature-scoped. Everything lives under `Features/NotificationInbox/` — no Core placement. Core views that need the data (e.g., `DrawerIconBar`) receive it as props through existing wrapper seams (see §10.3). This respects the `Core → never imports Features` rule.

Two atoms, one store.

#### `NotificationInboxAtom`

Path: `Features/NotificationInbox/State/NotificationInboxAtom.swift`
Role: canonical mutable state for the notification log. `@Observable @MainActor`, `private(set)` reads, mutation via methods.

```swift
@MainActor @Observable
final class NotificationInboxAtom {
    // State
    private(set) var notifications: [Notification]

    // Derived reads
    func unreadCount(forPaneId: UUID) -> Int
    func unreadCount(forWorktreeId: UUID) -> Int
    func unreadCount(forTabId: UUID) -> Int
    func unreadCount(forDrawerPaneIds: [UUID]) -> Int
    var globalUnreadCount: Int { get }

    // Mutations
    func append(_ notification: Notification)
    func markRead(id: UUID)
    func markRead(paneId: UUID)            // clears all for a pane
    func markAllRead()
    func dismissFromDrawer(id: UUID)
    func dismissFromDrawer(paneId: UUID)
    func toggleReadState(id: UUID)
    func clearReadHistory()
    func clearAll()
}
```

#### `NotificationInboxLayerAtom`

Path: `Features/NotificationInbox/State/NotificationInboxLayerAtom.swift`
Role: active/inactive state of the Inbox Layer (sidebar mode + keyboard layer). Peer of `ManagementModeAtom`.

```swift
@MainActor @Observable
final class NotificationInboxLayerAtom {
    private(set) var isActive: Bool   // true when sidebar is showing the Inbox
    func toggle()
    func activate()
    func deactivate()
}
```

#### Notification inbox view prefs (on `UIStateAtom`)

View preferences live on the existing `UIStateAtom` — they are UI state, not log data, and fit the atom already described in `AGENTS.md` as holding "expanded groups, colors, filter state." Adds:

```swift
struct NotificationInboxPrefs: Codable, Sendable, Equatable {
    var grouping: NotificationInboxGrouping = .none   // .none | .byRepo | .byPane | .byTab
    var sort: NotificationInboxSort = .newestFirst    // .newestFirst | .oldestFirst
    var bellEnabled: Bool = false                     // controls bellRang routing (§7)
}

// on UIStateAtom (in Core — existing atom, adds one property slice):
private(set) var notificationInbox: NotificationInboxPrefs
func setNotificationInboxGrouping(_ grouping: NotificationInboxGrouping)
func setNotificationInboxSort(_ sort: NotificationInboxSort)
func setNotificationInboxBellEnabled(_ enabled: Bool)
```

The grouping/sort enums live in the feature slice (`Features/NotificationInbox/State/`) and are referenced by `UIStateAtom` via the pref struct. Because `UIStateAtom` is in Core, the enum types must also be Core-safe — they are simple `Codable` enums with no feature imports, so we place the enum declarations in `Core/Models/NotificationInboxTypes.swift` (pure types; no logic; no Features import needed). The atoms themselves remain in the feature slice.

#### `NotificationInboxStore`

Path: `Features/NotificationInbox/State/NotificationInboxStore.swift`
Role: persistence wrapper over `NotificationInboxAtom`. One store per persistence boundary; this store wraps exactly one atom. Owns file I/O, debounced saves, schema versioning.

```swift
@MainActor
final class NotificationInboxStore {
    let atom: NotificationInboxAtom
    init(atom: NotificationInboxAtom, fileURL: URL, clock: any Clock<Duration> = ContinuousClock())
    func load() throws            // called at boot
    func save() async throws      // called on debounced mutation

    // Internal: subscribes to atom via Observation.withObservationTracking
    // and triggers debounced save on any mutation.
}
```

- File: `~/Library/Application Support/AgentStudio/<workspaceId>/notification-inbox.json`
- Save cadence: debounced ~500ms after mutations (injected clock; matches existing stores)
- Retention: cap **1000 entries per workspace**, evict oldest-first at append time. Provisional.

#### Registration

Feature atoms cannot be registered in `AtomRegistry` (which is in `Infrastructure/` and must not import Features). Instead, `NotificationInboxAtom` and `NotificationInboxLayerAtom` are instantiated in the app composition root (`App/Boot/`) and passed into the feature's views/routers via constructor injection. Views that live outside the feature slice (e.g., `Features/Sidebar/`) receive read-only references to `NotificationInboxAtom` through the same composition path. `NotificationInboxStore` is instantiated in the same boot path as `WorkspaceStore`/`RepoCacheStore`/`UIStateStore` and calls `load()` at boot.

## 5. Inbox Layer

The Inbox is not just a view — it is a **layer**, mirroring the existing Management Mode pattern. When active, it owns a scoped keyboard layer and a CommandBar scope.

### 5.1 Activation model

```
Sidebar state          Keyboard layer
─────────────────────────────────────────────────────
Worktrees (default)    App default shortcuts
⌘I toggles on          Inbox Layer keymap active
⌘I toggles off         App default shortcuts
⌘S (always)            Worktrees sidebar, App default shortcuts
```

`NotificationInboxLayerAtom.isActive` drives both the sidebar view and the keyboard layer. The CommandBar reads this atom directly to decide when to expose `.inbox`-scoped commands. `WorkspaceFocusDerived` is stateless and unchanged — it does not participate in layer tracking.

### 5.2 CommandBar integration

Add `CommandBarScope.inbox`. Behavior:

- **Fresh ⌘P while Inbox Layer is active:** CommandBar opens with `.inbox` as the default scope. Shows inbox-scoped actions first.
- **CommandBar already open when ⌘I fires:** CommandBar stays open; the user's current scope selection is preserved (⌘I does not override scope). The Inbox Layer activates underneath.
- **CommandBar open, Inbox Layer inactive, user manually picks `.inbox` scope:** valid — `.inbox` is always pickable. Activating the scope does not activate the Inbox Layer (scope and layer are independent).

Inbox-scoped actions:

- Mark all as read
- Clear read history
- Clear all notifications (with confirmation)
- Change grouping → None / Repo / Pane / Tab
- Toggle sort order
- Enable bell notifications / Disable bell notifications
- Return to worktree sidebar (⌘S)

### 5.3 Inbox Layer keymap

Only active when `NotificationInboxLayerAtom.isActive && sidebarHasFocus`.

```
⌘I               toggle Inbox Layer on/off
⌘S               switch sidebar to worktrees (always, from any state)

Inside the layer:
⌥F               focus search field
⌥G               toggle grouping menu open/closed
⌥S               toggle sort (newest ↔ oldest)

Navigation:
↓ / ↑            next / prev notification row
⌥↓ / ⌥↑          next / prev group (lands on first item of group,
                 skipping group header)
⌘↑ / ⌘↓          first / last notification

Actions:
Enter  or  →     jump to source pane + mark read
Space            toggle read/unread without jumping
Esc              if search active → clear search;
                 else → return focus to main content (layer stays open)

Group menu open state:
⌥G or Esc        close/cancel (no change)
↓ / ↑            change selection
Enter            commit selection
```

Headers (group labels) are never focus stops for ↓/↑ — arrow keys skip between item rows only. ⌥↓/⌥↑ provides the group-level jump.

Neither ⌘I nor ⌘S dismisses the CommandBar if it is open (see §5.2).

## 6. Inbox panel layout

```
┌─ Inbox ⌘I ─────────────────────────────────┐
│ [ 🔍 Search...                ]  [⇅] [☰]   │ ← header: search + sort + grouping
├─────────────────────────────────────────────┤
│ ● Codex done                         2m     │ ← line 1: dot + title + time
│   agent-studio · drawer-improvements        │ ← line 2: repo · worktree/branch
│   exit 0 · 4m 12s                           │ ← line 3: body, dim, optional
├─────────────────────────────────────────────┤
│ ● Build failed (exit 1)             11m     │
│   agent-vm · master                         │
├─────────────────────────────────────────────┤
│   Bell                              18m     │ ← read: no dot, title dim
│   agent-studio · zmx-ipc                    │
└─────────────────────────────────────────────┘
```

**Row anatomy:**

- Line 1: unread dot (●) + title + relative time (aligned right)
- Line 2: `<repo> · <worktree>` — omit branch suffix if branch name matches worktree name, else `<repo> · <worktree> / <branch>`
- Line 3: body snippet (only if `body` is non-empty), single line, dim

**Group headers (when grouping is active):**

```
▾ agent-studio                        ● 3     ← group header, non-focusable
    ● Codex done                    2m
      drawer-improvements
    ● Build failed                 11m
      drawer-improvements
      Bell                         18m
      zmx-ipc
```

For **By tab** grouping, panes appear as indented sub-headers under the tab (non-collapsible, non-focusable):

```
Tab: main-api                          ● 4
  terminal
    ● Codex done                    2m
      Build failed                 18m
  claude
    ● Codex done                   5m
    ● Bell                        11m
Tab: docs                              ● 1
  terminal
    ● Codex done                   6m
```

**Controls (header right side):**

- `[⇅]` — sort toggle button (⌥S). Icon flips between newest-first and oldest-first.
- `[☰]` — grouping button (⌥G). Opens dropdown: None, By repo, By pane, By tab.

**Empty state:** single centered message, "No notifications yet."

**Search:** filter-as-you-type across title, body, repo name, worktree name, branch name. Substring match, case-insensitive. No fuzzy matching in v1 (see §14).

## 7. Event routing contract

The explicit "which events notify" table. This is the routing contract the ticket requires to be legible in code.

| Source event | Notify? | `NotificationKind` | Gating rule |
|---|---|---|---|
| `GhosttyEvent.desktopNotificationRequested` (OSC 9/777) | **Yes** | `agentDesktopNotification` | Always |
| `GhosttyEvent.bellRang` | User setting | `bellRang` | Only when `UIStateAtom.notificationInbox.bellEnabled == true`; default `false` |
| `GhosttyEvent.commandFinished(exitCode, duration)` | Conditional | `commandFinished` | Only if source pane is not currently focused AND `duration ≥ 10s` |
| Bridge RPC `inbox.post` (new method) | **Yes** | `agentRpc` | Always; fire-and-forget JSON-RPC notification (no `id`) |
| `ArtifactEvent.approvalRequested` | **Yes** | `approvalRequested` | Always |
| `SecurityEvent.networkEgressBlocked` | **Yes** | `securityEvent` | Always |
| `SecurityEvent.filesystemAccessDenied` | **Yes** | `securityEvent` | Always |
| `SecurityEvent.secretAccessed` | **Yes** | `securityEvent` | Always |
| `SecurityEvent.processSpawnBlocked` | **Yes** | `securityEvent` | Always |
| `SecurityEvent.sandboxHealthChanged(healthy: false)` | **Yes** | `securityEvent` | Only on transition to `false` |
| `SecurityEvent.sandboxStarted` / `.sandboxStopped` / `.sandboxHealthChanged(healthy: true)` | **No** | — | Lifecycle, not alert |
| `FilesystemEvent.*` (branch, diff, files changed) | **No** | — | Status, not notification |
| `GhosttyEvent.progressReportUpdated` | **No** | — | Already lossy, not user-facing |
| Any other runtime event | **No** | — | Default deny |

**New Bridge RPC method shape** (additive; minimal surface):

```json
{
  "jsonrpc": "2.0",
  "method": "inbox.post",
  "params": {
    "title": "Claude Code finished",
    "body": "3 files changed, 142 lines"
  }
}
```

No `id` (notification, not request). `paneId` is inferred from the originating bridge pane context at RPC receive time — agents cannot spoof notifications from other panes. If the payload contains a `paneId` field, it is ignored.

## 8. Architecture

### 8.1 Component diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ Sources                                                          │
│                                                                  │
│  Ghostty (CLI)                      Bridge (Agent panes)         │
│    │ OSC 9/777                        │ inbox.post RPC           │
│    │ bell                             │                          │
│    │ commandFinished                  │                          │
│    ▼                                  ▼                          │
│  GhosttyAdapter                     RPCRouter                    │
│    │ .desktopNotificationRequested    │ (new handler emits       │
│    │ .bellRang                        │  PaneRuntimeEvent)       │
│    │ .commandFinished                 │                          │
│    └────────────┬─────────────────────┘                          │
│                 ▼                                                │
│         EventBus<RuntimeEnvelope>                                │
│                 │                                                │
│                 ▼                                                │
│  ┌────────────────────────────────────────────────────────┐      │
│  │ NotificationRouter  (leaf subscriber, @MainActor)      │      │
│  │  • applies §7 routing contract                         │      │
│  │  • enriches with repo/worktree/branch at emit time     │      │
│  │  • gating checks (pane focus, duration, bell setting)  │      │
│  │  • appends Notification → NotificationInboxAtom        │      │
│  └────────────┬───────────────────────────────────────────┘      │
│               │ append                                           │
│               ▼                                                  │
│  ┌────────────────────────────────────────────────────────┐      │
│  │ NotificationInboxAtom  (@Observable @MainActor)        │      │
│  │  notifications: [Notification]                         │      │
│  │  unreadCount(paneId/worktreeId/tabId/drawerIds)        │      │
│  │  markRead, markAllRead, dismissFromDrawer, toggle, ... │      │
│  └─────┬───────────────────────────────────────────┬──────┘      │
│        │ observed by                               │ read by     │
│        ▼                                           ▼             │
│  ┌──────────────────────────┐       ┌──────────────────────────┐ │
│  │ NotificationInboxStore   │       │  Views / readers         │ │
│  │ (persistence wrapper)    │       │  • InboxSidebarView      │ │
│  │  • debounced save        │       │  • DrawerInboxPopover    │ │
│  │  • load at boot          │       │  • Sidebar bell badge    │ │
│  │  • file I/O              │       │  • Drawer bell icon      │ │
│  └──────────────────────────┘       └───────────┬──────────────┘ │
│                                                 │ click / Enter  │
│                                                 ▼                │
│                                 PaneActionCommand.focusPane(id)  │
│                                 (CommandDispatcher → Coord)      │
└──────────────────────────────────────────────────────────────────┘

         ┌─ Side input ────────────────────────────────────────┐
         │ PaneFocusTracker (@MainActor) observes              │
         │ WorkspacePaneAtom.activePaneId transitions →        │
         │ AsyncStream<PaneId> → NotificationRouter →          │
         │ NotificationInboxAtom.markRead(paneId:)             │
         │                    .dismissFromDrawer(paneId:)      │
         └─────────────────────────────────────────────────────┘
```

### 8.2 Component placement

| Component | Slice | Rationale |
|---|---|---|
| `Notification` model | `Features/NotificationInbox/Models/` | Domain type used only by the feature and its immediate consumers (read through props) |
| `NotificationInboxTypes` (grouping/sort enums) | `Core/Models/` | Referenced by `UIStateAtom` in Core — pure Codable enums, no Features import |
| `NotificationInboxAtom` | `Features/NotificationInbox/State/` | Feature-scoped state |
| `NotificationInboxLayerAtom` | `Features/NotificationInbox/State/` | Feature-scoped mode |
| `NotificationInboxStore` | `Features/NotificationInbox/State/` | Feature-scoped persistence |
| `UIStateAtom.notificationInbox` slice | `Core/State/MainActor/Atoms/` | Existing Core atom; added property only |
| `NotificationRouter` | `Features/NotificationInbox/Routing/` | Consumes bus, writes atom |
| `PaneFocusTracker` | `Features/NotificationInbox/Routing/` | Observes `WorkspacePaneAtom`; emits focus-gained transitions |
| `InboxSidebarView` | `Features/NotificationInbox/Views/` | SwiftUI, replaces worktree list when layer active |
| `DrawerInboxPopover` | `Features/NotificationInbox/Views/` | SwiftUI popover |
| RPC `inbox.post` handler | `Features/Bridge/Transport/` | Minimal addition to `RPCRouter`; emits a new `PaneRuntimeEvent` |
| `.inbox` CommandBar scope | `Features/CommandBar/` | Extends existing scope enum; reads `NotificationInboxLayerAtom` via composition |

Single new feature slice: `Features/NotificationInbox/`.

### 8.3 Subscription pattern

`NotificationRouter` subscribes to `EventBus<RuntimeEnvelope>` via `AsyncStream` (no Combine, no NotificationCenter). It is a **leaf subscriber**: reads facts, writes to its own atom. It does not mutate other atoms, does not route commands. Matches the event-driven enrichment pattern described in `AGENTS.md`.

`NotificationInboxStore` observes `NotificationInboxAtom` via `Observation.withObservationTracking`, triggering a debounced save on any mutation. This matches `UIStateStore` / `RepoCacheStore`.

`PaneFocusTracker` observes `WorkspacePaneAtom` via `Observation.withObservationTracking`, diffs successive `activePaneId` values, and emits an `AsyncStream<PaneId>` of focus-gained transitions consumed by `NotificationRouter`.

### 8.4 Click-through routing

When the user activates a notification (click or Enter):

1. `NotificationInboxAtom.markRead(id: notification.id)`
2. `NotificationInboxAtom.dismissFromDrawer(id: notification.id)` (consistency rule per §4.2)
3. Detect pane liveness: `let paneAlive = workspacePaneAtom.pane(notification.paneId) != nil`
4. If `paneAlive`, dispatch `PaneActionCommand.focusPane(paneId)` → validator → `PaneCoordinator`.
5. If `!paneAlive` (or `notification.paneId` is `nil`), visually flash the row briefly (existing row-highlight animation) and stay in the inbox. No error modal.

## 9. Sidebar bell badge (existing)

The `🔔 N` pill already rendered per-worktree reads from `NotificationInboxAtom.unreadCount(forWorktreeId:)`. Shows `0` when there are no unread (existing behavior). Already wired to the data source once the atom is injected; no new UI work beyond binding. Clicking the pill is currently a no-op; opening Inbox with pre-filter is a stretch deferred to v2 (see §14).

## 10. Code-fact grounded details

Research pass against current code confirmed:

### 10.1 Focus detection

`WorkspaceFocusDerived` is stateless and snapshot-based (`currentFocus(...) -> WorkspaceFocus`). It exposes `activePaneId` but **does not** emit transition events. To clear state on "pane X gained focus":

- `PaneFocusTracker` (part of the feature slice) observes `WorkspacePaneAtom` via `Observation.withObservationTracking` and diffs successive `activePaneId` values.
- Emits `AsyncStream<PaneId>` of focus-gained transitions consumed by `NotificationRouter`.
- Router dispatches `NotificationInboxAtom.markRead(paneId:)` and `NotificationInboxAtom.dismissFromDrawer(paneId:)`.

Placement: `Features/NotificationInbox/Routing/PaneFocusTracker.swift`.

### 10.2 Drawer model

From `Core/Models/Drawer.swift` and `Core/Models/Pane.swift`:

- Flat 2-level hierarchy. A **layout pane** owns exactly one `Drawer`; a drawer owns **N child panes** (`drawerChild`). Child panes never have sub-drawers.
- A child pane's drawer context is therefore `pane.parentPaneId → parent.drawer`.
- The Drawer Inbox popover scope is well-defined: it shows notifications where `notification.paneId ∈ parent.drawer.paneIds` for the layout pane whose drawer hosts the currently focused pane.

### 10.3 Drawer icon strip integration

`DrawerIconBar` lives at `Core/Views/Drawer/DrawerIconBar.swift`, instantiated per-drawer via `DrawerOverlay`. It takes a `TrailingActions` struct for icons on the right side (currently Finder, Editor).

Integration path (preserves `Core → never imports Features`):

1. Extend `DrawerOverlay.TrailingActions` with `onOpenInbox: () -> Void` and `inboxUnreadCount: Int`.
2. The bell icon renders as a new `trailingActionButton` after a visible divider, as the rightmost slot.
3. The Features-level wrapper (e.g., the view that composes `DrawerOverlay`) reads `NotificationInboxAtom.unreadCount(forDrawerPaneIds: parent.drawer.paneIds)` and injects it into `TrailingActions`. Core code never imports the atom.

## 11. Resolved preference decisions

- **Bell setting UI (v1).** No settings pane exists yet. Bell on/off is a CommandBar action under `.inbox` scope: "Enable bell notifications" / "Disable bell notifications". State persisted on `UIStateAtom.notificationInbox.bellEnabled` (default `false`).
- **Focus target on ⌘I.** Top notification row (first in list given current sort). Makes ↓/↑ immediately productive. `⌥F` is one stroke to search.
- **⌘P + ⌘I coexistence.** ⌘I toggles the Inbox Layer regardless of CommandBar state and **does not dismiss the CommandBar**. If the CommandBar is already open, it stays open and its scope selection is preserved. Fresh ⌘P while Inbox Layer is active opens CommandBar with `.inbox` as the default scope (§5.2). ⌘S behaves the same way (does not dismiss CommandBar).
- **Global inbox toolbar indicator.** Red dot when any unread > 0 (v1 default). Optional count is deferred until we see it in use.
- **"Clear read history" scope.** Removes only read entries. A separate "Clear all notifications" action requires a confirmation dialog before acting.
- **Dead `paneId` on click-through.** Pane liveness checked via `WorkspacePaneAtom.pane(paneId) != nil`. If gone, do not navigate — flash the row briefly and keep focus in Inbox. Notification is already marked read by the click.

## 12. Open questions / deferred

- **User-configurable routing.** v1 has one toggle: bell notifications on/off. All other routing is code-level.
- **Retention tuning.** 1000-cap is provisional. If we see the log grow past that in practice, revisit.
- **Per-workspace vs cross-workspace.** v1 is per-workspace (`notification-inbox.json` under the workspace id). Cross-workspace aggregation is deferred.
- **UNUserNotificationCenter integration.** Separate follow-up ticket.
- **Inbox toolbar button: dot vs count.** v1 picks dot; count is deferred until we see the surface in use.
- **Stretch:** click on `🔔 N` sidebar bell badge opens Inbox with worktree pre-filtered in search.

## 13. Testing

Per `AGENTS.md` testing standards (Swift 6 Testing, colocate `_test.swift`, no wall-clock sleeps, injected clocks):

**Unit tests — `NotificationRouter`:**

- Each row of the §7 routing table: event in → notification out (or not). One `@Test` case per row.
- Gating rules: `commandFinished` with focused pane → no notification; unfocused + short duration → no notification; unfocused + ≥10s → notification.
- Bell setting: on/off toggles the routing outcome.
- Security subset: only alert-worthy cases produce notifications; lifecycle cases do not.

**Unit tests — `NotificationInboxAtom`:**

- Add, mark read, mark all read, dismiss from drawer — state transitions.
- Unread count queries across dimensions (pane, worktree, tab, drawer, global).
- Retention: insert 1001, confirm oldest is evicted.

**Unit tests — `NotificationInboxStore`:**

- Persistence roundtrip: save → clear → load → equal.
- Debounced save fires exactly once when multiple mutations occur within the window (injected clock).

**Unit tests — `PaneFocusTracker`:**

- Focus transition from paneA → paneB emits exactly one `PaneId(paneB)` event.
- No event emitted when `activePaneId` stays the same.

**Integration test — emission to display:**

- Emit `desktopNotificationRequested` on `EventBus` → assert `NotificationInboxAtom` contains the notification with correct denormalized context.
- Activate Inbox Layer via `NotificationInboxLayerAtom.toggle()` → assert keyboard layer queries route through the inbox keymap.
- Click notification → assert `PaneActionCommand.focusPane` dispatched → assert notification marked read.

**Integration test — Bridge RPC:**

- Fixture: valid `inbox.post` payload from a bridge pane → round-trips through `RPCRouter` → lands in `NotificationInboxAtom` with correct `paneId` inferred from bridge context.
- Agent cannot spoof `paneId` for another pane (assert payload `paneId` is ignored if present).

## 14. Documentation deliverables

- This spec, committed.
- Update `docs/architecture/workspace_data_architecture.md` event-bus consumer section to list `NotificationRouter` as a new leaf subscriber.
- Update `docs/architecture/directory_structure.md` Component → Slice Map with the new feature slice and `UIStateAtom` pref addition.
- Add Inbox Layer entry to keyboard shortcut documentation (currently unclear if one exists; create if not).

## 15. Out of scope (explicit)

- macOS UNUserNotificationCenter
- Cross-workspace aggregation
- Email / Slack / remote fan-out
- Rich notification content (images, actions beyond click-through)
- User-configurable routing UI (beyond bell on/off)
- Fuzzy search in inbox
- Collapsible group sections
- Toast / banner / transient popup of any kind

---

## Appendix A — Glossary

- **Notification Inbox** — the persistent notification log; both sidebar view and drawer popover share the same underlying data (`NotificationInboxAtom`).
- **Inbox Layer** — the mode state where the sidebar shows the Inbox and inbox-scoped shortcuts are active. Peer of Management Mode. Tracked by `NotificationInboxLayerAtom`.
- **Drawer Inbox** — the popover surface anchored on a drawer's bell icon; shows notifications for panes in that drawer only.
- **Global Inbox** — the sidebar view showing all notifications across all tabs/panes/drawers in the workspace.
- **Read / Unread** — state in the global inbox; toggled by focus-through, Enter, Space.
- **Dismissed from drawer** — local drawer state; notification disappears from drawer popover but remains in global inbox.
