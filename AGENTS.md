# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Build & Test

Build orchestration uses [mise](https://mise.jdx.dev/). Install with `brew install mise`.

```bash
mise run setup                # Init submodules, build vendored artifacts, copy resources
mise run build                # Build the Swift app
mise run test                 # Run tests (Swift 6 `Testing`)
mise run format               # Auto-format all Swift sources
mise run lint                 # Lint (swift-format + swiftlint + boundary checks)
.build/debug/AgentStudio      # Launch debug build
```

First-time setup: `mise install && mise run doctor-mac && mise run setup && mise run build`. See [Agent Resources](docs/guides/agent_resources.md) for full bootstrap.

> **Time-based note (2026-04): Xcode 26.4+ breaks vendored zig 0.15.2 builds.** Apple's Xcode 26.4 `MacOSX.sdk/usr/lib/libSystem.B.tbd` drops `arm64-macos` from top-level targets → zig 0.15.2's linker fails with `undefined symbol: _abort`, `_getenv`, etc. on Apple Silicon when building ghostty/zmx. Xcode 26.5 beta is also affected. Fixed in zig 0.16 (which ghostty hasn't adopted). Workaround: install **Xcode 26.3** side-by-side, `sudo xcode-select --switch /Applications/Xcode_26.3.app/Contents/Developer`, `xcodebuild -downloadComponent MetalToolchain`, `rm -rf ~/.cache/zig`. If `mise run setup` surfaces `undefined symbol: _abort` or similar libSystem errors, this is the cause. Refs: [ghostty#11991](https://github.com/ghostty-org/ghostty/issues/11991), [zig#31658](https://codeberg.org/ziglang/zig/issues/31658). Delete this note once ghostty bumps to zig 0.16 or Apple fixes the SDK.

Testing: Swift 6 `Testing` only — `@Suite`, `@Test`, `#expect`. No XCTest. A PostToolUse hook (`.claude/hooks/check.sh`) runs swift-format and swiftlint automatically after every Edit/Write on `.swift` files.

### No Wall-Clock Tests

Wall-clock sleeps make tests flaky. CI machines run at different speeds, so "sleep 50ms and expect X" is not a contract.

Do not:
- use `Task.sleep(...)` in test bodies to wait for async work
- assert intermediate state after an arbitrary delay
- rely on suite serialization to hide leaked async work

Instead:
- wait for the exact event or state you care about, with a bounded timeout
- use injected clocks for debounce/timer behavior
- fully shut down tasks, streams, actors, and observers before the test returns
- use explicit protocol seams and fakes for testability
- do not add new `#if DEBUG` test hooks in production files

## Architecture at a Glance

AppKit-main architecture hosting SwiftUI views. Shared app state is actor-bound and accessed through `AtomRegistry` + `AtomScope`, with `atom(\.foo)` as the primary read path. Canonical mutable state lives in `@MainActor @Observable` atoms under `Core/State/MainActor/Atoms`, and persistence wrappers live under `Core/State/MainActor/Persistence`. Two coordinators handle cross-slice sequencing. An `EventBus<RuntimeEnvelope>` connects runtime actors to the main-actor state system, and a separate app lifecycle monitor owns AppKit ingress.

`AtomRegistry` is the single root-level composition file at `Sources/AgentStudio/AtomRegistry.swift`. It may compose Core and Feature atoms. `Infrastructure/AtomLib` owns only the generic access helpers (`atom(\...)`, `AtomScope`, `AtomReader`, `Derived`, `DerivedSelector`) and must not own product atoms or feature-specific registry fields.

### Folder Arcs

Use these broad ownership rules first, then consult [Directory Structure](docs/architecture/directory_structure.md) for exact placement:

- `App/`
  Composition root and host-specific assembly. App-owned shells, pane/window controllers, lifecycle wiring, and cross-slice orchestration live here.
- `Core/`
  Shared domain state and contracts. Models, atoms, persistence wrappers, validated action routing, runtime contracts, and shared split/drawer primitives live here.
- `SharedComponents/`
  Reusable UI building blocks that are not themselves product features and do not own host placement. Use this for reusable menu content, row rendering, and small UI-facing models.
- `Features/`
  User-facing capability slices such as Terminal, Bridge, Webview, CodeViewer, CommandBar, RepoExplorer, InboxNotification, and feature-owned EditorChooser state. Features own capability-specific behavior that is broader than a reusable component.
- `Infrastructure/`
  Domain-agnostic utilities and external integrations. Organize these in subfolders by concern, such as `AtomLib/`, `Extensions/`, `Icons/`, `StateMachine/`, and integration-specific folders like `ExternalApps/`. `Infrastructure/AtomLib` holds generic atom access helpers only; the concrete `AtomRegistry` lives at the source root because it composes Core and Feature atoms.

### Shared UI, Styles, And Policies

When two app surfaces need the same visual control, extract a stateless primitive into `SharedComponents/` instead of copying styling between features. Shared components render from value parameters, `@Binding`, and closures; they do not subscribe to atoms and they do not import `Core/`, `Features/`, or `App/`.

Before creating a feature-local UI primitive, check for an existing shared component with the same interaction semantics. Reuse or extract keyboard, focus, selection, and command-toggle behavior even when row content differs. Styling parity alone is not enough.

Use `AppStyles` for presentation constants only: spacing, radii, icon sizes, opacity, typography, colors, and paint dimensions. Use `AppPolicies` for behavioral constants: limits, thresholds, retention caps, validation rules, routing rules, and accept/reject decisions. If changing the value can change state transitions or command/event behavior, it belongs in `AppPolicies` even when the UI reads it.

Search rule of thumb:
- Sidebar search surfaces use `SharedComponents/SidebarSearchField`.
- Command bar search remains command-bar-owned because it owns scope and shortcut semantics.
- Webview select-all fields remain Webview-owned until a second feature needs that exact AppKit behavior.

### Command Specs And Execution Owners

Before adding or changing a command, read [Commands and Shortcuts](docs/architecture/commands_and_shortcuts.md). Use `AppCommand` for identity, `AppShortcut` for bindings, `CommandSpec` for command-bar/tooltips, and `LocalActionSpec` for UI-only actions. App/window/sidebar shell commands may route through `AppDelegate`; pane, drawer, focus, layout, and workspace commands route through `PaneTabViewController` so keyboard shortcuts, command-bar rows, and drawer buttons share the same resolver.

Command-bar scopes have separate ownership:
- `>` owns verbs and command execution.
- `$` owns existing pane/tab navigation.
- `#` owns repo/worktree locations and opening.

Keep this split explicit. Do not add repo/worktree management rows to `$`, do
not add arbitrary verbs to `#`, and do not duplicate `LocalActionSpec` labels or
icons when a sidebar/local action already defines the presentation.

| Component | Owns | Location |
|-----------|------|----------|
| `AtomRegistry` | concrete root composition file for Core and Feature atoms plus derived helpers | `Sources/AgentStudio/AtomRegistry.swift` |
| `ActiveWorkspaceSelectionAtom` | global active workspace id selection, independent from per-workspace metadata hydration | `Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtom.swift` |
| `WorkspaceMetadataAtom` | workspace identity plus persisted window/sidebar metadata | `Core/State/MainActor/Atoms/WorkspaceMetadataAtom.swift` |
| `WorkspaceRepositoryTopologyAtom` | repos, worktrees, watched paths, availability | `Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift` |
| `WorkspacePaneAtom` | panes, pane metadata/content/residency, drawer state | `Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` |
| `WorkspaceTabLayoutAtom` | tabs, arrangements, active selection, zoom/minimize | `Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift` |
| `WorkspaceMutationCoordinator` | cross-atom workspace mutations spanning pane and tab layout state | `Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift` |
| `RepoCacheAtom` | repo enrichment, branches, git status, PR counts, recent targets | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `UIStateAtom` | expanded groups, colors, filter state | `Core/State/MainActor/Atoms/UIStateAtom.swift` |
| `WorkspaceFocusDerived` | shared app-wide focus reader for command visibility and status UI | `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` |
| `ManagementLayerAtom` | management layer active/inactive state | `Core/State/MainActor/Atoms/ManagementLayerAtom.swift` |
| `CommandBarSurfaceAtom` | runtime command-bar keyboard surface scope | `Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift` |
| `TransientKeyboardSurfaceAtom` | runtime transient keyboard surface stack | `Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtom.swift` |
| `ArrangementPanelPresentationAtom` | runtime pending arrangement panel presentation request | `Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift` |
| `SessionRuntimeAtom` | runtime status per pane | `Core/State/MainActor/Atoms/SessionRuntimeAtom.swift` |
| `WorkspaceStore` | persistence wrapper over the workspace-domain atoms | `Core/State/MainActor/Persistence/WorkspaceStore.swift` |
| `RepoCacheStore` | persistence wrapper for `RepoCacheAtom` | `Core/State/MainActor/Persistence/RepoCacheStore.swift` |
| `UIStateStore` | persistence wrapper for `UIStateAtom` | `Core/State/MainActor/Persistence/UIStateStore.swift` |
| `AppLifecycleAtom` | application active/terminating state | `Core/State/MainActor/Atoms/AppLifecycleAtom.swift` |
| `WindowLifecycleAtom` | key/focused window identity, registration, transient terminal geometry, launch-settle facts | `Core/State/MainActor/Atoms/WindowLifecycleAtom.swift` |
| `PaneFilesystemProjectionAtom` | pane-scoped filesystem projection state derived from runtime envelopes | `Core/State/MainActor/Atoms/PaneFilesystemProjectionAtom.swift` |
| `SurfaceManager` | Ghostty surface lifecycle, health, undo | `Features/Terminal/` |
| `SessionRuntime` | backend coordination, health checks, zmx/runtime orchestration over `SessionRuntimeAtom` | `Core/RuntimeEventSystem/Runtime/SessionRuntime.swift` |

**Worktree model is structure-only:** `id`, `repoId` (FK), `name`, `path`, `isMainWorktree`. No branch, no status. All enrichment lives in `RepoCacheAtom`, populated by the event bus.

**Event bus pattern:** Mutate the store directly → emit a fact on the bus → coordinator updates the other store. This is NOT CQRS — no command bus, no command handlers. `ApplicationLifecycleMonitor` is ingress-only and mutates lifecycle stores directly from AppKit callbacks. See [State Management Patterns](#state-management-patterns) below and [Event System Design](docs/architecture/workspace_data_architecture.md#event-system-design-what-it-is-and-isnt) for full detail.

**Embedded Ghostty host split:** Keep `Ghostty.shared` as the subsystem entrypoint and keep `Ghostty.App` thin. Host-side runtime responsibilities are split by isolation contract:
- `Ghostty.AppHandle` owns `ghostty_app_t` and config lifetime
- `Ghostty.CallbackRouter` owns the C callback table and userdata reconstruction
- `Ghostty.ActionRouter` owns the action switch and runtime routing seam
- `Ghostty.AppFocusSynchronizer` owns app-level focus sync via `AppLifecycleAtom.isActive`
Future terminal event-routing expansion belongs in `Ghostty.ActionRouter` plus adapter/runtime layers, not back in `Ghostty.swift`.

### Architecture Docs

Each doc owns a specific concern. See [Architecture Overview](docs/architecture/README.md) for the full document index.

| Doc | Covers |
|-----|--------|
| [Component Architecture](docs/architecture/component_architecture.md) | Data model, stores, coordinator, persistence, invariants |
| [Workspace Data Architecture](docs/architecture/workspace_data_architecture.md) | Three-tier persistence, enrichment pipeline, event bus contracts, sidebar data flow |
| [Pane Runtime Architecture](docs/architecture/pane_runtime_architecture.md) | Pane runtime contracts (C1-C16), RuntimeEnvelope, event taxonomy |
| [EventBus Design](docs/architecture/pane_runtime_eventbus_design.md) | Actor threading, connection patterns, multiplexing rule |
| [Session Lifecycle](docs/architecture/session_lifecycle.md) | Pane identity, creation, close, undo, restore, zmx backend |
| [Surface Architecture](docs/architecture/ghostty_surface_architecture.md) | Ghostty surface ownership, state machine, health, crash isolation |
| [App Architecture](docs/architecture/appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid, controllers, events |
| [Commands and Shortcuts](docs/architecture/commands_and_shortcuts.md) | The four-file system (AppCommand / AppShortcut / CommandSpec / LocalActionSpec), execution-owner decision tree (`AppDelegate` shell vs `PaneTabViewController` pane/drawer), contexts, alternateTriggers, and where constants live (AppShortcut vs AppPolicies vs AppStyles vs LocalActionSpec) |
| [Directory Structure](docs/architecture/directory_structure.md) | Module boundaries, Core vs Features, import rule, component placement |
| [Swift-React Bridge](docs/architecture/swift_react_bridge_design.md) | Bridge architecture, content-delivery status, JSON-RPC/push contracts, read-only CodeView/Shiki review surface, and LUNA-337 completion boundary |
| [Style Guide](docs/guides/style_guide.md) | macOS design conventions and visual standards |
| [Agent Resources](docs/guides/agent_resources.md) | Bootstrap, official Swift/macOS docs, DeepWiki sources, and research guidance |

### Plans

Active implementation plans live in `docs/plans/`. Plans are date-prefixed (`YYYY-MM-DD-feature-name.md`). If a plan's date is before the current branch's work started, it's likely completed — verify before executing.

## Before You Code

### UX-First (Mandatory for UI Changes)

**STOP. Before implementing ANY UI/UX change:**
1. Talk to the user FIRST — discuss the UX problem, align on the experience
2. Research using Perplexity/DeepWiki BEFORE coding
3. Propose the approach, get alignment, then implement
4. Verify with [Peekaboo](https://github.com/steipete/Peekaboo) after

Swift compile times are long. A wrong UX assumption wastes minutes per iteration. Research → discuss → implement → verify.

### Visual Verification

Agents **must** visually verify all UI/UX changes using Peekaboo. **Never target apps by name** when testing debug builds — use PID targeting. **Never `pkill` AgentStudio** — it kills the user's running app. The build dir is auto-allocated by `mise run build` (see [Running Swift Commands — Detail](#running-swift-commands--detail)); locate the binary and launch from there:

```bash
mise run build                              # claims a slot, prints "[swift-build-slot] using .build-agent-N"
BUILD_PATH=$(ls -dt .build-agent-*/debug/AgentStudio 2>/dev/null | head -1 | xargs dirname | xargs dirname)
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
peekaboo see --app "PID:$PID" --json
```

### Definition of Done

1. All requirements met
2. All tests pass (`mise run test` — show pass/fail counts)
3. Lint passes (`mise run lint` — zero errors)
4. Code reflects the shared mental model
5. Evidence provided (exit codes, counts)

### Agent Resources

Use DeepWiki and official documentation for grounded context. Never guess at APIs.
- **Guide**: [Agent Resources & Research](docs/guides/agent_resources.md) — first-time setup, DeepWiki knowledge base
- **Core Repos**: `ghostty-org/ghostty`, `swiftlang/swift`

---

## State Management Patterns

These four patterns govern all code. Follow them. Breaking them creates bugs that are expensive to find.

### 1. Atoms — canonical state

`@Observable @MainActor`, `private(set)` reads, mutation via methods (valtio-style). One atom per domain, one reason to change. No god-atom. Atoms never touch disk.

**Write-owner atoms are not SQL table models.** When moving persistence to SQLite, keep atom boundaries aligned to lifecycle and semantic write ownership, not relational normalization. A write-owner atom may project to multiple normalized tables when one validated user command must update those rows coherently. Use derived readers/atoms to compose rich UI/domain values from several write-owner atoms. Do not create one atom per table such as `pane`, `drawer_pane`, `tab_pane`, and `arrangement_layout_pane`; that pushes table orchestration into coordinators and destroys domain cohesion.

**Disclose atom and type roles.** When adding or splitting atom-backed state, name and document whether each affected type is write-owner atom state, a derived read model, a SQLite row projection, or a legacy import DTO. Rich UI names such as `Pane`, `Drawer`, `Tab`, `PaneArrangement`, and `DrawerView` may remain derived read-model names, but write-owner atoms should store explicit graph/cursor/presentation state, legacy JSON should use explicit `Legacy*Payload` DTOs, and future SQLite repositories should use explicit `*Row` projections. Do not let `Codable` legacy payload names become the live SQLite storage contract by accident.

**Survey does not mean persist.** During SQLite planning, every atom-backed field must be classified into one lifecycle lane: core graph, local UX memory, settings, cache, runtime/presentation, derived read model, legacy import DTO, or future row projection. Only the durable lanes get storage. Runtime/presentation atoms such as command-bar surfaces, transient keyboard surfaces, arrangement-panel requests, pane-note popover/draft state, focus handoffs, health snapshots, and ordinal helpers stay out of SQLite unless a separate UX decision explicitly promotes them to local memory with tests. Pane note text itself is durable pane metadata and belongs with the pane graph.

**SQLite cutover alignment.** The planned SQLite cutover splits lifecycle-mixed atoms before repository work: workspace identity vs window memory, tab shell vs cursor, pane graph vs drawer cursor, tab graph vs arrangement cursor vs runtime presentation, cache enrichment vs recent targets, and settings/runtime feature state. `active_workspace_id` is global core state and needs its own selection owner. Step 0 starts from `main` after pane-shortcuts and command-bar repo/worktree changes merged through `54c99b91`; action snapshots, validators, runtime shortcut/presentation atoms, `KeyboardRoutingContext`, `ActiveKeyboardSurface`, `PaneOrdinalMap`, pane-note metadata/presentation, CWD context updates, and RepoCacheStore observation are part of the Step 0 survey. When these boundaries are implemented, update this `AGENTS.md` component table and the architecture docs in the same changeset as the code.

**Path convention (universal):** `<owner>/State/MainActor/Atoms/` for all atoms, whether Core or Feature. Shared atoms in `Core/State/MainActor/Atoms/`; feature-scoped atoms in `Features/<slice>/State/MainActor/Atoms/`. Existing features without the `MainActor/` subpath are grandfathered; new features adopt the full path.

**Composition state vs feature state.** Composition state (app-wide UI shell — which surface is showing, has-focus, collapsed) lives on `UIStateAtom` in Core. Feature state (domain data specific to one feature) lives in feature atoms inside the feature slice. Never add a feature-specific property to a Core atom; never add a feature type to `Core/Models/` just because an atom references it — that forces feature types into Core.

Shared reads use `atom(\.foo)` or `AtomReader`; `@Atom(\.foo)` is optional convenience sugar. See [component_architecture.md](docs/architecture/component_architecture.md) and [directory_structure.md — Feature Slice Self-Containment](docs/architecture/directory_structure.md) for canonical examples.

### 2. Stores — persistence wrappers

One store per persistence boundary. A store may wrap one atom (`RepoCacheStore`) or many that persist together in one file (`WorkspaceStore`). Stores own file I/O, debounced saves, and schema versioning. Stores never contain domain logic.

**Path convention (universal):** `<owner>/State/MainActor/Persistence/` for all stores, whether Core or Feature. Shared stores in `Core/State/MainActor/Persistence/`; feature-scoped stores in `Features/<slice>/State/MainActor/Persistence/`. See [Three Persistence Tiers](docs/architecture/workspace_data_architecture.md#three-persistence-tiers) for the file-level mapping.

**Atom and store boundaries are architectural decisions — always ask the user before changing them:**
- **Adding a new atom or store:** "Does this earn its own atom/store? What's the one-sentence job description? What's the single reason it changes?"
- **Adding properties to an existing atom:** "Does this property belong here, or is it polluting this atom's job? Could it belong elsewhere or be derived?" An atom that accumulates unrelated properties is becoming a god-atom by accretion.
- **Adding new event types or coordinator responsibilities:** These expand the system's surface area. Discuss before implementing.

### 3. Coordinator Sequences, Doesn't Own

A coordinator sequences operations across stores for a user action. Owns no state, contains no domain logic. **The test:** if a coordinator method has an `if` that decides *what* to do with domain data, that logic belongs in a store. See [PaneCoordinator](docs/architecture/component_architecture.md#36-panecoordinator) for the cross-store pattern.

### 4. Event-Driven Enrichment — Bus → Coordinator → Stores

Runtime actors produce facts → `EventBus` → `WorkspaceCacheCoordinator` → updates stores.

```
FilesystemActor ──► .repoDiscovered(linkedWorktrees: .scanned([...])) ──┐
GitProjector    ──► .snapshotChanged, .branchChanged ───────────────────┤──► EventBus
ForgeActor      ──► .pullRequestCountsChanged ──────────────────────────┘      │
                                                                               ▼
                                                              WorkspaceCacheCoordinator
                                                              (topology accumulator)
                                                                       │
                                              ┌────────────────────────┼──────────────────────┐
                                              ▼                        ▼                      ▼
                                       WorkspaceRepositoryTopologyAtom  RepoCacheAtom  TopologyEffectHandler
                                       WorkspacePaneAtom + WorkspaceTabLayoutAtom     (PaneCoordinator)
                                              │                        │              orphan panes +
                                              └────────────┬───────────┘              sync FS roots
                                                           ▼
                                                    Sidebar (@Observable reader)
```

**Topology accumulator pattern:** For topology events with `LinkedWorktreeInfo.scanned(...)`, the coordinator uses `WorktreeReconciler` (pure function) to compute a `WorktreeTopologyDelta`, then calls `TopologyEffectHandler.topologyDidChange(delta)` for ordered effects. Cache pruning happens in the coordinator; pane orphaning + filesystem root sync happens in PaneCoordinator via the handler. PaneCoordinator does NOT subscribe to topology events on the bus. See [Workspace Data Architecture — Topology Accumulator Pattern](docs/architecture/workspace_data_architecture.md).

**This is NOT CQRS.** The event bus carries facts, not commands. Stores are mutated by their own methods. Typed command planes still exist, but they do **not** run through the bus:
- `PaneActionCommand` for workspace mutations (`CommandDispatcher` → `WorkspaceCommandResolver` builds `ActionStateSnapshot` → `WorkspaceCommandValidator` validates against snapshot → `PaneCoordinator`)
- `RuntimeCommand` for pane-runtime commands (`PaneCoordinator` → `RuntimeRegistry` → `runtime.handleCommand(...)`)
- `AppEventBus` for app-level notifications/facts that do not fit either command plane
- `ApplicationLifecycleMonitor` for AppKit/macOS lifecycle ingress into the lifecycle stores

**The pattern:** mutate store directly → emit fact on bus → coordinator updates other store.

**Do NOT:** add command enums, route mutations through the bus, create command/event type pairs, build read/write segregation.

**Do:** emit topology events after canonical mutations, make handlers idempotent (dedup by stableKey/worktreeId), use the bus for notification only.

### Coordination Plane Decision Table

Use the narrowest plane that still preserves the architecture boundary.

| If the change is... | Use | Notes |
|---------------------|-----|-------|
| Workspace mutation | `PaneActionCommand` | Validator-gated, then sequenced by `PaneCoordinator` into stores. |
| Runtime command | `RuntimeCommand` | Direct `PaneCoordinator -> RuntimeRegistry -> runtime.handleCommand(...)`. |
| Runtime fact | `PaneRuntimeEventBus` | Fact fan-out only; never route commands through it. |
| Topology fact (repo/worktree discovered/removed) | `PaneRuntimeEventBus` | Fact fan-out. Coordinator is the single accumulator. Uses `WorktreeReconciler` + `TopologyEffectHandler`. |
| Ordered post-topology effects (root sync, pane orphan) | `TopologyEffectHandler` | Direct handler call from coordinator to PaneCoordinator. NOT via bus — ordering must be deterministic. |
| App-level notification that is not a command | `AppEventBus` | Notification fan-out only. Not a workspace command boundary. |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` | Owns AppKit ingress and writes `AppLifecycleAtom` / `WindowLifecycleAtom`. |
| UI-only local state | Local `@Observable` state | Keep it in the owning view/controller. Do not bounce it through a bus or `NotificationCenter`. |

The old `AppCommand -> AppEventBus -> controller -> PaneActionCommand` chain has been removed. User-triggered workspace work now enters through validated `PaneActionCommand` routing directly.

For full detail:
- [Event namespaces](docs/architecture/workspace_data_architecture.md#event-namespaces) — which events exist and who produces them
- [Lifecycle flows](docs/architecture/workspace_data_architecture.md#lifecycle-flows) — boot, Add Folder, branch change step-by-step
- [Integration test examples](docs/architecture/workspace_data_architecture.md#writing-integration-tests-with-events) — how to test event flows with real stores
- [Idempotency contracts](docs/architecture/workspace_data_architecture.md#idempotency-contract) — dedup keys and ordering tolerance
- [Actor threading](docs/architecture/pane_runtime_eventbus_design.md#architecture-overview) — how actors connect to the bus

### Additional Patterns

**AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. No new Combine subscriptions. No new NotificationCenter observers.

**Choose the right coordination plane**:
- Asking the workspace to change shape: `PaneActionCommand`
- Asking one runtime to do work: `RuntimeCommand`
- Reporting that something already happened: `PaneRuntimeEventBus`
- Broadcasting an app-level fact/notification that does not belong on the command planes: `AppEventBus`
- Handling AppKit/macOS lifecycle ingress: `ApplicationLifecycleMonitor`

**Injectable Clock** — All store-level time-dependent logic accepts `any Clock<Duration>` as a constructor parameter. This makes undo TTLs, health checks, and debounce timers testable.

**Bridge-per-Surface** — Each Ghostty surface gets a typed bridge conforming to `PaneBridge` with its own observable state. See [Surface Architecture](docs/architecture/ghostty_surface_architecture.md).

**What we don't do:** No god-store. No Combine for new code. No NotificationCenter for new app-domain coordination. No `ObservableObject/@Published`. No `DispatchQueue.main.async` from C callbacks.

---

## Project Structure

See [Directory Structure](docs/architecture/directory_structure.md) for the full module boundary spec, Core vs Features decision process, and component placement rationale.

```
agent-studio/
├── Sources/AgentStudio/
│   ├── App/                          # Composition root — wires everything, imports all
│   │   ├── Boot/AppDelegate.swift
│   │   ├── Windows/MainWindowController.swift
│   │   ├── Coordination/PaneCoordinator.swift  # Cross-feature sequencing and orchestration
│   │   └── Panes/                    # Pane tab management and NSView registry
│   ├── Core/                         # Shared domain — models, stores, pane system
│   │   ├── Models/                   # Layout, Tab, Pane, Repo, Worktree, SidebarSurface,
│   │   │                             #   KeyboardOwner, ...
│   │   ├── State/
│   │   │   └── MainActor/
│   │   │       ├── Atoms/            # WorkspaceMetadataAtom, WorkspacePaneAtom,
│   │   │       │                     #   UIStateAtom, ManagementLayerAtom,
│   │   │       │                     #   WorkspaceFocusDerived, KeyboardOwnerDerived, ...
│   │   │       └── Persistence/      # WorkspaceStore, RepoCacheStore, UIStateStore
│   │   ├── RuntimeEventSystem/       # Runtime actors, event bus, SessionRuntime, ZmxBackend
│   │   ├── Actions/                  # PaneActionCommand, WorkspaceCommandResolver, WorkspaceCommandValidator
│   │   └── Views/                    # Tab bar, splits, drawer, arrangement
│   ├── Features/                     # Each feature is self-contained; see
│   │   │                             #   directory_structure.md — Feature Slice Self-Containment
│   │   ├── Terminal/                 # Ghostty C API bridge, SurfaceManager, views
│   │   ├── Bridge/                   # React/WebView pane system (transport, runtime, state)
│   │   ├── Webview/                  # Browser pane (navigation, history)
│   │   ├── CommandBar/               # ⌘P command palette
│   │   ├── RepoExplorer/             # Repo explorer (renamed from Features/Sidebar/ in
│   │   │                             #   LUNA-361; the "sidebar" itself is composition in
│   │   │                             #   App/, not a feature)
│   │   └── <NewFeature>/             # Features/<Feature>/{Components,Models,Routing,
│   │                                 #   State/MainActor/{Atoms,Persistence},Views}/
│   ├── SharedComponents/             # Stateless UI primitives (design system). Currently
│   │                                 #   hosts EditorChooser/; more primitives land here
│   │                                 #   over time. Imports only Infrastructure. No atom
│   │                                 #   subscriptions. State flows via @Binding / value
│   │                                 #   parameters.
│   └── Infrastructure/               # Domain-agnostic utilities
├── docs/architecture/                # Authoritative design docs (see table above)
├── docs/plans/                       # Date-prefixed implementation plans
├── vendor/ghostty/                   # Git submodule: Ghostty source
└── vendor/zmx/                       # Git submodule: zmx session multiplexer
```

**Import rule:** `App/ → Core/, Features/, Infrastructure/, SharedComponents/` | `Features/ → Core/, Infrastructure/, SharedComponents/` | `Core/ → Infrastructure/` | `SharedComponents/ → Infrastructure/` | Never `Core/ → Features/`, `Features/X → Features/Y`, `SharedComponents/ → Core|Features|App`

**Key config files:** `Package.swift` (SPM manifest), `.mise.toml` (build tasks), `.swift-format`, `.swiftlint.yml`

### Component → Slice Map

Where each key component lives — use this to decide where new files go. Apply the 4 tests from [directory_structure.md](docs/architecture/directory_structure.md): (1) Import test (2) Deletion test (3) Change driver (4) Multiplicity.

| Component | Slice | Role |
|-----------|-------|------|
| `AppDelegate` | `App/Boot/` | App lifecycle, restore, boot sequence |
| `PaneCoordinator` | `App/Coordination/` | Cross-store sequencing, action dispatch |
| `PaneCoordinator+ActionExecution` | `App/Coordination/` | Action command execution flow |
| `PaneCoordinator+FilesystemSource` | `App/Coordination/` | Filesystem root sync for pane runtimes |
| `PaneCoordinator+RuntimeDispatch` | `App/Coordination/` | Runtime command dispatch to session runtimes |
| `PaneCoordinator+TerminalPlaceholders` | `App/Coordination/` | Terminal placeholder creation and management |
| `PaneCoordinator+Undo` | `App/Coordination/` | Pane close undo support |
| `PaneCoordinator+ViewLifecycle` | `App/Coordination/` | NSView lifecycle orchestration for panes |
| `WorkspaceCacheCoordinator` | `App/` | Event bus consumer, updates stores |
| `WorkspaceMetadataAtom` | `Core/State/MainActor/Atoms/` | Workspace identity plus persisted window/sidebar metadata |
| `WorkspaceRepositoryTopologyAtom` | `Core/State/MainActor/Atoms/` | Repos, worktrees, watched paths, availability |
| `WorkspacePaneAtom` | `Core/State/MainActor/Atoms/` | Pane registry, pane metadata/content/residency, drawers |
| `WorkspaceTabLayoutAtom` | `Core/State/MainActor/Atoms/` | Tabs, arrangements, active selection, zoom/minimize |
| `WorkspaceMutationCoordinator` | `Core/State/MainActor/Atoms/` | Cross-atom workspace sequencing for pane + tab layout mutations |
| `RepoCacheAtom` | `Core/State/MainActor/Atoms/` | Derived enrichment (branches, git status, PR counts) |
| `WorkspaceStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for the workspace-domain atoms |
| `RepoCacheStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for `RepoCacheAtom` |
| `UIStateStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for `UIStateAtom` |
| `SessionRuntime` | `Core/RuntimeEventSystem/Runtime/` | Session backends, health checks, zmx |
| `SurfaceManager` | `Features/Terminal/` | Ghostty surface lifecycle, health, undo |
| `WorkspaceCommandResolver` | `Core/Actions/` | Resolves AppCommand into PaneActionCommand, builds ActionStateSnapshot |
| `WorkspaceCommandValidator` | `Core/Actions/` | Validates PaneActionCommand against ActionStateSnapshot |
| `BridgePaneController` | `Features/Bridge/` | WKWebView lifecycle for React panes |
| `RPCRouter` | `Features/Bridge/Transport/` | JSON-RPC dispatch for bridge messages |
| `CommandBarState` | `Features/CommandBar/` | Command palette state machine |

---

## Swift Concurrency

Target: Swift 6.2 / macOS 26. `@MainActor` for all stores, coordinators, and UI mutations.

1. **Isolation first** — `@MainActor` for UI/stores, `actor` for boundary work
2. **`@concurrent nonisolated` for blocking I/O** — In Swift 6.2 (SE-0461), plain `nonisolated async` inherits the caller's actor executor. Without `@concurrent`, blocking I/O called from inside an actor blocks that actor's serial executor. `@concurrent` forces escape to the global concurrent executor. **This is a correctness requirement in 6.2, not a style choice.**
3. **Structured concurrency** preferred; `Task.detached` only when isolation inheritance must be broken
4. **C callback bridging** — capture stable IDs synchronously, never defer pointer dereference across async hops
5. **AsyncStream standard** — `AsyncStream.makeStream(of:)`, explicit buffering policy, always cancel on shutdown

See [EventBus Design — Swift 6.2 concurrency rules](docs/architecture/pane_runtime_eventbus_design.md#swift-62-concurrency-rules-se-0461) for the full gotchas table and threading model.

---

## Running Swift Commands — Detail

**Always use `mise run` for build and test.** Mise tasks handle the WebKit serialized test split, benchmark mode, and build path isolation.

**For filtered test runs:** prefer mise (it allocates a slot for you):
```bash
mise run test -- --filter "CommandBarState"
```
If you must invoke `swift test` directly, source the slot helper first so you don't collide with another agent's build dir:
```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarState"
```

| Env Var | Default | Purpose |
|---------|---------|---------|
| `SWIFT_BUILD_DIR` | auto-allocated `.build-agent-{1..4}` via `scripts/swift-build-slot.sh` | Helper claims the first slot whose `.slot-claim` dir doesn't exist (atomic `mkdir`). Pin to a specific slot to override (rare). |
| `SWIFT_TEST_PARALLEL` | `1` (enabled) | Set to `0` to disable parallel workers |
| `SWIFT_TEST_WORKERS` | `hw.ncpu / 2` (max 4) | Parallel test worker count |

**Bounded 4-slot pool.** Every swift-running mise task sources `scripts/swift-build-slot.sh`. The helper iterates `.build-agent-{1..4}` and uses an atomic `mkdir <dir>/.slot-claim` to claim a slot; an EXIT trap on the calling shell removes the claim on normal exit. SwiftPM's own kernel-level flock handles serialization within a slot. Slots are reused by the next agent — disk usage is bounded by 4 × build size. Main agents and subagents share the pool; the helper handles allocation.

**Concurrent agents land on different slots.** Atomic `mkdir` guarantees that 4 agents racing simultaneously each claim a distinct slot. Within one shell, sourcing the helper once gives you one slot held for the lifetime of that shell — repeated `mise run` invocations in the same shell reuse the same slot (warm cache).

**If all 4 slots are busy** the helper aborts with `swift-build-slot: all 4 ... slots are busy`. This is rare; it means 4 other agents are actively building.

**SIGKILL leaks.** If a calling shell is `kill -9`'d, the EXIT trap doesn't fire and `.slot-claim` is left behind. Run `mise run clean-agent-builds` to reap stale claims (it removes `.slot-claim` from any slot whose `lsof +D` shows no open file descriptors, so it's safe to run while other agents are working).

**Timeouts are mandatory.** `60000` (60s) for test, `30000` (30s) for build. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention.

**Lock recovery:** If "Another instance of SwiftPM is already running..." — kill it (`pkill -f "swift-build"`) and retry.

---

## Linear Work Organization

Architecture documents in `docs/architecture/` are the source of truth for design. Linear tickets track progress. Docs answer "how does it work and why." Tickets answer "what's done and what's next."

- **Two levels only:** milestones and tasks. No sub-tasks — checklists in the description.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer" is a checklist item.
- **Dependencies are first-class.** `blockedBy`/`blocks` relations in Linear.
