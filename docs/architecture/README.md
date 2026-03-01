# Agent Studio Architecture

## TL;DR

Agent Studio is a macOS terminal application that embeds Ghostty terminal surfaces within a project/worktree management shell. The app uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. State is distributed across independent `@Observable` stores (Jotai-style atomic stores) with `private(set)` for unidirectional flow (Valtio-style). A coordinator pattern (`PaneCoordinator`) sequences cross-store operations. Panes are the primary identity — they exist independently of layout, view, or surface. Actions flow through a validated pipeline, and persistence is debounced.

## System Overview

```
┌───────────────────────────────────────────────────────────────┐
│                        AppDelegate                            │
│                                                               │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │WorkspaceStore │  │SessionRuntime │  │SurfaceManager    │  │
│  │ (workspace)   │  │(backends)     │  │(surfaces)        │  │
│  └───────┬───────┘  └───────┬───────┘  └────────┬─────────┘  │
│          │                  │                    │             │
│  ┌───────┴──────────────────┴────────────────────┴──────────┐ │
│  │              PaneCoordinator                              │ │
│  │     (sequences cross-store ops, owns no domain state)     │ │
│  └──────────────────────────┬───────────────────────────────┘ │
│                             │                                 │
│  ┌──────────────┐  ┌───────┴──────┐  ┌──────────────────────┐│
│  │ ViewRegistry │  │ TabBarAdapter│  │CommandBarPanel       ││
│  │(paneId→View) │  │(derived UI)  │  │Controller (⌘P)      ││
│  └──────────────┘  └──────────────┘  └──────────────────────┘│
└───────────────────────────────────────────────────────────────┘
  * WorkspacePersistor is internal to WorkspaceStore (JSON I/O)
  * Each store is @Observable with private(set) for unidirectional flow
```

## Architecture Principles

- **Pane as primary entity** — `Pane` is the stable identity across model, runtime, view registry, surface metadata, and restore flows
- **Atomic stores (Jotai-style)** — Each domain has its own `@Observable` store: `WorkspaceStore` (workspace structure), `SurfaceManager` (Ghostty surfaces), `SessionRuntime` (backends). No god-store. Each store owns one domain and has one reason to change.
- **Unidirectional flow (Valtio-style)** — All store state is `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers.
- **Coordinator for cross-store sequencing** — A coordinator sequences operations across stores for a single user action. Owns no state, contains no domain logic.
- **Immutable layout tree** — `Layout` is a pure value type; operations return new instances, never mutate
- **Surface independence** — Ghostty surfaces are ephemeral runtime resources; the model layer never holds `NSView` references
- **@MainActor everywhere** — Thread safety enforced at compile time, no runtime races
- **AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing Combine/NotificationCenter migrated incrementally.

## Data Model at a Glance

```
WorkspaceStore
├── repos: [Repo]
│   └── worktrees: [Worktree]          ← git branches on disk
├── panes: [Pane]                       ← primary pane identities
│   ├── source: .worktree | .floating
│   ├── provider: .ghostty | .zmx
│   ├── lifetime: .persistent | .temporary
│   └── residency: .active | .pendingUndo | .backgrounded
└── views: [ViewDefinition]             ← named pane arrangements
    ├── kind: .main | .saved | .worktree | .dynamic
    └── tabs: [Tab]
        └── layout: Layout              ← pure value-type split tree
            └── Node: .leaf(paneId) | .split(Split)
```

## Mutation Flow (Summary)

```
User Action → PaneAction → ActionResolver → ActionValidator
  → PaneCoordinator → Store.mutate()
    → @Observable tracks → SwiftUI re-renders
    → markDirty() → debounced save (500ms)

Command Bar → CommandDispatcher.dispatch() → CommandHandler
  → ActionResolver → ActionValidator → PaneCoordinator
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
| [Directory Structure](directory_structure.md) | Module boundaries and file placement | Core vs Features decision process, import rule, component → slice map, placement rationale |
| [Swift-React Bridge](swift_react_bridge_design.md) | Bridge transport for React panes | Three-stream bridge architecture, push pipeline, JSON-RPC command channel, content world isolation |
| [JTBD & Requirements](jtbd_and_requirements.md) | Product requirements | Jobs to be done, pain points, and requirements for the dynamic window system |

## Related

- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — Setup procedures, DeepWiki sources, and research guidance
