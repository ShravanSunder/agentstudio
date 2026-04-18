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
│ Sidebar toggle strip:                                            │
│   [ ⌘S worktrees ]  [ ⌘I inbox ]   ← red dot or count on inbox   │
│                                      when unread > 0             │
│                                                                  │
│                                                                  │
│  Sidebar (worktrees, default ⌘S):                                │
│   agent-studio · drawer-improvements  +447 -103 ↑0 ↓0 🔔 3       │
│   agent-studio · zmx-ipc              +0   -0  ↑0 ↓0 🔔 0       │
│                                                 ^ unread count   │
│                                                                  │
│  Sidebar (inbox, ⌘I):                                            │
│   replaces worktree list — see §5                                │
│                                                                  │
│                                                                  │
│  Drawer strip (per drawer, at bottom of each drawer):            │
│   [finder] [other] [other]   │   [🔔 3]                          │
│                           divider   ^ rightmost,                 │
│                                     count = unread in this       │
│                                     drawer's panes               │
└──────────────────────────────────────────────────────────────────┘
```

### 3.1 Global Inbox (sidebar, ⌘I)

- **Scope:** all notifications across all workspaces tabs/panes/drawers.
- **Surface:** replaces the worktree list in the sidebar. Sidebar is one view at a time; ⌘I and ⌘S switch between them.
- **Indicator:** red dot or small numeric count on the sidebar toggle strip.
- **Dismissal model:** read-state only — nothing is removed when you act on it. Inbox is the log of record.

### 3.2 Drawer Inbox (popover, ⌘⇧I)

- **Scope:** notifications for panes attached to the currently focused drawer.
- **Surface:** popover anchored on a bell icon placed as the rightmost icon in the drawer's icon strip, after a divider that separates it from the existing icons (finder, etc.).
- **Indicator:** numeric unread count on the bell icon.
- **Dismissal model:** true dismiss — acting on an item removes it from the drawer popover. Same item remains visible in the global Inbox (marked read).

### 3.3 Per-worktree bell badge

- Already rendering in the sidebar row (`🔔 N`).
- Reads `unreadCount(worktreeId)` off the same underlying data.
- Click: opens global Inbox with search pre-filled to the worktree name. (Stretch; can defer.)

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
    var isRead: Bool                   // global inbox dismissal
    var isDismissedFromDrawer: Bool    // drawer popover dismissal
}

enum NotificationKind: String, Sendable, Codable {
    case agentDesktopNotification     // Ghostty OSC 9/777
    case bellRang                     // Ghostty bell
    case commandFinished              // Ghostty command completion, gated
    case agentRpc                     // Bridge RPC notification.post
    case approvalRequested            // ArtifactEvent.approvalRequested
    case securityEvent                // SecurityEvent.*
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

### 4.3 Persistence

- **`InboxStore`** — new `@Observable @MainActor` atom + on-disk persistence, sibling to `WorkspaceStore` / `RepoCacheStore` / `UIStateStore` under `Core/State/MainActor/`. Stores the full `[Notification]` log.
  - File: `~/Library/Application Support/AgentStudio/<workspaceId>/inbox.json` (matching existing store layout).
  - Loaded at boot, same lifecycle as other stores.
- **Retention:** cap at **1000 entries per workspace**, evict oldest-first. Provisional; tune if needed. Not user-configurable in v1.
- **`UIStateStore`** extension — view preferences (`grouping`, `sort`) persisted separately. These are UI state, not log data.

```
UIStateStore adds:
  inboxView: {
    grouping: .none | .byRepo | .byPane | .byTab   (default: .none)
    sort: .newestFirst | .oldestFirst              (default: .newestFirst)
  }

InboxLayerAtom (new, @Observable @MainActor):
  isActive: Bool   // true when sidebar is showing the inbox
