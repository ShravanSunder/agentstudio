# Agent Studio Architecture

## TL;DR

Agent Studio is a macOS terminal application that embeds Ghostty terminal surfaces within a project/worktree management shell. The app uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. UI-observed canonical state is published from independent `@MainActor @Observable` atoms (Jotai-style) with `private(set)` for unidirectional flow (Valtio-style). Observation is the reason an atom exists; CRUD without a subscriber belongs in a repository. Persistence wrappers such as `WorkspaceStore`, `RepoCacheStore`, and `UIStateStore` snapshot atom-backed UI state that happens to be durable. `WorkspaceSurfaceCoordinator` sequences cross-store and cross-feature operations from the App composition root. Panes are the primary identity — they exist independently of layout, view, or surface. Actions flow through a validated pipeline, and persistence is debounced.

## How To Read This Index

Use this document as a routing layer, not as the full architecture. Pick the
smallest concern-specific doc, then verify the claim against the current code
and tests.

`AGENTS.md` owns the 5-line everyday proof ladder; this index names which proof
doc to open ([Observability And Traceability — Proof Model](observability_and_traceability.md#proof-model),
[Style Guide — Shared Shell Controls](../guides/style_guide.md#shared-shell-controls), and the other rows below).

| Question | Start here | What you get wrong if you skip | Then verify in code |
| --- | --- | --- | --- |
| Where does a file or new type go? | [Directory Structure — Decision Process](directory_structure.md#decision-process-where-does-this-file-go) | You put a Feature type in `Core/Models/` or skip the four-test process. Trees and compiled DAG: [Repository Root](directory_structure.md#repository-root), [Source And Target Structure](directory_structure.md#source-and-target-structure), [SwiftPM Module Graph](directory_structure.md#swiftpm-module-graph). | `Sources/AgentStudio/` placement and import direction |
| Where should a file or module test live? | [Directory Structure — Test Target Ownership](directory_structure.md#test-target-ownership) | You park a module test on the executable target or infer ownership from `swift test --filter`. | `Package.swift` target and source lists |
| Do I need an atom, a derived node, an eager projection, or just SQL? | [Atom Persistence Boundaries — Need An Atom?](atom_persistence_boundaries.md#need-an-atom) | You wrap CRUD in an atom, or reach for `EagerDerivedAtomFamily` as a default. | Product owner vs `*Repository` vs `TabBarAdapter` / `RepoExplorerProjectionAdapter` |
| Which command path, shortcut display, or dense-control tooltip source should I use? | [Command Specs And Execution Owners](commands_and_shortcuts.md#command-specs-and-execution-owners) | You invent a parallel `.help`, tooltip, shortcut, or IPC path that the dispatcher never sees. | `App/Commands/`, `Core/Actions/`, command specs, local action presentation |
| Which shared UI primitive or dense-control visual pattern should I use? | [Style Guide — Shared Shell Controls](../guides/style_guide.md#shared-shell-controls) | You copy styling into a feature, or you put a behavior constant in `AppStyles`. | `SharedComponents/`, `AppStyles`, `AppPolicies` |
| How do the native titlebar, tab hit testing, tab dragging, and window dragging fit together? | [AppKit + SwiftUI Hybrid Architecture — Native Titlebar And Tab Strip](appkit_swiftui_architecture.md#native-titlebar-and-tab-strip) | You treat tab dragging as SwiftUI-local and break window-rooted hit testing. | `MainWindowController`, `MainToolbarChromeView`, `DraggableTabBarHostingView`, window-rooted toolbar tests |
| Is this app state, runtime state, or persisted state? | [Atom Persistence Boundaries — Lifecycle Lanes](atom_persistence_boundaries.md#lifecycle-lanes) | You persist a runtime/presentation atom, or you leave a durable field unsaved. | `Core/State/MainActor/Atoms/`, persistence wrappers |
| Is this write-owner atom / derived read model / SQLite row? | [Atom Persistence Boundaries — Roles](atom_persistence_boundaries.md#roles) | A `Codable` convenience type becomes both live atom state and the SQLite contract. | Atom types vs `*Row` projections vs derived `Pane`/`Tab` readers |
| Workspace command vs pane runtime command vs bus fact vs AppKit lifecycle? | [Mutation Flow](#mutation-flow-summary) in this index; then [Pane Runtime EventBus Design — Admission And Hop Shape](pane_runtime_eventbus_design.md#admission-and-hop-shape) and [Commands and Shortcuts — Command planes](commands_and_shortcuts.md#command-planes) | You route a command through the bus, or you bounce AppKit lifecycle through `WorkspaceActionCommand`. | `WorkspaceActionCommand`, `PaneRuntimeCommand`, `PaneRuntimeEventBus`, `ApplicationLifecycleMonitor` |
| How do pane/runtime commands and facts move? | [Pane Runtime Architecture — Three Data Flow Planes](pane_runtime_architecture.md#three-data-flow-planes) and [Pane Runtime EventBus Design — TL;DR](pane_runtime_eventbus_design.md#tl-dr) | You infer hop shape from `@MainActor` annotations and wake MainActor for raw samples. | `Core/RuntimeEventSystem/`, `App/Coordination/` |
| What may run on MainActor vs off-main? | [Pane Runtime EventBus Design — Admission And Hop Shape](pane_runtime_eventbus_design.md#admission-and-hop-shape) | A `@MainActor` type becomes permission to derive, schedule, or admit there. | Terminal drain/projector, `EagerDerivedAtom`, `FilesystemProjectionIndex` |
| Where are high-rate source signals admitted, contracted, and projected? | [Pane Runtime Architecture — Contract 7](pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction) and [Pane Runtime EventBus Design — Typed Admission](pane_runtime_eventbus_design.md#typed-admission-before-multiplexing); for filesystem effects, [Workspace Data Architecture — Filesystem Effect Admission](workspace_data_architecture.md#filesystem-effect-admission-and-projection) | Raw callbacks wake the bus or MainActor; you skip source admission. | Terminal source routing/projectors and `FilesystemProjectionIndex` |
| How should expensive derived facts react to product demand without polling or stale publication? | [Demand-Driven Derived-State Refresh — Selection Rule](demand_driven_derived_state_refresh.md#selection-rule) | Debounce/throttle is treated as a classification; the wrong mechanism silently drops ordering, scope, or currentness. | The concrete observer, admission owner, executor, publication path, and keyed read model |
| How do I prove telemetry or performance? | [Observability And Traceability — Proof Model](observability_and_traceability.md#proof-model) | Unit tests and feel stand in for marker-scoped Victoria proof. | Trace tags, proof scripts, Victoria verifier output |
| How do I launch debug/beta proof? | [Observability And Traceability — Local proof launch](observability_and_traceability.md#local-proof-launch) | You inherit production identity, share zmx state across worktrees, or treat JSONL as proof. | Debug/beta launchers, identity print, Victoria marker verifiers |
| How does programmatic control stay out of zmx internals? | [AgentStudio App IPC Architecture — Target Ownership](agentstudio_ipc_architecture.md#target-ownership) | App IPC reaches into zmx sockets or session internals. | `App/IPCComposition/`, app ports, runtime adapters |
| How does Bridge Viewer split work between native Swift/WebKit and BridgeWeb? | [Bridge Viewer Architecture — System Map](bridge_viewer_architecture.md#system-map), then [Bridge Product Transport — The three route jobs](bridge_product_transport_architecture.md#the-three-route-jobs), [Bridge Native Runtime — Ownership Map](bridge_native_runtime_architecture.md#ownership-map), or [Bridge Web Runtime — Runtime Topology](bridge_web_runtime_architecture.md#runtime-topology) | Git/protocol work lands in TypeScript, or native and web ownership duplicate. | `Sources/AgentStudio/Features/Bridge/`, `BridgeWeb/src/` |
| When editing BridgeWeb React UI? | [BridgeWeb AGENTS.md — UI Components](../../BridgeWeb/AGENTS.md#ui-components), then [Bridge Viewer Architecture — System Map](bridge_viewer_architecture.md#system-map) | You hand-roll a route-local control instead of owned primitives, or you skip the BridgeWeb operating contract. | `BridgeWeb/src/components/ui/`, FileViewer/ReviewViewer shared chrome |
| BridgeWeb Vite loop, zig/Xcode, or Swift build-slot recovery? | [Agent Resources — BridgeWeb Fast UI Loop](../guides/agent_resources.md#bridgeweb-fast-ui-loop), [Xcode And Zig](../guides/agent_resources.md#xcode-and-zig-vendor-builds), [Swift Build-Slot Recovery](../guides/agent_resources.md#swift-build-slot-recovery) | You rebuild the full app for Bridge UI, hydrate vendors by hand, or collide on `.build`. | `mise` tasks, `scripts/swift-build-slot.sh`, Bridge development server |
| Local SQLite recovery internals? | [Atom Persistence Boundaries — Local recovery](atom_persistence_boundaries.md#local-recovery) | You reconstruct quarantine/reopen from an agent contract instead of the persistence owner. | `WorkspaceSQLiteRecoveryClassifier`, sidecar quarantine |

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
│  │Filesystem   │  │GitProjector │  │ForgeActor   │                    │
│  │Actor        │  │(git status) │  │(PR counts)  │                    │
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
- **Atomic stores (Jotai-style)** — Use an atom only when UI or another subscriber must observe shared state. CRUD without Observation belongs in a repository; see [Need An Atom?](atom_persistence_boundaries.md#need-an-atom). Each justified atom owns one domain and has one reason to change. Compatibility facades such as `WorkspacePaneAtom`, `WorkspaceTabArrangementAtom`, and `WorkspaceTabLayoutAtom` bridge existing call sites while split write owners land. Persistence wrappers snapshot atom groups that happen to be durable. Feature atoms live inside their feature slice at `Features/<slice>/State/MainActor/Atoms/` — see [Directory Structure — Feature Slice Self-Containment](directory_structure.md#feature-slice-self-containment).
- **Unidirectional flow (Valtio-style)** — All store state is `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers.
- **Coordinator for cross-store sequencing** — A coordinator sequences operations across stores for a single user action. Owns no state, contains no domain logic.
- **Lifecycle ingress stays separate** — `ApplicationLifecycleMonitor` owns AppKit ingress only. It mutates `AppLifecycleAtom` and `WindowLifecycleAtom`, both `@Observable` atomic stores with `private(set)` mutation surfaces. `WindowLifecycleAtom` holds transient window facts only: key/focus state, terminal container bounds, launch-layout-settle state, and derived readiness; none of those readiness properties are persisted.
- **Immutable layout tree** — `Layout` is a pure value type; operations return new instances, never mutate
- **Surface independence** — Ghostty surfaces are ephemeral runtime resources; the model layer never holds `NSView` references
- **Main-actor UI state, off-main runtime work** — AppKit, SwiftUI, atoms, observable UI state, and WebKit integration stay on `@MainActor`; expensive runtime work such as file I/O, hashing, diff preparation, and provider calls belongs behind actors/services with `Sendable` request/result models.
- **AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing Combine/NotificationCenter migrated incrementally.
- **Trace tags select instrumentation** — Observability emitters are gated by `AGENTSTUDIO_TRACE_TAGS`; backends are selected separately by `AGENTSTUDIO_TRACE_BACKEND` and loopback OTLP variables. Do not add one-off env vars for individual emitters. See [Observability And Traceability — Control Plane](observability_and_traceability.md#control-plane).

Current atom vocabulary:

- **Atoms** own mutable state and synchronous domain operations. Application-global owners include `ActiveWorkspaceSelectionAtom`, `RepositoryTopologyAtom`, `RepoEnrichmentCacheAtom`, and `ApplicationEntityRecencyAtom`. Workspace owners include identity, pane/tab/drawer graph and cursors, and `WorkspaceEntityRecencyAtom`. Window-keyed owners hold frame/sidebar shell and expanded-group memory. Runtime-only owners include focus, transient keyboard surfaces, app/window lifecycle, and session runtime. `WorkspacePaneAtom`, `WorkspaceTabArrangementAtom`, `WorkspaceTabLayoutAtom`, and `RepoCacheAtom` remain composed compatibility/read surfaces for existing consumers.
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
├── cached WorkspaceLocalRepository    ← non-authoritative local UX/cache/inbox rows
└── WorkspaceSQLiteSnapshot            ← live actor-crossing snapshot, not a row projection

WorkspaceSidebarMemoryAtom (window-keyed rows in app-root local.sqlite)
├── filterText, isFilterVisible
└── sidebarCollapsed, sidebarSurface

SidebarFocusRuntimeAtom (runtime only)
└── sidebarHasFocus

WorkspaceSidebarState
└── composed UI-facing reader/mutator over sidebar memory + runtime focus
```

## Mutation Flow (Summary)

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

Each document owns a specific concern. No two documents are authoritative for the same topic. When in doubt about where something belongs, the ownership column determines the home.

| Document | Ownership | Covers |
|----------|-----------|--------|
| [Component Architecture](component_architecture.md) | Structural overview — how components compose | Data model (pane, tab, layout, session), service layer, command bar, persistence format, store boundaries, coordinator role, invariants |
| [Workspace Data Architecture](workspace_data_architecture.md) | Workspace-level data — repos, worktrees, enrichment | Three-tier persistence, canonical vs enrichment models, enrichment pipeline, topology reconciliation, typed filesystem/Git pane-projection admission, affected-key effects, sidebar data flow, ordering/replay contracts |
| [Demand-Driven Derived-State Refresh](demand_driven_derived_state_refresh.md) | Generic classify-first vocabulary for expensive derived facts | Selection rule, nine-stage loop, bounded outcome telemetry, R-INV suppression/deferral gates, and drift discipline |
| [Atom Persistence Boundaries](atom_persistence_boundaries.md) | Atom-to-SQLite ownership model | Write-owner atom rules, current lifecycle lanes, derived read models, current row projections, runtime-only surfaces, and ownership map |
| [Pane Runtime Architecture](pane_runtime_architecture.md) | Pane-level runtime contracts | Pane runtime contracts (C1-C16), typed Ghostty source admission and bounded contraction (C7), event envelopes, per-pane event taxonomy, adapter/runtime/coordinator layers, attach and restart contracts, command dispatch, and source/sink/projection vocabulary |
| [Pane Runtime EventBus Design](pane_runtime_eventbus_design.md) | EventBus threading and coordination | Concrete admission-to-coordination mechanics, actor fan-out, boundary actors, compact MainActor application, semantic projection, connection patterns, and Swift 6.2 threading model |
| [Window System Design](window_system_design.md) | Window/tab/pane structural model | Window/tab/pane/drawer data model, dynamic views, arrangements, orphaned pane pool, ownership invariants |
| [Session Lifecycle](session_lifecycle.md) | Pane identity and session backend lifecycle | Pane identity contract, creation, close, undo, restore, runtime status, zmx backend |
| [Zmx Restore and Sizing](zmx_restore_and_sizing.md) | Zmx-specific attach and sizing | Deferred attach sequencing, geometry readiness, restart reconcile policy, zmx restore/sizing test coverage |
| [Surface Architecture](ghostty_surface_architecture.md) | Ghostty surface management | Surface ownership, state machine, health monitoring, crash isolation, CWD propagation |
| [App Architecture](appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid shell | AppKit hosting model, controllers, command bar panel, event handling |
| [Commands and Shortcuts](commands_and_shortcuts.md) | Command + shortcut system | Shared command identity, independent exhaustive interactive/IPC projections, typed surfaces and targeting, capability and execution, shortcut routing, and tooltip projection |
| [AgentStudio App IPC Architecture](agentstudio_ipc_architecture.md) | App-level programmatic control | SwiftPM target split, socket/JSON-RPC foundation, auth, permission grants, protocol ports, CLI/smoke client, and the boundary between app IPC and internal zmx IPC |
| [Remote zmx Architecture Ideas](remote_zmx_architecture_ideas.md) | Remote zmx daemons and fork strategy | SSH tunnel architecture (Option C), security model, connection lifecycle, case for forking zmx |
| [Directory Structure](directory_structure.md) | Module, test, and file-placement boundaries | Repo-root tree, `Sources/AgentStudio/` tree, compiled SwiftPM graph, package visibility, Core vs Features decision process, import rule, paired tests, executable integration ownership |
| [Architecture Lint Inventory](architecture_lint_inventory.md) | Architecture lint enforcement map | SwiftLint rule IDs, former shell-script coverage, blocking/report-only/test/review classifications |
| [AgentStudio IPC Architecture](agentstudio_ipc_architecture.md) | App-level programmatic-control boundaries | Public contract, AppIPC port, app composition, zmx separation, and lint-rule ownership boundaries |
| [Bridge Viewer Architecture](bridge_viewer_architecture.md) | End-to-end Bridge Viewer ownership | Product boundaries, native/web split, source-to-paint lifecycle, viewer modes, freshness, and proof routing |
| [Bridge Product Transport Architecture](bridge_product_transport_architecture.md) | Bridge native/web product transport | Command, metadata, content, demand, application-protocol, and placement boundaries |
| [Bridge Native Runtime Architecture](bridge_native_runtime_architecture.md) | Swift/WebKit Bridge runtime | Shared construction, `agentstudio-git`, Git scheduling, pane publication, transport, activity, and teardown |
| [Bridge Web Runtime Architecture](bridge_web_runtime_architecture.md) | BridgeWeb runtime | One comm worker per pane, separate File/Review state, demand, cache, Pierre/Shiki rendering, suspension, and reconvergence |
| [JTBD & Requirements](jtbd_and_requirements.md) | Product requirements | Jobs to be done, pain points, and requirements for the dynamic window system |

## Related

- Component note: `SharedComponents/EditorChooser/` owns the reusable numbered editor chooser menu content and bookmark UI used by host shells such as the drawer toolbar.
- [Style Guide](../guides/style_guide.md) — macOS design conventions and visual standards
- [Agent Resources](../guides/agent_resources.md) — Bootstrap, BridgeWeb Vite loop, zig/Xcode, Swift build-slot recovery, DeepWiki sources, and research guidance
- Platform docs used by this architecture: [Swift](https://www.swift.org/documentation/), [Swift Package Manager](https://docs.swift.org/package-manager/), [AppKit](https://developer.apple.com/documentation/appkit), [SwiftUI](https://developer.apple.com/documentation/swiftui), [Observation](https://developer.apple.com/documentation/observation), [WebKit](https://developer.apple.com/documentation/webkit), and [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
