# Actor-Bound Atom Store Design

## Status

Proposed design spec for review.

This document supersedes the dependency-injection direction in [2026-04-02-swift-dependencies-adoption.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.atoms-refactor-impl/docs/superpowers/specs/2026-04-02-swift-dependencies-adoption.md) for atom/state access.

## Decision

Do not use a general dependency-injection library to inject live atom instances.

Instead:

- keep state atoms fully actor-bound on `@MainActor`
- introduce an explicit `AtomStore` composition root that owns the live atom instances
- introduce `AtomScope` as the ambient access mechanism for the current atom store
- make `atom(\.foo)` the primary runtime access API
- keep `@Atom(\.foo)` only as optional convenience sugar
- implement derived selectors on top of ambient atom access rather than constructor-injected DI
- keep persistence as separate store wrappers with explicit constructor injection for non-state dependencies such as clocks and persistors

This is a Jotai-inspired + Valtio-inspired design translated into Swift 6.2’s actor model rather than into a generic DI framework model.

## Why

### 1. Swift 6.2 actor correctness matters more than DI elegance

The app’s canonical UI-facing state belongs on the main actor. `WorkspaceAtom`, `RepoCacheAtom`, `UIStateAtom`, `ManagementModeAtom`, and `SessionRuntimeAtom` are all UI/runtime state that directly drive SwiftUI/AppKit rendering and coordination. Making them fully `@MainActor` gives the strongest correctness story.

Generic DI frameworks are a bad fit for directly registering actor-isolated state holders because they typically rely on:

- nonisolated static registration/defaults
- key-path based dependency access
- generic container access outside a specific actor boundary

That conflicts with Swift 6.2’s strict actor-isolation model for `@MainActor` classes.

This is a mismatch between:

- a DI framework designed for globally-available dependencies
- and app state objects that should remain isolated to a single actor

not a problem caused by “too many actors” in the app.

### 2. Explicit ownership matches this codebase better

This codebase already has a strong composition root in `AppDelegate` / boot sequence. The app is not a pure SwiftUI tree with lightweight transient state. It is an AppKit + SwiftUI hybrid that already wires long-lived runtime objects explicitly.

An `AtomStore` owned by the composition root fits that existing shape better than trying to make atoms behave like injectable service dependencies.

### 3. Derived selectors still give us the Jotai feel we want

Jotai’s mental model is valuable here because it gives us:

- state atoms
- derived computations over atoms
- selector-style composition
- scoped overrides in tests

We can preserve those ideas without copying Jotai’s store implementation literally.

The Swift translation is:

- state atoms are `@Observable @MainActor` classes
- `AtomStore` owns the live atom instances
- `AtomScope` exposes the current atom store for the current scope
- `atom(\.workspace)` is the primary runtime access API
- `AtomReader` is the Jotai-like `get`
- `Derived<Value>` and `DerivedSelector<Param, Value>` are the v1 derivation primitives
- derived selectors read atoms implicitly from that ambient scope
- scoped test overrides replace the current store for a test scope without leaking into sibling tests

### 4. The atom system is for state, not for everything

This design is intentionally narrow. It solves:

- state atom access
- derived selector access
- scoped override/testing of state

It does **not** try to become a general-purpose DI framework.

Other dependencies:

- clocks
- persistors
- services
- process executors
- networking clients

stay on explicit constructor injection unless proven otherwise.

## Research Basis

This design is based on:

- Swift actor isolation and `MainActor` semantics
- Swift Observation access tracking behavior
- SwiftUI/AppKit hybrid state-management guidance
- the observed mismatch between actor-isolated state holders and generic DI registration patterns

Key references:

- Swift actors proposal: https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md
- `MainActor` docs: https://developer.apple.com/documentation/Swift/MainActor
- WWDC 2025 Swift concurrency session: https://developer.apple.com/videos/play/wwdc2025/268/
- Swift Observation docs: https://developer.apple.com/documentation/Observation
- Observation tracking explanation: https://talk.objc.io/episodes/S01E362-swift-observation-access-tracking
- Swift forums on `@MainActor` state and singletons: https://forums.swift.org/t/swift-6-and-singletons-observable-and-data-races/71101
- Swift forums on observable re-render behavior: https://forums.swift.org/t/understanding-when-swiftui-re-renders-an-observable/77876
- Composition-root initialization guidance: https://nilcoalescing.com/blog/InitializingObservableClassesWithinTheSwiftUIHierarchy
- Swift task-local values: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency#TaskLocal-values
- SE-0401 property wrapper isolation inference: https://github.com/apple/swift-evolution/blob/main/proposals/0401-remove-property-wrapper-isolation.md

