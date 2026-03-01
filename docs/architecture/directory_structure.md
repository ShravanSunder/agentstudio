# Directory Structure & Module Boundaries

## TL;DR

Agent Studio uses a **hybrid** directory structure: infrastructure stays layer-based (`App/`, `Ghostty/`, `Core/`, `Infrastructure/`) while user-facing capabilities live in feature directories (`Features/Terminal/`, `Features/Bridge/`, etc.). Swift imports are by module, not file path — moving files between directories has **zero impact on import statements** and causes no merge conflicts. The structure is enforced by a one-way import rule: `Core` never imports `Features`.

---

## Why Hybrid

Pure layer-based (the current `Models/`, `Services/`, `Views/`) spreads a single feature across many directories. Adding a terminal behavior means touching `Models/`, `Services/`, `Views/`, and `Actions/` — four directories for one concept. Pure feature-based loses the "shared infrastructure" story — where does `WorkspaceStore` live if three features need it?

The hybrid approach (inspired by Ghostty's own codebase structure) keeps infrastructure layers for shared concerns and groups feature-specific code by capability.

---

## Target Structure

```
Sources/AgentStudio/
├── App/                              # Composition root — wires everything together
│   ├── AppDelegate.swift             # App lifecycle, restore, zmx cleanup
│   ├── MainWindowController.swift    # Window management
│   ├── MainSplitViewController.swift # Top-level split (sidebar/content)
│   ├── Panes/
│   │   ├── PaneTabViewController.swift # Tab container (manages any pane type)
│   │   └── ViewRegistry.swift        # PaneId → NSView mapping (type-agnostic)
│   └── PaneCoordinator.swift         # Cross-feature sequencing (imports from all)
│
├── Core/                             # Shared domain — pane system, models, stores
│   ├── Models/                       # Pane, Layout, Tab, ViewDefinition, PaneView
│   ├── Stores/                       # WorkspaceStore, SessionRuntime
│   ├── Actions/                      # PaneAction, ActionResolver, ActionValidator
│
├── Features/
│   ├── Terminal/                     # Everything Ghostty-specific
│   │   ├── Ghostty/                  # C API bridge, SurfaceManager, SurfaceTypes
│   │   ├── Views/                    # AgentStudioTerminalView, SurfaceErrorOverlay
│   │   └── GhosttyBridge.swift       # PaneBridge conformance for terminal surfaces
│   │
│   ├── Bridge/                       # React/WebView pane system
│   │   ├── Transport/                # JSON-RPC transport and bootstrap wiring
│   │   │   ├── RPCRouter.swift
│   │   │   ├── RPCMethod.swift
│   │   │   ├── RPCMessageHandler.swift
│   │   │   ├── BridgeBootstrap.swift
│   │   │   ├── BridgeSchemeHandler.swift
│   │   │   └── Methods/              # AgentMethods, DiffMethods, ReviewMethods, SystemMethods
│   │   ├── Runtime/                  # BridgePaneController runtime/lifecycle orchestration
│   │   ├── State/                    # Domain state + push state transport
│   │   │   ├── BridgeDomainState.swift
│   │   │   ├── BridgePaneState.swift
│   │   │   └── Push/                 # PushTransport, PushPlan, Slice, EntitySlice, RevisionClock
│   │   ├── Views/                    # BridgePaneView, BridgePaneContentView
│   │   └── BridgeNavigationDecider.swift
│   │
│   ├── CommandBar/                   # ⌘P command palette
│   │   ├── CommandBarState.swift
│   │   ├── CommandBarPanel.swift
│   │   ├── CommandDispatcher.swift
│   │   └── Commands/                 # Individual command handlers
│   │
│   └── Sidebar/                      # Sidebar content (repo list, worktree tree)
│       ├── SidebarViewController.swift
│       └── SidebarViews/
│
├── Infrastructure/                   # Utilities used by anyone, domain-agnostic
│   ├── ProcessExecutor.swift         # CLI execution protocol
│   ├── CWDNormalizer.swift           # Path normalization
│   ├── StateMachine/                 # Generic state machine + effects
│   └── Extensions/                   # Foundation/AppKit extensions
│
├── Resources/                        # Assets, xib, storyboard
├── AppDelegate.swift → App/
├── main.swift
└── Package.swift
```

---

## Import Rule (Hard Boundary)

This is the single most important constraint. It determines where every file lives:

```
App/            ──imports──►  Core/, Features/, Infrastructure/
Features/*      ──imports──►  Core/, Infrastructure/
Core/           ──imports──►  Infrastructure/
Infrastructure/ ──imports──►  (nothing internal)
```

**Never:** `Core/ → Features/`, `Features/X → Features/Y`, `Infrastructure/ → Core/`

If a file needs to know about `SurfaceManager` (Terminal) **and** `BridgePaneController` (Bridge), it can't be in `Core`. It lives in `App/` (composition root) or uses protocols defined in `Core/`.

### Slice Vocabulary (Core Slice vs Vertical Slice)

To keep ownership decisions consistent, use these terms:

- **Core slice**
  - Reusable, feature-agnostic domain and infrastructure.
  - Usually belongs in `Core/` or `Infrastructure/`.
  - Examples: `WorkspaceStore`, `Tab`, `Layout`, `ActionResolver`, `ActionValidator`.

- **Vertical slice**
  - A user-facing slice that traverses multiple layers and orchestrates behavior for a flow.
  - Usually belongs in `App/` (composition root) or a specific `Features/X/` directory.
  - Includes controller/stateful orchestration, platform event wiring, and cross-service flow.
  - Examples: `MainSplitViewController`, `PaneTabViewController`, `PaneCoordinator`.

Practical rule:
- If a component imports two or more feature services, it is a vertical slice in `App/` (or should be split).
- If a component has no feature-specific logic and is shared by multiple features, it belongs in a core slice.

### Why Swift Makes This Free

Swift imports are by **module** (`import Foundation`, `import SwiftUI`), not by file path. Agent Studio is a single SPM target — all files share one module. Moving a file from `Services/WorkspaceStore.swift` to `Core/Stores/WorkspaceStore.swift` changes zero import statements in the entire codebase. No merge conflicts from the restructure itself.

---

## Decision Process: Where Does This File Go?

Four tests, applied in order:

### 1. The Import Rule Test

What does this file need to import (from within the project)?

| Imports from... | Placement |
|---|---|
| Multiple Features | `App/` (composition root) |
| One Feature only | That `Features/X/` directory |
| Only Core + Infrastructure | `Core/` |
| Nothing internal | `Infrastructure/` |

### 2. The Deletion Test

Could you delete `Features/Bridge/` entirely and this file still compiles?

- **Yes** for all features → probably `Core/` or `Infrastructure/`
- **No**, deleting one specific feature breaks it → lives in that feature (or needs a protocol in `Core/`)

### 3. The Change Driver Test

What causes this file to change?

| Change driver | Lives in |
|---|---|
| New pane type added | `Core/` (pane system is type-agnostic) |
| New terminal behavior (scrollbar, action, clipboard) | `Features/Terminal/` |
| New bridge protocol method or push slice | `Features/Bridge/` |
| App lifecycle / window management | `App/` |
| New utility used by multiple features | `Infrastructure/` |

### 4. The Multiplicity Test

How many features use this?

- **Exactly one feature** → belongs in that feature
- **Two or more features** → `Core/` (models, stores, services) or `Infrastructure/` (utilities)

### Decision Flowchart

```
Q1: Does it import from multiple Features?
    YES → App/ (composition root)
    NO  → continue

Q2: Does it import from ONE Feature?
    YES → that Feature/
    NO  → continue

Q3: Is it a utility/tool used by anyone?
    YES → Infrastructure/
    NO  → continue

Q4: Is it a domain model, store, or service
    that the pane system needs regardless of pane type?
    YES → Core/
    NO  → re-evaluate (something was missed)
```

---

## Component Placement Decisions

These are the resolved placements for components that could reasonably go multiple places:

### PaneCoordinator → `App/`

Today's cross-feature coordinator is `PaneCoordinator`. It sequences operations across `SurfaceManager` (Terminal feature), `WorkspaceStore` (Core), `SessionRuntime` (Core), and `BridgePaneController` (Bridge feature).

**Import test:** imports from multiple features → can't be `Core/`. Lives in `App/` as the composition root — this is where Ghostty puts its coordination too (`AppDelegate` delegates to feature controllers).

**Alternative considered:** Protocol-based `Core/` — define `PaneLifecycleHandler` protocol in Core, features implement it, coordinator dispatches through protocols without importing features. Cleaner dependency graph but more abstraction upfront. We chose `App/` for now (simpler, matches Ghostty's pattern). Can revisit when a third pane type arrives.

### ViewRegistry → `App/Panes/`

Stores views by pane ID. Doesn't care what type the view is — terminal, bridge, webview. Stores `PaneView` (the base class). Adding a new feature doesn't change ViewRegistry.

**Deletion test:** passes for any single feature. **Change driver:** only changes if the pane registration mechanism itself changes, not when new pane types arrive.

### PaneTabViewController → `App/Panes/`

Manages `NSTabViewItems` containing pane views. Handles focus, layout, tab switching. The container doesn't care what's inside — renamed from `TerminalTabViewController` during LUNA-334 restructure.

**Deletion test:** passes for any single feature. **Change driver:** tab management behavior changes, not new pane types.

### PaneLeafContainer + Split Drop Components → `Core/Views/Splits/`

`PaneLeafContainer`, `PaneDragCoordinator`, `SplitContainerDropCaptureOverlay`, and `PaneDropTargetOverlay`
belong in `Core/Views/Splits/` because they are pane-type-agnostic split-system primitives:

- They operate on pane IDs and frame geometry, not terminal/webview/bridge-specific APIs.
- They are reused by any pane feature rendered inside split trees.
- Their change driver is split interaction behavior, not any individual feature implementation.

### MainSplitViewController → `App/`

Manages the top-level split between sidebar and content area. Feature-agnostic but app-lifecycle-coupled.

**Change driver:** app layout changes, not domain changes.

---

## Migration Strategy

Since Swift imports are module-level (not path-based), the restructure is a pure file-move operation:

1. Create the target directory structure
2. Move files — `git mv` preserves history
3. No import changes needed (same SPM module)
4. ~~Rename `TerminalTabViewController` → `PaneTabViewController`~~ (done in LUNA-334)
5. Update `CLAUDE.md` structure section
6. Verify build compiles

The restructure should be done on its own branch and merged into `main` and all active branches before other work continues — it's a pure organizational change with no behavioral impact.

---

## Key Files

| File | Role |
|------|------|
| This document | Directory structure spec and decision principles |
| [Architecture Overview](README.md) | System overview and document index |
| [Component Architecture](component_architecture.md) | Data model, service layer, ownership |
| [Session Lifecycle](session_lifecycle.md) | Session creation, close, undo, restore |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface ownership and lifecycle |
| [App Architecture](appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid, controllers |