```

## 5. Inbox Layer

The Inbox is not just a view — it is a **layer**, mirroring the existing Management Mode pattern. When active, it owns a scoped keyboard layer and a CommandBar scope.

### 5.1 Activation model

```
Sidebar state          Keyboard layer
─────────────────────────────────────────────────────
Worktrees (default)    App default shortcuts
⌘I →  Inbox Layer      Inbox Layer keymap active
⌘I →  Worktrees        App default shortcuts (toggles off)
⌘S →  Worktrees        App default shortcuts (explicit)
```

`InboxLayerAtom.isActive` drives both the sidebar view and the keyboard layer. `WorkspaceFocusDerived` (already the centralized reader for command visibility) consults this atom to expose inbox-specific CommandBar commands.

### 5.2 CommandBar integration

Add `CommandBarScope.inbox`. When the Inbox Layer is active, ⌘P opens the command bar scoped to inbox actions:

- Mark all as read
- Clear read history
- Change grouping → None / Repo / Pane / Tab
- Toggle sort order
- Return to worktree sidebar (⌘S)

### 5.3 Inbox Layer keymap

Only active when `InboxLayerAtom.isActive && sidebarHasFocus`.

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
▾ agent-studio                        ● 3      ← group header, non-focusable
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

**Search:** filter-as-you-type across title, body, repo name, worktree name, branch name. No fuzzy matching in v1 — substring match, case-insensitive.

## 7. Event routing contract

The explicit "which events notify" table. This is the routing contract that the ticket requires to be legible in code.

| Source event | Notify? | `NotificationKind` | Gating rule |
|---|---|---|---|
| `GhosttyEvent.desktopNotificationRequested` (OSC 9/777) | **Yes** | `agentDesktopNotification` | Always |
| `GhosttyEvent.bellRang` | User setting | `bellRang` | Default **off**; user can enable per-workspace |
| `GhosttyEvent.commandFinished` | Conditional | `commandFinished` | Only if source pane is not currently focused AND duration ≥ 10s |
| Bridge RPC `notification.post` (new method) | **Yes** | `agentRpc` | Always; fire-and-forget JSON-RPC notification (no `id`) |
| `ArtifactEvent.approvalRequested` | **Yes** | `approvalRequested` | Always |
| `SecurityEvent.*` (egress blocked, fs denied, etc.) | **Yes** | `securityEvent` | Always |
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
    "body": "3 files changed, 142 lines",
    "kind": "agentRpc"
  }
}
```

No `id` (notification, not request). `paneId` is inferred from the originating bridge pane context at RPC receive time — agents cannot spoof notifications from other panes.

## 8. Architecture

### 8.1 Component diagram

```
┌───────────────────────────────────────────────────────────────┐
│ Sources                                                       │
│                                                               │
│  Ghostty (CLI)                      Bridge (Agent panes)      │
│    │ OSC 9/777                        │ inbox.post RPC        │
│    │ bell                             │                       │
│    │ commandFinished                  │                       │
│    ▼                                  ▼                       │
│  GhosttyAdapter                     RPCRouter                 │
│    │ .desktopNotificationRequested    │ (new handler emits    │
│    │ .bellRang                        │  PaneRuntimeEvent)    │
│    │ .commandFinished                 │                       │
│    └────────────┬─────────────────────┘                       │
│                 ▼                                             │
│         EventBus<RuntimeEnvelope>                             │
│                 │                                             │
│                 ▼                                             │
│  ┌─────────────────────────────────────────────────────┐      │
│  │ NotificationRouter  (new, leaf on bus, @MainActor)  │      │
│  │  • applies §7 routing contract                      │      │
│  │  • enriches with repo/worktree/branch at emit time  │      │
│  │  • gating checks (pane focus, duration, settings)   │      │
│  │  • emits Notification record → InboxStore           │      │
│  └─────────────────────┬───────────────────────────────┘      │
│                        ▼                                      │
│  ┌─────────────────────────────────────────────────────┐      │
│  │ InboxStore  (@Observable @MainActor)                │      │
│  │  • notifications: [Notification]                    │      │
│  │  • unreadCount(paneId/worktreeId/tabId/drawerId)    │      │
│  │  • markRead(id), markAllRead(), dismissFromDrawer   │      │
│  │  • persisted to disk, capped at 1000                │      │
│  └───────┬──────────────────────┬──────────────────────┘      │
│          │                      │                             │
│          ▼                      ▼                             │
│   InboxSidebarView       DrawerInboxPopover                   │
│   (⌘I surface)           (⌘⇧I surface)                        │
│          │                      │                             │
│          └──────────┬───────────┘                             │
│                     ▼                                         │
│           PaneActionCommand                                   │
│           .focusPane(paneId)                                  │
│           (via CommandDispatcher → PaneCoordinator)           │
└───────────────────────────────────────────────────────────────┘
```

### 8.2 Component placement

