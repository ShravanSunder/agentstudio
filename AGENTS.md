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

### Folder Arcs

Use these broad ownership rules first, then consult [Directory Structure](docs/architecture/directory_structure.md) for exact placement:

- `App/`
  Composition root and host-specific assembly. App-owned shells, pane/window controllers, lifecycle wiring, and cross-slice orchestration live here.
- `Core/`
  Shared domain state and contracts. Models, atoms, persistence wrappers, validated action routing, runtime contracts, and shared split/drawer primitives live here.
- `SharedComponents/`
  Reusable UI building blocks that are not themselves product features and do not own host placement. Use this for reusable menu content, row rendering, and small UI-facing models.
- `Features/`
  User-facing capability slices such as Terminal, Bridge, CommandBar, Sidebar, and Webview. Features own capability-specific behavior that is broader than a reusable component.
- `Infrastructure/`
  Domain-agnostic utilities and external integrations. Organize these in subfolders by concern, such as `AtomLib/`, `Extensions/`, `Icons/`, `StateMachine/`, and integration-specific folders like `ExternalApps/`.

| Component | Owns | Location |
|-----------|------|----------|
| `AtomRegistry` | composition root for shared main-actor atoms and derived helpers | `Infrastructure/AtomLib/AtomRegistry.swift` |
| `WorkspaceMetadataAtom` | workspace identity plus persisted window/sidebar metadata | `Core/State/MainActor/Atoms/WorkspaceMetadataAtom.swift` |
| `WorkspaceRepositoryTopologyAtom` | repos, worktrees, watched paths, availability | `Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift` |
| `WorkspacePaneAtom` | panes, pane metadata/content/residency, drawer state | `Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` |
| `WorkspaceTabLayoutAtom` | tabs, arrangements, active selection, zoom/minimize | `Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift` |
| `WorkspaceMutationCoordinator` | cross-atom workspace mutations spanning pane and tab layout state | `Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift` |
| `RepoCacheAtom` | repo enrichment, branches, git status, PR counts, recent targets | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `UIStateAtom` | expanded groups, colors, filter state | `Core/State/MainActor/Atoms/UIStateAtom.swift` |
| `WorkspaceFocusDerived` | shared app-wide focus reader for command visibility and status UI | `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` |
| `ManagementModeAtom` | management mode active/inactive state | `Core/State/MainActor/Atoms/ManagementModeAtom.swift` |
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
| [Directory Structure](docs/architecture/directory_structure.md) | Module boundaries, Core vs Features, import rule, component placement |
| [Style Guide](docs/guides/style_guide.md) | macOS design conventions and visual standards |

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

Agents **must** visually verify all UI/UX changes using Peekaboo. **Never target apps by name** when testing debug builds — use PID targeting. **Never `pkill` AgentStudio** — it kills the user's running app. Each agent session builds to its own `.build-agent-$PPID/` directory; launch from there:

