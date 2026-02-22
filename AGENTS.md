# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Structure

Agent Studio uses a hybrid directory layout under `Sources/AgentStudio/`. Infrastructure stays layer-based, user-facing capabilities live in feature directories.

| Layer | Path | Role |
|-------|------|------|
| **Composition root** | `App/` | Wires everything together. Controllers, PaneCoordinator, ViewRegistry. Imports all layers. |
| **Shared domain** | `Core/` | Feature-agnostic models, stores, actions. One reason to change per component. |
| **Pane runtime** | `Core/PaneRuntime/` | Contracts (protocols, events, envelopes, RuntimeCommand), registry, event reduction, replay. Shared by all pane types. |
| **Features** | `Features/X/` | Per-capability code: Terminal/ (Ghostty FFI + runtime), Bridge/ (React/WebView), Webview/ (browser pane), CommandBar/, Sidebar/. |
| **Utilities** | `Infrastructure/` | Domain-agnostic: state machine, extensions, process executor. Imports nothing internal. |

**Import rule:** `App/ → Core/, Features/, Infrastructure/` | `Features/ → Core/, Infrastructure/` | `Core/ → Infrastructure/` | Never `Core/ → Features/`, never `Features/X → Features/Y`

For file placement decisions (4-test framework, component rationale, per-kind event enum placement, slice vocabulary), read [Directory Structure](docs/architecture/directory_structure.md).

### Component → Slice Map

Where each key component lives and why — use this to decide where new files go.

| Component | Slice | Role | Change Driver |
|-----------|-------|------|---------------|
| `AppDelegate` | `App/` | App lifecycle, restore, zmx cleanup | App lifecycle |
| `MainSplitViewController` | `App/` | Top-level sidebar/content split | App layout |
| `MainWindowController` | `App/` | Window creation, toolbar, state restore | Window management |
| `PaneCoordinator` | `App/` | Dispatches PaneActions + RuntimeCommands, owns RuntimeRegistry, consumes event streams | Cross-store sequencing |
| `WorkspaceStore` | `Core/Stores/` | Tabs, layouts, views, pane metadata | Workspace structure |
| `SessionRuntime` | `Core/Stores/` | Session status, health checks, zmx backend | Session backends |
| `WorkspacePersistor` | `Core/Stores/` | Disk persistence for workspace state | Persistence format |
| `DynamicViewProjector` | `Core/Stores/` | Projects dynamic views into workspace | View projection |
| `PaneTabViewController` | `App/` | NSTabView container for any pane type | Tab management |
| `ViewRegistry` | `App/` | PaneId → NSView mapping (type-agnostic) | Pane registration |
| `ActionResolver` | `Core/Actions/` | Resolves workspace PaneAction to concrete mutations | Action resolution |
| `PaneRuntime` protocol | `Core/PaneRuntime/Contracts/` | Per-pane runtime contract (events, commands, lifecycle) | Pane system contract |
| `RuntimeRegistry` | `Core/PaneRuntime/Registry/` | paneId → runtime lookup | Pane system contract |
| `NotificationReducer` | `Core/PaneRuntime/Reduction/` | Priority-aware event delivery | Pane system contract |
| `EventReplayBuffer` | `Core/PaneRuntime/Replay/` | Bounded replay for late-joining consumers | Pane system contract |
| `RuntimeCommand` | `Core/PaneRuntime/Contracts/` | Commands to individual runtimes (distinct from workspace PaneAction) | Pane system contract |
| `GhosttyAdapter` | `Features/Terminal/Ghostty/` | Singleton FFI boundary, routes C callbacks to TerminalRuntime | Ghostty C API |
| `TerminalRuntime` | `Features/Terminal/Runtime/` | PaneRuntime conformance for terminals | Terminal behavior |
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
mise run test                 # Run tests (Swift 6 `Testing`)
mise run create-app-bundle    # Create signed AgentStudio.app
mise run clean                # Remove all build artifacts
```

Individual steps:
- `mise run build-ghostty` — Build GhosttyKit.xcframework only
- `mise run build-zmx` — Build zmx binary only
- `mise run setup-dev-resources` — Copy shell-integration + terminfo for SPM
- `mise run copy-xcframework` — Copy xcframework to Frameworks/

## Testing Standard

This worktree is SwiftPM-first and Swift 6 `Testing` only:

- Use `import Testing` with `@Suite`, `@Test`, and `#expect`.
- Do not adopt legacy XCTest-style APIs (`XCTestCase`, `XCTAssert*`, `setUp`/`tearDown`).
- Do not use legacy XCTest-style or Xcode UI test scaffolding.
- Prefer `mise run test` (Swift 6 `Testing`) and SwiftPM-native test execution.

