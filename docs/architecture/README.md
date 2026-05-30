# Agent Studio Architecture

## TL;DR

Agent Studio is a macOS terminal application that embeds Ghostty terminal surfaces within a project/worktree management shell. The app uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. Canonical mutable state is distributed across independent `@MainActor @Observable` atoms (Jotai-style atomic stores) with `private(set)` for unidirectional flow (Valtio-style). Persistence wrappers such as `WorkspaceStore`, `RepoCacheStore`, and `UIStateStore` wrap atoms instead of owning broad domains directly. `PaneCoordinator` sequences cross-store and cross-feature operations from the App composition root. Panes are the primary identity — they exist independently of layout, view, or surface. Actions flow through a validated pipeline, and persistence is debounced.

## System Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                            AppDelegate                                  │
│                                                                        │
│  PERSISTENCE WRAPPERS OVER MAIN-ACTOR ATOMS                           │
│  ┌───────────────┐  ┌─────────────────┐  ┌───────────────┐            │
│  │WorkspaceStore │  │RepoCacheStore   │  │UIStateStore   │            │
│  │metadata/topol │  │RepoCacheAtom    │  │SidebarMemory  │            │
│  │pane/tab atoms │  │(enrichment)     │  │(sidebar mem)  │            │
│  └───────┬───────┘  └────────┬────────┘  └───────────────┘            │
│          │                   │                                         │
│  ┌───────┴──────────┐  ┌─────┴────────────┐                           │
│  │AppLifecycleAtom │  │WindowLifecycleAtom│                         │
│  │(active/terminate)│  │(focus/key + launch geometry)│                │
│  └───────┬──────────┘  └─────┬────────────┘                           │
│          │                   │                                         │
│          │    ┌──────────────┴──────────────────┐                      │
│          │    │   WorkspaceCacheCoordinator      │                      │
│          │    │   (event bus → store mutations)  │                      │
│          │    └──────────────┬──────────────────┘                      │
│          │                   │ consumes                                 │
│  ┌───────┴───────────────────┴─────────────────────────────────┐       │
│  │                    EventBus<RuntimeEnvelope>                  │       │
│  └──────┬────────────────┬─────────────────┬───────────────────┘       │
│         │                │                 │                           │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐                    │
│  │Filesystem   │  │GitProjector │  │ForgeActor   │                    │
│  │Actor        │  │(git status) │  │(PR counts)  │                    │
│  └─────────────┘  └─────────────┘  └─────────────┘                    │
│                                                                        │
│  ┌───────────────┐  ┌───────────────┐                                  │
│  │SessionRuntime │  │SurfaceManager │                                  │
│  │(backends)     │  │(surfaces)     │                                  │
│  └───────┬───────┘  └────────┬──────┘                                  │
│  ┌───────┴───────────────────┴──────────────────────────────────┐      │
│  │              PaneCoordinator                                  │      │
│  │     (sequences cross-store ops, owns no domain state)         │      │
│  └───────────────────────────────────────────────────────────────┘      │
└────────────────────────────────────────────────────────────────────────┘
```

## Architecture Principles

- **Pane as primary entity** — `Pane` is the stable identity across model, runtime, view registry, surface metadata, and restore flows
- **Atomic stores (Jotai-style)** — Each domain has its own `@MainActor @Observable` atom: workspace metadata, repository topology, pane registry, tab layout, repo enrichment, UI shell state, app lifecycle, window lifecycle, terminal surfaces, runtime status, and feature-local state. No god-store. Each atom owns one domain and has one reason to change. Persistence wrappers save atom groups to disk. Feature atoms live inside their feature slice at `Features/<slice>/State/MainActor/Atoms/` — see [directory_structure.md — Feature Slice Self-Containment](directory_structure.md).
- **Unidirectional flow (Valtio-style)** — All store state is `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers.
- **Coordinator for cross-store sequencing** — A coordinator sequences operations across stores for a single user action. Owns no state, contains no domain logic.
- **Lifecycle ingress stays separate** — `ApplicationLifecycleMonitor` owns AppKit ingress only. It mutates `AppLifecycleAtom` and `WindowLifecycleAtom`, both `@Observable` atomic stores with `private(set)` mutation surfaces. `WindowLifecycleAtom` holds transient window facts only: key/focus state, terminal container bounds, launch-layout-settle state, and derived readiness; none of those readiness properties are persisted.
- **Immutable layout tree** — `Layout` is a pure value type; operations return new instances, never mutate
- **Surface independence** — Ghostty surfaces are ephemeral runtime resources; the model layer never holds `NSView` references
- **@MainActor everywhere** — Thread safety enforced at compile time, no runtime races
- **AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing Combine/NotificationCenter migrated incrementally.