```bash
BUILD_PATH=".build-agent-$PPID"
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

### 1. Unidirectional Flow — Valtio-style `private(set)`

Every `@Observable` store exposes state as `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers. See [WorkspaceStore](docs/architecture/component_architecture.md#32-workspacestore) for the canonical example.

### 2. Atomic Stores — Jotai-style Independent Atoms

Each atom owns one domain with one reason to change. No god-store. Cross-atom coordination flows through coordinators or persistence wrappers, not direct atom-to-atom mutation. Shared reads use `atom(\.foo)` or `AtomReader`; `@Atom(\.foo)` is optional convenience sugar when stored-property access is genuinely cleaner. See [Three Persistence Tiers](docs/architecture/workspace_data_architecture.md#three-persistence-tiers) for how atoms map to persistence files.

**Store boundaries are architectural decisions — always ask the user before changing them:**
- **Adding a new store:** "Does this domain earn its own store? What's the one sentence job description? What's the single reason it changes?"
- **Adding properties to an existing store:** "Does this property belong here, or is it polluting this store's job? Could it belong in a different store or be derived?" A store that accumulates unrelated properties is becoming a god-store by accretion.
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
│   ├── SharedComponents/             # Reusable UI building blocks
│   ├── Core/                         # Shared domain — models, stores, pane system
│   │   ├── Models/                   # Layout, Tab, Pane, Repo, Worktree
│   │   ├── State/
│   │   │   └── MainActor/
│   │   │       ├── Atoms/            # WorkspaceMetadataAtom, WorkspaceRepositoryTopologyAtom, WorkspacePaneAtom, WorkspaceTabLayoutAtom, WorkspaceMutationCoordinator, ...
│   │   │       └── Persistence/      # WorkspaceStore, RepoCacheStore, UIStateStore
│   │   ├── RuntimeEventSystem/       # Runtime actors, event bus, SessionRuntime, ZmxBackend
│   │   ├── Actions/                  # PaneActionCommand, WorkspaceCommandResolver, WorkspaceCommandValidator
│   │   └── Views/                    # Tab bar, splits, drawer, arrangement
│   ├── Features/
│   │   ├── Terminal/                 # Ghostty C API bridge, SurfaceManager, views
│   │   ├── Bridge/                   # React/WebView pane system (transport, runtime, state)
│   │   ├── Webview/                  # Browser pane (navigation, history)
│   │   ├── CommandBar/               # ⌘P command palette
│   │   └── Sidebar/                  # Sidebar repo/worktree list
│   └── Infrastructure/               # Utilities and integrations, organized by concern
├── docs/architecture/                # Authoritative design docs (see table above)
├── docs/plans/                       # Date-prefixed implementation plans
├── vendor/ghostty/                   # Git submodule: Ghostty source
└── vendor/zmx/                       # Git submodule: zmx session multiplexer
```

**Import rule:** `App/ → Core/, Features/, Infrastructure/` | `Features/ → Core/, Infrastructure/` | `Core/ → Infrastructure/` | Never `Core/ → Features/`

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

**For filtered test runs:**
```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

| Env Var | Default | Purpose |
|---------|---------|---------|
| `SWIFT_BUILD_DIR` | `.build-agent-$PPID` | Build path isolation — auto-derived from parent process ID, stable per agent session |
| `SWIFT_TEST_PARALLEL` | `1` (enabled) | Set to `0` to disable parallel workers |
| `SWIFT_TEST_WORKERS` | `hw.ncpu / 2` (max 4) | Parallel test worker count |

**Build dir: `$PPID` for main agent, `$$` (PID) for subagents.** Main agent and top-level bashes use the default `SWIFT_BUILD_DIR=.build-agent-$PPID`. Subagents and secondary bashes must override with `SWIFT_BUILD_DIR=".build-agent-$$" mise run …` so they don't share a lock with the parent.

**No parallel Swift commands in the same `SWIFT_BUILD_DIR`.** SwiftPM holds an exclusive lock per build dir — two concurrent swift processes on the same dir deadlock (up to 256s then fail). Different build dirs are fine.
- NEVER use `run_in_background: true` for swift build/test commands in the main agent's dir
- NEVER issue two parallel Bash calls that both invoke swift in the same dir
- Within one build dir, run swift commands strictly sequentially

**Timeouts are mandatory.** `60000` (60s) for test, `30000` (30s) for build. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention.

**Lock recovery:** If "Another instance of SwiftPM is already running..." — kill it (`pkill -f "swift-build"`) and retry.

---

## Linear Work Organization

Architecture documents in `docs/architecture/` are the source of truth for design. Linear tickets track progress. Docs answer "how does it work and why." Tickets answer "what's done and what's next."

- **Two levels only:** milestones and tasks. No sub-tasks — checklists in the description.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer" is a checklist item.
- **Dependencies are first-class.** `blockedBy`/`blocks` relations in Linear.