### Formatting & Linting

```bash
mise run format               # Auto-format all Swift sources with swift-format
mise run lint                  # Lint all Swift sources (swift-format + swiftlint)
```

Requires `brew install swift-format swiftlint`. A PostToolUse hook (`.claude/hooks/check.sh`) runs swift-format and swiftlint automatically after every Edit/Write on `.swift` files.

### ⚠️ Running Swift Commands

SwiftPM's interactive progress output (carriage returns, ANSI escapes) breaks in agent bash contexts. Always redirect to a file and check the exit code.

```bash
swift test --build-path .build-agent-$RANDOM > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test --build-path .build-agent-$RANDOM --filter "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**No parallel Swift commands. No background Swift commands.** SwiftPM holds an exclusive lock on `.build/`. Two concurrent swift processes — even `swift test --filter A` and `swift test --filter B`, or a foreground + background task — will deadlock waiting for the lock (up to 256s then fail). This means:
- NEVER use `run_in_background: true` for any `swift build`, `swift test`, or `swift package` command
- NEVER issue two Bash tool calls that both invoke swift in the same message (parallel tool calls)
- NEVER launch a swift subagent while a swift command is running in the main session
- Run them strictly one at a time, sequentially. If you need multiple test filters, just run the full suite once.

**Test/build contention across agents.** Use a unique `.build-agent-<suffix>` folder per agent session so SwiftPM lock files do not collide across concurrent sessions.

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "ZmxE2ETests"
swift build --build-path "$SWIFT_BUILD_DIR"
swift test --build-path "$SWIFT_BUILD_DIR"
```

Keep this `BUILD_DIR` constant for your entire session to avoid mixing artifacts.

Run via `mise` (defaults to `.build-agent-$RANDOM`):

```bash
mise run test
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

## State Management Guard Rails

State patterns, code examples, and rationale live in [Component Architecture](docs/architecture/component_architecture.md). Read that doc before any state management work. These are the anti-patterns to avoid in all new code:

- **No god-store** — no single object that owns everything. Each `@Observable` store owns one domain.
- **No Combine** for new code — `AsyncStream` + `swift-async-algorithms` replaces publishers
- **No NotificationCenter** for new event plumbing — typed streams replace string-keyed notifications
- **No ObservableObject/@Published** — `@Observable` macro everywhere
- **No DispatchQueue.main.async** from C callbacks — `MainActor.assumeIsolated` or `Task { @MainActor in }`
- **No domain logic in coordinators** — coordinators sequence stores, stores own domain decisions

## Architecture Docs (read on demand)

Agent Studio follows an **AppKit-main** architecture. Target: macOS 26 only. These docs are the source of truth for design — read the relevant one before working in that domain.

| When you're... | Read |
|---|---|
| Deciding where a new file goes | [Directory Structure](docs/architecture/directory_structure.md) — 4-test framework, component placement, import rule |
| Understanding data model or store ownership | [Component Architecture](docs/architecture/component_architecture.md) — stores, state patterns, persistence, invariants |
| Working on pane runtime, events, commands | [Pane Runtime Architecture](docs/architecture/pane_runtime_architecture.md) — contracts 1-16, event taxonomy, priority system |
| Working on session create/close/undo/restore | [Session Lifecycle](docs/architecture/session_lifecycle.md) — lifecycle flows, zmx backend |
| Working on Ghostty surfaces | [Surface Architecture](docs/architecture/ghostty_surface_architecture.md) — ownership, state machine, health, crash isolation |
| Working on window/tab/drawer structure | [Window System Design](docs/architecture/window_system_design.md) — data model, dynamic views, arrangements |
| Working on AppKit/SwiftUI integration | [App Architecture](docs/architecture/appkit_swiftui_architecture.md) — hybrid shell, controllers, events |
| Checking visual/UX conventions | [Style Guide](docs/guides/style_guide.md) — macOS design conventions |
| Starting from the top | [Architecture Overview](docs/architecture/README.md) — system overview, principles, full document index |

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
