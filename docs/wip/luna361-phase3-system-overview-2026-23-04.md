# LUNA-361 Phase 3 — System Overview (actual state on disk)

**Date:** 2026-04-23
**Branch:** `notification-system-1-attended-pane`
**Current branch checked:** through `014f1c9` hardening restore plus `5ed91ee` plan cleanup
**Status:** Main code loop was green after the main merge and hardening restore. All code tasks from Phase 3/3b/3c that belong in this PR have landed, but the live OSC visual smoke remains unclaimed. `docs/wip/` is tracked working documentation in this branch.

**Note:** This overview was first written at `b65f195`; the companion checklist has been refreshed through the Phase 3b/3c hardening work and is the source of truth for current done/not-done status.

**Purpose:** Grounded snapshot of the Phase 3 inbox as actually implemented — what atoms exist, where files live, what's wired, what a user can do, and what notification sources are live vs dormant.

---

## End-of-Phase-3 goal vs actual

```
┌─ END-OF-PHASE-3 GOAL vs ACTUAL ──────────────────────────────────────┐
│                                                                      │
│  Goal (from spec §1-§3):                                             │
│    A functional in-app notification inbox — notifications from       │
│    terminal, agents, approvals, and security events land in a        │
│    sidebar/drawer UI the user can navigate, act on, and dismiss.     │
│                                                                      │
│  Actual delivery:                                                    │
│    Inbox infrastructure is complete and LIVE for the two sources     │
│    that exist in the codebase today (terminal + bridge). Approval    │
│    and security sources are pre-wired on the receive side but have   │
│    no upstream emitters yet — their systems don't exist.             │
│                                                                      │
│  Translation: notifications DO flow. Just not from every kind        │
│  listed in the spec's §7 routing table.                              │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Event wiring status

```
┌─ EVENT WIRING STATUS ────────────────────────────────────────────────┐
│                                                                      │
│   Source                            Emitter exists    Lands in UI?   │
│   ────────────────────────────────  ────────────────  ─────────────  │
│   Terminal OSC 9/777                yes               YES            │
│     GhosttyAdapter.swift:824                                         │
│   Terminal bell                     yes               YES (gated)    │
│     GhosttyAdapter.swift:533                                         │
│   Terminal command finished         yes               YES (gated)    │
│     GhosttyActionRouter.swift:358                                    │
│   Bridge inbox.post RPC             yes               YES            │
│     InboxMethods.swift + BridgePaneController:288                    │
│                                                                      │
│   ArtifactEvent.approvalRequested   NO                dormant        │
│     router classifies; nothing emits                                 │
│   SecurityEvent.networkEgressBlocked                                 │
│   SecurityEvent.filesystemAccessDenied                               │
│   SecurityEvent.secretAccessed      NO (all)          dormant        │
│   SecurityEvent.processSpawnBlocked                                  │
│   SecurityEvent.sandboxHealthChanged                                 │
│                                                                      │
│   Gates in place:                                                    │
│     bellRang         → InboxNotificationPrefsAtom.bellEnabled        │
│     commandFinished  → unfocused + duration ≥                        │
│                        AppPolicies.InboxNotification                 │
│                         .commandFinishedMinDurationSeconds           │
│     sandboxHealth    → true→false edge per pane (when emitters       │
│                        exist)                                        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Atom inventory (actual files on disk)

