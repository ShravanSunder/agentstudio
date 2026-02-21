# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Structure

See [Directory Structure](docs/architecture/directory_structure.md) for the full module boundary spec, Core vs Features decision process, and component placement rationale.

```
agent-studio/
├── Sources/AgentStudio/
│   ├── App/                          # Composition root — wires everything, imports all
│   │   ├── AppDelegate.swift
│   │   ├── MainWindowController.swift
│   │   ├── MainSplitViewController.swift
│   │   ├── Panes/                    # Pane tab management and NSView registry
│   │   │   ├── PaneTabViewController.swift
│   │   │   └── ViewRegistry.swift
│   │   └── PaneCoordinator.swift         # Cross-feature sequencing and orchestration
│   ├── Core/                         # Shared domain — models, stores, pane system
│   │   ├── Models/                   # Layout, Tab, Pane, PaneView, SessionStatus
│   │   ├── Stores/                   # WorkspaceStore, SessionRuntime, WorkspacePersistor
│   │   ├── Actions/                  # PaneAction, ActionResolver, ActionValidator
│   │   ├── Views/                    # Tab bar, splits, drawer, arrangement
│   │   │   ├── Splits/              # SplitTree, SplitView, TerminalPaneLeaf
│   │   │   └── Drawer/             # DrawerLayout, DrawerPanel, DrawerIconBar
│   │   └── NotificationNames.swift
│   ├── Features/
│   │   ├── Terminal/                 # Everything Ghostty-specific
│   │   │   ├── Ghostty/              # C API bridge, SurfaceManager, SurfaceTypes
│   │   │   └── Views/               # AgentStudioTerminalView, SurfaceErrorOverlay
│   │   ├── Bridge/                   # React/WebView pane system
│   │   │   ├── Push/               # Push pipeline, EntitySlice, PushPlan
│   │   │   └── Views/              # BridgePaneView, BridgePaneContentView
│   │   ├── Webview/                  # Browser pane (navigation, history, dialog)
│   │   │   └── Views/              # WebviewPaneView, WebviewNavigationBar
│   │   ├── CommandBar/               # ⌘P command palette
│   │   │   └── Views/              # CommandBarView, search field, results
│   │   └── Sidebar/                  # Sidebar filter (future: repo list, worktree tree)
│   └── Infrastructure/               # Domain-agnostic utilities
│       ├── StateMachine/            # Generic state machine
│       └── Diagnostics/             # RestoreTrace
├── Frameworks/                       # Generated: GhosttyKit.xcframework (not in git)
├── vendor/ghostty/                   # Git submodule: Ghostty source
├── scripts/                          # Icon generation
├── docs/                             # Detailed documentation
└── tmp/                              # Temporary docs and status files
```

**Import rule:** `App/ → Core/, Features/, Infrastructure/` | `Features/ → Core/, Infrastructure/` | `Core/ → Infrastructure/` | Never `Core/ → Features/`

### Slice Vocabulary

- **Core slice**: shared, feature-agnostic domain/data logic.
- **Vertical slice**: user-flow orchestration across layers (controllers, coordinators, feature entry points).

If a file imports from multiple features, it is usually a vertical slice and belongs in `App/` unless it can be decomposed into smaller feature-specific coordinators.

### Component → Slice Map

Where each key component lives and why — use this to decide where new files go.

