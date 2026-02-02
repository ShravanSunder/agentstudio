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

## Vendor Directory
- `vendor/ghostty/` - Git submodule pointing to ghostty-org/ghostty
- Build artifacts inside are ignored by .gitignore
- Submodule tracks specific commit, not files

## Integration
- **GhosttySurfaceView** wraps Ghostty C API in AppKit view
- **SessionManager** manages terminal sessions/tabs
- **WorktrunkService** integrates git worktree workflows
