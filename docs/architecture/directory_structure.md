# Directory Structure & Module Boundaries

## TL;DR

Agent Studio uses a **hybrid** directory structure: shared composition and domain infrastructure stay layer-based (`App/`, `Core/`, `Infrastructure/`), while pane implementations and user-facing capabilities live in feature directories (`Features/Terminal/`, `Features/Bridge/`, `Features/Webview/`, etc.). Swift imports are by module, not file path — moving files between directories has **zero impact on import statements** and causes no merge conflicts. The structure is enforced by a one-way import rule: `Core` never imports `Features`.

---

## Why Hybrid

Pure layer-based organization (`Models/`, `Stores/`, `Views/`, `Actions/`) spreads a single feature across many directories. Adding a terminal behavior means touching models, stores, views, and actions — four directories for one concept. Pure feature-based loses the "shared infrastructure" story — where does `WorkspaceStore` live if three features need it?

The hybrid approach (inspired by Ghostty's own codebase structure) keeps infrastructure layers for shared concerns and groups feature-specific code by capability.

---

## Target Structure

```
Sources/AgentStudio/
├── AtomRegistry.swift                # Single concrete registry composing Core + Feature atoms
├── App/                              # Composition root — wires everything together
│   ├── Boot/                         # Launch restore, lifecycle routing, boot sequencing
│   ├── Commands/                     # App-owned command entry points
│   ├── Coordination/                 # Cross-store / cross-feature sequencing
│   ├── Events/                       # App-scoped notification bus types
│   ├── Lifecycle/                    # ApplicationLifecycleMonitor, ManagementLayerMonitor,
│   │                                 #   ManagementLayerToolbarButton, WindowRestoreBridge
│   ├── PaneAgents/                   # App-owned pane-agent process launch,
│   │                                 #   fd bootstrap remap, lifecycle cleanup
│   ├── Panes/                        # App-owned pane hosting, tab management, empty states
│   │   ├── Hosting/                  # PaneHostView, management-layer drag shield
│   │   ├── Status/                   # Workspace status chips
│   │   └── TabBar/                   # Tab bar arrangement + adapter views
│   └── Windows/                      # Main window / split-window controllers and settings
│
├── Core/                             # Shared domain — pane system, models, state, runtime contracts
│   ├── Actions/                      # WorkspaceActionCommand, WorkspaceCommandResolver, WorkspaceCommandValidator, command/action metadata
│   ├── Models/                       # Pane, Layout, Tab, Repo, Worktree, arrangement, FlatTabStripMetrics,
│   │                                 #   composition-cutting enums (SidebarSurface, KeyboardOwner)
│   ├── RuntimeEventSystem/           # Shared pane-runtime contracts, buses, projectors
│   ├── State/
│   │   └── MainActor/
│   │       ├── Atoms/                # Workspace atoms, lifecycle atoms, repo/UI atoms, derived readers
│   │       └── Persistence/          # WorkspaceStore, RepoCacheStore, UIStateStore
│   └── Views/                        # Shared pane/tree/drawer primitives
│       ├── Drawer/                   # DrawerLayout, DrawerPanel, DrawerOverlay, DrawerIconBar
│       └── Panes/                    # FlatTabStripContainer, FlatPaneStripContent, CollapsedPaneBar,
│                                     #   PaneLeafContainer, SplitContainerDropCaptureOverlay,
│                                     #   PaneDragCoordinator, PaneDropTargetOverlay, SplitView
│
├── Features/                         # Each feature is a self-contained slice (see §Feature Slice
│   │                                 #   Self-Containment below)
│   ├── Bridge/                       # React/WebView pane system
│   │   ├── Components/               # Reusable views within Bridge
│   │   ├── Models/                   # Domain types owned by Bridge
│   │   ├── Routing/                  # Bus subscribers / focus trackers
│   │   ├── State/
│   │   │   └── MainActor/
│   │   │       ├── Atoms/            # BridgeDomainState, BridgePaneState, Push/*
│   │   │       └── Persistence/      # (if needed)
│   │   ├── Transport/                # Feature-specific (JSON-RPC): RPCRouter, RPCMethod, ...
│   │   └── Views/                    # Composable screens
│   │
│   ├── CodeViewer/                   # Native code-viewer pane mount view
│   ├── CommandBar/                   # ⌘P command palette
│   ├── RepoExplorer/                 # (renamed from Features/Sidebar/ in LUNA-361; the repo
│   │                                 #   explorer feature. The sidebar itself is composition
│   │                                 #   in App/, not a feature)
│   ├── Terminal/                     # Everything Ghostty-specific
│   │   ├── Components/               # Reusable views within Terminal
│   │   ├── Ghostty/                  # C API bridge, SurfaceManager, SurfaceTypes
│   │   ├── Hosting/                  # TerminalPaneMountView, GhosttyMountView, placeholder hosting
│   │   ├── Models/                   # Feature-owned domain types
│   │   ├── Restore/                  # Terminal restore scheduling/runtime
│   │   ├── Routing/                  # Feature-local bus subscribers
│   │   ├── Runtime/                  # TerminalRuntime
│   │   ├── State/MainActor/          # Atoms/ and Persistence/ when feature holds state
│   │   └── Views/                    # SurfaceErrorOverlay, SurfaceStartupOverlay
│   │
│   └── Webview/                      # Plain browser pane controller/runtime/views
│
├── SharedComponents/                 # Stateless, cross-app UI primitives (design system).
│   │                                 #   Imports ONLY from Infrastructure.
│   │                                 #   Never subscribes to atoms; state flows via bindings
│   │                                 #   and value parameters.
│   └── EditorChooser/                # Editor chooser menu content + row item model
│
├── Infrastructure/                   # Utilities used by anyone, domain-agnostic
│   ├── AtomLib/                      # Generic atom access helpers: AtomScope, AtomReader,
│   │                                 #   Derived, DerivedSelector. No product atom ownership.
│   ├── Diagnostics/                  # RestoreTrace
│   ├── Extensions/                   # Foundation/AppKit extensions, UniformType, NSColor+Hex
│   ├── Icons/                        # OcticonImage, OcticonLoader
│   ├── StateMachine/                 # Generic state machine + effects
│   ├── CWDNormalizer.swift           # Path normalization
│   ├── ProcessExecutor.swift         # CLI execution protocol
│   ├── WorktreeReconciler.swift      # Pure-function worktree topology diffing
│   └── WorktrunkService.swift        # Worktrunk CLI integration
│
├── Resources/                        # Assets, xib, storyboard
├── main.swift
└── Package.swift
```

> **Note on existing feature directories:** the tree above shows the target convention. Existing features like `Features/Bridge/State/` (without the `MainActor/` subpath), `Features/InboxNotification/State/`, and `Features/EditorChooser/State/` are grandfathered — they predate the convention and migrate in follow-up tickets. All NEW features adopt the full `State/MainActor/{Atoms,Persistence}/` path from day one.

---

## SwiftPM IPC Target Split

Most AgentStudio code still lives in the `AgentStudio` executable target and
uses the folder rules below. App IPC adds smaller SwiftPM targets so the
compiler can enforce boundaries before lint or review:

```
Sources/AgentStudioIPCTransport/
  Unix sockets, peer credentials, NDJSON framing, JSON-RPC codec.
  No AgentStudio product imports.

Sources/AgentStudioProgrammaticControl/
  Public semantic contracts: method metadata, handles, principals, permission
  scopes, schema descriptions.
  No SwiftUI/AppKit, product state, runtime owners, or app composition.

Sources/AgentStudioAppIPC/
  App IPC service shell, auth, method registry, authorization, grant ledger,
  permission broker, event broker, and protocol ports into app/runtime owners.
  No concrete app/runtime owner imports and no direct atom reads.

Sources/AgentStudioIPCClientCore/
  CLI socket discovery, command-to-JSON-RPC request mapping, and one-shot
  Unix socket client calls.
  Depends only on transport and public programmatic-control contracts.

Sources/AgentStudioIPCClient/
  Thin `agentstudio-ipc` executable entrypoint.
  Depends only on the client core.

Sources/AgentStudioPaneAgent/
  Thin `agentstudio-pane-agent` helper. Reads the app-supplied bootstrap fd
  once, authenticates with `auth.login`, and verifies runtime identity.
  Depends only on the client core.

Sources/AgentStudio/App/IPCComposition/
  Concrete adapters from AgentStudioAppIPC protocol ports into WorkspaceSurfaceCoordinator,
  RuntimeRegistry, PaneRuntime, and app-owned state.

Sources/AgentStudio/App/PaneAgents/
  App-owned launch and lifecycle surface for pane-agent child processes.
  Requests bootstrap descriptors from AgentStudioAppIPC, remaps the token fd
  into the helper, cancels unused bootstraps on spawn failure, and calls the
  server revocation seam when pane-agent authority must end.

Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift
  App-owned live IPC server composition and lifecycle. It may import
  AgentStudioAppIPC and concrete app owners because it is in the executable
  target; reusable AppIPC policy and protocol code still belongs in
  Sources/AgentStudioAppIPC/.
```

This target split keeps `App/IPC` from becoming a god box. IPC services own
transport-adjacent policy and protocol contracts; app behavior still belongs to
the existing app/runtime owners behind narrow ports.

See [AgentStudio App IPC Architecture](agentstudio_ipc_architecture.md) for the
request authority path, auth model, permission grants, and zmx boundary.

---

## Import Rule (Hard Boundary)

This is the single most important constraint. It determines where every file lives:

```
App/              ──imports──►  Core/, Features/, Infrastructure/, SharedComponents/
Features/*        ──imports──►  Core/, Infrastructure/, SharedComponents/
Core/             ──imports──►  Infrastructure/
SharedComponents/ ──imports──►  Infrastructure/
Infrastructure/   ──imports──►  (nothing internal)
```

**Never:** `Core/ → Features/`, `Features/X → Features/Y`, `Core/ → App/`, `SharedComponents/ → Core|Features|App`, `Infrastructure/ → anything above`

This boundary is enforced in lint by `agentstudio_import_direction`. Keep new
import-policy exceptions out of source files; change the architecture rule and
this document together when the layering model changes.

If a file needs to know about `SurfaceManager` (Terminal) **and** `BridgePaneController` (Bridge), it can't be in `Core`. It lives in `App/` (composition root) or uses protocols defined in `Core/`.

### Feature Slice Self-Containment

Every feature slice under `Features/<slice>/` owns its own state, models, components, views, and routing. Features do not import each other; they do not leak types into Core.

#### What lives inside a feature slice

```
Features/<slice>/
├── Components/                   Reusable views within this feature.
│                                 Can compose SharedComponents/, can
│                                 accept @Binding / callbacks, should
│                                 generally be stateless or hold only
│                                 ephemeral view state.
│
├── Models/                       Domain types owned by this feature.
│                                 Stay feature-local when possible.
│                                 Move to Core/Models/ only when
│                                 genuinely cross-cutting.
│
├── Routing/                      Event bus subscribers, focus
│                                 trackers, other reactive glue.
│                                 Leaf subscribers on the bus.
│
├── State/
│   └── MainActor/
│       ├── Atoms/                @MainActor @Observable canonical
│       │                         state, private(set) reads,
│       │                         mutation via methods. One atom
│       │                         per domain, one reason to change.
│       │
│       └── Persistence/          Store wrappers over the atoms.
│                                 One store per persistence boundary;
│                                 may wrap one or many atoms that
│                                 persist together.
│
└── Views/                        Composable screens — top-level
                                  views the feature presents.
                                  Compose Components/ and
                                  SharedComponents/. Connect to
                                  feature atoms via injection.
```

#### Universal path for atoms and stores

`State/MainActor/{Atoms,Persistence}/` is the path for atoms and stores **everywhere**:

- Core atoms live at `Core/State/MainActor/Atoms/`
- Feature atoms live at `Features/<slice>/State/MainActor/Atoms/`
- Core stores live at `Core/State/MainActor/Persistence/`
- Feature stores live at `Features/<slice>/State/MainActor/Persistence/`

The `MainActor/` segment makes actor isolation visible in the filesystem and leaves room for future actor-scoped paths if other isolation domains ever earn their own atom homes.

#### Composition state vs feature state

There are two kinds of state. They live in different places:

- **Composition state** — app-wide UI shell state generic enough that multiple features consume it. Persisted sidebar memory (filter, collapsed state, active surface) lives on `WorkspaceSidebarMemoryAtom`; runtime-only sidebar focus lives on `SidebarFocusRuntimeAtom`; UI surfaces read the composed `WorkspaceSidebarState`. Generic tags only — this layer does not reference feature-specific types.

- **Feature state** — domain data owned by one feature. Examples: notification log, inbox view prefs, repo-explorer expanded groups. Lives in feature atoms inside the feature slice. Never leaks into Core.

If you are tempted to add a feature-specific property to the sidebar composition atoms, that property belongs in a feature atom instead. If you are tempted to add a feature type to `Core/Models/`, test it: does *multiple features* and *cross-cutting composition* consume it? If only one feature uses it, it belongs in that feature.

Current exception to watch: `PaneContent.bridgePanel(BridgePaneState)` stores bridge-pane payload in `Core/Models/PaneContent.swift`. This exists because the persisted pane union is currently defined in Core while pane content variants are decoded from workspace state. Treat it as a transitional persistence boundary, not a precedent for adding more feature-owned types to Core. New bridge domain state still belongs in `Features/Bridge/State/...`; any future cleanup should move toward a Core-owned content descriptor or feature registration seam instead of widening Core's knowledge of Bridge internals.

#### The Core-imports-nothing-from-Features rule

Feature atoms may be registered in `AtomRegistry` because the concrete registry is the single root-level composition file at `Sources/AgentStudio/AtomRegistry.swift`, outside `Core/`, `Features/`, and `Infrastructure/`. The atom type and behavior still belong to the owning feature slice. Do not store feature atoms as ad hoc fields on `AppDelegate`; add app-wide feature atoms to the root `AtomRegistry.swift` and wire views, routers, and stores from there.

Core views (e.g., `DrawerOverlay`, `DrawerIconBar`) that need to display feature-owned data take that data as props (struct parameters). The caller that supplies the props lives in a layer that *can* import the feature — usually `App/` or a different feature if called from there (which would then require the caller to be in `App/` per the cross-feature rule).

### SharedComponents — the design-system layer

`Sources/AgentStudio/SharedComponents/` is a single top-level directory holding stateless UI primitives used across the app. Buttons, pills, typography tokens, icon wrappers, small custom controls, layout primitives — the design system.

#### Rules

**Stateless.** Shared components do not subscribe to atoms. They do not hold observable state. They accept input via `@Binding`, value parameters, and closures for actions. They render from those inputs and emit intentions via the closures.

Lint rule `agentstudio_shared_components_are_stateless` enforces the hard part
of this contract by rejecting `@Atom`, `@State`, `@StateObject`,
`@ObservedObject`, and `@EnvironmentObject` in `SharedComponents/`.

**Imports only from Infrastructure.** `SharedComponents/` can import `Infrastructure/`, SwiftUI, AppKit, Foundation, and stdlib. It must not import `Core/`, `Features/`, or `App/`.

**Imported by anyone.** Any layer (`Core/`, `Features/`, `App/`) can import from `SharedComponents/` freely.

**Extract on second use.** When two surfaces need the same visual control or row primitive, extract the shared rendering into `SharedComponents/` and pass feature-specific data/actions as values and closures. Do not keep parallel hand-rolled controls that drift in spacing, typography, or focus treatment.

**Share interaction semantics, not only pixels.** If two surfaces have the same behavior contract — selected row, arrow navigation, Return activation, Escape close, same-shortcut dismiss, numbered row activation, focus capture — extract that behavior into `SharedComponents/` and pass feature-specific row content/actions as closures. A feature may keep its own row rendering; it may not duplicate the keyboard/focus state machine without a documented reason.

**Style and policy source.** Shared components may consume `AppStyles` presentation tokens through `Infrastructure/`, but they should not own policy decisions. Behavioral limits, routing decisions, caps, and validation thresholds belong in `AppPolicies` and are applied by the feature/composition owner before values reach the component.

#### Search and text input ownership

`SidebarSearchField` is the shared sidebar search control. Sidebar surfaces use it with `AppStyles.Shell.Sidebar.SearchField` tokens instead of hand-rolling rounded search boxes.

Do not merge `CommandBarSearchField` into `SidebarSearchField`: the command bar owns scope, command filtering, and command-palette shortcut semantics. It may share future lower-level text-field pieces only after those semantics are separated.

Do not move `SelectAllTextField` out of Webview until a second feature needs that exact AppKit select-all behavior. Reuse starts at the behavior contract, not at a coincidental visual resemblance.

#### What belongs here

- Reusable buttons with consistent styling
- Pills, chips, badges
- Search fields and shell controls reused by sidebar surfaces, such as `SidebarSearchField`
- Typography / color tokens
- Layout primitives with design intent (e.g., `DividerBar`, `SectionStack`)
- Icon wrappers (`OcticonImage` could reasonably live here; today it's in `Infrastructure/Icons/` — existing placement is grandfathered until a dedicated refactor)
- Custom controls not tied to any feature's domain

#### What does NOT belong here

- Views that read from atoms → these are feature or composition views
- Views that import from a specific feature → these are feature or composition views
- Anything tied to a single feature's domain (those are feature `Components/`)

#### Naming rationale

"Components" at top level would collide semantically with feature-level `Components/`. Adding the `Shared` prefix makes it unambiguous. A bit verbose, but unambiguous beats cute.

### Slice Vocabulary (Core Slice vs Vertical Slice)

To keep ownership decisions consistent, use these terms:

- **Core slice**
  - Reusable, feature-agnostic domain and infrastructure.
  - Usually belongs in `Core/` or `Infrastructure/`.
  - Examples: `WorkspaceStore`, `Tab`, `Layout`, `WorkspaceCommandResolver`, `WorkspaceCommandValidator`, `WorkspaceFocus`, `AppCommandSpec`, `ActionSpec`.

- **Vertical slice**
  - A user-facing slice that traverses multiple layers and orchestrates behavior for a flow.
  - Usually belongs in `App/` (composition root) or a specific `Features/X/` directory.
  - Includes controller/stateful orchestration, platform event wiring, and cross-service flow.
  - Examples: `MainSplitViewController`, `PaneTabViewController`, `WorkspaceSurfaceCoordinator`.

- **Component slice**
  - Reusable UI building blocks that are not themselves a product feature and do not own host placement.
  - Usually belongs in `SharedComponents/`.
  - Owns rendering, layout, and small UI-facing models.
  - Examples: `SharedComponents/EditorChooser/EditorChooserMenuContent`, `SharedComponents/EditorChooser/EditorChoiceItem`.

Practical rule:
- If a component imports two or more feature services, it is a vertical slice in `App/` (or should be split).
- If a component has no feature-specific logic and is shared by multiple features, it belongs in a core slice.
- If a component is reusable UI but not host-specific assembly and not shared domain state, it belongs in `SharedComponents/`.

Host-shell plus feature-content split:
- Keep host-owned shell assembly in `App/` when placement, anchoring, divider rules, or pane/window wiring are specific to a host surface.
- Put reusable UI content in `SharedComponents/` when the content may be reused by multiple hosts, even if the first host lives in `App/`.
- Example:
  - `App/Panes/DrawerEditorChooser/` owns the drawer button, placement, anchoring, divider, and pane wiring
  - `SharedComponents/EditorChooser/` owns numbered rows, bookmark UI, and the chooser menu content

### Why Swift Makes This Free

Swift imports are by **module** (`import Foundation`, `import SwiftUI`), not by file path. Agent Studio is a single SPM target — all files share one module. Moving a file from `Services/WorkspaceStore.swift` to `Core/State/MainActor/Persistence/WorkspaceStore.swift` changes zero import statements in the entire codebase. No merge conflicts from the restructure itself.

---

## Decision Process: Where Does This File Go?

Four tests, applied in order:

### 1. The Import Rule Test

What does this file need to import (from within the project)?

| Imports from... | Placement |
|---|---|
| Multiple Features | `App/` (composition root) |
| One Feature only | That `Features/X/` directory |
| Only Core + Infrastructure + SharedComponents | `Core/` |
| Only Infrastructure (and it's a stateless UI primitive) | `SharedComponents/` |
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
| New sidebar surface added | New `Features/<surface>/` slice + composition wiring in `App/` |
| New sidebar shell / composition state | `WorkspaceSidebarMemoryAtom`, `SidebarFocusRuntimeAtom`, or `WorkspaceSidebarState` in `Core/State/MainActor/Atoms/` depending on lifecycle (UI shell state is composition, not feature state) |
| New design-system primitive (button, pill, token) | `SharedComponents/` |
| New reusable view within a single feature | `Features/X/Components/` |
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

Q3: Is it a stateless UI primitive that could be used anywhere?
    (no atom subscriptions, state via @Binding / parameters only,
     imports only Infrastructure)
    YES → SharedComponents/
    NO  → continue

Q4: Is it a utility/tool used by anyone?
    YES → Infrastructure/
    NO  → continue

Q5: Is it a domain model, store, or service
    that the pane system needs regardless of pane type?
    YES → Core/
    NO  → re-evaluate (something was missed)

---

Parallel test for atoms specifically:

  Is the state I'm storing:
    • composition state (app-wide UI shell — surface, focus, collapsed)?
        → WorkspaceSidebarMemoryAtom for persisted shell memory
        → SidebarFocusRuntimeAtom for runtime focus
        → WorkspaceSidebarState for composed UI reads

    • feature domain state (specific to one feature)?
        → new atom in Features/<slice>/State/MainActor/Atoms/

    • cross-cutting primitive needed by multiple features AND App?
        → new atom in Core/State/MainActor/Atoms/

  Never add a feature-specific property to a Core atom.
  Never add a feature type to Core/Models/ "because an atom references it."
```

---

## Component Placement Decisions

These are the resolved placements for components that could reasonably go multiple places:

### WorkspaceSurfaceCoordinator → `App/Coordination/`

Today's cross-feature coordinator is `WorkspaceSurfaceCoordinator`. It sequences operations across `SurfaceManager` (Terminal feature), `WorkspaceStore` (Core), `SessionRuntime` (Core), and `BridgePaneController` (Bridge feature).

**Import test:** imports from multiple features → can't be `Core/`. Lives under `App/Coordination/` in the composition root — this is where Ghostty puts its coordination too (`AppDelegate` delegates to feature controllers).

**Alternative considered:** Protocol-based `Core/` — define `PaneLifecycleHandler` protocol in Core, features implement it, coordinator dispatches through protocols without importing features. Cleaner dependency graph but more abstraction upfront. We chose `App/` for now (simpler, matches Ghostty's pattern). Can revisit when a third pane type arrives.

### ViewRegistry → `App/Panes/`

Stores stable pane hosts by pane ID. `ViewRegistry` stores `PaneHostView` and resolves mounted content only for callers that need pane-kind-specific behavior. Adding a new pane kind does not change the split tree's host contract.

**Deletion test:** passes for any single feature. **Change driver:** only changes if the pane registration mechanism itself changes, not when new pane types arrive.

### PaneTabViewController → `App/Panes/`

Manages `NSTabViewItems` containing pane views. Handles focus, layout, tab switching. The container doesn't care what's inside — renamed from `TerminalTabViewController` during LUNA-334 restructure.

**Deletion test:** passes for any single feature. **Change driver:** tab management behavior changes, not new pane types.

### Pane Layout & Flat Tab Strip Components → `Core/Views/Panes/`

`FlatTabStripContainer`, `FlatPaneStripContent`, `CollapsedPaneBar`, `PaneLeafContainer`, `PaneDragCoordinator`, `SplitContainerDropCaptureOverlay`, and `PaneDropTargetOverlay`
belong in `Core/Views/Panes/` because they are pane-type-agnostic pane layout primitives:

- They operate on pane IDs, tab metadata, and frame geometry — not terminal/webview/bridge-specific APIs.
- They are reused by any pane feature rendered inside split trees or the flat tab strip.
- Their change driver is split interaction or tab strip behavior, not any individual feature implementation.
- `FlatTabStripMetrics` (the layout constants model) lives in `Core/Models/`.

### MainSplitViewController → `App/Windows/`

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