| Component | Slice | Role | Change Driver |
|-----------|-------|------|---------------|
| `AppDelegate` | `App/` | App lifecycle, restore, zmx cleanup | App lifecycle |
| `MainSplitViewController` | `App/` | Top-level sidebar/content split | App layout |
| `MainWindowController` | `App/` | Window creation, toolbar, state restore | Window management |
| `PaneCoordinator` | `App/` | Dispatches PaneActions to stores and manages model↔view↔surface orchestration | Cross-store sequencing |
| `WorkspaceStore` | `Core/Stores/` | Tabs, layouts, views, pane metadata | Workspace structure |
| `SessionRuntime` | `Core/Stores/` | Session status, health checks, zmx backend | Session backends |
| `WorkspacePersistor` | `Core/Stores/` | Disk persistence for workspace state | Persistence format |
| `DynamicViewProjector` | `Core/Stores/` | Projects dynamic views into workspace | View projection |
| `PaneTabViewController` | `App/` | NSTabView container for any pane type | Tab management |
| `ViewRegistry` | `App/` | PaneId → NSView mapping (type-agnostic) | Pane registration |
| `ActionResolver` | `Core/Actions/` | Resolves PaneAction to concrete mutations | Action resolution |
| `Layout`, `Tab`, `Pane` | `Core/Models/` | Core domain models | Domain rules |
| `SplitTree`, `SplitView` | `Core/Views/Splits/` | Split pane rendering | Split layout |
| `DrawerLayout`, `DrawerPanel` | `Core/Views/Drawer/` | Drawer overlay system | Drawer UX |
| `SurfaceManager` | `Features/Terminal/` | Ghostty surface lifecycle, health, undo | Terminal behavior |
| `GhosttySurfaceView` | `Features/Terminal/` | NSView wrapping Ghostty surface | Terminal rendering |
| `BridgePaneController` | `Features/Bridge/` | WKWebView lifecycle for React panes | Bridge integration |
| `RPCRouter` | `Features/Bridge/` | JSON-RPC dispatch for bridge messages | RPC protocol |
| `PushTransport` | `Features/Bridge/Push/` | State push pipeline to React | Push protocol |
| `WebviewPaneController` | `Features/Webview/` | Browser pane lifecycle (independent of Bridge) | Browser UX |
| `CommandBarState` | `Features/CommandBar/` | Command palette state machine | Command palette |
| `SidebarFilter` | `Features/Sidebar/` | Sidebar filtering logic | Sidebar behavior |
| `ProcessExecutor` | `Infrastructure/` | CLI execution protocol | Utility |
| `StateMachine` | `Infrastructure/` | Generic state machine + effects | Utility |

**Decision process for new files:** Apply the 4 tests from [directory_structure.md](docs/architecture/directory_structure.md): (1) Import test — what does it import? (2) Deletion test — could you delete a feature and it still compiles? (3) Change driver — what causes it to change? (4) Multiplicity — how many features use it?

## Key Files
- `Package.swift` - SPM manifest, links GhosttyKit as binary target
- `.mise.toml` - Tool versions (zig) and build task definitions
- `.swift-format` - swift-format configuration (4-space indent, 120-char lines)
- `.swiftlint.yml` - SwiftLint configuration (strict mode, Swift 6 rules)
- `.gitignore` - Excludes build artifacts (.zig-cache, macos/build, *.xcframework)

## Build Flow