```
┌─ ATOM INVENTORY ─────────────────────────────────────────────────────┐
│                                                                      │
│  CORE — Sources/AgentStudio/Core/State/MainActor/Atoms/              │
│                                                                      │
│   Canonical (store-backed or app-lifetime):                          │
│    AppLifecycleAtom              app activation state                │
│    ManagementLayerAtom           management-mode active?             │
│    RepoCacheAtom                 git enrichment, PR counts           │
│    SessionRuntimeAtom            per-pane runtime status             │
│    UIStateAtom                   sidebar shell + prefs               │
│    WelcomeAtom                   welcome/launcher state              │
│    WindowLifecycleAtom           key window, registered windows      │
│    WorkspaceMetadataAtom         workspace id + window geom          │
│    WorkspacePaneAtom             pane records (content, drawer)      │
│    WorkspaceRepositoryTopologyAtom                                   │
│                                  repos + worktrees                   │
│    WorkspaceTabArrangementAtom   arrangements per tab                │
│    WorkspaceTabLayoutAtom        tabs + active tab + active          │
│                                  pane (CANONICAL active-pane         │
│                                  source)                             │
│    WorkspaceTabShellAtom         shell/active-tab state              │
│    PaneFilesystemProjectionAtom  fs projection per pane              │
│                                                                      │
│   Derived (push-based, no canonical state):                          │
│    AttendedPaneAtom              ← NEW in Phase 3                    │
│                                  attendedPaneId: UUID?               │
│                                  transitions: AsyncStream<UUID?>     │
│                                  derived from 3 inputs:              │
│                                    tabLayout.activeTab.activePaneId  │
│                                    windowLifecycle.isWorkspaceKey    │
│                                    !managementLayer.isActive         │
│                                                                      │
│  FEATURE — Features/InboxNotification/State/MainActor/Atoms/         │
│                                                                      │
│    InboxNotificationAtom         the log + mutation surface          │
│                                    append, markRead, markAllRead,    │
│                                    dismissFromDrawer, clearAll,      │
│                                    toggleReadState, retention cap    │
│    InboxNotificationPrefsAtom    grouping, sort, bellEnabled         │
│                                                                      │
│  DERIVED HELPERS (structs, no state):                                │
│    ArrangementDerived            arrangement reads                   │
│    CommandContextDerived         command-visibility snapshot         │
│                                  (← renamed from WorkspaceFocus)     │
│    PaneDisplayDerived            pane display formatting             │
│    TabDisplayDerived             tab display formatting              │
│    WorkspaceTabDerived           tab composition over shell+arr      │
│    WorkspaceLookupDerived        lookup helpers                      │
│    DynamicViewDerived            view composition                    │
│                                                                      │
│  Everything builds through AtomRegistry (Infrastructure/AtomLib/).   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Feature slice: Features/InboxNotification/

```
┌─ FEATURE SLICE: Features/InboxNotification/ ─────────────────────────┐
│                                                                      │
│   Components/                                                        │
│     InboxNotificationEmptyState.swift      12 L                      │
│     InboxNotificationGroupHeader.swift     24 L                      │
│     InboxRow.swift                         76 L                      │
│                                                                      │
│   Models/                                                            │
│     InboxNotification.swift                33 L   core record        │
│     InboxNotificationListModel.swift      169 L   grouping/sort/     │
│                                                   search/nav         │
│                                                                      │
│   Routing/                                                           │
│     InboxNotificationRouter.swift         200 L   leaf bus sub       │
│     PaneFocusTracker.swift                 45 L   attended pane      │
│                                                   → focus-gained     │
│                                                   stream             │
│                                                                      │
│   State/MainActor/                                                   │
│     Atoms/InboxNotificationAtom.swift     106 L                      │
│     Atoms/InboxNotificationPrefsAtom.swift 25 L                      │
│     Persistence/InboxNotificationStore.swift                         │
│                                           102 L   JSON + debounce    │
│                                                   + quarantine       │
│                                                                      │
│   Views/                                                             │
│     InboxNotificationSidebarView.swift    419 L   main inbox screen  │
│     InboxNotificationDrawerPopover.swift   81 L   drawer popover     │
│     InboxNotificationDrawerPresenter.swift 39 L   popover request    │
│                                                   state              │
│                                                                      │
│   NO Bridge/ subfolder — inbox.post RPC lives in                     │
│   Features/Bridge/Transport/Methods/InboxMethods.swift               │
│   and routes through BridgePaneController.ingestRuntimeEvent.        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Cross-cutting seams (Core / App / other features)

