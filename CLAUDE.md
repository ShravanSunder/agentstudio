# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Structure
```
agent-studio/
├── Sources/AgentStudio/      # Swift source
│   ├── App/                  # Window/tab controllers
│   ├── Ghostty/              # Ghostty C API wrapper
│   ├── Models/               # TerminalSession, Layout, Tab, ViewDefinition
│   └── Services/             # WorkspaceStore, SessionRuntime, WorktrunkService
├── Frameworks/               # Generated: GhosttyKit.xcframework (not in git)
├── vendor/ghostty/           # Git submodule: Ghostty source
├── scripts/                  # Build automation
├── docs/                     # Detailed documentation
└── tmp/                      # Temporary docs and status files
```

## Key Files
- `Package.swift` - SPM manifest, links GhosttyKit as binary target
- `scripts/build-ghostty.sh` - Builds Ghostty → generates xcframework
- `.gitignore` - Excludes build artifacts (.zig-cache, macos/build, *.xcframework)

## Build Flow
1. `./scripts/build-ghostty.sh` - Runs `zig build -Demit-xcframework=true` in vendor/ghostty
2. Copies `macos/GhosttyKit.xcframework` → `Frameworks/`
3. `swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL"` - Links against xcframework

### ⚠️ Running Swift Commands (CRITICAL)

**NEVER pipe `swift build` or `swift test` output through grep, tail, head, or any other command.** These commands use interactive output (progress bars, carriage returns) that breaks when piped, causing the process to hang indefinitely.

**ALWAYS redirect output to a file and check the exit code.** This avoids capturing 100KB+ of interactive output in the tool response, which causes massive slowdowns and round-trip overhead.

```bash
# CORRECT — dump to file, check exit code
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"

# Filtered tests
swift test --filter "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"

# WRONG — captures 100KB+ of interactive output, extremely slow
swift test
swift build
swift test 2>&1 | tail -5
swift test 2>&1 | grep "passed"
```

**Timeouts:** Use a 50-second timeout for `swift test` and `swift build` commands. Tests complete in ~15 seconds; builds in ~5 seconds. Anything longer means something is stuck.


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

Solo project. Organizational overhead that doesn't directly serve building is waste.

- **Two levels only: milestones and tasks.** Milestones are conceptual phases. Tasks are deliverables within them. Never create sub-tasks — checklists in the description carry that role.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer", "tab generator", "navigation wiring" are implementation details that belong in the description.
- **If two tasks always ship together, they're one task.** The test: can each task be delivered and verified independently? If not, merge them.
- **Depth belongs in the description, not in ticket count.** A rich description with acceptance criteria, design notes, and checklists is better than splitting scope across multiple shallow tickets.

## State Management Mental Model

Agent Studio's state architecture draws from two JavaScript patterns adapted for Swift's type system and concurrency model. These are the governing principles for **all new code** and the target for incremental refactoring of existing code.

> **Implementation status:** These patterns are the TARGET architecture being implemented via LUNA-325 (bridge + surface state + runtime refactor), LUNA-326 (native scrollbar), and LUNA-327 (state ownership + @Observable migration + coordinator). The current codebase still uses `ActionExecutor` + `TerminalViewCoordinator` (two separate classes) which will be refactored into `PaneCoordinator`. Existing `ObservableObject`/`@Published` will migrate to `@Observable`/`private(set)`. Existing Combine/NotificationCenter will migrate to AsyncStream. **For new code, follow these patterns. For existing code, refactor incrementally when touching those files.**

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
