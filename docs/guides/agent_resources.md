# Agent Resources & Research Guide

This guide provides grounded context, setup procedures, and research tools for agents working on the Agent Studio codebase.

## First-Time Setup

A fresh clone or worktree cannot build or test until its vendored inputs are
prepared. A standalone clone is its own primary worktree. The primary hydrates
and builds Ghostty and zmx once; linked worktrees normally reuse those outputs.
`mise run setup` owns both paths.

### Prerequisites

- **macOS 26 + Xcode 26 toolchain** — the package targets `.macOS(.v26)` and uses current Swift concurrency, Observation, WebKit, and AppKit APIs.
- **mise** — build orchestrator: `brew install mise`
- **swift-format** — code formatter: `brew install swift-format`
- **swiftlint** — stock SwiftLint for `.swiftlint.yml` rules: `brew install swiftlint`
- **xcbeautify** — beautifies swift build/test output: `brew install xcbeautify`

`mise run lint` uses stock SwiftLint for `.swiftlint.yml` rules and the
repo-local SwiftPM/SwiftSyntax architecture linter in
`Tools/AgentStudioArchitectureLint`. Homebrew SwiftLint alone is not the full
lint gate for this repo; the local architecture tool must also pass.

### Bootstrap Steps

Run these in order from the project root:

```bash
# 1. Install pinned tool versions (zig 0.15.2)
mise install

# 2. Check local macOS prerequisites and known env hazards
mise run doctor-mac

# 3. Prepare or reuse vendored artifacts/resources
mise run setup

# 4. Build the Swift app
mise run build
```

Do not initialize vendor submodules or run low-level vendor tasks directly.
Agents use plain `mise run setup` by default. Use
`mise run setup --use-local-vendors` only when the user explicitly requests
Ghostty/zmx vendor work or the accepted task requires changing a vendor. That
explicit mode hydrates and builds private vendor inputs in the current linked
worktree; it is not a recovery switch for ordinary setup failures.

### Vendor Inputs (All Gitignored)

| Artifact | Primary or local-vendor worktree | Shared linked worktree | Required for |
|----------|----------------------------------|------------------------|--------------|
| `Frameworks/GhosttyKit.xcframework` | Built locally | Symlink to primary output | `swift build` (SPM binary target) |
| `Sources/AgentStudio/Resources/ghostty/` | Generated locally | Regular local copy from primary | Runtime shell integration |
| `Sources/AgentStudio/Resources/terminfo/67/ghostty` | Generated locally | Regular local copy from primary | Runtime Ghostty terminfo |
| `vendor/zmx/zig-out/bin/zmx` | Built locally | Reached through a symlink to primary `zig-out` | Session multiplexer backend |

If these inputs are missing or incompatible, rerun `mise run setup`. `mise run
build` consumes them; it does not generate them. A linked worktree whose vendor
pins differ from the primary must prepare the matching pins in the primary, or
use the explicitly authorized local-vendor setup for actual vendor work.

### Verifying the Setup

```bash
# Confirm this worktree's vendor role, inputs, and relevant prerequisites
mise run doctor-mac

# Run tests
mise run test
```

## DeepWiki Knowledge Base
Use DeepWiki to gather grounded context on core dependencies and libraries.

- **Ghostty (Core Terminal)**: `ghostty-org/ghostty`
  - *Usage*: `wiki_question(repo: "ghostty-org/ghostty", question: "...")`
  - *Focus*: C API, terminal emulation logic, Zig build system.
- **Swift (Language)**: `swiftlang/swift`
  - *Usage*: `wiki_question(repo: "swiftlang/swift", question: "...")`
  - *Focus*: Language features, standard library, runtime behavior.

## Documentation Links

### Current Swift and Apple Platform References

Use these primary docs when updating architecture docs or implementation details. Do not infer platform behavior from memory when the API has likely moved.

