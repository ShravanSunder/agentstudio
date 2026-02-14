# Agent Studio

A macOS application that integrates the Ghostty terminal emulator, providing a modern terminal experience with advanced features.

## Install

```bash
brew tap ShravanSunder/agentstudio
brew install --cask agent-studio
```

This installs AgentStudio.app to `/Applications/`. Session persistence is handled by the bundled **zmx** binary (no external dependencies).

## Features

- Native macOS application built with AppKit
- Embedded Ghostty terminal emulator
- Project and worktree management
- Session management for terminal tabs
- Integration with worktrunk for git worktree workflows

## Prerequisites

- **macOS 14.0 or later**
- **Xcode 15.0 or later** (for Swift compilation)
- **[Zig compiler](https://ziglang.org/download/)** (for building Ghostty from source)

### Installing Zig

```bash
# Using Homebrew (recommended)
brew install zig

# Or download directly from https://ziglang.org/download/
```

Verify installation:
```bash
zig version
```

## Quick Start

1. **Clone the repository with submodules:**
```bash
git clone --recurse-submodules https://github.com/ShravanSunder/agentstudio.git
cd agent-studio
```

Or if you already cloned without submodules:
```bash
git submodule update --init --recursive
```

2. **Build Ghostty and generate the XCFramework:**
```bash
./scripts/build-ghostty.sh
```

This script will:
- Verify Zig is installed
- Build Ghostty from source in `vendor/ghostty/`
- Generate the `GhosttyKit.xcframework`
- Copy it to the `Frameworks/` directory

**Note:** This step takes 5-10 minutes on first build. Subsequent builds are faster.

3. **Build the Swift package:**
```bash
swift build
```

4. **Run the application:**
```bash
swift run AgentStudio
```

## Development

### Project Structure

```
agent-studio/
├── Sources/AgentStudio/     # Swift source code
│   ├── App/                 # Main app controllers
│   ├── Ghostty/             # Ghostty integration
│   ├── Models/              # Data models
│   └── Services/            # Business logic
├── Frameworks/              # Built XCFrameworks (generated, not in git)
├── vendor/ghostty/          # Ghostty source code
├── scripts/                 # Build and maintenance scripts
├── Package.swift            # Swift package manifest
└── README.md
```

### Key Components

- **GhosttySurfaceView** - SwiftUI/AppKit view wrapping Ghostty terminal
- **WorkspaceStore** - Central state store for sessions, tabs, and layouts
- **WorktrunkService** - Git worktree integration
- **MainWindowController** - Main application window management

### Rebuilding Ghostty

After pulling updates to the Ghostty submodule:

```bash
./scripts/build-ghostty.sh
```

To clean and rebuild everything:

```bash
# Clean all build artifacts
rm -rf .build Frameworks/GhosttyKit.xcframework
cd vendor/ghostty && rm -rf .zig-cache zig-out macos/build && cd ../..

# Rebuild
./scripts/build-ghostty.sh
swift build
```

### Build Artifacts (Not in Git)

The following directories are generated during build and excluded from version control:

- `Frameworks/GhosttyKit.xcframework/` - Built Ghostty framework (~135MB)
- `vendor/ghostty/.zig-cache/` - Zig build cache
- `vendor/ghostty/macos/build/` - Xcode build artifacts
- `vendor/ghostty/zig-out/` - Zig build outputs
- `.build/` - Swift build artifacts

## Troubleshooting

### "Zig not found" error

Install Zig using Homebrew:
```bash
brew install zig
```

### "XCFramework not found" after build

The build script may have failed. Check the output for errors. Common issues:
- Xcode command line tools not installed: `xcode-select --install`
- Wrong Xcode version selected: `sudo xcode-select --switch /Applications/Xcode.app`

### Build takes very long

First build of Ghostty compiles from source and takes 5-10 minutes. This is normal. Subsequent builds are incremental and much faster.

### "Cannot find 'GhosttyKit'" in Swift

The XCFramework wasn't built. Run:
```bash
./scripts/build-ghostty.sh
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Architecture

Agent Studio is built using:
- **Swift 5.9+** with Swift Package Manager
- **AppKit** for native macOS UI
- **Ghostty** (via C API) for terminal emulation
- **Zig build system** for Ghostty compilation

The application embeds Ghostty as a binary XCFramework, providing a native Swift interface to the terminal emulator while maintaining high performance.

## License

[Your license here]

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) - Fast, native, feature-rich terminal emulator
- Built with ❤️ for developers who love great terminal experiences
