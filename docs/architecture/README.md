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

| Document | Covers |
|----------|--------|
| [Component Architecture](component_architecture.md) | Data model, service layer, command bar, data flow, persistence, invariants |
| [Pane Runtime Architecture](pane_runtime_architecture.md) | Pane runtime contracts (1-16), event taxonomy, priority system, adapter/runtime/coordinator layers, filesystem batching, attach readiness (5a), restart reconcile (5b), visibility-tier scheduling (12a), Ghostty action coverage (7a), RuntimeCommand dispatch (10), source/sink/projection vocabulary, agent harness model, directory placement, migration path |
| [Pane Runtime EventBus Design](pane_runtime_eventbus_design.md) | EventBus coordination: actor fan-out, boundary actors (filesystem/forge/container) plus plugin context mediation, `@concurrent nonisolated` for per-pane work, multiplexed `@Observable` + event stream, connection patterns (AsyncStream vs direct call vs @Observable), data flow per contract, Swift 6.2 threading model |
| [Window System Design](window_system_design.md) | Window/tab/pane/drawer data model, dynamic views, arrangements, orphaned pane pool, ownership invariants |
| [Session Lifecycle](session_lifecycle.md) | Pane identity contract, creation, close, undo, restore, runtime status, zmx backend |
| [Zmx Restore and Sizing](zmx_restore_and_sizing.md) | Deferred attach sequencing, geometry readiness, restart reconcile policy, and zmx restore/sizing test coverage |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface ownership, state machine, health monitoring, crash isolation, CWD propagation |
| [App Architecture](appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid shell, controllers, command bar panel, event handling |
| [Directory Structure](directory_structure.md) | Module boundaries, Core vs Features decision process, import rule, component placement |
| [Swift-React Bridge](swift_react_bridge_design.md) | Three-stream bridge architecture, push pipeline, JSON-RPC command channel, content world isolation |
| [JTBD & Requirements](jtbd_and_requirements.md) | Jobs to be done, pain points, and requirements for the dynamic window system |

## Related

- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — Setup procedures, DeepWiki sources, and research guidance
