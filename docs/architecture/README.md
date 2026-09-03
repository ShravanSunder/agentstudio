# Agent Studio Architecture

## TL;DR

Agent Studio is a macOS terminal application that embeds Ghostty terminal surfaces within a project/worktree management shell. The app uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. **Shared UI state** is published from independent `@MainActor @Observable` atoms (inspired by Jotai) with `private(set)` for unidirectional flow (Valtio-style). Observation is the reason an atom exists; an atom does not have to be backed by SQLite. CRUD without a subscriber belongs in a repository. Persistence wrappers such as `WorkspaceStore`, `RepoCacheStore`, and `UIStateStore` snapshot atom-backed UI state that happens to be durable. `WorkspaceSurfaceCoordinator` sequences cross-store and cross-feature operations from the App composition root. Panes are the primary identity — they exist independently of layout, view, or surface. Actions flow through a validated pipeline, and persistence is debounced.

## How To Read This Index

Use this document as a routing layer, not as the full architecture. Pick the
smallest concern-specific doc, then verify the claim against the current code
and tests. Architecture source paths are markdown links to the tree; if a path
is not clickable, treat it as stale and open Directory Structure or the owning
doc's file table instead.

Current owners and historical/background docs are listed separately in
[Document Index](#document-index). Do not treat a self-disclaimed or idea
document as current authority.

`AGENTS.md` owns the 5-line everyday proof ladder; this index names which proof
doc to open ([Observability And Traceability — Proof Model](observability/observability_and_traceability.md#proof-model),
[Style Guide — Shared Shell Controls](../guides/style_guide.md#shared-shell-controls), and the other rows below).

| Question | Start here | What you get wrong if you skip | Then verify in code |
| --- | --- | --- | --- |
| Where does a file or new type go? | [Directory Structure — Decision Process](structure/directory_structure.md#decision-process-where-does-this-file-go) | You put a Feature type in [`Core/Models/`](../../Sources/AgentStudio/Core/Models) or skip the four-test process. Trees and compiled DAG: [Repository Root](structure/directory_structure.md#repository-root), [Source And Target Structure](structure/directory_structure.md#source-and-target-structure), [SwiftPM Module Graph](structure/directory_structure.md#swiftpm-module-graph). | [`Sources/AgentStudio/`](../../Sources/AgentStudio) placement and import direction |
| Where should a file or module test live? | [Directory Structure — Test Target Ownership](structure/directory_structure.md#test-target-ownership) | You park a module test on the executable target or infer ownership from `swift test --filter`. | [`Package.swift`](../../Package.swift) target and source lists |
| Do I need an atom, a derived node, an eager projection, or a repository? | [Atom Persistence Boundaries — Need An Atom?](state/atom_persistence_boundaries.md#need-an-atom) | You wrap CRUD in an atom, assume every atom is a SQL table, or reach for `EagerDerivedAtomFamily` as a default. | Product owner vs `*Repository` vs `TabBarAdapter` / `RepoExplorerProjectionAdapter` |
| Which command path, shortcut display, or dense-control tooltip source should I use? | [Command Specs And Execution Owners](commands/command_specs.md#command-specs-and-execution-owners), then [Files to load](commands/command_specs.md#files-to-load), [Adding a new command — decision tree](commands/command_specs.md#adding-a-new-command-decision-tree), and [Exhaustive interactive and IPC projections](commands/command_specs.md#exhaustive-interactive-and-ipc-projections) | You put a label, icon, tooltip, shortcut, or IPC method on a view instead of the spec catalog. Display: [Tooltips, help text, and compact control copy](commands/command_specs.md#tooltips-help-text-and-compact-control-copy). | The [file table](commands/command_specs.md#files-to-load); never infer paths from this index |
| Which shared UI primitive or dense-control visual pattern should I use? | [Style Guide — Shared Shell Controls](../guides/style_guide.md#shared-shell-controls) | You copy styling into a feature, or you put a behavior constant in `AppStyles`. | [`SharedComponents/`](../../Sources/AgentStudio/SharedComponents), [`AppStyles.swift`](../../Sources/AgentStudio/Infrastructure/AppStyles.swift), [`AppPolicies.swift`](../../Sources/AgentStudio/Infrastructure/AppPolicies.swift) |
| How do the native titlebar, tab hit testing, tab dragging, and window dragging fit together? | [AppKit + SwiftUI Hybrid Architecture — Native Titlebar And Tab Strip](hosting/appkit_swiftui_architecture.md#native-titlebar-and-tab-strip) | You treat tab dragging as SwiftUI-local and break window-rooted hit testing. | `MainWindowController`, `MainToolbarChromeView`, `DraggableTabBarHostingView`, window-rooted toolbar tests |
| Is this app state, runtime state, or persisted state? | [Atom Persistence Boundaries — Lifecycle Lanes](state/atom_persistence_boundaries.md#lifecycle-lanes) | You persist a runtime/presentation atom, or you leave a durable field unsaved. | [`Core/State/MainActor/Atoms/`](../../Sources/AgentStudio/Core/State/MainActor/Atoms), persistence wrappers |
| Is this write-owner atom / derived read model / SQLite row? | [Atom Persistence Boundaries — Roles](state/atom_persistence_boundaries.md#roles) | A `Codable` convenience type becomes both live atom state and the SQLite contract. | Atom types vs `*Row` projections vs derived `Pane`/`Tab` readers |
| Workspace command vs pane runtime command vs bus fact vs AppKit lifecycle? | [Mutation Flow](#mutation-flow) in this index; then [Pane Runtime EventBus Design — Admission And Hop Shape](runtime/pane_runtime_eventbus_design.md#admission-and-hop-shape) and [Command Specs — Command planes](commands/command_specs.md#command-planes) | You route a command through the bus, or you bounce AppKit lifecycle through `WorkspaceActionCommand`. | `WorkspaceActionCommand`, `PaneRuntimeCommand`, `PaneRuntimeEventBus`, `ApplicationLifecycleMonitor` |
| How do pane/runtime commands and facts move? | [Pane Runtime Architecture — Three Data Flow Planes](runtime/pane_runtime_architecture.md#three-data-flow-planes) and [Pane Runtime EventBus Design — TL;DR](runtime/pane_runtime_eventbus_design.md#tldr) | You infer hop shape from `@MainActor` annotations and wake MainActor for raw samples. | [`Core/RuntimeEventSystem/`](../../Sources/AgentStudio/Core/RuntimeEventSystem), [`App/Coordination/`](../../Sources/AgentStudio/App/Coordination) |
| How does AgentStudio link `agentstudio-git`, and may I shell out to `git`? | [agentstudio-git](state/agentstudio_git.md#agentstudio-git) then the [agentstudio-git package](https://github.com/ShravanSunder/agentstudio-git) at the `Package.swift` revision | You spawn `git`/`wt`, reimplement Git in this repo, or skip reading the package. | [`Package.swift`](../../Package.swift) revision pin |
| I have a new signal, derived fact, or EventBus case? | [Pane Runtime Architecture — New signal decision tree](runtime/pane_runtime_architecture.md#new-signal-decision-tree) then [Need An Atom?](state/atom_persistence_boundaries.md#need-an-atom) and [Selection Rule](state/demand_driven_derived_state_refresh.md#selection-rule) | You invent a bus event and transform it on MainActor, or skip admission. | Source admission owner, atom vs repository choice, EventBus fact topic |
| What may run on MainActor vs off-main? | [Pane Runtime EventBus Design — Admission And Hop Shape](runtime/pane_runtime_eventbus_design.md#admission-and-hop-shape) | A `@MainActor` type becomes permission to derive, schedule, or admit there. | Terminal drain/projector, `EagerDerivedAtom`, `FilesystemProjectionIndex` |
| Where are high-rate source signals admitted, contracted, and projected? | [Pane Runtime Architecture — Contract 7](runtime/pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction) and [Pane Runtime EventBus Design — Typed Admission](runtime/pane_runtime_eventbus_design.md#typed-admission-before-multiplexing); for filesystem effects, [Workspace Data Architecture — Filesystem Effect Admission](state/workspace_data_architecture.md#filesystem-effect-admission-and-projection) | Raw callbacks wake the bus or MainActor; you skip source admission. | Terminal source routing/projectors and `FilesystemProjectionIndex` |
| How should expensive derived facts react to product demand without polling or stale publication? | [Demand-Driven Derived-State Refresh — Selection Rule](state/demand_driven_derived_state_refresh.md#selection-rule) | Debounce/throttle is treated as a classification; the wrong mechanism silently drops ordering, scope, or currentness. | The concrete observer, admission owner, executor, publication path, and keyed read model |
| How do I prove telemetry or performance? | [Observability And Traceability — Proof Model](observability/observability_and_traceability.md#proof-model) | Unit tests and feel stand in for marker-scoped Victoria proof. | Trace tags, proof scripts, Victoria verifier output |
| How do I launch debug/beta proof? | [Observability And Traceability — Local proof launch](observability/observability_and_traceability.md#local-proof-launch) | You inherit production identity, share zmx state across worktrees, or treat JSONL as proof. | Debug/beta launchers, identity print, Victoria marker verifiers |
| How does programmatic control stay out of zmx internals? | [AgentStudio App IPC Architecture — Target Ownership](commands/ipc.md#target-ownership) | App IPC reaches into zmx sockets or session internals. | [`App/IPCComposition/`](../../Sources/AgentStudio/App/IPCComposition), app ports, runtime adapters |
| How does Bridge Viewer split work between native Swift/WebKit and BridgeWeb? | [Bridge Viewer Architecture — System Map](bridge/bridge_viewer_architecture.md#system-map), then [Bridge Product Transport — The three route jobs](bridge/bridge_product_transport_architecture.md#the-three-route-jobs), [Bridge Native Runtime — Ownership Map](bridge/bridge_native_runtime_architecture.md#ownership-map), or [Bridge Web Runtime — Runtime Topology](bridge/bridge_web_runtime_architecture.md#runtime-topology) | Git/protocol work lands in TypeScript, or native and web ownership duplicate. | [`Sources/AgentStudio/Features/Bridge/`](../../Sources/AgentStudio/Features/Bridge), [`BridgeWeb/src/`](../../BridgeWeb/src) |
| When editing BridgeWeb React UI? | [BridgeWeb AGENTS.md — UI Components](../../BridgeWeb/AGENTS.md#ui-components), then [Bridge Viewer Architecture — System Map](bridge/bridge_viewer_architecture.md#system-map) | You hand-roll a route-local control instead of owned primitives, or you skip the BridgeWeb operating contract. | [`BridgeWeb/src/components/ui/`](../../BridgeWeb/src/components/ui), FileViewer/ReviewViewer shared chrome |
| BridgeWeb Vite loop, zig/Xcode, or Swift build-slot recovery? | [Agent Resources — BridgeWeb Fast UI Loop](../guides/agent_resources.md#bridgeweb-fast-ui-loop), [Xcode And Zig](../guides/agent_resources.md#xcode-and-zig-vendor-builds), [Swift Build-Slot Recovery](../guides/agent_resources.md#swift-build-slot-recovery) | You rebuild the full app for Bridge UI, hydrate vendors by hand, or collide on `.build`. | `mise` tasks, [`scripts/swift-build-slot.sh`](../../scripts/swift-build-slot.sh), Bridge development server |
| Local SQLite recovery internals? | [Atom Persistence Boundaries — Local recovery](state/atom_persistence_boundaries.md#local-recovery) | You reconstruct quarantine/reopen from an agent contract instead of the persistence owner. | `WorkspaceSQLiteRecoveryClassifier`, sidecar quarantine |

## Compiled Module Graph

```text
AgentStudio executable (App composition + resources)
  ├── eight Feature modules: Bridge, CodeViewer, CommandBar, EditorChooser,
  │   InboxNotification, RepoExplorer, Terminal, Webview
  ├── AgentStudioCore
  ├── AgentStudioSharedComponents
  └── AgentStudioInfrastructure

Features ──► Core / SharedComponents / Infrastructure
Core     ──► SharedComponents / Infrastructure
SharedComponents ──► Infrastructure
```

There are no sibling Feature imports. App owns cross-Feature composition and
the concrete `AtomRegistry`; Core owns the sole `CoreAtomScope`; Feature state
is explicitly injected. SharedComponents is stateless and depends only on
Infrastructure. One coarse Core is intentional for this graph, and further
decomposition is deferred. Cross-target product APIs use `package` visibility
instead of broad `public` promotion.

Paired test targets own module tests. `AgentStudioTestSupport` depends only on
Core, while executable-level `AgentStudioTests` owns App, cross-Feature,
resource, WebKit, zmx, and packaged integration. Test lane filters and
serialization remain execution policy rather than module ownership.

## System Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                            AppDelegate                                  │
│                                                                        │
│  PERSISTENCE WRAPPERS OVER MAIN-ACTOR ATOMS                           │
│  ┌───────────────┐  ┌─────────────────┐  ┌───────────────┐            │
│  │WorkspaceStore │  │RepoCacheStore   │  │UIStateStore   │            │
│  │metadata/topol │  │EnrichmentCache  │  │SidebarMemory  │            │
│  │pane/tab atoms │  │+RecentTargets   │  │(sidebar mem)  │            │
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
│  │Filesystem   │  │GitWorkingDir │  │ForgeActor   │                    │
│  │Actor        │  │Projector     │  │(PR facts)   │                    │
│  └─────────────┘  └─────────────┘  └─────────────┘                    │
│                                                                        │
│  ┌───────────────┐  ┌───────────────┐                                  │
│  │SessionRuntime │  │SurfaceManager │                                  │
│  │(backends)     │  │(surfaces)     │                                  │
│  └───────┬───────┘  └────────┬──────┘                                  │
│  ┌───────┴───────────────────┴──────────────────────────────────┐      │
│  │              WorkspaceSurfaceCoordinator                                  │      │
│  │     (sequences cross-store ops, owns no domain state)         │      │
│  └───────────────────────────────────────────────────────────────┘      │
└────────────────────────────────────────────────────────────────────────┘
```

## Architecture Principles

- **Pane as primary entity** — `Pane` is the stable identity across model, runtime, view registry, surface metadata, and restore flows
- **Atomic stores (inspired by Jotai)** — Use an atom only for **shared UI state** that SwiftUI, a command surface, or a derived projection must observe. Read [Need An Atom?](state/atom_persistence_boundaries.md#need-an-atom) and [`Sources/AgentStudio/Infrastructure/AtomLib/`](../../Sources/AgentStudio/Infrastructure/AtomLib). CRUD without Observation belongs in a repository. An atom does not have to be backed by SQLite. Each justified atom owns one observed domain and has one reason to change. Compatibility facades such as `WorkspacePaneAtom`, `WorkspaceTabArrangementAtom`, and `WorkspaceTabLayoutAtom` bridge existing call sites while split write owners land. Persistence wrappers snapshot atom groups that happen to be durable. Feature atoms live inside their feature slice at `Features/<slice>/State/MainActor/Atoms/` — see [Directory Structure — Feature Slice Self-Containment](structure/directory_structure.md#feature-slice-self-containment).
- **Unidirectional flow (Valtio-style)** — All store state is `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers.
- **Coordinator for cross-store sequencing** — A coordinator sequences operations across stores for a single user action. Owns no state, contains no domain logic.
- **Lifecycle ingress stays separate** — `ApplicationLifecycleMonitor` owns AppKit ingress only. It mutates `AppLifecycleAtom` and `WindowLifecycleAtom`, both `@Observable` atomic stores with `private(set)` mutation surfaces. `WindowLifecycleAtom` holds transient window facts only: key/focus state, terminal container bounds, launch-layout-settle state, and derived readiness; none of those readiness properties are persisted.
- **Immutable layout tree** — `Layout` is a pure value type; operations return new instances, never mutate
- **Surface independence** — Ghostty surfaces are ephemeral runtime resources; the model layer never holds `NSView` references
- **Main-actor UI state, off-main runtime work** — AppKit, SwiftUI, atoms, observable UI state, and WebKit integration stay on `@MainActor`; expensive runtime work such as file I/O, hashing, diff preparation, and provider calls belongs behind actors/services with `Sendable` request/result models.
- **AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing Combine/NotificationCenter migrated incrementally.
- **Trace tags select instrumentation** — Observability emitters are gated by `AGENTSTUDIO_TRACE_TAGS`; backends are selected separately by `AGENTSTUDIO_TRACE_BACKEND` and loopback OTLP variables. Do not add one-off env vars for individual emitters. See [Observability And Traceability — Control Plane](observability/observability_and_traceability.md#control-plane).

Current atom vocabulary:

- **Atoms** publish shared UI-observed state. Application-global owners include `ActiveWorkspaceSelectionAtom`, `RepositoryTopologyAtom`, `RepoEnrichmentCacheAtom`, and `ApplicationEntityRecencyAtom`. Workspace owners include identity, pane/tab/drawer graph and cursors, and `WorkspaceEntityRecencyAtom`. Window-keyed owners hold frame/sidebar shell and expanded-group memory. Runtime-only owners include focus, transient keyboard surfaces, app/window lifecycle, and session runtime. `WorkspacePaneAtom`, `WorkspaceTabArrangementAtom`, `WorkspaceTabLayoutAtom`, and `RepoCacheAtom` remain composed compatibility/read surfaces for existing consumers.
- **Persistence wrappers** own load/save boundaries and debounced disk I/O, for example `WorkspaceStore`, `RepoCacheStore`, `SidebarCacheStore`, and `UIStateStore`.
- **Derived readers** compute projections without owning data, for example `WorkspacePaneDerived`, `WorkspaceTabLayoutDerived`, `WorkspaceFocusedPaneResolver`, `CommandContextDerived`, `WorkspaceLookupDerived`, `PaneDisplayDerived`, and `TabDisplayDerived`. `WorkspaceFocusOwnerAtom` remains the sole mutable workspace-focus owner.
- **Coordinators** sequence mutations across atoms/stores and runtime systems. They own no durable domain state.

## Coordination Planes

Use the smallest boundary that still matches the kind of work being done.

| Change shape | Boundary | Notes |
|--------------|----------|-------|
| Workspace mutation | `WorkspaceActionCommand` | Validator-gated, then sequenced into stores by `WorkspaceSurfaceCoordinator`. |
| Runtime command | `PaneRuntimeCommand` | Direct command routing to a single runtime via `RuntimeRegistry`. |
| Runtime fact | `PaneRuntimeEventBus` | Fan-out for runtime/system facts only. Never route commands through it. |
| Ordered post-topology effects | `TopologyEffectHandler` | After topology facts; not via the bus. |
| App-level notification that is not a command | `AppEventBus` | Notification fan-out only. |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` | Owns AppKit callbacks and writes lifecycle stores. |
| UI-only local state | Local `@Observable` view/controller state | Keep it local; do not bounce it through a bus or `NotificationCenter`. |

The old `AppCommand -> AppEventBus -> controller -> WorkspaceActionCommand` chain is retired. Workspace work now enters through validated `WorkspaceActionCommand` routing directly, and AppKit lifecycle state lives in the lifecycle stores.

## Data Model at a Glance

```
ActiveWorkspaceSelectionAtom            ← global active workspace id

Application-global state
├── RepositoryTopologyAtom              ← repos, worktrees, watched paths, availability
├── RepoEnrichmentCacheAtom             ← rebuildable repo/worktree/PR enrichment
└── ApplicationEntityRecencyAtom        ← repository/worktree recency

WorkspaceStore (core.sqlite + workspace-keyed local cursor/window persistence wrapper)
├── WorkspaceIdentityAtom               ← workspace id, name, created-at timestamp
├── WorkspaceWindowMemoryAtom           ← window-keyed sidebar width and frame
├── repositoryTopologyAtom              ← reference to the application-global topology owner
├── WorkspacePaneGraphAtom              ← pane identity/content/residency, durable metadata, drawer membership
├── WorkspaceDrawerCursorAtom           ← local drawer expansion cursor
├── WorkspacePaneAtom                   ← compatibility facade over pane graph + drawer cursor
├── WorkspaceTabShellAtom               ← tab identity and ordering
├── WorkspaceTabCursorAtom              ← active tab cursor
├── WorkspaceTabGraphAtom               ← tab membership and arrangement/layout graph
├── WorkspaceArrangementCursorAtom      ← active arrangement, active pane, drawer child cursors
├── WorkspacePanePresentationAtom       ← runtime pane presentation such as zoom
├── WorkspaceTabArrangementAtom         ← compatibility mutation facade over tab graph/cursors/presentation
├── WorkspaceTabLayoutAtom              ← compatibility read facade
└── WorkspaceTabLayoutDerived           ← rich tab read model

RepoCacheStore (application local.sqlite, rebuildable global cache)
├── RepoEnrichmentCacheAtom            ← origin, identity, branch, git snapshot,
│                                         PR counts, rebuild metadata
└── RepoCacheAtom                      ← composed read surface for repo/sidebar UI

EntityRecencyStore (application local.sqlite)
├── ApplicationEntityRecencyAtom       ← global repository/worktree rows
└── WorkspaceEntityRecencyAtom         ← workspace-keyed pane rows

WorkspaceSQLiteDatastore (authoritative core.sqlite + non-authoritative app-root local.sqlite)
├── WorkspaceCoreRepository            ← authoritative graph/topology rows
├── cached WorkspaceLocalRepository    ← active local UX/cache plus dormant retained Inbox rows
└── WorkspaceSQLiteSnapshot            ← live actor-crossing snapshot, not a row projection

WorkspaceSidebarMemoryAtom (window-keyed rows in app-root local.sqlite)
├── filterText, isFilterVisible
└── sidebarCollapsed, sidebarSurface

SidebarFocusRuntimeAtom (runtime only)
└── sidebarHasFocus

WorkspaceSidebarState
└── composed UI-facing reader/mutator over sidebar memory + runtime focus
```

## Mutation Flow

```
User Action → WorkspaceActionCommand
  → WorkspaceCommandResolver.snapshot() builds ActionStateSnapshot
  → WorkspaceCommandValidator.validate(action, snapshot) → ValidatedAction
  → WorkspaceSurfaceCoordinator → Store.mutate()
    → @Observable tracks → SwiftUI re-renders
    → markDirty() → debounced save (500ms)

Command Bar
  → WorkspaceFocusedPaneResolver → WorkspaceFocusedPane status presentation
  → CommandContextDerived → CommandContext
  → AppCommandSpec.shouldPresent(.commandBar, subject) for presence
  → AppCommandTargeting chooses contextual dispatch or target drill-in
  → matching AppCommandDispatcher.canDispatch() for enablement
  → AppCommandDispatcher.dispatch() repeats mode/target-kind preflight
  → WorkspaceCommandHandling (PaneTabViewController)
  → WorkspaceCommandResolver.resolve() → WorkspaceActionCommand
  → WorkspaceCommandResolver.snapshot() → ActionStateSnapshot
  → WorkspaceCommandValidator.validate() → WorkspaceSurfaceCoordinator

Runtime command → WorkspaceSurfaceCoordinator.dispatchRuntimeCommand()
  → RuntimeRegistry.runtime(for:) → runtime.handleCommand(envelope)

Runtime fact → PaneRuntimeEventBus.post(envelope)
  → WorkspaceCacheCoordinator / other consumers subscribe independently

App-level notification that is not a command → AppEventBus
AppKit/macOS lifecycle ingress → ApplicationLifecycleMonitor → AppLifecycleAtom / WindowLifecycleAtom
```

## Document Index

**Current owners** below are the architecture catalog, grouped by folder. No two
current owners are authoritative for the same topic. Historical documents live
only under [`archive/`](archive/README.md).

### structure/

| Document | Ownership |
|----------|-----------|
| [Directory Structure](structure/directory_structure.md) | Module, test, and file-placement boundaries |
| [Component Architecture](structure/component_architecture.md) | Structural overview — how components compose |
| [Architecture Lint Inventory](structure/architecture_lint_inventory.md) | Live architecture-lint rule map |

### state/

| Document | Ownership |
|----------|-----------|
| [Atom Persistence Boundaries](state/atom_persistence_boundaries.md) | Atom vs repository vs derived / SQLite roles |
| [agentstudio-git](state/agentstudio_git.md) | Git operations package pin; read that repo at the pinned revision |
| [Workspace Data Architecture](state/workspace_data_architecture.md) | Repos, worktrees, enrichment, sidebar projection |
| [Demand-Driven Derived-State Refresh](state/demand_driven_derived_state_refresh.md) | Classify-first vocabulary for expensive derived facts |

### runtime/

| Document | Ownership |
|----------|-----------|
| [Pane Runtime Architecture](runtime/pane_runtime_architecture.md) | Planes, named contracts, new-signal tree; verify against `PaneRuntime.swift` |
| [Pane Runtime EventBus Design](runtime/pane_runtime_eventbus_design.md) | Admission, hop shape, two buses, shipped actors, Swift 6.2 |
| [Session Lifecycle](runtime/session_lifecycle.md) | Pane identity and session backend lifecycle |
| [Zmx Restore and Sizing](runtime/zmx_restore_and_sizing.md) | Deferred attach and zmx sizing |
| [Surface Architecture](runtime/ghostty_surface_architecture.md) | Ghostty surface ownership |

### commands/

| Document | Ownership |
|----------|-----------|
| [Command Specs](commands/command_specs.md) | `AppCommand` identity, `AppCommandSpec`, `ipcSpec`, `LocalActionSpec`, shortcuts |
| [App IPC](commands/ipc.md) | Socket/JSON-RPC transport, ports, auth — hops to command specs for catalog |

### hosting/

| Document | Ownership |
|----------|-----------|
| [AppKit + SwiftUI Hybrid Architecture](hosting/appkit_swiftui_architecture.md) | Native chrome hosts that consume command specs |

### bridge/

| Document | Ownership |
|----------|-----------|
| [Bridge Viewer Architecture](bridge/bridge_viewer_architecture.md) | End-to-end Bridge ownership |
| [Bridge Product Transport](bridge/bridge_product_transport_architecture.md) | Native/web product transport |
| [Bridge Native Runtime](bridge/bridge_native_runtime_architecture.md) | Swift/WebKit Bridge runtime |
| [Bridge Web Runtime](bridge/bridge_web_runtime_architecture.md) | BridgeWeb runtime |
| [BridgeWeb Design Tokens](bridge/bridgeweb_design_token_architecture.md) | Token layer ownership |

### observability/

| Document | Ownership |
|----------|-----------|
| [Observability And Traceability](observability/observability_and_traceability.md) | Proof model and local proof launch |

### archive/

Not current authority. See [archive/README.md](archive/README.md).

| Document | Live owner instead |
|----------|--------------------|
| [Window System Design](archive/window_system_design.md) | Component / Session / Hosting |
| [Remote zmx Ideas](archive/remote_zmx_architecture_ideas.md) | Zmx restore / App IPC |
| [JTBD & Requirements](archive/jtbd_and_requirements.md) | Current owners above |
| [Zmx Terminal Integration Lessons](archive/zmx_terminal_integration_lessons.md) | Session / Zmx restore |

## Related

- Component note: [`SharedComponents/EditorChooser/`](../../Sources/AgentStudio/SharedComponents/EditorChooser) owns the reusable numbered editor chooser menu content and bookmark UI used by host shells such as the drawer toolbar.
- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — Bootstrap, BridgeWeb Vite loop, zig/Xcode, Swift build-slot recovery, DeepWiki sources, and research guidance
- Platform docs used by this architecture: [Swift](https://www.swift.org/documentation/), [Swift Package Manager](https://docs.swift.org/package-manager/), [AppKit](https://developer.apple.com/documentation/appkit), [SwiftUI](https://developer.apple.com/documentation/swiftui), [Observation](https://developer.apple.com/documentation/observation), [WebKit](https://developer.apple.com/documentation/webkit), and [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
