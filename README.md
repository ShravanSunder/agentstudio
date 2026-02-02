# Agent Studio

A macOS application that integrates Ghostty terminal emulator.

## Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- [Zig](https://ziglang.org/download/) compiler (for building Ghostty)

### Installing Zig

```bash
# Using Homebrew
brew install zig

# Or download from https://ziglang.org/download/
```

## Setup

1. Clone the repository:
```bash
git clone <your-repo-url>
cd agent-studio
```

2. Build Ghostty and generate the XCFramework:
```bash
./scripts/build-ghostty.sh
```

This script will:
- Build Ghostty from source
- Generate the GhosttyKit.xcframework
- Copy it to the Frameworks directory

3. Build the Swift package:
```bash
swift build
```

## Development

The project uses Swift Package Manager. The Ghostty integration is provided through a binary XCFramework target that links against the built Ghostty library.

### Project Structure

- `Sources/` - Swift source code
- `Frameworks/` - Built XCFrameworks (generated, not tracked in git)
- `vendor/ghostty/` - Ghostty source code (build artifacts excluded from git)
- `scripts/` - Build scripts

### Rebuilding Ghostty

If you need to rebuild Ghostty after updates:

```bash
./scripts/build-ghostty.sh
```

## License

[Your license here]