## Core Infrastructure

The core atom access system is intentionally small.

## Folder Structure

The shared app-wide main-actor state system lives under:

```text
Sources/AgentStudio/
├── Infrastructure/
│   └── AtomLib/
│       ├── AtomStore.swift
│       ├── AtomScope.swift
│       ├── Atom.swift
│       ├── AtomReader.swift
│       ├── Derived.swift
│       └── DerivedSelector.swift
└── Core/
    └── State/
        └── MainActor/
            ├── Atoms/
            │   ├── WorkspaceAtom.swift
            │   ├── RepoCacheAtom.swift
            │   ├── UIStateAtom.swift
            │   ├── ManagementModeAtom.swift
            │   ├── SessionRuntimeAtom.swift
            │   ├── PaneDisplayDerived.swift
            │   └── DynamicViewDerived.swift
            └── Persistence/
                ├── WorkspaceStore.swift
                ├── RepoCacheStore.swift
                └── UIStateStore.swift
```

Rules:

- derived atoms/selectors live in `Atoms/` and are distinguished by the `Derived` suffix in their type/file name
- there is no shared `Derived/` folder
- `Persistence/` is only for persistence wrappers
- actor files themselves do **not** move into a global actor folder; they stay with the feature/subsystem that owns the work

Future actor-local state systems, if introduced, live with the owning feature/subsystem and may use a local `State/` folder there. They do not belong in the shared `MainActor` state tree.

### 1. `AtomStore`

`AtomStore` is the composition root for live state atoms.

Rules:

- `@MainActor`
- owns live atom instances
- one app-scope production instance
- fresh test instances per test scope
- `let` properties so atom instances are not swapped at runtime
- no business logic beyond owning atoms and optionally vending selectors

Example:

```swift
@MainActor
final class AtomStore {
    let workspace: WorkspaceAtom
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let managementMode: ManagementModeAtom
    let sessionRuntime: SessionRuntimeAtom

    init(
        workspace: WorkspaceAtom = .init(),
        repoCache: RepoCacheAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementMode: ManagementModeAtom = .init(),
        sessionRuntime: SessionRuntimeAtom = .init()
    ) {
        self.workspace = workspace
        self.repoCache = repoCache
        self.uiState = uiState
        self.managementMode = managementMode
        self.sessionRuntime = sessionRuntime
    }
}
```

### 2. `AtomScope`

`AtomScope` is the ambient access point to the current atom store.

Rules:

- `AtomScope` itself is `nonisolated`
- production store is set once at boot
- test override is scoped via `@TaskLocal`
- active store = scoped override if present, otherwise production store
- the active store accessor is `@MainActor`

Example:

```swift
nonisolated enum AtomScope {
    @MainActor
    private static var production: AtomStore!

    @TaskLocal
    static var override: AtomStore?

    @MainActor
    static var store: AtomStore {
        override ?? production
    }

    @MainActor
    static func setUp(_ store: AtomStore) {
        production = store
    }
}
```

This gives us:

- a stable production store
- scoped override ability for tests
- no generic DI framework

Accessing `AtomScope.store` before `AtomScope.setUp(_:)` is a programming error and should crash intentionally.

### 3. `atom(_:)`

`atom(_:)` is the primary runtime access function for the current atom store.

Rules:

- `@MainActor`
- plain function over `AtomScope.store`
- usable in SwiftUI, AppKit, coordinators, selectors, and stores
- does not create state or a new scope
- only reads from the current ambient scope

Example:

```swift
@MainActor
func atom<Value>(_ keyPath: KeyPath<AtomStore, Value>) -> Value {
    AtomScope.store[keyPath: keyPath]
}
```

This gives us Jotai-like usage:

```swift
let workspace = atom(\.workspace)
let label = atom(\.paneDisplay).displayLabel(for: paneId)
```