Build orchestration uses [mise](https://mise.jdx.dev/). Install with `brew install mise`.

```bash
mise install                  # Install pinned tool versions (zig 0.15.2)
mise run build                # Full debug build (ghostty + zmx + dev resources + swift)
mise run build-release        # Full release build
mise run test                 # Run tests
mise run create-app-bundle    # Create signed AgentStudio.app
mise run clean                # Remove all build artifacts
```

Individual steps:
- `mise run build-ghostty` — Build GhosttyKit.xcframework only
- `mise run build-zmx` — Build zmx binary only
- `mise run setup-dev-resources` — Copy shell-integration + terminfo for SPM
- `mise run copy-xcframework` — Copy xcframework to Frameworks/

### Formatting & Linting

```bash
mise run format               # Auto-format all Swift sources with swift-format
mise run lint                  # Lint all Swift sources (swift-format + swiftlint)
```

Requires `brew install swift-format swiftlint`. A PostToolUse hook (`.claude/hooks/check.sh`) runs swift-format and swiftlint automatically after every Edit/Write on `.swift` files.

### ⚠️ Running Swift Commands

SwiftPM's interactive progress output (carriage returns, ANSI escapes) breaks in agent bash contexts. Always redirect to a file and check the exit code.

```bash
SWIFT_BUILD_DIR=".build-agent-0" SWIFT_TEST_TIMEOUT_SECONDS=600 scripts/test-agent-timeout.sh > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
SWIFT_BUILD_DIR=".build-agent-0" SWIFT_TEST_TIMEOUT_SECONDS=600 scripts/test-agent-timeout.sh "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**No parallel Swift commands. No background Swift commands.** SwiftPM holds an exclusive lock on `.build/`. Two concurrent swift processes — even `swift test --filter A` and `swift test --filter B`, or a foreground + background task — will deadlock waiting for the lock (up to 256s then fail). This means:
- NEVER use `run_in_background: true` for any `swift build`, `swift test`, or `swift package` command
- NEVER issue two Bash tool calls that both invoke swift in the same message (parallel tool calls)
- NEVER launch a swift subagent while a swift command is running in the main session
- Run them strictly one at a time, sequentially. If you need multiple test filters, just run the full suite once.

**Test/build contention across agents.** Use a unique `.build-agent-<suffix>` folder per agent session so SwiftPM lock files do not collide across concurrent sessions.

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" SWIFT_TEST_TIMEOUT_SECONDS=600 \
scripts/test-agent-timeout.sh "ZmxE2ETests"
swift build --build-path "$SWIFT_BUILD_DIR"
SWIFT_BUILD_DIR="$SWIFT_BUILD_DIR" SWIFT_TEST_TIMEOUT_SECONDS=600 \
scripts/test-agent-timeout.sh
```

Keep this `BUILD_DIR` constant for your entire session to avoid mixing artifacts.

If you want a single command that enforces both an isolated build path and a hard timeout, use the agent helper:

```bash
# default timeout: 600s, default build dir: .build-agent-$RANDOM
SWIFT_TEST_TIMEOUT_SECONDS=600 scripts/test-agent-timeout.sh

# filter a single test suite (also uses random .build-agent-* path)
SWIFT_TEST_TIMEOUT_SECONDS=600 scripts/test-agent-timeout.sh "CommandBarState"
```

Run via `mise` (defaults to `.build-agent-0`, with the same env override semantics):

```bash
SWIFT_TEST_TIMEOUT_SECONDS=600 SWIFT_BUILD_DIR=".build-agent-0" mise run test
mise run test-agent-timeout
```

**Lock contention recovery.** If you see "Another instance of SwiftPM is already running using '.build', waiting..." — do NOT launch more swift commands. Kill the stuck process (`pkill -f "swift-build"`) and retry.

**Timeouts are mandatory.** Always set the Bash tool's `timeout` parameter: `60000` (60s) for `swift test`, `30000` (30s) for `swift build`. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention or a hung process. Without an explicit timeout the Bash tool uses its 2-minute default, which silently wastes time on a stuck process the user then has to manually kill.


### Launching the App

**Always launch from the build directory directly:**
```bash
.build/release/AgentStudio
```

## Development Workflow (CRITICAL)

### ⚠️ UX-First Approach (MANDATORY)

**STOP. Before implementing ANY UI/UX change, you MUST:**

1. **Talk to the user FIRST** - Discuss the UX problem, understand the user's intent, and align on the desired experience
2. **Do NOT assume** you understand what the user wants visually or experientially
3. **Ask clarifying questions** about look, feel, interaction patterns, and edge cases

This is non-negotiable. Swift compile times are long (minutes, not seconds). A wrong assumption about UX wastes significant time. Get alignment BEFORE writing code.

### Why This Matters

- **Swift compile times are slow** - Each iteration costs real time
- **Swift/AppKit patterns are nuanced** - Solutions require research, not guessing
- **UX is subjective** - Only the user knows what they want

### Research Before Implementation

For UX design and fixes, **always** use MCP research tools BEFORE coding:

1. **Perplexity tools** - Look up macOS UX patterns, AppKit/SwiftUI solutions, design conventions
2. **DeepWiki** - Query `ghostty-org/ghostty` and `swiftlang/swift` for implementation patterns

Never guess at UX solutions. Research first, discuss with user, then implement.

### Development Loop

1. **Understand** - Talk to user, clarify UX requirements
2. **Research** - Use Perplexity/DeepWiki to find grounded solutions
3. **Propose** - Share approach with user before coding
4. **Implement** - Write code only after alignment
5. **Verify** - Use Peekaboo to visually confirm

## Linear Work Organization

### The paradigm: docs are truth, tickets are tracking

Architecture documents in `docs/architecture/` are the source of truth for design, plans, and implementation details. Linear tickets are project management — they track progress, dependencies, and what's blocked. Understanding why this split exists matters:

**Agents lose context between sessions.** A ticket description is ephemeral — it lives in an API, not the repo. An architecture doc is durable — it's versioned, searchable, and survives context loss. When a new session starts, the agent reads docs from the repo and has full context. If the spec lived only in tickets, continuity would depend on fetching and re-reading every ticket, which is fragile and slow.

**Two sources of truth always drift.** If a ticket duplicates what's in a design doc, one will become stale. The doc gets updated during implementation; the ticket doesn't. Now the ticket is lying. Instead, tickets link to the doc sections they cover. One truth, one place.

**Tickets answer "what's done and what's next."** Docs answer "how does it work and why." These are different questions with different update cadences. Mixing them creates noise in both directions.

### What a ticket looks like

A ticket has: a title, a rough scope description, links to the architecture doc sections it covers, `blockedBy`/`blocks` dependencies, and acceptance criteria. The doc is the plan; the ticket tracks whether the plan is done. Checklists in the ticket description track implementation steps within a single deliverable.

### Structural principles

- **Two levels only: milestones and tasks.** Milestones are conceptual phases. Tasks are deliverables within them. No sub-tasks — checklists in the description carry that role.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer", "tab generator", "navigation wiring" are implementation details that belong in the description.
- **If two tasks always ship together, they're one task.** The test: can each task be delivered and verified independently? If not, merge them.
- **Dependencies are first-class.** Cross-project and cross-milestone dependencies use Linear's `blockedBy`/`blocks` relations. This is how agents know what's unblocked and what to work on next.

## State Management Mental Model

Agent Studio's state architecture draws from two JavaScript patterns adapted for Swift's type system and concurrency model. These are the governing principles for **all new code** and the target for incremental refactoring of existing code.

> **Implementation status:** These patterns are the TARGET architecture in this worktree: `PaneCoordinator` is the canonical cross-feature coordinator (consolidated action dispatch + surface orchestration), domain state lives in `@Observable` stores, and ownership is surfaced with `private(set)` where state is mutable. Existing `ObservableObject`/`@Published` and Combine/NotificationCenter usage is migration debt to be removed as files are touched.

### Valtio-style: `private(set)` for Unidirectional Flow

Every `@Observable` store exposes state as `private(set)` — the store alone decides how state changes. External code reads freely but mutates only through store methods. This gives unidirectional data flow without the ceremony of Redux/TCA action enums and reducers.

```swift
@Observable @MainActor
final class WorkspaceStore {
    private(set) var tabs: [Tab] = []
    private(set) var activePaneId: UUID?

    // Only the store mutates its own state
    func closeTab(_ id: UUID) -> TabSnapshot? { ... }
    func insertTab(_ tab: Tab, at index: Int) { ... }
}
```

### Jotai-style: Independent Atomic Stores

Each domain has its own `@Observable` store. No god-store. Stores are independent atoms — each owns one domain, has one reason to change, and can be tested in isolation.

| Store | Domain | Owns |
|-------|--------|------|
| `WorkspaceStore` | Workspace structure | tabs, layouts, views, pane metadata |
| `SurfaceManager` | Ghostty surfaces | surface lifecycle, health, undo stack |
| `SessionRuntime` | Session backends | runtime status, health checks, zmx |

Stores never call each other's mutation methods directly. Cross-store coordination flows through a coordinator.

### Coordinator Pattern: Sequences, Doesn't Own

A coordinator sequences operations across multiple stores for a single user action. It owns **no state** and contains **no domain logic** — it's pure orchestration.

```swift
@MainActor
final class PaneCoordinator {
    let workspace: WorkspaceStore
    let surfaces: SurfaceManager
    let runtime: SessionRuntime

    func closeTab(_ tabId: UUID) {
        // 1. workspace removes the tab (domain logic lives in the store)
        guard let snapshot = workspace.removeTab(tabId) else { return }
        // 2. surfaces move to undo (domain logic lives in the store)
        surfaces.moveSurfacesToUndo(snapshot.paneIds, ttl: .seconds(300))
        // 3. runtime marks sessions pending undo
        runtime.markSessionsPendingUndo(snapshot.paneIds)
        // 4. coordinator manages its own undo stack (sequencing state)
        undoStack.append(.tab(snapshot))
    }
}
```

**The test:** If a coordinator method contains an `if` that decides *what* to do with domain data, that logic belongs in a store. The coordinator only decides *which stores to call and in what order*.

### Bridge-per-Surface Pattern

Each Ghostty surface gets a typed bridge object that replaces NotificationCenter dispatch for C API callbacks. The bridge owns the surface's observable state and provides a type-safe interface.

```swift
protocol PaneBridge: AnyObject, Sendable {
    associatedtype PaneState: Observable
    var state: PaneState { get }
    func activate()
    func deactivate()
}
```

This extends to future pane types: `GhosttyBridge`, `WebViewBridge`, `CodeViewerBridge` — each conforming to `PaneBridge` with its own state type.

### Event Transport: AsyncStream

All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. No new Combine subscriptions. No new NotificationCenter observers. Existing Combine/NotificationCenter usage is migrated incrementally.

```swift
@MainActor
final class PaneEventBus {
    private let continuation: AsyncStream<PaneLifecycleEvent>.Continuation
    let events: AsyncStream<PaneLifecycleEvent>

    nonisolated func emit(_ event: PaneLifecycleEvent) {
        continuation.yield(event)
    }
}
```

**Why not Combine:** Apple's Xcode 26 guidance explicitly steers away from Combine. AsyncStream integrates naturally with Swift concurrency, has no publisher/subscriber ceremony, and composes via `swift-async-algorithms` (merge, debounce, throttle).

### Swift 6 Concurrency from C Callbacks

Ghostty C API callbacks arrive on arbitrary threads. The pattern is static `@Sendable` trampolines that hop to MainActor:

```swift
nonisolated static func handleAction(
    _ surface: ghostty_surface_t,
    _ action: ghostty_action_s
) {
    MainActor.assumeIsolated {
        guard let bridge = SurfaceManager.shared
            .terminalBridge(for: surface) else { return }
        bridge.handleAction(action)
    }
}
```

**Never** use `DispatchQueue.main.async` from C callbacks — use `MainActor.assumeIsolated` for synchronous hops or `Task { @MainActor in }` for async work.

### Testable Time: Injectable Clock

All time-dependent logic accepts `any Clock<Duration>` as a constructor parameter instead of calling `Task.sleep` directly. This makes undo TTLs, health check intervals, and debounce timers testable without real delays.

```swift
@Observable @MainActor
final class SurfaceManager {
    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func scheduleUndoExpiration(for entry: UndoEntry) async {
        try? await clock.sleep(for: .seconds(300))
        expireIfStillPending(entry)
    }
}
```

### Summary: What We Don't Do

- **No god-store** — no single object that owns everything
- **No Combine** for new code — AsyncStream replaces publishers
- **No NotificationCenter** for new event plumbing — typed streams replace string-keyed notifications
- **No ObservableObject/@Published** — `@Observable` macro everywhere
- **No DispatchQueue.main.async** from C callbacks — MainActor primitives only

## Architectural Guidance
Agent Studio follows an **AppKit-main** architecture. See the
[Architecture Overview](docs/architecture/README.md) for the full
system design, data model, and document index. Target: macOS 26 only.

- **Architecture Overview**: [README](docs/architecture/README.md) — system overview, principles, document index
- **Component Architecture**: [Component Architecture](docs/architecture/component_architecture.md) — data model, services, data flow, persistence, invariants
- **Session Lifecycle**: [Session Lifecycle](docs/architecture/session_lifecycle.md) — creation, close, undo, restore, zmx backend
- **Surface Architecture**: [Surface Management](docs/architecture/ghostty_surface_architecture.md) — ownership, state machine, health, crash isolation
- **App Architecture**: [App Architecture](docs/architecture/appkit_swiftui_architecture.md) — AppKit+SwiftUI hybrid, controllers, events
- **Directory Structure**: [Directory Structure](docs/architecture/directory_structure.md) — module boundaries, Core vs Features decision process, import rule
- **Style Guide**: [macOS Design & Style](docs/guides/style_guide.md)

## Agent Resources
Use DeepWiki and official documentation to gather grounded context on core dependencies.

- **Guide**: [Agent Resources & Research](docs/guides/agent_resources.md)
- **Core Repos**: `ghostty-org/ghostty`, `swiftlang/swift`

## Visual Verification (Mandatory)
To ensure high product quality, agents **must** visually verify all UI/UX changes and bug fixes.

- **Requirement**: Use [Peekaboo](https://github.com/steipete/Peekaboo) to capture screenshots or snapshots of the running application.
- **Definition of Done**: A task is **NOT DONE** until the agent has visually inspected the work using Peekaboo to confirm it looks correct and the fix is verified in the actual UI.

### ⚠️ Testing Debug Builds vs Installed Apps

**NEVER target apps by name when testing debug builds.** An installed `/Applications/AgentStudio.app` may exist and Peekaboo will target the WRONG process.

**ALWAYS follow this procedure:**

1. **Kill ALL existing instances first:**
   ```bash
   pkill -9 -f "AgentStudio"
   ```

2. **Launch the debug build explicitly:**
   ```bash
   .build/debug/AgentStudio &
   ```

3. **Get the PID and use PID-targeting:**
   ```bash
   PID=$(pgrep -f ".build/debug/AgentStudio")
   peekaboo app switch --to "PID:$PID"
   peekaboo see --app "PID:$PID" --json
   ```

4. **Verify you're testing the right binary:**
   ```bash
   ps aux | grep AgentStudio  # Should show .build/debug path
   ```

**Why this matters:** Using `--app "AgentStudio"` may target an installed app instead of your debug build, causing you to verify the WRONG code.
