# swift-dependencies Adoption Spec

> **Superseded:** The atom/state access direction in this document has been replaced by [2026-04-04-actor-bound-atom-store-design.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.atoms-refactor-impl/docs/superpowers/specs/2026-04-04-actor-bound-atom-store-design.md).
>
> This document is retained as historical context only. Do not use it as the implementation source of truth for atoms, derived selectors, or test scoping.

## Decision

Adopt Point-Free's `swift-dependencies` library as part of the atoms/stores refactor. This replaces singletons and constructor-threaded dependency passing with `@Dependency` property wrappers and `withDependencies` test scoping.

## Why

- Eliminates singleton state leakage between tests
- Removes 5+ constructor parameters from coordinators and stores
- `withDependencies` gives isolated state per test for free
- `swift-clocks` comes as a transitive dependency — replaces our custom `TestPushClock`
- Matches the Jotai mental model: atoms are dependencies, stores compose them

## Package

```swift
// Package.swift
.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0")
```

Add `Dependencies` to the target's dependencies.

**Transitive dependencies:** `swift-clocks`, `swift-concurrency-extras`, `combine-schedulers`, `xctest-dynamic-overlay`, `swift-syntax`

## Core Pattern

### Dependency keys for atoms

```swift
// Sources/AgentStudio/Infrastructure/DependencyKeys.swift
import Dependencies

struct WorkspaceAtomKey: DependencyKey {
    static let liveValue = WorkspaceAtom()
    static let testValue = WorkspaceAtom()
}

struct ManagementModeAtomKey: DependencyKey {
    static let liveValue = ManagementModeAtom()
    static let testValue = ManagementModeAtom()
}

// ... one key per atom

extension DependencyValues {
    var workspaceAtom: WorkspaceAtom {
        get { self[WorkspaceAtomKey.self] }
        set { self[WorkspaceAtomKey.self] = newValue }
    }
    var managementModeAtom: ManagementModeAtom {
        get { self[ManagementModeAtomKey.self] }
        set { self[ManagementModeAtomKey.self] = newValue }
    }
}
```

### Usage in @Observable classes

```swift
@Observable
@MainActor
final class SomeFeature {
    @ObservationIgnored @Dependency(\.workspaceAtom) var workspace
    @ObservationIgnored @Dependency(\.managementModeAtom) var managementMode

    // Access workspace.tabs, workspace.pane(id), etc.
}
```

**Rules:**
- `@ObservationIgnored` is MANDATORY on every `@Dependency` in `@Observable` classes
- Never put `@Dependency` on static properties
- Use `withDependencies(from: self)` when creating child objects

### Usage in tests

```swift
@Test func featureTest() {
    let feature = withDependencies {
        $0.workspaceAtom = WorkspaceAtom()  // fresh
        $0.managementModeAtom = ManagementModeAtom()  // fresh
    } operation: {
        SomeFeature()
    }
    // Completely isolated — no shared state
}
```

### Stores observe atoms via @Dependency

```swift
@MainActor
final class WorkspaceStore {
    @ObservationIgnored @Dependency(\.workspaceAtom) var atom

    func restore() {
        // load from disk → atom.hydrate(...)
        startObserving()
    }

    private func startObserving() {
        // withObservationTracking on atom properties
    }
}
```

## What we're NOT doing

- NOT replacing `@Environment` in SwiftUI views — that already works
- NOT making `WorkspacePersistor` a dependency — it's I/O, not state
- NOT making `ZmxBackend` a dependency — it's a backend, not an atom
- NOT using `@Dependency` on `static let shared` properties — this breaks Task Local resolution

## Singletons to eliminate

**All `.shared` singletons are eliminated.** `static let shared` is incompatible with `@Dependency` — it captures stale Task Local context at first access, breaking test isolation.

| Current singleton | Replacement |
|------------------|-------------|
| `ManagementModeMonitor.shared` | `@Dependency(\.managementModeMonitor)` — monitor is itself a dependency |
| `ManagementModeAtom` (new) | `@Dependency(\.managementModeAtom)` — accessed via monitor or directly |
| `CommandDispatcher.shared` | `@Dependency(\.commandDispatcher)` |
| `SurfaceManager.shared` | Keep as singleton for now — Core can't import Features types, and it's behavior-heavy. Future: make it a dependency when Features types are accessible. |

**Rule: Never use `@Dependency` inside a `static let shared` initializer.** The `static let` captures Task Local context at first access, which is always the default (live) context. Test overrides via `withDependencies` won't reach it.

**Delete `ManagementModeTestLock`** — the custom serialization actor exists solely because of singleton state sharing. With dependency injection, each test gets isolated instances by construction.

## Migration order

1. Add package to `Package.swift`
2. Create dependency keys for all atoms
3. Each task in the atoms refactor uses `@Dependency` instead of constructor injection
4. Tests use `withDependencies` instead of manual construction
5. Gradually migrate existing singleton usage to `@Dependency` in subsequent PRs
