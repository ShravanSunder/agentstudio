# Agent Resources & Research Guide

This guide provides grounded context and research tools for agents working on the Agent Studio codebase.

## DeepWiki Knowledge Base
Use DeepWiki to gather grounded context on core dependencies and libraries.

- **Ghostty (Core Terminal)**: `ghostty-org/ghostty`
  - *Usage*: `wiki_question(repo: "ghostty-org/ghostty", question: "...")`
  - *Focus*: C API, terminal emulation logic, Zig build system.
- **Swift (Language)**: `swiftlang/swift`
  - *Usage*: `wiki_question(repo: "swiftlang/swift", question: "...")`
  - *Focus*: Language features, standard library, runtime behavior.

## Documentation Links
- **Ghostty Docs**: [https://ghostty.org/docs](https://ghostty.org/docs)
- **Swift.org**: [https://www.swift.org/documentation/](https://www.swift.org/documentation/)
- **Apple Developer Docs**: [https://developer.apple.com/documentation/](https://developer.apple.com/documentation/)
  - [AppKit](https://developer.apple.com/documentation/appkit)
  - [SwiftUI](https://developer.apple.com/documentation/swiftui)
  - [Metal](https://developer.apple.com/documentation/metal)
  - [Foundation](https://developer.apple.com/documentation/foundation)

## Research Guidance

### C API / Interop
When working on `Ghostty.swift` or `GhosttySurfaceView.swift`, verify C function signatures and memory management patterns in the Ghostty repo. Pay close attention to pointer ownership and lifetime.

### AppKit Patterns
For UI changes in `Sources/AgentStudio/App/`, refer to Apple's AppKit documentation for native macOS behaviors. This includes the responder chain, window delegation, and menu management.

### Zig Build System
If modifying `scripts/build-ghostty.sh`, check `build.zig` in the Ghostty repo for available build options and optimization flags.

### Swift Concurrency
The project targets macOS 14+, so modern Swift concurrency (async/await, Actors) should be used. Refer to the [Swift Language Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) for best practices.