### 4. Optional `@Atom`

`@Atom` is a typed property-wrapper sugar over `AtomScope.store`.

Rules:

- `@MainActor`
- plain property wrapper, not tied to SwiftUI environment
- usable in SwiftUI, AppKit, coordinators, selectors, and stores
- does not create state or a new scope
- only reads from the current ambient scope

Example:

```swift
@MainActor
@propertyWrapper
struct Atom<Value> {
    private let keyPath: KeyPath<AtomStore, Value>

    init(_ keyPath: KeyPath<AtomStore, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        AtomScope.store[keyPath: keyPath]
    }
}
```

This gives us convenience sugar:

```swift
@Atom(\.workspace) private var workspace
@Atom(\.repoCache) private var repoCache
```

without a DI framework.

`@Atom` is optional convenience sugar. The primary design model is function-based access through `atom(\.foo)` and derivation-time access through `AtomReader`.

`@Atom` is an actor-isolated accessor, not a type-isolation mechanism. Any non-`body` method or escaping closure that touches `@Atom` must itself be explicitly `@MainActor` or perform an actor hop.

## Core Model

### 1. State atoms

State atoms are the single source of truth for one domain.

Rules:

- `@Observable`
- `@MainActor`
- `private(set)` for owned state
- mutation methods express the legal writes
- no persistence logic
- no event-bus subscription logic
- no background actor ownership

Examples:

- `WorkspaceAtom`
- `RepoCacheAtom`
- `UIStateAtom`
- `ManagementModeAtom`
- `SessionRuntimeAtom`

Example:

```swift
import Observation

@MainActor
@Observable
final class WorkspaceAtom {
    private(set) var repos: [Repo] = []
    private(set) var panes: [UUID: Pane] = [:]
    private(set) var tabs: [Tab] = []

    func addRepo(_ repo: Repo) {
        repos.append(repo)
    }

    func addPane(_ pane: Pane) {
        panes[pane.id] = pane
    }

    func pane(_ id: UUID) -> Pane? {
        panes[id]
    }
}
```

### 2. Derived selectors

Derived selectors are read-only computations over atoms.

Rules:

- `@MainActor` if they read live atom state directly
- no owned canonical state
- no persistence
- no background actor ownership
- may be zero-input or parameterized
- may delegate heavy algorithms to pure helpers

Two selector shapes are first-class:

- zero-input computed selectors
- parameterized selectors

Examples:

```swift
@MainActor
struct ActivePaneCountDerived {
    @Atom(\.workspace) private var workspace

    var value: Int {
        workspace.panes.count
    }
}
```

```swift
@MainActor
struct PaneDisplayDerived {
    @Atom(\.workspace) private var workspace
    @Atom(\.repoCache) private var repoCache

    func displayLabel(for paneId: UUID) -> String {
        guard let pane = workspace.pane(paneId) else {
            return "Unknown"
        }

        if let worktreeId = pane.worktreeId,
           let enrichment = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]
        {
            return enrichment.branch
        }

        return pane.metadata.title
    }
}
```

### 5. Base derivation primitives

V1 includes a very small derivation helper layer:

- `AtomReader`
- `Derived<Value>`
- `DerivedSelector<Param, Value>`

Example:

```swift
@MainActor
struct AtomReader {
    func callAsFunction<Value>(_ keyPath: KeyPath<AtomStore, Value>) -> Value {
        AtomScope.store[keyPath: keyPath]
    }
}

@MainActor
struct Derived<Value> {
    let compute: (AtomReader) -> Value

    var value: Value {
        compute(AtomReader())
    }
}

@MainActor
struct DerivedSelector<Param, Value> {
    let compute: (AtomReader, Param) -> Value

    func value(for param: Param) -> Value {
        compute(AtomReader(), param)
    }
}
```

These are part of v1 because Jotai-like derivation and future higher-order composition are explicit project requirements.

Concrete selectors such as `PaneDisplayDerived` and `DynamicViewDerived` still exist; the generic helpers are the shared foundation underneath them or for simpler one-liner derivations.

### 6. Read-only in v1, writable later

V1 selectors are read-only.

That means:

- `Derived`
- `DerivedSelector`
- concrete selector types

must not mutate atoms directly.

