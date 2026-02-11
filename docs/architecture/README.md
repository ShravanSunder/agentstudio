# Agent Studio Architecture

## TL;DR

Agent Studio is a macOS terminal application that embeds Ghostty terminal surfaces within a project/worktree management shell. The app uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. All state lives in a single `WorkspaceStore` backed by immutable value-type models. Sessions are the primary identity — they exist independently of layout, view, or surface. Actions flow through a validated pipeline, and persistence is debounced.

## System Overview

```
┌───────────────────────────────────────────────────────────────┐
│                        AppDelegate                            │
│                                                               │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │WorkspaceStore │  │SessionRuntime │  │  ViewRegistry     │  │
│  │ (all state)   │  │(health/status)│  │ (sessionId→View) │  │
│  └───────┬───────┘  └───────┬───────┘  └────────┬─────────┘  │
│          │                  │                    │             │
│  ┌───────┴──────────────────┴────────────────────┴──────────┐ │
│  │              TerminalViewCoordinator                      │ │
│  │          (sole bridge: model ↔ view ↔ surface)            │ │
│  └──────────────────────────┬───────────────────────────────┘ │
│                             │                                 │
│  ┌──────────────────────────┴───────────────────────────────┐ │
│  │                SurfaceManager (singleton)                 │ │
│  │           active | hidden | undoStack surfaces            │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐│
│  │ActionExecutor│  │ TabBarAdapter│  │CommandBarPanel       ││
│  │(action hub)  │  │(derived UI)  │  │Controller (⌘P)      ││
│  └──────────────┘  └──────────────┘  └──────────────────────┘│
└───────────────────────────────────────────────────────────────┘
  * WorkspacePersistor is internal to WorkspaceStore (JSON I/O)
```

## Architecture Principles

- **Session as primary entity** — `TerminalSession` is the stable identity for a terminal, independent of layout, view, or surface
- **Single ownership boundary** — `WorkspaceStore` owns all persisted state; other services are collaborators, not peers
- **Immutable layout tree** — `Layout` is a pure value type; operations return new instances, never mutate
- **Surface independence** — Ghostty surfaces are ephemeral runtime resources; the model layer never holds `NSView` references
- **@MainActor everywhere** — Thread safety enforced at compile time, no runtime races

## Data Model at a Glance

```
WorkspaceStore
├── repos: [Repo]
│   └── worktrees: [Worktree]          ← git branches on disk
├── sessions: [TerminalSession]         ← primary terminal identities
│   ├── source: .worktree | .floating
│   ├── provider: .ghostty | .tmux
│   ├── lifetime: .persistent | .temporary
│   └── residency: .active | .pendingUndo | .backgrounded
└── views: [ViewDefinition]             ← named session arrangements
    ├── kind: .main | .saved | .worktree | .dynamic
    └── tabs: [Tab]
        └── layout: Layout              ← pure value-type split tree
            └── Node: .leaf(sessionId) | .split(Split)
```

## Mutation Flow (Summary)

```
User Action → PaneAction → ActionResolver → ActionValidator
  → ActionExecutor → WorkspaceStore.mutate()
    → @Published fires → SwiftUI re-renders
    → markDirty() → debounced save (500ms)

Command Bar → CommandDispatcher.dispatch() → CommandHandler
  → ActionResolver → ActionValidator → ActionExecutor
```

## Document Index

| Document | Covers |
|----------|--------|
| [Component Architecture](component_architecture.md) | Data model, service layer, command bar, data flow, persistence, invariants |
| [Session Lifecycle](session_lifecycle.md) | Session creation, close, undo, restore, runtime status, tmux backend |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface ownership, state machine, health monitoring, crash isolation |
| [App Architecture](app_architecture.md) | AppKit+SwiftUI hybrid shell, controllers, command bar panel, event handling |

## Related

- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — DeepWiki sources and research guidance