Current atom vocabulary:

- **Atoms** own mutable state and synchronous domain operations, for example `ActiveWorkspaceSelectionAtom`, `WorkspaceIdentityAtom`, `WorkspaceWindowMemoryAtom`, `WorkspaceRepositoryTopologyAtom`, `WorkspacePaneAtom`, `WorkspaceTabLayoutAtom`, `RepoCacheAtom`, `WorkspaceSidebarMemoryAtom`, `SidebarFocusRuntimeAtom`, `AppLifecycleAtom`, `WindowLifecycleAtom`, `SessionRuntimeAtom`, and feature atoms.
- **Persistence wrappers** own load/save boundaries and debounced disk I/O, for example `WorkspaceStore`, `RepoCacheStore`, `SidebarCacheStore`, and `UIStateStore`.
- **Derived readers** compute projections without owning data, for example `WorkspaceFocusDerived`, `WorkspaceLookupDerived`, `PaneDisplayDerived`, and `TabDisplayDerived`.
- **Coordinators** sequence mutations across atoms/stores and runtime systems. They own no durable domain state.

## Coordination Planes

Use the smallest boundary that still matches the kind of work being done.

| Change shape | Boundary | Notes |
|--------------|----------|-------|
| Workspace mutation | `PaneActionCommand` | Validator-gated, then sequenced into stores by `PaneCoordinator`. |
| Runtime command | `RuntimeCommand` | Direct command routing to a single runtime via `RuntimeRegistry`. |
| Runtime fact | `PaneRuntimeEventBus` | Fan-out for runtime/system facts only. Never route commands through it. |
| App-level notification that is not a command | `AppEventBus` | Notification fan-out only. |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` | Owns AppKit callbacks and writes lifecycle stores. |
| UI-only local state | Local `@Observable` view/controller state | Keep it local; do not bounce it through a bus or `NotificationCenter`. |

The old `AppCommand -> AppEventBus -> controller -> PaneActionCommand` chain is retired. Workspace work now enters through validated `PaneActionCommand` routing directly, and AppKit lifecycle state lives in the lifecycle stores.

## Data Model at a Glance

```
ActiveWorkspaceSelectionAtom            ← global active workspace id

WorkspaceStore (workspace.state.json persistence wrapper)
├── WorkspaceIdentityAtom               ← workspace id, name, created-at timestamp
├── WorkspaceWindowMemoryAtom           ← local sidebar width and window frame
├── WorkspaceRepositoryTopologyAtom     ← repos, worktrees, watched paths, availability
├── WorkspacePaneAtom                   ← panes, metadata/content/residency, drawers
└── WorkspaceTabLayoutAtom              ← tabs, arrangements, active selection, layout

RepoCacheAtom (derived enrichment — workspace.cache.json, rebuildable)
├── repoEnrichmentByRepoId             ← origin, identity, groupKey, displayName
├── worktreeEnrichmentByWorktreeId     ← branch, git snapshot
├── pullRequestCountByWorktreeId       ← PR badges
└── (notification counts moved — unread bells now derive from
                                        InboxNotificationAtom.unreadCount(
                                        forWorktreeId:) per LUNA-361)

WorkspaceSidebarMemoryAtom (workspace.ui.json)
├── filterText, isFilterVisible
└── sidebarCollapsed, sidebarSurface

SidebarFocusRuntimeAtom (runtime only)
└── sidebarHasFocus

WorkspaceSidebarState
└── composed UI-facing reader/mutator over sidebar memory + runtime focus
```

## Mutation Flow (Summary)

```
User Action → PaneActionCommand
  → WorkspaceCommandResolver.snapshot() builds ActionStateSnapshot
  → WorkspaceCommandValidator.validate(action, snapshot) → ValidatedAction
  → PaneCoordinator → Store.mutate()
    → @Observable tracks → SwiftUI re-renders
    → markDirty() → debounced save (500ms)

Command Bar
  → CommandSpec visibility + metadata
  → CommandDispatcher.dispatch()
  → WorkspaceCommandHandling (PaneTabViewController)
  → WorkspaceCommandResolver.resolve() → PaneActionCommand
  → WorkspaceCommandResolver.snapshot() → ActionStateSnapshot
  → WorkspaceCommandValidator.validate() → PaneCoordinator

Runtime command → PaneCoordinator.dispatchRuntimeCommand()
  → RuntimeRegistry.runtime(for:) → runtime.handleCommand(envelope)