| Component | Slice | Rationale |
|---|---|---|
| `Notification` model | `Core/Models/` | Domain model, widely referenced |
| `InboxStore` | `Core/State/MainActor/Persistence/` | Peer of `WorkspaceStore`, `UIStateStore` |
| `InboxLayerAtom` | `Core/State/MainActor/Atoms/` | Peer of `ManagementModeAtom` |
| `NotificationRouter` | `Features/Inbox/Routing/` | New feature slice; consumes bus, writes store |
| `InboxSidebarView` | `Features/Inbox/Views/` | SwiftUI, replaces worktree list |
| `DrawerInboxPopover` | `Features/Inbox/Views/` | SwiftUI popover |
| RPC `inbox.post` handler | `Features/Bridge/Transport/` | Minimal addition to RPCRouter |
| `.inbox` CommandBar scope | `Features/CommandBar/` | Extends existing scope enum |

Single new feature slice: `Features/Inbox/`.

### 8.3 Subscription pattern

`NotificationRouter` subscribes to `EventBus<RuntimeEnvelope>` via `AsyncStream` (matches house style — no Combine, no NotificationCenter for new code). It is a **leaf subscriber**: reads facts, writes to its own store. It does not mutate other stores, does not route commands. Matches the event-driven enrichment pattern described in CLAUDE.md.

### 8.4 Click-through routing

When the user activates a notification (click or Enter):

1. `InboxStore.markRead(notification.id)`
2. `InboxStore.dismissFromDrawer(notification.id)` (consistency rule per §4.2)
3. If `notification.paneId` exists and pane is still alive:
   - Dispatch `PaneActionCommand.focusPane(paneId)` → validator → `PaneCoordinator`
4. If pane is gone, visually flash the row briefly and stay in the inbox (no navigation). No error modal.

## 9. Sidebar bell badge (existing)

The `🔔 N` pill already rendered per-worktree reads from `InboxStore.unreadCount(worktreeId:)`. When count is 0, pill shows `0` (existing behavior). Already wired to the data source once `InboxStore` exists; no new UI work beyond binding.

## 10. Code-fact grounded details

Research pass against current code confirmed:

### 10.1 Focus detection

`WorkspaceFocusDerived` is stateless and snapshot-based (`currentFocus(...) -> WorkspaceFocus`). It exposes `activePaneId` but **does not** emit transition events. To clear state on "pane X gained focus":

- Introduce a small `PaneFocusTracker` (`@MainActor`, part of the Inbox feature) that observes `WorkspacePaneAtom` via `Observation.withObservationTracking` and diffs successive `activePaneId` values.
- Emits `AsyncStream<PaneId>` of focus-gained transitions consumed by `NotificationRouter`.
- Router dispatches to `InboxStore.markRead(paneId:)` and `InboxStore.dismissFromDrawer(paneId:)`.

Placement: `Features/Inbox/Routing/PaneFocusTracker.swift`.

### 10.2 Drawer model

From `Core/Models/Drawer.swift` and `Core/Models/Pane.swift`:

- Flat 2-level hierarchy. A **layout pane** owns exactly one `Drawer`; a drawer owns **N child panes** (`drawerChild`). Child panes never have sub-drawers.
- A child pane's drawer context is therefore `pane.parentPaneId → parent.drawer`.
- This means: the Drawer Inbox popover scope is well-defined — it shows notifications where `notification.paneId ∈ parent.drawer.paneIds` for whichever layout pane's drawer is currently active/expanded.

### 10.3 Drawer icon strip integration

`DrawerIconBar` lives at `Core/Views/Drawer/DrawerIconBar.swift`, instantiated per-drawer via `DrawerOverlay`. It takes a `TrailingActions` struct for icons on the right side (currently Finder, Editor).

Integration path:

1. Extend `DrawerOverlay.TrailingActions` with `onOpenInbox: () -> Void` and `inboxUnreadCount: Int`.
2. Add the bell `trailingActionButton` after a visible divider, as the rightmost slot — matches `CLAUDE.md` style guide for drawer icon placement.
3. Unread count is read from `InboxStore.unreadCount(forDrawerPaneIds: parent.drawer.paneIds)`.

## 11. Resolved preference decisions