```
┌─ CROSS-CUTTING SEAMS ────────────────────────────────────────────────┐
│                                                                      │
│  Core/Models/                                                        │
│    InboxNotificationCommands.swift          CommandBar callback      │
│                                             bundle — 10 @MainActor   │
│                                             @Sendable closures       │
│    InboxNotificationTypes.swift             Grouping + Sort enums    │
│                                                                      │
│  Core/Views/Drawer/                                                  │
│    PaneInboxPresentation.swift              drawer placement seam —  │
│                                             6 closures + one         │
│                                             trailingActions helper.  │
│                                             Primitives + AnyView     │
│                                             only. Zero feature types │
│                                             leak into Core.          │
│                                                                      │
│  Core/State/MainActor/Persistence/                                   │
│    WorkspaceStore+DrawerSelection.swift     visiblePaneIdsFor-       │
│                                             ActiveExpandedDrawer     │
│                                                                      │
│  App/Boot/ (composition root — where Core ignorance ends)            │
│    AppDelegate+InboxNotificationBoot.swift     constructs atom +     │
│                                                store + router +      │
│                                                tracker; wires        │
│                                                lifecycle             │
│    AppDelegate+InboxNotificationCommands.swift builds the            │
│                                                InboxNotification-    │
│                                                Commands bundle       │
│                                                from atom refs        │
│    AppDelegate+CommandBar.swift                binds the commands    │
│                                                bundle into           │
│                                                CommandBarData-       │
│                                                Source                │
│                                                                      │
│  Features/CommandBar/                                                │
│    CommandBarDataSource+Inbox.swift         10 inbox actions         │
│                                             (markAllRead,            │
│                                             clearReadHistory,        │
│                                             clearAll, 4 grouping     │
│                                             rows, toggleSort,        │
│                                             toggleBell, return)      │
│                                             — consumes Commands      │
│                                             bundle, no atom          │
│                                             imports                  │
│                                                                      │
│  Features/Bridge/Transport/Methods/                                  │
│    InboxMethods.swift                       inbox.post JSON-RPC      │
│                                             handler, pane id         │
│                                             derived server-side      │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Data flow — one notification's journey

```
┌─ DATA FLOW ──────────────────────────────────────────────────────────┐
│                                                                      │
│  Emit side (4 live sources):                                         │
│                                                                      │
│    Ghostty C API                Bridge JSON-RPC                      │
│    (terminal event)             (agent calling inbox.post)           │
│           │                              │                           │
│           ▼                              ▼                           │
│    GhosttyAdapter               InboxMethods.handle                  │
│    GhosttyActionRouter          BridgePaneController                 │
│           │                     .ingestRuntimeEvent                  │
│           ▼                              │                           │
│    TerminalRuntime.emit                  │                           │
│           │                              │                           │
│           └──────────────┬───────────────┘                           │
│                          │                                           │
│                          ▼                                           │
│              PaneRuntimeEventBus.shared                              │
│                   (AsyncStream of                                    │
│                   RuntimeEnvelope)                                   │
│                          │                                           │
│                          ▼                                           │
│              InboxNotificationRouter                                 │
│              .handle(envelope)                                       │
│                  │                                                   │
│                  ├─► classify(envelope) → InboxNotificationKind?     │
│                  │     • bellRang        if prefs.bellEnabled        │
│                  │     • commandFinished if not attended AND         │
│                  │                       duration ≥ threshold        │
│                  │     • sandboxHealth   if edge true→false          │
│                  │                       (per pane, router state)    │
│                  │     • others unconditional                        │
│                  │                                                   │
│                  ▼                                                   │
│              InboxNotificationAtom.append(note)                      │
│                  │  (retention cap + id dedup)                       │
│                  │                                                   │
│       ┌──────────┼──────────┬──────────┬──────────┐                  │
│       ▼          ▼          ▼          ▼          ▼                  │
│  Sidebar    Toolbar    Drawer     Worktree    Persistence            │
│  view       bell dot   bell +     row pill    store                  │
│             (global    popover    (primitive  (debounced             │
│             unread)    (drawer    Int prop)   JSON file +            │
│                        scoped)                quarantine)            │
│                                                                      │
│  Dismiss side:                                                       │
│    AttendedPaneAtom detects attention change                         │
│        ↓ transitions                                                 │
│    PaneFocusTracker emits focus-gained                               │
│        ↓                                                             │
│    InboxNotificationRouter: markRead + dismissFromDrawer             │
│        ↓                                                             │
│    Atoms notify observers → UI updates                               │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## What the user sees at end of Phase 3

```
┌─ USER-FACING AFFORDANCES ────────────────────────────────────────────┐
│                                                                      │
│  Affordances live                                                    │
│    ⌘I                  toggle inbox in sidebar                       │
│    ⌘S                  toggle worktree list in sidebar               │
│    ⌘⇧I                 pane inbox popover                            │
│    Toolbar bell icon   with red dot when global unread > 0           │
│    Per-worktree pill   🔔 N in RepoExplorerWorktreeRow               │
│    Drawer bell         numeric count, opens popover                  │
│    ⌘P from inbox       defaults to .inbox scope (10 actions)         │
│    Inbox keymap        ⌥F search, ⌥G grouping, ⌥S sort,              │
│                        ↓↑ navigate rows (headers skipped),           │
│                        ⌥↓⌥↑ group boundaries,                        │
│                        ⌘↓⌘↑ first/last,                              │
│                        Enter activate, Space toggle read,            │
│                        Esc clear-search-or-return-focus              │
│                                                                      │
│  Data                                                                │
│    Terminal OSC notifications appear in inbox                        │
│    Terminal bell alerts appear (if enabled)                          │
│    Long unfocused commands appear (default ≥ 10s)                    │
│    Agent JSON-RPC notifications appear                               │
│    Focus-gained auto-marks-read + auto-dismisses-from-drawer         │
│    Click-through focuses source pane (flash if pane is gone)         │
│    Persist across restarts, quarantine on corrupt load               │
│                                                                      │
│  Not yet                                                             │
│    Approval requests (system doesn't emit them yet)                  │
│    Security events (system doesn't emit them yet)                    │
│    macOS UNUserNotificationCenter (explicitly deferred)              │
│    Full live OSC visual proof across sidebar, toolbar, drawer,       │
│    and worktree pill surfaces                                        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

**Summary**: notifications ARE wired for the sources that exist — terminal + bridge — and the full UI + persistence + keymap are live. The approval/security kinds in spec §7 are pre-wired on the inbox side but dormant because those upstream systems haven't been built. Phase 3 ships a working inbox with two live sources and a ready slot for two future sources. Real feature, not notifications-free plumbing. The remaining current-PR evidence gap is native visual OSC smoke across every visible notification surface.