Runtime fact → PaneRuntimeEventBus.post(envelope)
  → WorkspaceCacheCoordinator / other consumers subscribe independently

App-level notification that is not a command → AppEventBus
AppKit/macOS lifecycle ingress → ApplicationLifecycleMonitor → AppLifecycleAtom / WindowLifecycleAtom
```

## Document Index

Each document owns a specific concern. No two documents are authoritative for the same topic. When in doubt about where something belongs, the ownership column determines the home.

| Document | Ownership | Covers |
|----------|-----------|--------|
| [Component Architecture](component_architecture.md) | Structural overview — how components compose | Data model (pane, tab, layout, session), service layer, command bar, persistence format, store boundaries, coordinator role, invariants |
| [Workspace Data Architecture](workspace_data_architecture.md) | Workspace-level data — repos, worktrees, enrichment | Three-tier persistence (canonical/cache/UI), canonical vs enrichment models, enrichment pipeline (FilesystemActor → GitWorkingDirectoryProjector → ForgeActor → CacheCoordinator), topology/discovery lifecycle, sidebar data flow, ordering/replay contracts |
| [Pane Runtime Architecture](pane_runtime_architecture.md) | Pane-level runtime contracts | Pane runtime contracts (C1-C16), event envelope (RuntimeEnvelope), per-pane event taxonomy, priority system, adapter/runtime/coordinator layers, filesystem batching, attach readiness (5a), restart reconcile (5b), visibility-tier scheduling (12a), Ghostty action coverage (7a), RuntimeCommand dispatch (10), source/sink/projection vocabulary, agent harness model, directory placement, migration path |
| [Pane Runtime EventBus Design](pane_runtime_eventbus_design.md) | EventBus threading and coordination | Actor fan-out, boundary actors (FilesystemActor, ForgeActor, ContainerActor) plus plugin context mediation, `@concurrent nonisolated` for per-pane work, multiplexed `@Observable` + event stream, connection patterns (AsyncStream vs direct call vs @Observable), data flow per contract, Swift 6.2 threading model |
| [Window System Design](window_system_design.md) | Window/tab/pane structural model | Window/tab/pane/drawer data model, dynamic views, arrangements, orphaned pane pool, ownership invariants |
| [Session Lifecycle](session_lifecycle.md) | Pane identity and session backend lifecycle | Pane identity contract, creation, close, undo, restore, runtime status, zmx backend |
| [Zmx Restore and Sizing](zmx_restore_and_sizing.md) | Zmx-specific attach and sizing | Deferred attach sequencing, geometry readiness, restart reconcile policy, zmx restore/sizing test coverage |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface management | Surface ownership, state machine, health monitoring, crash isolation, CWD propagation |
| [App Architecture](appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid shell | AppKit hosting model, controllers, command bar panel, event handling |
| [Commands and Shortcuts](commands_and_shortcuts.md) | Command + shortcut system | Four-file model (AppCommand / AppShortcut / CommandSpec / LocalActionSpec), decision tree for adding bindings, contexts, alternateTriggers, where constants live (AppShortcut vs AppPolicies vs AppStyles vs LocalActionSpec) |
| [Remote zmx Architecture Ideas](remote_zmx_architecture_ideas.md) | Remote zmx daemons and fork strategy | SSH tunnel architecture (Option C), security model, connection lifecycle, case for forking zmx |
| [Directory Structure](directory_structure.md) | Module boundaries and file placement | Core vs Features decision process, import rule, component → slice map, placement rationale |
| [Swift-React Bridge](swift_react_bridge_design.md) | Bridge architecture and current LUNA-337 status | Three-stream bridge architecture, push pipeline, JSON-RPC command channel, content world isolation, read-only CodeView/Shiki review surface, and explicit implemented-vs-planned bridge delivery boundaries |
| [JTBD & Requirements](jtbd_and_requirements.md) | Product requirements | Jobs to be done, pain points, and requirements for the dynamic window system |

## Related

- Component note: `SharedComponents/EditorChooser/` owns the reusable numbered editor chooser menu content and bookmark UI used by host shells such as the drawer toolbar.
- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — Setup procedures, DeepWiki sources, and research guidance
- Platform docs used by this architecture: [Swift](https://www.swift.org/documentation/), [Swift Package Manager](https://docs.swift.org/package-manager/), [AppKit](https://developer.apple.com/documentation/appkit), [SwiftUI](https://developer.apple.com/documentation/swiftui), [Observation](https://developer.apple.com/documentation/observation), [WebKit](https://developer.apple.com/documentation/webkit), and [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