Future Jotai-like writable/action semantics are an explicit extension point, but they are not part of the first implementation. Cross-atom writes remain the responsibility of main-actor coordinators, stores, and explicit domain mutation APIs.

### 7. Pure helpers stay separate

Heavy pure algorithms remain explicit-argument helpers.

Examples:

- `WorktreeReconciler`
- `DynamicViewProjectionBuilder`

They do not need to be actor-bound if they only consume plain values.

## Production Setup

Production code should create one app-scope `AtomStore` at boot and bind it to `AtomScope`.

Example:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var atoms: AtomStore!
    private var workspaceStore: WorkspaceStore!
    private var paneCoordinator: PaneCoordinator!
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let atoms = AtomStore()
        let persistor = WorkspacePersistor()

        AtomScope.setUp(atoms)

        self.atoms = atoms
        self.workspaceStore = WorkspaceStore(
            persistor: persistor,
            clock: ContinuousClock()
        )
        self.paneCoordinator = PaneCoordinator()
        self.windowController = MainWindowController(atoms: atoms)

        workspaceStore.restore()
    }
}
```

Production invariants:

- one app-scope `AtomStore`
- one live atom graph for that scope
- all UI/AppKit/state readers use those same instances
- ambient access resolves to that same store unless a scoped override is active

## Persistence Model

Persistence remains separate from state ownership.

Rules:

- atoms own state
- persistence stores own save/restore/debounce policy
- persistence stores may compose one atom or multiple atoms
- stores are `@MainActor`
- non-state dependencies such as clocks and persistors are constructor-injected explicitly

Examples:

- `WorkspaceStore`
- `RepoCacheStore`
- `UIStateStore`

Example:

```swift
@MainActor
final class UIStateStore {
    let persistor: WorkspacePersistor
    let clock: any Clock<Duration>

    @Atom(\.uiState) private var uiState

    init(
        persistor: WorkspacePersistor,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.persistor = persistor
        self.clock = clock
    }

    func flush() {
        // read one or more UI atoms and persist
    }
}
```

`UIStateStore` is explicitly allowed to compose multiple UI atoms if that proves useful later.

## End-to-End Example

This example shows the intended layering for one concrete feature:

- one actor-bound atom
- one derived selector
- one persistence store
- one SwiftUI view
- one AppKit consumer

```swift
import Observation
import SwiftUI

@MainActor
@Observable
final class WorkspaceAtom {
    private(set) var panes: [UUID: Pane] = [:]

    func addPane(_ pane: Pane) {
        panes[pane.id] = pane
    }

    func pane(_ id: UUID) -> Pane? {
        panes[id]
    }
}

@MainActor
final class AtomStore {
    let workspace = WorkspaceAtom()
    let repoCache = RepoCacheAtom()

    lazy var paneDisplay = PaneDisplayDerived()
}

nonisolated enum AtomScope {
    @MainActor private static var production: AtomStore!
    @TaskLocal static var override: AtomStore?

    @MainActor
    static var store: AtomStore { override ?? production }

    @MainActor
    static func setUp(_ store: AtomStore) { production = store }
}

@MainActor
@propertyWrapper
struct Atom<Value> {
    private let keyPath: KeyPath<AtomStore, Value>

    init(_ keyPath: KeyPath<AtomStore, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        AtomScope.store[keyPath: keyPath]
    }
}

@MainActor
struct PaneDisplayDerived {
    @Atom(\.workspace) private var workspace
    @Atom(\.repoCache) private var repoCache

    func displayLabel(for paneId: UUID) -> String {
        guard let pane = workspace.pane(paneId) else { return "Unknown" }

        if let worktreeId = pane.worktreeId,
           let enrichment = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]
        {
            return enrichment.branch
        }

        return pane.metadata.title
    }
}

@MainActor
final class WorkspaceStore {
    let persistor: WorkspacePersistor

    @Atom(\.workspace) private var workspace

    init(persistor: WorkspacePersistor) {
        self.persistor = persistor
    }

    func flush() {
        // read workspace and persist
    }
}

struct PaneLabelView: View {
    @Atom(\.workspace) private var workspace
    @Atom(\.paneDisplay) private var paneDisplay

    let paneId: UUID

    var body: some View {
        Text(paneDisplay.displayLabel(for: paneId))
    }
}