- **Bell setting UI (v1).** No settings pane exists yet. Bell on/off is a CommandBar action under `.inbox` scope: "Enable bell notifications" / "Disable bell notifications". State persisted in `UIStateStore.inboxView.bellEnabled` (default `false`).
- **Focus target on ⌘I.** Top notification row (first in list given current sort). Makes ↓/↑ immediately productive. `⌥F` is one stroke to search.
- **⌘P + ⌘I coexistence.** ⌘I toggles the Inbox Layer regardless of CommandBar state and **does not dismiss the CommandBar**. If the CommandBar was open, it stays open. Its scope selection is preserved — the user chose it, ⌘I doesn't override it. ⌘S behaves the same way (does not dismiss CommandBar). This means both surfaces can be simultaneously active.
- **"Clear read history" scope.** Removes only read entries. A separate "Clear all notifications" action requires a confirmation dialog before acting.
- **Dead `paneId` on click-through.** If the pane is gone, do not navigate. Flash the row briefly (existing row-highlight animation) and keep focus in Inbox. Notification is already marked read by the click.

## 12. Open questions / deferred

- **User-configurable routing.** v1 has one toggle: bell notifications on/off. All other routing is code-level.
- **Retention tuning.** 1000-cap is provisional. If we see the log grow past that in practice, revisit.
- **Per-workspace vs global Inbox.** v1 is per-workspace (`inbox.json` under the workspace id). Multi-workspace aggregation is deferred.
- **UNUserNotificationCenter integration.** Separate follow-up ticket.
- **Stretch:** click on `🔔 N` sidebar bell badge opens Inbox with worktree pre-filtered in search.

## 11. Testing

Per `CLAUDE.md` testing standards (Swift 6 Testing, colocate `_test.swift`, no wall-clock sleeps, injected clocks):

**Unit tests — `NotificationRouter`:**

- Each row of §7 routing table: event in → notification out (or not). One `@Test` case per row.
- Gating rules: `commandFinished` with focused pane → no notification; unfocused + short duration → no notification; unfocused + ≥10s → notification.
- Bell setting: on/off toggles the routing outcome.

**Unit tests — `InboxStore`:**

- Add, mark read, mark all read, dismiss from drawer — state transitions.
- Unread count queries across dimensions (pane, worktree, tab, drawer, global).
- Retention: insert 1001, confirm oldest is evicted.
- Persistence roundtrip: save → clear → load → equal.

**Integration test — emission to display:**

- Emit `desktopNotificationRequested` on `EventBus` → assert `InboxStore` contains the notification with correct denormalized context.
- Activate Inbox Layer (⌘I simulated as state toggle) → assert keyboard layer queries route through the inbox keymap.
- Click notification → assert `PaneActionCommand.focusPane` dispatched → assert notification marked read.

**Integration test — Bridge RPC:**

- Fixture: valid `inbox.post` payload from a bridge pane → round-trips through `RPCRouter` → lands in `InboxStore` with correct `paneId` inferred from bridge context.
- Agent cannot spoof `paneId` for another pane (assert payload `paneId` is ignored if present).

## 12. Documentation deliverables

- This spec, committed.
- Update `docs/architecture/workspace_data_architecture.md` event-bus consumer section to list `NotificationRouter` as a new leaf subscriber.
- Update `docs/architecture/directory_structure.md` Component → Slice Map with the new Inbox components.
- Add Inbox Layer entry to whatever document lists keyboard shortcuts (currently unclear; see if one exists, create if not).

## 13. Out of scope (explicit)

- macOS UNUserNotificationCenter
- Multi-workspace aggregation
- Email / Slack / remote fan-out
- Rich notification content (images, actions beyond click-through)
- User-configurable routing UI (beyond bell on/off)
- Fuzzy search in inbox
- Collapsible group sections
- Toast / banner / transient popup of any kind

---

## Appendix A — Glossary

- **Inbox** — the persistent notification log (both sidebar view and drawer popover share the same data).
- **Inbox Layer** — the mode state where the sidebar shows the Inbox and inbox-scoped shortcuts are active. Peer of Management Mode.
- **Drawer Inbox** — the popover surface anchored on a drawer's bell icon; shows notifications for panes in that drawer only.
- **Global Inbox** — the sidebar view showing all notifications across all tabs/panes/drawers.
- **Read / Unread** — state in the global inbox; toggled by focus-through, Enter, Space.
- **Dismissed from drawer** — local drawer state; notification disappears from drawer popover but remains in global inbox.
