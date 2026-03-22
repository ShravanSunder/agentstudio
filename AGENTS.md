# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Build & Test

Build orchestration uses [mise](https://mise.jdx.dev/). Install with `brew install mise`.

```bash
mise run build                # Full debug build (ghostty + zmx + dev resources + swift)
mise run test                 # Run tests (Swift 6 `Testing`)
mise run format               # Auto-format all Swift sources
mise run lint                 # Lint (swift-format + swiftlint + boundary checks)
.build/debug/AgentStudio      # Launch debug build
```

First-time setup: `git submodule update --init --recursive && mise install && mise run build`. See [Agent Resources](docs/guides/agent_resources.md) for full bootstrap.

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

## Architecture at a Glance

AppKit-main architecture hosting SwiftUI views. Seven `@Observable` atomic stores with `private(set)` for unidirectional flow. Two coordinators for cross-store sequencing. An `EventBus<RuntimeEnvelope>` connects runtime actors to stores, and a separate app lifecycle monitor owns AppKit ingress.

| Store | Owns | File |
|-------|------|------|
| `WorkspaceStore` | repos, worktrees, tabs, panes, layouts | `workspace.state.json` |
| `WorkspaceRepoCache` | repo enrichment, branches, git status, PR counts | `workspace.cache.json` |
| `WorkspaceUIStore` | expanded groups, colors, filter | `workspace.ui.json` |
| `AppLifecycleStore` | application active/terminating state | in-memory |
| `WindowLifecycleStore` | key/focused window identity and registration | in-memory |
| `SurfaceManager` | Ghostty surface lifecycle, health, undo | — |
| `SessionRuntime` | runtime status, health checks, zmx | — |

**Worktree model is structure-only:** `id`, `repoId` (FK), `name`, `path`, `isMainWorktree`. No branch, no status. All enrichment lives in `WorkspaceRepoCache`, populated by the event bus.

**Event bus pattern:** Mutate the store directly → emit a fact on the bus → coordinator updates the other store. This is NOT CQRS — no command bus, no command handlers. `ApplicationLifecycleMonitor` is ingress-only and mutates lifecycle stores directly from AppKit callbacks. See [State Management Patterns](#state-management-patterns) below and [Event System Design](docs/architecture/workspace_data_architecture.md#event-system-design-what-it-is-and-isnt) for full detail.

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

Agents **must** visually verify all UI/UX changes using Peekaboo. **Never target apps by name** when testing debug builds — use PID targeting:

```bash
pkill -9 -f "AgentStudio"
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
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

Each store owns one domain with one reason to change. No god-store. Stores never call each other's mutation methods. Cross-store coordination flows through coordinators. See [Three Persistence Tiers](docs/architecture/workspace_data_architecture.md#three-persistence-tiers) for how stores map to persistence files.

**Store boundaries are architectural decisions — always ask the user before changing them:**
- **Adding a new store:** "Does this domain earn its own store? What's the one sentence job description? What's the single reason it changes?"
- **Adding properties to an existing store:** "Does this property belong here, or is it polluting this store's job? Could it belong in a different store or be derived?" A store that accumulates unrelated properties is becoming a god-store by accretion.
- **Adding new event types or coordinator responsibilities:** These expand the system's surface area. Discuss before implementing.

### 3. Coordinator Sequences, Doesn't Own

A coordinator sequences operations across stores for a user action. Owns no state, contains no domain logic. **The test:** if a coordinator method has an `if` that decides *what* to do with domain data, that logic belongs in a store. See [PaneCoordinator](docs/architecture/component_architecture.md#36-panecoordinator) for the cross-store pattern.

### 4. Event-Driven Enrichment — Bus → Coordinator → Stores

Runtime actors produce facts → `EventBus` → `WorkspaceCacheCoordinator` → updates stores.

```
FilesystemActor ──► .repoDiscovered ──┐
GitProjector    ──► .snapshotChanged ─┤──► EventBus ──► WorkspaceCacheCoordinator
ForgeActor      ──► .prCountsChanged ─┘        │               │
                                                │        ┌──────┴──────┐
                                                │        ▼             ▼
                                                │  WorkspaceStore  WorkspaceRepoCache
                                                │  (associations)  (enrichment)
                                                │
                                                └──► Sidebar observes both via @Observable
```

**This is NOT CQRS.** The event bus carries facts, not commands. Stores are mutated by their own methods. Typed command planes still exist, but they do **not** run through the bus:
- `PaneActionCommand` for workspace mutations (`CommandDispatcher` → `ActionResolver` → `ActionValidator` → `PaneCoordinator`)
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
| App-level notification that is not a command | `AppEventBus` | Notification fan-out only. Not a workspace command boundary. |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` | Owns AppKit ingress and writes `AppLifecycleStore` / `WindowLifecycleStore`. |
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
│   │   ├── AppDelegate.swift
│   │   ├── MainWindowController.swift
│   │   ├── MainSplitViewController.swift
│   │   ├── Panes/                    # Pane tab management and NSView registry
│   │   └── PaneCoordinator.swift     # Cross-feature sequencing and orchestration
│   ├── Core/                         # Shared domain — models, stores, pane system
│   │   ├── Models/                   # Layout, Tab, Pane, Repo, Worktree
│   │   ├── Stores/                   # WorkspaceStore, WorkspaceRepoCache, SessionRuntime
│   │   ├── Actions/                  # PaneActionCommand, ActionResolver, ActionValidator
│   │   └── Views/                    # Tab bar, splits, drawer, arrangement
│   ├── Features/
│   │   ├── Terminal/                 # Ghostty C API bridge, SurfaceManager, views
│   │   ├── Bridge/                   # React/WebView pane system (transport, runtime, state)
│   │   ├── Webview/                  # Browser pane (navigation, history)
│   │   ├── CommandBar/               # ⌘P command palette
│   │   └── Sidebar/                  # Sidebar repo/worktree list
│   └── Infrastructure/               # Domain-agnostic utilities
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
| `AppDelegate` | `App/` | App lifecycle, restore, boot sequence |
| `PaneCoordinator` | `App/` | Cross-store sequencing, action dispatch |
| `WorkspaceCacheCoordinator` | `App/` | Event bus consumer, updates stores |
| `WorkspaceStore` | `Core/Stores/` | Canonical associations (repos, worktrees, tabs, panes) |
| `WorkspaceRepoCache` | `Core/Stores/` | Derived enrichment (branches, git status, PR counts) |
| `SessionRuntime` | `Core/Stores/` | Session backends, health checks, zmx |
| `SurfaceManager` | `Features/Terminal/` | Ghostty surface lifecycle, health, undo |
| `ActionResolver` | `Core/Actions/` | Resolves PaneActionCommand to mutations |
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
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

| Env Var | Default | Purpose |
|---------|---------|---------|
| `SWIFT_BUILD_DIR` | `.build-agent-$RANDOM` | Build path isolation between agent sessions |
| `SWIFT_TEST_PARALLEL` | `1` (enabled) | Set to `0` to disable parallel workers |
| `SWIFT_TEST_WORKERS` | `hw.ncpu / 2` (max 4) | Parallel test worker count |

**No parallel Swift commands. No background Swift commands.** SwiftPM holds an exclusive lock on `.build/`. Two concurrent swift processes deadlock (up to 256s then fail).
- NEVER use `run_in_background: true` for swift build/test commands
- NEVER issue two parallel Bash tool calls that both invoke swift
- NEVER launch a swift subagent while a swift command is running
- Run strictly one at a time, sequentially

**Timeouts are mandatory.** `60000` (60s) for test, `30000` (30s) for build. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention.

**Lock recovery:** If "Another instance of SwiftPM is already running..." — kill it (`pkill -f "swift-build"`) and retry.

---

## Linear Work Organization

Architecture documents in `docs/architecture/` are the source of truth for design. Linear tickets track progress. Docs answer "how does it work and why." Tickets answer "what's done and what's next."

- **Two levels only:** milestones and tasks. No sub-tasks — checklists in the description.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer" is a checklist item.
- **Dependencies are first-class.** `blockedBy`/`blocks` relations in Linear.