@MainActor
final class PaneCoordinator {
    @Atom(\.workspace) private var workspace
    @Atom(\.paneDisplay) private var paneDisplay

    func renameFocusedPane(_ paneId: UUID) {
        let currentLabel = paneDisplay.displayLabel(for: paneId)
        _ = currentLabel
    }
}
```

Important takeaways:

- `WorkspaceAtom` owns state
- `PaneDisplayDerived` reads state but owns none
- `WorkspaceStore` persists state but does not own it
- `PaneLabelView` and `PaneCoordinator` both resolve the same underlying atom instances
- the same access mechanism works in SwiftUI and AppKit/non-view code
- `AtomStore` vending selectors is convenience, not a requirement of the architecture

## Call-Site Ergonomics

This design intentionally supports the same atom values across SwiftUI and non-SwiftUI code.

### Same-state invariant

All access paths must resolve the same live atom instances for a given app scope.

That means:

- SwiftUI views using `@Atom(\.workspace)`
- AppKit/controllers using `@Atom(\.workspace)` or `AtomScope.store.workspace`
- derived selectors reading through `@Atom`
- persistence stores reading through `@Atom`

must all observe and mutate the same underlying `WorkspaceAtom` instance for that scope.

Helpers are alternate access paths, not alternate state containers.

### SwiftUI views

Usage:

```swift
struct SidebarView: View {
    @Atom(\.workspace) private var workspace
    @Atom(\.paneDisplay) private var paneDisplay

    let paneId: UUID

    var body: some View {
        VStack {
            Text("\\(workspace.panes.count)")
            Text(paneDisplay.displayLabel(for: paneId))
        }
    }
}
```

### AppKit / coordinators / non-view code

Usage:

```swift
@MainActor
final class PaneCoordinator {
    @Atom(\.workspace) private var workspace
    @Atom(\.sessionRuntime) private var sessionRuntime
}
```

This is acceptable because `@Atom` is not a SwiftUI-specific environment wrapper in this design. It is just sugar over `AtomScope.store`.

## Common Usage

### 1. Adding a new state atom

When a new domain earns its own atom:

1. create a focused `@MainActor @Observable` atom type
2. keep state `private(set)` unless a field is truly local-only/transient
3. add domain mutation methods
4. add the atom instance to `AtomStore`
5. only add persistence support if the atom actually needs persistence

Example:

```swift
@MainActor
@Observable
final class SidebarSelectionAtom {
    private(set) var selectedRepoId: UUID?

    func selectRepo(_ id: UUID?) {
        selectedRepoId = id
    }
}
```

### 2. Adding a new derived selector

When a concept repeatedly reads one or more atoms:

1. create a selector type for that concept
2. keep it read-only
3. keep it on `@MainActor` if it reads live atom state
4. move repeated explicit-arg computation into pure helpers underneath if useful

Example:

```swift
@MainActor
struct SidebarDisplayDerived {
    @Atom(\.workspace) private var workspace
    @Atom(\.sidebarSelection) private var sidebarSelection

    func selectedRepoName() -> String? {
        guard let repoId = sidebarSelection.selectedRepoId else { return nil }
        return workspace.repos.first(where: { $0.id == repoId })?.name
    }
}
```

### 3. Reading atoms directly

Direct reads are acceptable when the concept is local and does not justify a selector:

```swift
let paneCount = AtomScope.store.workspace.panes.count
```

If multiple call sites repeat the same multi-atom logic, add a selector.

### 4. Using the generic derivation primitives

For simple one-liners, prefer `Derived` / `DerivedSelector` over inventing an ad hoc concrete type.

Examples:

```swift
let activePaneCount = Derived<Int> { get in
    get(\.workspace).panes.count
}
```

```swift
let paneDisplayLabel = DerivedSelector<UUID, String> { get, paneId in
    let workspace = get(\.workspace)
    let repoCache = get(\.repoCache)

    guard let pane = workspace.pane(paneId) else { return "Unknown" }

    if let worktreeId = pane.worktreeId,
       let enrichment = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]
    {
        return enrichment.branch
    }

    return pane.metadata.title
}
```

### 5. Background actor to main-actor update flow

Background/runtime actors should not mutate atoms directly.

Example shape:

```swift
actor RepoScannerActor {
    func scan() async -> [Repo] {
        // background work
    }
}

