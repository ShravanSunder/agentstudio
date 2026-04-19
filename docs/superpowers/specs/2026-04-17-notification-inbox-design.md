# Notification Inbox — Design Spec

**Status:** Draft · Design Mode
**Linear:** [LUNA-361](https://linear.app/askluna/issue/LUNA-361/show-agent-and-cli-notifications-in-notification-center)
**Related:** LUNA-355 (Ghostty host event consumers)
**Interaction model:** [2026-04-18 Interaction Model WIP](2026-04-18-interaction-model-wip.md) — authoritative for layer vs focus-scoped keys, `KeyboardOwner`, and sidebar surface selection. This spec conforms to that model.
**Date:** 2026-04-17 (revised 2026-04-19)
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
│                           • red dot (v1) when unread > 0         │
│                           • click runs the ⌘I composite command  │
│                                                                  │
│  Sidebar (worktrees, default):                                   │
│   agent-studio · drawer-improvements  +447 -103 ↑0 ↓0 🔔 3       │
│   agent-studio · zmx-ipc              +0   -0  ↑0 ↓0 🔔 0       │
│                                                 ^ per-worktree    │
│                                                   unread count   │
│                                                                  │
│  Sidebar (inbox, after ⌘I):                                      │
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
- **Surface:** when `UIStateAtom.sidebarSurface == .inbox`, the sidebar renders the Inbox view (see §6) in place of the worktree list. Sidebar is one view at a time; ⌘I and ⌘S are composite commands that toggle between them (see §5.1).
- **Toolbar entry point:** a new bell icon in the existing sidebar toolbar, next to the show/hide sidebar button. Shows a red dot (v1 default) when unread > 0. Clicking it runs the same composite command as ⌘I.
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

This section is grounded in [directory_structure.md — Feature Slice Self-Containment](../../architecture/directory_structure.md): feature atoms live at `Features/<slice>/State/MainActor/Atoms/`, feature stores at `Features/<slice>/State/MainActor/Persistence/`. Composition state (app-wide UI shell) lives on `UIStateAtom` in Core. Feature-specific types stay in the feature slice.

It is NOT a Layer (see the [Interaction Model WIP](2026-04-18-interaction-model-wip.md) §1-§2 for what earns Layer status). There is no `NotificationInboxLayerAtom`.

**Two feature atoms (inbox log + inbox prefs), one feature store, and three small additions split between Core and `UIStateAtom`.**

#### `NotificationInboxAtom` — feature-scoped (log)

Path: `Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxAtom.swift`
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

The atom knows nothing about whether the sidebar is currently showing the inbox. That's composition state (see `UIStateAtom` below).

#### `NotificationInboxPrefsAtom` — feature-scoped (prefs)

Path: `Features/NotificationInbox/State/MainActor/Atoms/NotificationInboxPrefsAtom.swift`
Role: user preferences for the inbox — grouping, sort, bell enable. `@Observable @MainActor`.

```swift
@MainActor @Observable
final class NotificationInboxPrefsAtom {
    private(set) var grouping: NotificationInboxGrouping = .none
    private(set) var sort: NotificationInboxSort = .newestFirst
    private(set) var bellEnabled: Bool = false

    func setGrouping(_ grouping: NotificationInboxGrouping)
    func setSort(_ sort: NotificationInboxSort)
    func setBellEnabled(_ enabled: Bool)
}
```

Prefs are feature-specific — they stay in the feature slice, NOT on `UIStateAtom`. This keeps Core from growing per-feature properties. Supporting enum types (`NotificationInboxGrouping`, `NotificationInboxSort`) live in `Features/NotificationInbox/Models/NotificationInboxTypes.swift`.

#### `UIStateAtom` additions — composition state only (`sidebarCollapsed`, `sidebarSurface`, `sidebarHasFocus`)

Path: `Core/State/MainActor/Atoms/UIStateAtom.swift` (existing)
Role: app-wide UI shell state. These three fields are composition state — they describe how features are assembled into the UI, not feature-specific data.

```swift
// on UIStateAtom (existing Core atom; additive):
private(set) var sidebarCollapsed: Bool = false     // published by MainSplitViewController
private(set) var sidebarSurface: SidebarSurface = .repos
private(set) var sidebarHasFocus: Bool = false      // runtime-only; not persisted

func setSidebarCollapsed(_ value: Bool)
func setSidebarSurface(_ surface: SidebarSurface)
func setSidebarHasFocus(_ value: Bool)
```

- `sidebarCollapsed` — **this is a state-ownership migration, not just a new field.** Today, sidebar collapsed state is owned entirely by `MainSplitViewController` and persisted via the `sidebarCollapsed` key in `UserDefaults` (`MainSplitViewController.swift:45`, read/write at lines ~96 and ~120). This ticket moves ownership into `UIStateAtom` (atom-owned + persisted via `UIStateStore` → `workspace.ui.json`). During transition we **dual-write**: `MainSplitViewController` publishes every collapsed-state change into `UIStateAtom` AND continues writing the legacy `UserDefaults` key so restore behavior doesn't regress. A follow-up ticket drops the `UserDefaults` write path once we're confident `UIStateStore` has fully taken over restore responsibility. Read path during the transition: atom is authoritative when a value has been loaded from `UIStateStore`; fall back to `UserDefaults` only when `UIStateStore` hasn't loaded yet (rare — boot sequence).
- `sidebarSurface` is persisted via `UIStateStore`. Default `.repos`. No prior state to migrate.
- `sidebarHasFocus` is runtime-only, reset to `false` on launch. Published by each sidebar surface view via `@FocusState.onChange`. Only one surface is visible at a time, so only one publishes at a time.

**SidebarSurface lives in Core** (`Core/Models/SidebarSurface.swift`), not in the feature slice. Justification: `SidebarSurface` is composition-cutting — it names all sidebar surfaces, tags `UIStateAtom.sidebarSurface`, and appears in `KeyboardOwner.sidebar(SidebarSurface)` (§4.4). It is a generic enum (`.repos | .inbox`), not a feature-specific type. Core is the right home.

**New runtime seam.** The app currently has no general "sidebar has focus" signal — the only existing sidebar focus seam is the filter field at `Features/RepoExplorer/RepoExplorerView.swift` (currently `Features/Sidebar/RepoSidebarContentView.swift:28` pre-rename). Wiring `sidebarHasFocus` is net-new work.

**Contract for `sidebarHasFocus` (one-line):**

> `sidebarHasFocus == true` iff the active sidebar surface owns keyboard navigation (selected list/row) OR a focused text/search control within that same surface is first responder. Equivalently: any declared `@FocusState` target inside the currently-visible sidebar surface is non-nil.

Each surface declares its own internal focus enum listing the controls that participate:

```swift
// Features/NotificationInbox/Views/InboxSidebarView.swift
enum InboxFocus: Hashable {          // feature-internal; not in Core
    case search
    case list
    case row(UUID)
    case groupingMenu
}

@FocusState private var focusedField: InboxFocus?

var body: some View {
    // ... attach .focused($focusedField, equals: .search), .list, etc.
    .onChange(of: focusedField) { _, new in
        uiState.setSidebarHasFocus(new != nil)
    }
}
```

`Features/RepoExplorer/RepoExplorerView.swift` follows the same pattern with its own `RepoExplorerFocus` enum declaring its focusable controls.

**What this rule explicitly means:**

- **Search field focused → has focus.** (`.inboxSearch` / `.reposFilter` cases are declared.)
- **Any list row focused → has focus.** (`.inboxRow(id)` / `.reposRow(id)` cases are declared.)
- **Grouping menu popover focused → has focus.** (`.inboxGroupingMenu` case is declared.)
- **Main content (pane) focused → no focus on sidebar.** (Sidebar's enum is nil.)
- **CommandBar opens → sidebar loses responder chain position → `focusedField` becomes nil → `sidebarHasFocus == false`.** Correct behavior (CommandBar owns keys).

**What this rule does NOT do:**

- It does NOT walk the AppKit NSView responder chain. Rule is SwiftUI-level only.
- It does NOT auto-include new focusable elements. Adding a focusable control inside a surface requires extending that surface's focus enum and declaring `.focused($focusedField, equals: newCase)`. That's intentional — the set of declared focus targets is the explicit definition of "sidebar has focus" for that surface.

Only one surface is visible at a time (`uiState.sidebarSurface`), so only one surface publishes at a time. No race.

Covered in §8.4 and §13.

#### `NotificationInboxStore` — feature-scoped (one store, two atoms)

Path: `Features/NotificationInbox/State/MainActor/Persistence/NotificationInboxStore.swift`
Role: persistence wrapper. One store, one file, wraps both feature atoms (matches `WorkspaceStore` pattern — one store wrapping multiple atoms that persist together).

```swift
@MainActor
final class NotificationInboxStore {
    let inboxAtom: NotificationInboxAtom
    let prefsAtom: NotificationInboxPrefsAtom

    init(
        inboxAtom: NotificationInboxAtom,
        prefsAtom: NotificationInboxPrefsAtom,
        fileURL: URL,
        clock: any Clock<Duration> = ContinuousClock()
    )
    func load() throws            // called at boot
    func save() async throws      // called on debounced mutation

    // Internal: subscribes to both atoms via Observation.withObservationTracking
    // and triggers debounced save on any mutation.
}
```

- File: `~/.agentstudio/workspaces/<workspaceId>/notification-inbox.json` (canonical workspace bundle path per [workspace_data_architecture.md](../../architecture/workspace_data_architecture.md); sibling of `workspace.state.json`, `workspace.cache.json`, `workspace.ui.json`)
- File shape: `{ schemaVersion, notifications: [...], prefs: { grouping, sort, bellEnabled } }`
- Save cadence: debounced ~500ms after mutations (injected clock; matches existing stores)
- Retention: cap **1000 entries per workspace**, evict oldest-first at append time. Provisional.

#### Registration

Feature atoms (`NotificationInboxAtom`, `NotificationInboxPrefsAtom`) are instantiated in the app composition root (`App/Boot/AppDelegate.swift`) and passed into the feature's views/routers via constructor injection. Views outside the feature slice (e.g., the sidebar worktree row in `Features/Sidebar/`, or `SidebarSurfaceHost` in App) receive read-only references through the same composition path. Feature atoms are NOT registered in `AtomRegistry` (which lives in `Infrastructure/` and must not import Features).

`NotificationInboxStore` is instantiated in the same boot path as `WorkspaceStore`/`RepoCacheStore`/`UIStateStore` and calls `load()` at boot.

### 4.4 `KeyboardOwnerDerived` — v1, in Core

Per the [Interaction Model WIP](2026-04-18-interaction-model-wip.md) §4, `KeyboardOwner` is a derived abstraction that names who owns keyboard interpretation at any moment. It lands in v1 (not deferred) because CommandBar scope defaulting is a v1 consumer.

Paths:
- `Core/Models/KeyboardOwner.swift`
- `Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift`

Role: stateless factory; follows the `WorkspaceFocusDerived` pattern exactly (takes atom references, reads what it needs, returns a plain value snapshot, owns no state or observation lifecycle).

**Scope acknowledgment.** Shipping `KeyboardOwner` in v1 brings four things into this ticket:

1. `Core/Models/KeyboardOwner.swift` — enum type (~15 lines)
2. `Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift` — stateless factory (~25 lines)
3. `WindowLifecycleAtom.isWorkspaceWindowKey` — one computed accessor (~3 lines)
4. `Features/CommandBar/CommandBarState.swift` default-scope logic — reads `KeyboardOwnerDerived.current(...)` for `.inbox` scope gating (see §5.2)

Plus the corresponding tests (see §13 — `KeyboardOwnerDerived` precedence cases, `isWorkspaceWindowKey` cases).

The alternative — deferring `KeyboardOwnerDerived` — would require CommandBar scope defaulting to inline the precedence check directly against `uiState.sidebarSurface` / `sidebarHasFocus`. That's duplication-by-inlining, which the next consumer (repos navigation) would then have to either copy or refactor into `KeyboardOwnerDerived` anyway. Shipping the type now is the cheaper path given CommandBar is already a v1 consumer.

```swift
// Core/Models/KeyboardOwner.swift
enum KeyboardOwner: Equatable, Sendable {
    case otherWindow
    case managementLayer
    case sidebar(SidebarSurface)
    case none
}

// Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift
@MainActor
struct KeyboardOwnerDerived {
    func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom
    ) -> KeyboardOwner {
        guard windowLifecycle.isWorkspaceWindowKey else {
            return .otherWindow
        }
        if managementLayer.isActive {
            return .managementLayer
        }
        if !uiState.sidebarCollapsed && uiState.sidebarHasFocus {
            return .sidebar(uiState.sidebarSurface)
        }
        return .none
    }
}
```

All inputs are Core atoms (with composition state on `UIStateAtom`, the shell-state reads don't need to cross layers). Consistent with `WorkspaceFocusDerived`.

#### `WindowLifecycleAtom` — one accessor added

`WindowLifecycleAtom` (`Core/State/MainActor/Atoms/WindowLifecycleAtom.swift`) already tracks `keyWindowId` and `registeredWindowIds`. Grows one computed property used by `KeyboardOwnerDerived`:

```swift
var isWorkspaceWindowKey: Bool {
    keyWindowId.map { registeredWindowIds.contains($0) } ?? false
}
```

No new storage; derived from existing fields.

## 5. Keyboard behavior — focus-scoped keys, not a Layer

Per the [Interaction Model WIP](2026-04-18-interaction-model-wip.md), inbox keyboard behavior is **Kind 3 (focus-scoped keys)**, not Kind 1 (Layer). There is no `NotificationInboxLayerAtom`. There is no stored "inbox layer is active" boolean. The inbox's custom shortcuts (⌥F, ⌥G, ⌥S, etc.) fire when the sidebar has focus and is showing the inbox surface — derived, not toggled.

`KeyboardOwner` (designed in the WIP §4, **implemented in v1** per §4.4) names this state as `.sidebar(.inbox)`. The inbox's own runtime shortcuts do NOT call `KeyboardOwnerDerived` — they dispatch natively through SwiftUI `.keyboardShortcut()` + AppKit responder chain. But `KeyboardOwnerDerived` itself ships in this ticket because CommandBar default-scope logic (§5.2) is a v1 consumer.

### 5.1 ⌘I and ⌘S as composite commands

```
⌘I  →  ensureSidebarVisible()
       uiState.setSidebarSurface(.inbox)
       if !commandBarIsKey { moveFocusToInboxFirstRow() }

⌘S  →  ensureSidebarVisible()
       uiState.setSidebarSurface(.repos)
       // Does not force focus — respects current focus
```

Mirrors the existing pattern at `MainSplitViewController.showSidebarFilter()` (`App/Windows/MainSplitViewController.swift:136-145`), which already does composite work (expand sidebar, set UI state, focus a field).

Neither command dismisses the CommandBar if it is open. If CommandBar is key:
- Surface still switches (the visible sidebar changes behind CommandBar).
- Focus is NOT moved into the sidebar (would steal focus from CommandBar).
- CommandBar's scope selection is preserved.

### 5.2 CommandBar integration

Add `CommandBarScope.inbox`. Behavior:

- **Fresh ⌘P when `uiState.sidebarSurface == .inbox && uiState.sidebarHasFocus`:** CommandBar opens with `.inbox` as the default scope. Shows inbox-scoped actions first.
- **CommandBar already open when ⌘I fires:** CommandBar stays open; the user's current scope selection is preserved. The sidebar surface flips behind it.
- **CommandBar open, surface ≠ inbox, user manually picks `.inbox` scope:** valid — `.inbox` is always pickable. Activating the scope does not change the sidebar surface.

Default-scope selection reads `KeyboardOwnerDerived.current(...)` (implemented in v1 per §4.4). Full matrix:

| `KeyboardOwner` | Fresh ⌘P default scope | Status in this ticket |
|---|---|---|
| `.otherWindow` | N/A — CommandBar panel itself becomes the key window, so "fresh ⌘P" while `.otherWindow` doesn't happen for our CommandBar | No change |
| `.managementLayer` | Preserve existing management-layer CommandBar behavior (no change) | Unchanged |
| `.sidebar(.inbox)` | `.inbox` | **New in this ticket** |
| `.sidebar(.repos)` | Existing default (`.everything`) for now; repo-scope default lands with the future repo-navigation ticket | Unchanged by this ticket; placeholder |
| `.none` | `.everything` (existing default) | Unchanged |

Only the `.sidebar(.inbox)` row is new. Other rows preserve existing behavior; they become meaningful signals as other features (repo navigation, management-layer-aware CommandBar) are developed. The matrix earns its keep in v1 for inbox; its structural value compounds as more consumers land.

Inbox-scoped actions:

- Mark all as read
- Clear read history
- Clear all notifications (with confirmation)
- Change grouping → None / Repo / Pane / Tab
- Toggle sort order
- Enable bell notifications / Disable bell notifications
- Return to worktree sidebar (⌘S)

### 5.3 Inbox keymap

Lives as `.keyboardShortcut()` modifiers attached to views inside `InboxSidebarView`. AppKit responder chain handles dispatch — these keys fire only when the sidebar view is in the first-responder path of the key window.

No custom NSEvent monitor. No InboxLayerAtom precondition. No runtime gating beyond "sidebar view is focused in the key window" — which is AppKit's own rule for `.keyboardShortcut()`.

```
Global shortcuts (always available when workspace window is key):
⌘I               run CMD+I composite command
⌘S               run CMD+S composite command
⌘⇧I              open drawer inbox popover (no-op if not applicable)

Inside the inbox view (active when the sidebar has focus):
⌥F               focus search field
⌥G               toggle grouping menu open/closed
⌥S               toggle sort (newest ↔ oldest)

Navigation (inside the list):
↓ / ↑            next / prev notification row
⌥↓ / ⌥↑          next / prev group (lands on first item of group,
                 skipping group header)
⌘↑ / ⌘↓          first / last notification

Actions:
Enter  or  →     jump to source pane + mark read
Space            toggle read/unread without jumping
Esc              if search active → clear search;
                 else → return focus to main content

Group menu open state:
⌥G or Esc        close/cancel (no change)
↓ / ↑            change selection
Enter            commit selection
```

Headers (group labels) are never focus stops for ↓/↑ — arrow keys skip between item rows only.

## 6. Inbox panel layout

```
┌─ Inbox (⌘I) ───────────────────────────────┐
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

**Search:** filter-as-you-type across title, body, repo name, worktree name, branch name. Substring match, case-insensitive. No fuzzy matching in v1 (see §15).

## 7. Event routing contract

The explicit "which events notify" table. This is the routing contract the ticket requires to be legible in code.

| Source event | Notify? | `NotificationKind` | Gating rule |
|---|---|---|---|
| `GhosttyEvent.desktopNotificationRequested` (OSC 9/777) | **Yes** | `agentDesktopNotification` | Always |
| `GhosttyEvent.bellRang` | User setting | `bellRang` | Only when `NotificationInboxPrefsAtom.bellEnabled == true`; default `false` |
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

### 8.1 Folder structure

The full map of new and modified files, following the conventions in [directory_structure.md — Feature Slice Self-Containment](../../architecture/directory_structure.md). Every atom at `<owner>/State/MainActor/Atoms/`; every store at `<owner>/State/MainActor/Persistence/`. Features self-contained. Composition state on `UIStateAtom` in Core.

```
Sources/AgentStudio/
│
├── Features/NotificationInbox/                         [NEW SLICE]
│   ├── Components/
│   │   ├── InboxRow.swift                              reusable inbox
│   │   ├── InboxGroupHeader.swift                      view pieces
│   │   └── InboxEmptyState.swift
│   ├── Models/
│   │   ├── Notification.swift                          domain type
│   │   └── NotificationInboxTypes.swift                grouping / sort
│   │                                                    enums
│   ├── Routing/
│   │   ├── NotificationRouter.swift                    bus subscriber
│   │   └── PaneFocusTracker.swift                      focus diff →
│   │                                                    AsyncStream
│   ├── State/
│   │   └── MainActor/
│   │       ├── Atoms/
│   │       │   ├── NotificationInboxAtom.swift         log
│   │       │   └── NotificationInboxPrefsAtom.swift    grouping/sort/
│   │       │                                            bellEnabled
│   │       └── Persistence/
│   │           └── NotificationInboxStore.swift        wraps both
│   │                                                    atoms; one JSON
│   └── Views/
│       ├── InboxSidebarView.swift                      composed screen
│       ├── DrawerInboxPopover.swift                    composed screen
│       └── DrawerInboxBellHost.swift                   integration
│                                                        wrapper that
│                                                        injects unread
│                                                        count into
│                                                        TrailingActions
│
├── Features/RepoExplorer/                              [RENAMED from
│   │                                                    Features/Sidebar/
│   │                                                    in this ticket;
│   │                                                    pure file-move
│   │                                                    rename, no
│   │                                                    behavior change.
│   │                                                    "Sidebar" is
│   │                                                    composition
│   │                                                    (App/Windows/),
│   │                                                    not a feature —
│   │                                                    this feature is
│   │                                                    the repo
│   │                                                    explorer.]
│   ├── RepoExplorerView.swift                          [MOD — was
│   │                                                    RepoSidebarCon-
│   │                                                    tentView.swift;
│   │                                                    @FocusState
│   │                                                    publishes to
│   │                                                    UIStateAtom.set-
│   │                                                    SidebarHasFocus]
│   ├── RepoExplorerWorktreeRow.swift                   [MOD — was
│   │                                                    SidebarWorktree-
│   │                                                    Row.swift;
│   │                                                    +bell count
│   │                                                    binding]
│   ├── RepoExplorerFilter.swift                        [renamed from
│   │                                                    SidebarFilter]
│   └── RepoExplorerGroupHeader.swift                   [renamed from
│                                                        SidebarGroup-
│                                                        Header]
│
├── Features/Bridge/Transport/                          [EXISTING, MOD]
│   └── RPCRouter.swift                                 [MOD — +inbox.post
│                                                        handler]
│
├── Features/CommandBar/                                [EXISTING, MODS]
│   ├── CommandBarState.swift                           [MOD — +.inbox
│   │                                                    scope; default
│   │                                                    scope reads
│   │                                                    KeyboardOwner]
│   └── CommandBarDataSource.swift                      [MOD — inbox-
│                                                        scoped actions]
│
├── Core/
│   ├── Models/
│   │   ├── SidebarSurface.swift                        [NEW — composition
│   │   │                                                enum, used by
│   │   │                                                UIStateAtom and
│   │   │                                                KeyboardOwner]
│   │   └── KeyboardOwner.swift                         [NEW — derived
│   │                                                    enum]
│   └── State/
│       └── MainActor/
│           ├── Atoms/
│           │   ├── UIStateAtom.swift                   [MOD — +sidebar-
│           │   │                                        Collapsed,
│           │   │                                        +sidebarSurface,
│           │   │                                        +sidebarHasFocus]
│           │   ├── WindowLifecycleAtom.swift           [MOD — +is-
│           │   │                                        WorkspaceWindow-
│           │   │                                        Key accessor]
│           │   └── KeyboardOwnerDerived.swift          [NEW — stateless
│           │                                            factory; follows
│           │                                            WorkspaceFocus-
│           │                                            Derived pattern]
│           └── Persistence/
│               └── UIStateStore.swift                  [MOD — persist
│                                                        sidebarSurface
│                                                        and sidebar-
│                                                        Collapsed;
│                                                        dual-write to
│                                                        UserDefaults
│                                                        short-term]
│
├── Core/Views/Drawer/                                  [EXISTING, MOD]
│   ├── DrawerOverlay.swift                             [MOD — Trailing-
│   │                                                    Actions gains
│   │                                                    onOpenInbox +
│   │                                                    inboxUnread-
│   │                                                    Count]
│   └── DrawerIconBar.swift                             [MOD — render
│                                                        bell after
│                                                        divider]
│
└── App/
    ├── Boot/
    │   └── AppDelegate.swift                           [MOD — instan-
    │                                                    tiate feature
    │                                                    atoms + store +
    │                                                    router]
    ├── Commands/
    │   ├── AppCommand.swift                            [MOD — +.show-
    │   │                                                NotificationIn-
    │   │                                                box, .showWork-
    │   │                                                treeSidebar,
    │   │                                                .showDrawer-
    │   │                                                Inbox]
    │   └── AppShortcut.swift                           [MOD — bind ⌘I,
    │                                                    ⌘S, ⌘⇧I]
    └── Windows/
        ├── MainSplitViewController.swift               [MOD — publish
        │                                                sidebarCollapsed
        │                                                to UIStateAtom;
        │                                                host SidebarSur-
        │                                                faceHost]
        └── SidebarSurfaceHost.swift                    [NEW — SwiftUI
                                                         switcher view;
                                                         imports both
                                                         features; lives
                                                         alongside
                                                         MainSplitView-
                                                         Controller]
```

**Counts:**

```
NEW files                                   14
  Features/NotificationInbox/               10 (full slice)
  Core/Models/ (composition enums)           2
  Core/State/MainActor/Atoms/                1 (KeyboardOwnerDerived)
  App/Windows/ (SidebarSurfaceHost)          1

MODIFIED files                              11
  UIStateAtom + UIStateStore                 2
  WindowLifecycleAtom                        1
  DrawerOverlay + DrawerIconBar              2
  Features/RepoExplorer/ (2 files)           2 (post-rename)
  RPCRouter                                  1
  CommandBar (state + data source)           2
  AppDelegate                                1
  AppCommand + AppShortcut                   2
  MainSplitViewController                    1

RENAMED (in this ticket, file moves only)   4
  Features/Sidebar/* → Features/RepoExplorer/*
    SidebarFilter.swift       → RepoExplorerFilter.swift
    SidebarGroupHeader.swift  → RepoExplorerGroupHeader.swift
    RepoSidebarContentView    → RepoExplorerView
    SidebarWorktreeRow        → RepoExplorerWorktreeRow

UNCHANGED referenced                        ~8
```

### 8.2 Component diagram

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

         ┌─ Presentation state (separate from data flow) ──────┐
         │ UIStateAtom.sidebarSurface  (.repos | .inbox)        │
         │ UIStateAtom.sidebarHasFocus (runtime-only, bool)     │
         │ ⌘I / ⌘S composite commands set these directly.      │
         │ Root sidebar SwiftUI view publishes focus via        │
         │ @FocusState.onChange → setSidebarHasFocus(...)       │
         └─────────────────────────────────────────────────────┘
```

### 8.3 Component placement

| Component | Slice | Rationale |
|---|---|---|
| `Notification` model | `Features/NotificationInbox/Models/` | Feature-owned domain type |
| `NotificationInboxTypes` (grouping/sort enums) | `Features/NotificationInbox/Models/` | Feature-specific; only the feature references them |
| `SidebarSurface` enum | `Core/Models/` | Composition tag; referenced by `UIStateAtom` and `KeyboardOwner` in Core |
| `KeyboardOwner` enum | `Core/Models/` | Composition-derived type; used by `KeyboardOwnerDerived` |
| `NotificationInboxAtom` | `Features/NotificationInbox/State/MainActor/Atoms/` | Feature-scoped state |
| `NotificationInboxPrefsAtom` | `Features/NotificationInbox/State/MainActor/Atoms/` | Feature-scoped prefs |
| `NotificationInboxStore` | `Features/NotificationInbox/State/MainActor/Persistence/` | Feature-scoped persistence; wraps both feature atoms |
| `UIStateAtom` — additions | `Core/State/MainActor/Atoms/` | Existing Core atom; +`sidebarCollapsed`, +`sidebarSurface`, +`sidebarHasFocus` — composition state only |
| `WindowLifecycleAtom` — addition | `Core/State/MainActor/Atoms/` | Existing Core atom; +`isWorkspaceWindowKey` computed accessor |
| `KeyboardOwnerDerived` | `Core/State/MainActor/Atoms/` | Stateless factory; mirrors `WorkspaceFocusDerived`; reads Core atoms |
| `NotificationRouter` | `Features/NotificationInbox/Routing/` | Consumes bus, writes atom |
| `PaneFocusTracker` | `Features/NotificationInbox/Routing/` | Observes `WorkspacePaneAtom`; emits focus-gained transitions |
| `InboxSidebarView` | `Features/NotificationInbox/Views/` | SwiftUI composed screen; rendered by `SidebarSurfaceHost` when `sidebarSurface == .inbox` |
| `DrawerInboxPopover` | `Features/NotificationInbox/Views/` | SwiftUI composed popover |
| `DrawerInboxBellHost` | `Features/NotificationInbox/Views/` | Integration wrapper; reads `NotificationInboxAtom.unreadCount` and injects into `DrawerOverlay.TrailingActions` |
| Inbox `Components/` | `Features/NotificationInbox/Components/` | Row / group header / empty state — reusable within the feature |
| RPC `inbox.post` handler | `Features/Bridge/Transport/` | Minimal addition to `RPCRouter`; emits a new `PaneRuntimeEvent` |
| `.inbox` CommandBar scope | `Features/CommandBar/` | Extends existing scope enum; default-scope logic calls `KeyboardOwnerDerived` |
| `SidebarSurfaceHost` | `App/Windows/` | SwiftUI switcher view; imports both feature surfaces; lives alongside `MainSplitViewController` which already imports features |

Single new feature slice: `Features/NotificationInbox/`.

### 8.4 Subscription pattern

`NotificationRouter` subscribes to `EventBus<RuntimeEnvelope>` via `AsyncStream` (no Combine, no NotificationCenter). It is a **leaf subscriber**: reads facts, writes to its own atom. It does not mutate other atoms, does not route commands. Matches the event-driven enrichment pattern described in `AGENTS.md`.

`NotificationInboxStore` observes `NotificationInboxAtom` via `Observation.withObservationTracking`, triggering a debounced save on any mutation. This matches `UIStateStore` / `RepoCacheStore`.

`PaneFocusTracker` observes `WorkspacePaneAtom` via `Observation.withObservationTracking`, diffs successive `activePaneId` values, and emits an `AsyncStream<PaneId>` of focus-gained transitions consumed by `NotificationRouter`.

**New sidebar-focus seam.** The app currently lacks a general "sidebar has focus" signal (only the filter field at `Features/RepoExplorer/RepoExplorerView.swift` (currently `Features/Sidebar/RepoSidebarContentView.swift:28` pre-rename) tracks focus today). Per the §4.3 contract, each **surface** view (not the root container) publishes its own focus state using its own internal focus enum.

```swift
// Features/NotificationInbox/Views/InboxSidebarView.swift
enum InboxFocus: Hashable {           // feature-internal; not in Core
    case search
    case list
    case row(UUID)
    case groupingMenu
}

@FocusState private var focusedField: InboxFocus?

var body: some View {
    // ... attach .focused($focusedField, equals: .search) on the
    //     search field, .focused($focusedField, equals: .list) on
    //     the list container, etc.
    .onChange(of: focusedField) { _, new in
        uiState.setSidebarHasFocus(new != nil)
    }
}
```

`Features/RepoExplorer/RepoExplorerView.swift` follows the same pattern with its own `RepoExplorerFocus` enum. Because only one surface is visible at a time (driven by `uiState.sidebarSurface`), only one publishes at a time — no race, no conflict.

This preserves the §4.3 contract: `sidebarHasFocus` is true iff any declared focus target inside the currently-visible surface is non-nil. The root sidebar container does NOT publish directly — publishing is a per-surface responsibility so the set of focus targets is explicit and auditable per surface.

Any consumer (`KeyboardOwnerDerived`, CommandBar scope defaulting) reads `uiState.sidebarHasFocus` — no new observation wiring.

### 8.5 Click-through routing

When the user activates a notification (click or Enter):

1. `NotificationInboxAtom.markRead(id: notification.id)`
2. `NotificationInboxAtom.dismissFromDrawer(id: notification.id)` (consistency rule per §4.2)
3. Detect pane liveness: `let paneAlive = workspacePaneAtom.pane(notification.paneId) != nil`
4. If `paneAlive`, dispatch `PaneActionCommand.focusPane(paneId)` → validator → `PaneCoordinator`.
5. If `!paneAlive` (or `notification.paneId` is `nil`), visually flash the row briefly (existing row-highlight animation) and stay in the inbox. No error modal.

## 9. Sidebar bell badge (existing)

The `🔔 N` pill already rendered per-worktree reads from `NotificationInboxAtom.unreadCount(forWorktreeId:)`. Shows `0` when there are no unread (existing behavior). Already wired to the data source once the atom is injected; no new UI work beyond binding. Clicking the pill is currently a no-op; opening Inbox with pre-filter is a stretch deferred (see §12).

## 10. Code-fact grounded details

### 10.1 Pane focus detection

`WorkspaceFocusDerived` at `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` is stateless and snapshot-based. It exposes `activePaneId` but does not emit transition events. To clear state on "pane X gained focus":

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

- **Bell setting UI (v1).** No settings pane exists yet. Bell on/off is a CommandBar action under `.inbox` scope: "Enable bell notifications" / "Disable bell notifications". State persisted on `NotificationInboxPrefsAtom.bellEnabled` (default `false`).
- **Focus target on ⌘I.** Top notification row (first in list given current sort). Makes ↓/↑ immediately productive. `⌥F` is one stroke to search. If CommandBar is key when ⌘I fires, the focus move is skipped (see §5.1).
- **⌘P + ⌘I coexistence.** ⌘I runs its composite command regardless of CommandBar state and **does not dismiss the CommandBar**. If the CommandBar is already open, it stays open and its scope selection is preserved. Fresh ⌘P when the sidebar is showing the inbox and has focus opens CommandBar with `.inbox` as the default scope (§5.2). ⌘S behaves the same way.
- **Global inbox toolbar indicator.** Red dot when any unread > 0 (v1 default). Optional count is deferred until we see the surface in use.
- **"Clear read history" scope.** Removes only read entries. A separate "Clear all notifications" action requires a confirmation dialog before acting.
- **Dead `paneId` on click-through.** Pane liveness checked via `WorkspacePaneAtom.pane(paneId) != nil`. If gone, do not navigate — flash the row briefly and keep focus in Inbox. Notification is already marked read by the click.

## 12. Open questions / deferred

- **User-configurable routing.** v1 has one toggle: bell notifications on/off. All other routing is code-level.
- **Retention tuning.** 1000-cap is provisional. If we see the log grow past that in practice, revisit.
- **Per-workspace vs cross-workspace.** v1 is per-workspace (`notification-inbox.json` under the workspace id). Cross-workspace aggregation is deferred.
- **UNUserNotificationCenter integration.** Separate follow-up ticket.
- **Inbox toolbar button: dot vs count.** v1 picks dot; count is deferred until we see the surface in use.
- **Unified keyboard dispatcher.** The three parallel interception mechanisms (key window, ManagementLayerMonitor, responder chain) could be unified under `KeyboardOwner`. Out of scope for LUNA-361; tracked as accumulating debt in the WIP §5.
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

**Unit tests — `NotificationInboxPrefsAtom`:**

- `setGrouping(.byRepo)` → `grouping == .byRepo`.
- `setSort(.oldestFirst)` → `sort == .oldestFirst`.
- `setBellEnabled(true)` → `bellEnabled == true`.

**Unit tests — `UIStateAtom` composition additions:**

- `setSidebarCollapsed(true)` → `sidebarCollapsed == true`.
- `setSidebarSurface(.inbox)` → `sidebarSurface == .inbox`; `setSidebarSurface(.repos)` → `.repos`.
- `setSidebarHasFocus(true)` → `sidebarHasFocus == true`.
- Persistence: `sidebarCollapsed` and `sidebarSurface` roundtrip through `UIStateStore`; `sidebarHasFocus` is NOT persisted (always resets to `false` on load).

**Unit tests — `KeyboardOwnerDerived`:**

- Precedence: main window not key → `.otherWindow` regardless of other state.
- Precedence: window key + management layer active → `.managementLayer`.
- Precedence: window key + no management + sidebar collapsed → `.none`.
- Precedence: window key + no management + sidebar visible + has focus + surface `.inbox` → `.sidebar(.inbox)`.
- Precedence: window key + no management + sidebar visible + no focus → `.none`.
- Precedence: window key + no management + sidebar visible + has focus + surface `.repos` → `.sidebar(.repos)`.

**Unit tests — `WindowLifecycleAtom.isWorkspaceWindowKey`:**

- `keyWindowId == nil` → `false`.
- `keyWindowId` set but not in `registeredWindowIds` → `false`.
- `keyWindowId` set and in `registeredWindowIds` → `true`.

**Integration test — sidebar surface switching:**

- Start with `sidebarSurface == .repos`. Dispatch the ⌘I composite command. Assert `sidebarSurface == .inbox` and (if CommandBar not key) `sidebarHasFocus == true` after the focus handler runs.
- Dispatch ⌘S. Assert `sidebarSurface == .repos` and focus state is unchanged.

**Integration test — emission to display:**

- Emit `desktopNotificationRequested` on `EventBus` → assert `NotificationInboxAtom` contains the notification with correct denormalized context.
- Click notification → assert `PaneActionCommand.focusPane` dispatched → assert notification marked read.

**Integration test — Bridge RPC:**

- Fixture: valid `inbox.post` payload from a bridge pane → round-trips through `RPCRouter` → lands in `NotificationInboxAtom` with correct `paneId` inferred from bridge context.
- Agent cannot spoof `paneId` for another pane (assert payload `paneId` is ignored if present).

## 14. Documentation deliverables

- This spec, committed.
- [Interaction Model WIP](2026-04-18-interaction-model-wip.md), committed (sibling doc; authoritative for the layer/focus model).
- Update `docs/architecture/workspace_data_architecture.md` event-bus consumer section to list `NotificationRouter` as a new leaf subscriber.
- [directory_structure.md](../../architecture/directory_structure.md) updated in this ticket: Feature Slice Self-Containment, universal `State/MainActor/{Atoms,Persistence}/` path, SharedComponents layer, composition-state-vs-feature-state rule.
- [AGENTS.md](../../../AGENTS.md) updated in this ticket: atoms/stores path convention, composition vs feature state, `ManagementLayerAtom` naming fix.
- Update `docs/architecture/workspace_data_architecture.md` event-bus consumer section to list `NotificationRouter` as a new leaf subscriber (in this ticket).
- Add inbox shortcut entry to keyboard shortcut documentation (create if not present).

## 15. Out of scope (explicit)

- macOS UNUserNotificationCenter
- Cross-workspace aggregation
- Email / Slack / remote fan-out
- Rich notification content (images, actions beyond click-through)
- User-configurable routing UI (beyond bell on/off)
- Fuzzy search in inbox
- Collapsible group sections
- Toast / banner / transient popup of any kind
- Unified keyboard dispatcher (deferred debt; see WIP §5)
- Introducing `SharedComponents/` at top level (deferred to a dedicated design-system ticket — doc-only in this ticket)

---

## Appendix A — Glossary

- **Notification Inbox** — the persistent notification log; both sidebar view and drawer popover share the same underlying data (`NotificationInboxAtom`).
- **Sidebar surface** — which content the sidebar renders. Stored on `UIStateAtom.sidebarSurface`: `.repos` or `.inbox`.
- **Drawer Inbox** — the popover surface anchored on a drawer's bell icon; shows notifications for panes in that drawer only.
- **Global Inbox** — the sidebar view showing all notifications across all tabs/panes/drawers in the workspace.
- **Read / Unread** — state in the global inbox; toggled by focus-through, Enter, Space.
- **Dismissed from drawer** — local drawer state; notification disappears from drawer popover but remains in global inbox.
- **`KeyboardOwner`** — derived abstraction naming who owns keyboard interpretation at a moment. Designed in [Interaction Model WIP](2026-04-18-interaction-model-wip.md) §4; implemented in this ticket per §4.4. Not a Layer; not stored. Consumed in v1 by CommandBar default-scope logic (§5.2); not called by the inbox's own runtime shortcuts (those dispatch via native SwiftUI `.keyboardShortcut()` + responder chain).