- **Swift docs index**: [https://www.swift.org/documentation/](https://www.swift.org/documentation/)
- **Swift language guide — concurrency**: [https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- **Swift Package Manager**: [https://docs.swift.org/package-manager/](https://docs.swift.org/package-manager/)
- **Swift Testing**: [https://developer.apple.com/documentation/testing](https://developer.apple.com/documentation/testing)
- **AppKit**: [https://developer.apple.com/documentation/appkit](https://developer.apple.com/documentation/appkit)
- **SwiftUI**: [https://developer.apple.com/documentation/swiftui](https://developer.apple.com/documentation/swiftui)
- **SwiftUI/AppKit integration**: [https://developer.apple.com/documentation/swiftui/appkit-integration](https://developer.apple.com/documentation/swiftui/appkit-integration)
- **Observation**: [https://developer.apple.com/documentation/observation](https://developer.apple.com/documentation/observation)
- **WebKit**: [https://developer.apple.com/documentation/webkit](https://developer.apple.com/documentation/webkit)
- **Designing for macOS**: [https://developer.apple.com/design/human-interface-guidelines/designing-for-macos](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

Project target note: Swift.org may show a newer downloadable Swift toolchain than this repo targets. Follow `Package.swift`, `.mise.toml`, and the Xcode toolchain selected by `doctor-mac` for builds; use the docs links above for current API semantics.

### Dependency and Vendor References

- **Ghostty Docs**: [https://ghostty.org/docs](https://ghostty.org/docs)
- **Pierre Diffs / CodeView Docs**: [https://diffs.com/docs](https://diffs.com/docs)
- **Trees Docs**: [https://trees.software/docs](https://trees.software/docs)
- **Shiki Docs**: [https://shiki.style/](https://shiki.style/)
- **Hunk inspiration**: [https://github.com/modem-dev/hunk](https://github.com/modem-dev/hunk) and [https://deepwiki.com/modem-dev/hunk](https://deepwiki.com/modem-dev/hunk). Use for annotation/review workflow research only; do not copy its terminal UI architecture into the React CodeView pane.
- **swift-async-algorithms**: [https://github.com/apple/swift-async-algorithms](https://github.com/apple/swift-async-algorithms)
- **JSON-RPC 2.0**: [https://www.jsonrpc.org/specification](https://www.jsonrpc.org/specification)
- **Foundation**: [https://developer.apple.com/documentation/foundation](https://developer.apple.com/documentation/foundation)
- **Metal**: [https://developer.apple.com/documentation/metal](https://developer.apple.com/documentation/metal)

## Research Guidance

### C API / Interop
When working on `Ghostty.swift` or `GhosttySurfaceView.swift`, verify C function signatures and memory management patterns in the Ghostty repo. Pay close attention to pointer ownership and lifetime.

### AppKit Patterns
For UI changes in `Sources/AgentStudio/App/`, refer to Apple's AppKit documentation for native macOS behaviors. This includes the responder chain, window delegation, and menu management.

### App Organization
The current app layout is hybrid:

- `App/` owns composition, boot, lifecycle, windows, pane hosting, and cross-feature coordination.
- `Core/` owns shared models, actions, runtime contracts, main-actor atoms, persistence wrappers, and feature-agnostic pane UI.
- `Features/` owns vertical capability slices such as `Terminal`, `Bridge`, `Webview`, `CodeViewer`, `CommandBar`, `RepoExplorer`, and `InboxNotification`.
- `SharedComponents/` owns reusable UI primitives. It imports only `Infrastructure`
  and receives state through explicit values, bindings, callbacks, or shared/infrastructure
  observable view models, not atoms or global stores.
- `Infrastructure/` owns domain-agnostic utilities and external integrations.

Use [Directory Structure & Module Boundaries](../architecture/directory_structure.md) as the placement source of truth.

### Zig Build System
Ghostty and zmx are built by `mise run setup` in the primary worktree or an
explicitly authorized local-vendor worktree. Shared linked worktrees reuse those
prepared inputs and may not contain hydrated vendor source. If investigating
build options or optimization flags, inspect the pinned vendor sources in the
primary, or use `mise run setup --use-local-vendors` when the accepted task
requires changing Ghostty or zmx.

### Swift Concurrency
The project targets **macOS 26 only** (`.macOS(.v26)` in `Package.swift`). Use Swift 6.2 concurrency features deliberately: `@MainActor` for UI/state mutation, actors for boundary work, `AsyncStream`/`AsyncThrowingStream` for event streams, and `@concurrent nonisolated` for blocking work that must escape an actor executor. Refer to the [Swift Language Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) and [Pane Runtime EventBus Design](../architecture/pane_runtime_eventbus_design.md) before changing concurrency boundaries.