@MainActor
final class WorkspaceCacheCoordinator {
    let scanner: RepoScannerActor

    @Atom(\.workspace) private var workspace

    init(scanner: RepoScannerActor) {
        self.scanner = scanner
    }

    func refreshRepos() async {
        let repos = await scanner.scan()
        workspace.replaceRepos(repos)
    }
}
```

The actor boundary is explicit and compile-time enforced.

## Actor Boundary Rules

These are the most important rules in the design.

### 1. Live atoms do not cross actor boundaries casually

Atoms are `@MainActor`.

That means:

- views may read them directly
- AppKit controllers/coordinators/stores may read and mutate them on `@MainActor`
- background/runtime actors do not hold atom references for mutation

### 2. Anything that reads live atom state directly is also `@MainActor`

This applies to:

- derived selectors
- persistence stores
- UI coordinators/controllers
- `AtomStore` itself

If a type reads live atom state directly, it belongs on the same actor.

### 3. Background actors communicate by facts/data, not by direct atom mutation

Runtime actors should:

- fetch data
- compute results
- emit facts/deltas/events

Then a `@MainActor` coordinator/store applies those results to the atoms.

This keeps actor boundaries explicit and aligned with Swift 6.2.

### 4. Pure helpers are exempt

Pure functions that take plain values do not need to live on `@MainActor`.

Only live state access creates the actor-boundary requirement.

### 5. Scoped overrides must not leak

Tests and other scoped override contexts must be able to replace atoms/selectors/helpers for a scope without:

- leaking into other tests
- mutating global production state
- serializing otherwise independent tests unnecessarily

This is a hard invariant.

Scoped overrides are allowed through `AtomScope.$override.withValue(...)`.

The test-support API must make the safe path the default.

### 6. Cross-actor payloads must be `Sendable`

Any value crossing actor boundaries must be:

- `Sendable`
- or converted into an immutable `Sendable` snapshot/fact/delta first

Background actors do not send live atom references across actors.

### 6. Non-UI actor stores are a future possibility, not a v1 driver

UI/main-actor atoms are:

- shared across the app’s UI scope
- directly render-driving
- actor-bound to `MainActor`

actor-local background state is different:

- owned by one actor
- not necessarily shared UI state
- may have different scoping and lifecycle rules

So non-UI actor stores are a future possibility, not a design driver for v1.

## Observation Model

Derived selectors rely on Swift Observation correctly tracking the underlying atom reads during tracked evaluation.

That means:

- a selector does not itself need to be `@Observable` if it is only a read layer
- observation comes from the underlying `@Observable` atom properties that it reads
- reads must happen during `body` evaluation or `withObservationTracking`

This is a required validation step before implementation:

- create a focused test proving that a struct-based derived selector reading `@Observable` atoms triggers `onChange` when those atoms mutate

If that test fails:

- promote the selector to an `@MainActor final class`
- or revisit the helper design before broad migration

## Test Scoping and Isolation

Tests should create a fresh `AtomStore` per test scope unless a broader shared fixture is explicitly justified.

Example:

```swift
@MainActor
func withTestAtomStore<T>(
    _ body: (AtomStore) throws -> T
) rethrows -> T {
    let atoms = AtomStore(
        workspace: WorkspaceAtom(),
        repoCache: RepoCacheAtom(),
        uiState: UIStateAtom(),
        managementMode: ManagementModeAtom(),
        sessionRuntime: SessionRuntimeAtom()
    )

    return try AtomScope.$override.withValue(atoms) {
        try body(atoms)
    }
}
```

Usage:

```swift
@MainActor
@Test
func paneDisplay_showsPaneTitle() throws {
    try withTestAtomStore { atoms in
        let pane = Pane(source: .floating(launchDirectory: nil, title: nil), title: "Hello")
        atoms.workspace.addPane(pane)

        let selector = PaneDisplayDerived()
        let label = selector.displayLabel(for: pane.id)

        #expect(label == "Hello")
    }
}
```

This is the intended isolation model:

- production has one app-scope `AtomStore`
- tests create their own scoped `AtomStore`
- scoped overrides do not leak across tests

## Required Validation Tests

The first implementation must include targeted validation tests for the architectural invariants, not just behavior tests.

### 1. Observation flows through struct-based derived selectors

Prove that a struct-based derived selector reading `@Observable` atom state inside `withObservationTracking` triggers `onChange` when the source atom mutates.

### 2. `@Atom` resolves the same live atom instance

Prove that reads through `@Atom(\.workspace)` see the same underlying atom instance as direct reads through `AtomScope.store.workspace`.

### 3. Background actor access requires an actor hop

Add a compile-time proof point or a focused test fixture showing that background actor code cannot casually mutate main-actor atoms without an explicit hop.

### 4. Scoped test overrides are isolated

Prove that a test-scoped override:

- is visible inside that test scope
- is not visible in a concurrent sibling test
- is restored after the scope exits

### 5. Persistence stores operate on the intended atom scope

Prove that persistence stores save/restore against the same live atom instances used by views/controllers for a given scope.

### 6. Task-topology semantics are explicit and tested

Validate override semantics in:

- `Task { }`
- `async let`
- `withTaskGroup`
- `Task.detached`
- escaped callbacks / non-inherited contexts

Especially prove:

- scoped overrides are visible in structured child tasks where intended
- detached tasks do not inherit the override accidentally

## What This Design Does Not Solve

This system intentionally does not solve:

- clock injection for persistence debounce
- `WorkspacePersistor` injection
- service locator patterns for non-state dependencies
- generic DI for runtime services

Those remain plain constructor injection concerns.

This system is only for:

- state atoms
- derived selectors
- scoped state overrides

That boundary is intentional.

## Hypothetical Future Extensions

These are explicitly out of scope for the first implementation, but worth naming so the design stays open-ended.

### 1. Cached derived helper

If some selectors become expensive, introduce a reusable cache/invalidation helper rather than ad hoc per-selector caches.

Concept:

- cached selector remains `@MainActor`
- reads exact atom properties it depends on
- invalidates on observation change

This would be analogous to a Jotai extension utility, not a core atom feature.

### Higher-order helper rule

Caching and other complex computation behavior should be implemented as higher-order helpers layered on top of `Derived` / `DerivedSelector`, not ad hoc inside individual selectors.

Examples of allowed future helpers:

- `cached(...)`
- `family(...)`
- `loadable(...)`
- `withDefault(...)`

These helpers must preserve:

- actor safety
- same-instance invariant
- task-scope semantics
- read/write boundary rules

### 2. Cross-actor communication helper

If we repeatedly need the same “background actor produces fact, main-actor store applies it” pattern, add a helper that standardizes:

- fact delivery
- actor hop to main actor
- application of deltas to atoms

This should remain a helper layer, not a backdoor that lets background actors mutate atoms directly.

### 3. Narrow persisted-atom protocol

The existing `PersistedAtom` idea may still be useful:

- `snapshot()`
- `hydrate(from:)`
- `readTrackedProperties()`

This remains compatible with the `AtomStore` architecture because it concerns persistence, not DI.

## Non-Goals

- no general-purpose DI framework for atoms
- no attempt to make atoms cross-actor injectable services
- no self-persisting atoms
- no god-store that replaces atom boundaries
- no speculative caching framework in the first pass

## Open Questions For Review

1. Resolved: `@Atom` is in v1. It is the standard sugar for atom access in both SwiftUI and non-view `@MainActor` code. Raw `AtomScope.store` remains valid for local/direct reads.
2. Resolved: `Derived` / `DerivedSelector` are part of v1 as the base derivation primitives. Concrete selectors are still preferred for richer multi-method concepts.
3. Resolved: persistence stores default to one atom, but multi-atom composition is explicitly allowed where it earns its place.
4. Resolved: `AtomStore` may vend prebuilt selectors (for example `lazy var paneDisplay = PaneDisplayDerived()`) as a convenience, but ad-hoc `PaneDisplayDerived()` construction is equally valid. Selectors do not rely on `AtomStore` vending to function.

## Recommended Next Step

If this spec is approved:

- rewrite the atoms/stores implementation plan against this architecture
- mark the `swift-dependencies` atom-injection docs/plan as superseded
- add the early observation-flow validation task before broad migration
