# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Structure
```
agent-studio/
├── Sources/AgentStudio/      # Swift source
│   ├── App/                  # Window/tab controllers
│   ├── Ghostty/              # Ghostty C API wrapper
│   ├── Models/               # AppState, Project, Worktree
│   └── Services/             # SessionManager, WorktrunkService
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
3. `swift build` - Links against xcframework

## Architectural Guidance
Agent Studio follows an **AppKit-main** architecture, hosting SwiftUI views where declarative UI is most effective. This provides direct control over the macOS lifecycle and key handling while leveraging SwiftUI for complex layouts.

- **Deep Dive**: [AppKit + SwiftUI Hybrid UI](docs/architecture/app_architecture.md)
- **Style Guide**: [macOS Design & Style](docs/guides/style_guide.md)

## Agent Resources
Use DeepWiki and official documentation to gather grounded context on core dependencies.

- **Guide**: [Agent Resources & Research](docs/guides/agent_resources.md)
- **Core Repos**: `ghostty-org/ghostty`, `swiftlang/swift`

## Visual Verification (Mandatory)
To ensure high product quality, agents **must** visually verify all UI/UX changes and bug fixes.

- **Requirement**: Use [Peekaboo](https://github.com/steipete/Peekaboo) to capture screenshots or snapshots of the running application.
- **Definition of Done**: A task is **NOT DONE** until the agent has visually inspected the work using Peekaboo to confirm it looks correct and the fix is verified in the actual UI.
