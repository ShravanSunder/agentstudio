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

## Architectural Guidance
Agent Studio follows an **AppKit-main** architecture. See the
[Architecture Overview](docs/architecture/README.md) for the full
system design, data model, and document index. Target: macOS 26 only.

- **Architecture Overview**: [README](docs/architecture/README.md) — system overview, principles, document index
- **Component Architecture**: [Component Architecture](docs/architecture/component_architecture.md) — data model, services, data flow, persistence, invariants
- **Session Lifecycle**: [Session Lifecycle](docs/architecture/session_lifecycle.md) — creation, close, undo, restore, tmux
- **Surface Architecture**: [Surface Management](docs/architecture/ghostty_surface_architecture.md) — ownership, state machine, health, crash isolation
- **App Architecture**: [App Architecture](docs/architecture/app_architecture.md) — AppKit+SwiftUI hybrid, controllers, events
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
