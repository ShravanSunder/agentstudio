# AgentStudio Coarse SwiftPM Target Modularization

Date: 2026-07-23
Updated: 2026-07-26
Status: revised draft; atom contract reviewed and synchronized
Source version: `fix-tests` at `5a7bd64690a3566dcb57fdf4d5a6dd34f9ed056c`

## Decision

Keep one Swift package and create:

- one `AgentStudioInfrastructure` target;
- one `AgentStudioSharedComponents` target;
- one coarse `AgentStudioCore` target;
- one target for each existing feature;
- the existing `AgentStudio` executable as the only App/composition target;
- one paired test target for every source target;
- executable-level integration tests for assembled-app behavior.

`AgentStudio` continues to own every `App/**` subfolder, `main.swift`,
`AtomRegistry.swift`, and all resources. App subfolders do not become targets.
Core does not split into domain, state, persistence, or UI targets.

This creates compiler-enforced ownership boundaries. It does not promise faster
builds or tests until the resulting graph is measured.

## Review Map

Read the spec top-down through four questions:

```text
1. Scope       Are these the right coarse targets?
      |
      v
2. DAG         Are the allowed dependency directions correct?
      |
      v
3. Contracts   Are atom, pane, resource, and App boundaries sufficient?
      |
      v
4. Proof       Do module tests and app integration preserve behavior?
```

The proposal is intentionally narrow:

```text
changes    folder ownership becomes compiler-enforced target ownership
preserves  one package, one App target, app-owned resources and distribution
defers     Core/App subtargets, new build tooling, performance conclusions
```

## Intent

The current folders communicate ownership but remain one executable module.
The target graph must:

- enforce Core/Feature/App dependency direction at compile time;
- give every Feature and Core a dependency-clean test owner;
- preserve product, persistence, vendor, resource, signing, and release
  behavior;
- avoid a granular Core or App redesign.

The existing IPC source/test targets are the local pattern to reuse.

```text
Today

App + Core + Features + SharedComponents + Infrastructure
                         |
                         v
             one AgentStudio module
                         |
                         v
            most tests import the app

Desired

App executable -> Feature -> Core -> SharedComponents -> Infrastructure
       |             |         |              |               |
       v             v         v              v               v
 app integration   paired    paired         paired          paired
      tests         tests     tests          tests           tests

Resources and distribution remain owned by the App executable.
```

## Boundary and Target DAG

In this map, `A -> B` means A depends on B:

```text
AgentStudio executable
  |
  +-> every Feature target
  |     |
  |     +-> AgentStudioCore
  |     +-> AgentStudioSharedComponents
  |     +-> AgentStudioInfrastructure
  |
  +-> AgentStudioCore
  |     |
  |     +-> AgentStudioSharedComponents
  |     +-> AgentStudioInfrastructure
  |
  +-> AgentStudioSharedComponents
  |     |
  |     +-> AgentStudioInfrastructure
  |
  +-> AgentStudioInfrastructure
```

No Feature depends on another Feature. Infrastructure depends on no internal
target.

The Feature targets are:

- `AgentStudioBridge`
- `AgentStudioCodeViewer`
- `AgentStudioCommandBar`
- `AgentStudioEditorChooser`
- `AgentStudioInboxNotification`
- `AgentStudioRepoExplorer`
- `AgentStudioTerminal`
- `AgentStudioWebview`

`AgentStudioTerminal` may depend directly on `GhosttyKit`. Other targets declare
only the external products they directly import. Existing IPC targets and their
graph remain unchanged.

## Ownership

| Target | Owns |
| --- | --- |
| `AgentStudioInfrastructure` | Domain-agnostic utilities, generic integrations, shared presentation tokens/policies, and generic atom primitives that name no product state |
| `AgentStudioSharedComponents` | Stateless reusable UI and reusable interaction primitives |
| `AgentStudioCore` | Shared workspace models, state, persistence, workspace UI, contracts used by multiple features, and the concrete `CoreAtoms` / `CoreAtomScope` typed access surface |
| `AgentStudio<Feature>` | One feature's models, state, behavior, persistence, and UI |
| `AgentStudio` | All App subfolders, lifecycle, host assembly, cross-feature composition, the non-ambient concrete root `AtomRegistry`, resources, and distribution wiring |

Core intentionally remains coarse even though it mixes domain, state,
persistence, and shared workspace UI. This avoids introducing speculative
subtargets.

SwiftPM target paths may continue pointing at the existing directories. A file
moves only when its dependencies contradict its current owner; wholesale source
tree relocation is not required.

## App Boundary

The following remain folders inside the single `AgentStudio` executable target:

- Boot
- Commands
- Coordination
- Diagnostics
- Events
- IPCComposition
- Lifecycle
- PaneAgents
- Panes
- Windows

No `AgentStudioWindows`, `AgentStudioCommands`, `AgentStudioPaneHosting`, or
similar App target is introduced.

Code coordinating multiple Features stays in App. Code that is no longer
composition-specific moves to an existing lower owner; it does not create a new
App target.

## Required Boundary Corrections

The current folders cannot become targets mechanically. The following contracts
are the minimum needed to remove known reverse edges.

```text
AgentStudio executable
  |
  +-- owns non-ambient AtomRegistry
  |      |
  |      +-- owns one CoreAtoms ------> AgentStudioCore
  |      +-- owns concrete Feature atoms and facades
  |      +-- passes exact Feature state or consumer-owned facts
  |
  +-- owns resource bundle
  |      |
  |      +-- explicit resource input -> Infrastructure, Core, Features
  |
  +-- owns PaneHostView
         |
         +-- mounts Feature views ----> Core-owned pane contract

AgentStudioCore
  |
  +-- owns CoreAtoms + CoreAtomScope
         |
         +-- typed Core lookup: KeyPath<CoreAtoms, Value>

AgentStudioInfrastructure
  |
  +-- owns generic atom primitives only
```

### State precursor

The companion
[Core Atom Scope and Explicit Feature State](../2026-07-25-core-atom-scope-feature-injection/2026-07-25-core-atom-scope-feature-injection.md)
specification is authoritative for Core atom composition, Feature-state
injection, cross-Feature state facts, state-driven persistence and pane-hosting
corrections, mutation boundaries, and state test ownership. This parent
specification owns the realized SwiftPM targets and the remaining non-state
boundary work. If the two documents conflict on state access, the reviewed
state precursor governs.

### Atom access

The executable remains the sole concrete cross-Feature `AtomRegistry` owner,
but that root is not an ambient key-path namespace.

The synchronized state contract is:

- `AgentStudioCore` owns one concrete `CoreAtoms`, one `CoreAtomScope`, and the
  typed product lookup `atom(KeyPath<CoreAtoms, Value>)`;
- Infrastructure retains only generic primitives such as `AtomValue`,
  `AtomEntityMap`, mutation contexts, and `DerivedValue`; it owns no product
  lookup and references no Core or Feature state;
- App `AtomRegistry` constructs one `CoreAtoms` plus the existing concrete
  Feature atoms and facades directly, then installs only its exact `core` in
  `CoreAtomScope`;
- the App root retains its typed default initializer inputs because constructing
  the canonical graph is its responsibility; Feature consumers receive
  canonical Feature state through required inputs without production defaults;
- `AppDelegate` accesses its existing root property; other App-owned types
  receive the exact Feature atom or facade they use;
- a Feature receives its own canonical state explicitly when needed;
- a Feature needing a sibling Feature fact receives the smallest
  consumer-owned read-only closure or snapshot supplied by App;
- canonical atom storage is `private(set)` or `private`, and callers mutate
  through named owner methods or coordinators rather than direct assignment or
  writable bindings.

The cutover leaves no lower `KeyPath<AtomRegistry, ...>`, compatibility
overload, Feature ambient scope, runtime registry, resolver, registration
table, service locator, mandatory `*FeatureState`, or universal Feature entry
point. The production-unused `@Atom`, `AtomReader`, `Derived`, and
`DerivedSelector` APIs are removed; generic `DerivedValue` remains in
Infrastructure.

### Pane hosting and persisted content

Core owns the minimal pane-content contract implemented by multiple Features,
including the interaction contract currently named `PaneMountedContent`.

The executable continues to own `PaneHostView`, host lifecycle, feature
selection, mounting, and cross-feature view composition.

The concrete pane-hosting closure named by the state precursor is App-owned:

- `PaneLeafContainer`;
- `FlatPaneStripContent`;
- `FlatTabStripContainer`;
- `SingleTabContent`;
- `ActiveTabContent`;
- `DrawerPanel`;
- `DrawerPanelOverlay`.

`TabDragPayload`, `PaneDragPayload`, `DrawerIconBarFrameKey`, and
`FlatPaneDivider` remain Core-owned, along with pure pane models, metrics,
geometry, and Feature-neutral interaction policies.

Core also owns stable persisted pane-content descriptors because workspace
persistence consumes them across features. Features own behavior and rich
runtime state. The existing persisted encoding and round-trip behavior remain
unchanged.

A minimal Bridge pane descriptor may therefore be Core-owned. The initial
design does not add a dynamic feature-registration system.

### Cross-feature coordination

Files coordinating multiple concrete Features belong in the executable.
Examples include persistence coordination across feature atoms and host views
that downcast to or construct concrete Feature content.

`WorkspaceSettingsStore` therefore becomes App-owned because it coordinates
EditorChooser, RepoExplorer, and InboxNotification preferences with the
Core-owned datastore. The ignored `EditorChooserState` input in `UIStateStore`
is removed rather than replaced. Bridge attendance supplied to RepoExplorer and
Terminal pinned-state facts supplied to InboxNotification use the
consumer-owned read-only contracts defined by the state precursor.

Pure derivation shared by Core and a Feature belongs in Core rather than being
called through a Feature view type.

### Resources

All resources and `Bundle.module` discovery remain executable-owned. The
generated `AgentStudio_AgentStudio.bundle` name and packaged location remain
unchanged.

Infrastructure, Core, and Features receive required resource URLs, roots, or
narrow loaders through explicit inputs. Lower targets must not discover the
executable resource bundle or create replacement Feature bundles.

This preserves:

- BridgeWeb assets;
- Ghostty resources and shell integration;
- terminfo;
- icons and application artwork;
- resource-dependent session configuration;
- Info.plist, entitlements, app icons, zmx packaging, signing, and release
  assembly.

### Access control

Cross-target declarations use Swift `package` access by default. `public` is
reserved for APIs intentionally consumed outside this package. The split must
not broadly promote internal declarations to `public`.

## Test Boundary

Each source target has one paired test target:

```text
AgentStudioInfrastructureTests -> AgentStudioInfrastructure
AgentStudioSharedComponentsTests -> AgentStudioSharedComponents
AgentStudioCoreTests -> AgentStudioCore
AgentStudioBridgeTests -> AgentStudioBridge
...
AgentStudioTerminalTests -> AgentStudioTerminal
```

A module test may depend on its owner and permitted lower targets. It must not
depend on:

- the `AgentStudio` executable;
- an unrelated Feature;
- the concrete root `AtomRegistry`;
- executable resources unless supplied as explicit fixture inputs.

State tests follow the concrete owner:

- the shared Core test helper lazily installs one default Core fallback on
  first use, never from a global initializer, package-wide suite trait, or
  process-startup hook; Core and Feature module tests layer task-local
  `CoreAtomScope` overrides when exact fixtures are required;
- escaped Observation, AppKit, WebKit, and other framework callbacks outside
  the override's dynamic scope resolve the process fallback;
- Feature tests construct only their Feature-owned state plus permitted Core
  fixtures;
- RepoExplorer tests supply deterministic Bridge attendance ordinals;
- InboxNotification tests supply deterministic Terminal pinned-state facts;
- an App-owned factory constructs the complete `AtomRegistry`; Swift Testing
  exit tests prove exact App production installation and setup preconditions in
  fresh child processes;
- the target-split plan must designate one package-wide test-support owner while
  SwiftPM uses its default aggregate test product, or prove separate isolated
  test products before permitting per-target installers.

The current shared test-registry seam has 112 caller files outside its helper
definition when counting `installTestAtomRegistryIfNeeded`,
`makeInstalledTestAtomRegistry`, `withTestAtomRegistry`,
`withAsyncTestAtomRegistry`, and direct `AtomScope.$override` use. The plan must
partition those callers between Core-scope fixtures and complete App-root
fixtures; this is a substantial mechanical migration, not a fixture rename.
The current partition is 54 App, 18 Core, 36 Feature, and four integration
files.

Tests requiring cross-feature composition, the root registry, application
resources, pane hosting, WebKit product integration, zmx, signing, or packaged
behavior remain executable-level integration tests.

Paired tests improve ownership, not ordinary root test selection. A normal
same-package `swift test --filter` still compiles the aggregate test product.

## Requirements

| ID | Requirement |
| --- | --- |
| TM-01 | AgentStudio remains one package with the target set defined in this spec. |
| TM-02 | `AgentStudio` remains the only App executable and owns all App subfolders and resources. |
| TM-03 | Core remains one coarse target; no App or Feature subtargets are introduced. |
| TM-04 | The target graph is acyclic; Features do not import App or other Features; Infrastructure imports no internal target. |
| TM-05 | SharedComponents retains its stateless explicit-input contract and imports only Infrastructure internally. |
| TM-06 | State modularization must satisfy the reviewed state precursor: Core owns `CoreAtoms`, `CoreAtomScope`, and `KeyPath<CoreAtoms, Value>` lookup; App owns the non-ambient concrete `AtomRegistry`; Infrastructure names no product state; Feature state and sibling facts are supplied explicitly without a resolver or mandatory aggregate. |
| TM-07 | Core owns the minimal pane-mount and persisted-content contracts shared across Features plus the four Core declarations named above; the seven concrete Feature-composing pane-host files are App-owned. |
| TM-08 | Cross-Feature coordination, including settings persistence and concrete state wiring, remains App-owned instead of creating a plugin, resolver, or dependency-injection layer. |
| TM-09 | Resources remain executable-owned and lower modules receive resource locations explicitly. |
| TM-10 | IPC, GhosttyKit, zmx, BridgeWeb, persistence encodings, signing, debug/beta identity, and release behavior remain unchanged. |
| TM-11 | Cross-target APIs prefer `package` access and receive no blanket `public` promotion. |
| TM-12 | Every source target has a paired dependency-clean module test target; state tests construct only owner state and permitted lower fixtures using one package-test-process Core fallback plus task-local overrides, while isolated exit tests and executable integration prove production setup, the complete registry, and real cross-Feature wiring. |
| TM-13 | Architecture documentation and lint agree with the compiler-visible graph. |
| TM-14 | No performance improvement is claimed without representative before/after measurements, and representative hot-read and product-path performance must not regress beyond the repository's accepted comparator threshold across the realized module boundaries. |

## Tradeoffs

Gain:

- compiler-enforced ownership;
- a real SwiftPM target DAG without multiple packages;
- Feature-local source and test dependency closures;
- limited structural churn.

Cost:

- explicit imports and a substantial `package` access-annotation inventory
  across the existing internal API; this is a dominant mechanical cost, not
  incidental cleanup;
- relocation of known reverse-edge files;
- one Core ambient atom graph, explicit App-to-Feature state wiring, and
  explicit resource inputs;
- owner-partitioning the shared state test fixture across 112 current caller
  files;
- moving seven concrete pane-host files to App while extracting four
  Feature-neutral declarations back to Core;
- aggregate root test compilation remains;
- Core remains a high-fan-out dependency.

The coarse Core fan-out is accepted. It becomes a separate design concern only
if measurements show it dominates downstream rebuild time or cannot remain
acyclic.

## Alternatives Rejected

- Folder/test reorganization alone: no compiler or build boundary.
- Multiple local packages: unnecessary product/public-API and CI cost.
- Granular Core or App targets: excessive initial churn.
- Feature resource bundles: changes packaging and runtime lookup.
- Dynamic Feature/plugin registration: solves a broader problem than required.
- Tuist, Bazel, remote caching, or selective-testing infrastructure: outside
  this ownership change.

## Security and Runtime Invariants

This design adds no authentication, authorization, parsing, network, subprocess,
secret, or external-service surface.

Existing IPC authority, zmx isolation, resource integrity, signing,
notarization, debug/beta identity, and release-channel separation remain
invariants. Changing them exceeds this spec.

## Proof Expectations

The implementation plan must provide:

- static proof of the acyclic target/import graph;
- static proof that Infrastructure names no product state, Core names no
  Feature state, Features name no sibling Feature state, and lower targets
  contain no `KeyPath<AtomRegistry, ...>`;
- static proof that canonical Core and Feature atom storage exposes no external
  setter or writable binding;
- architecture-lint good/bad fixtures that scope the canonical-mutation rule to
  atom-owner classes under `State/MainActor/Atoms`, excluding value snapshots,
  derived readers, and unrelated observable controllers;
- representative target-level build proof;
- module-test proof without App or sibling Feature dependencies, including the
  112-caller test-fixture partition;
- executable integration proof for exact Core/Feature atom identity,
  cross-Feature state facts, settings persistence, pane hosting, and resource
  injection;
- permanent Swift Testing exit-test proof that Core scope access before
  production setup fails, exact App Core installation succeeds, and a second
  setup fails in a fresh child process;
- packaged-product proof for resources, BridgeWeb, Ghostty, terminfo, signing,
  debug/beta identity, and release layout;
- before/after measurements before any performance claim;
- equivalent release-configuration performance proof showing no regression
  beyond the repository's accepted comparator threshold across the realized
  module boundaries.

No proof layer may be weakened or relabeled to demonstrate a speed improvement.

## Explicit Non-Goals

- Core, App, or Feature subtargets.
- Additional packages or repositories.
- Feature resource bundles.
- A new plugin system or general dependency-injection framework.
- A runtime atom resolver, registration table, Feature ambient scope,
  mandatory `*FeatureState`, or universal Feature entry point.
- An app-wide rewrite of non-atom controller or local UI state.
- CI/build-system redesign or caching infrastructure.
- Persisted schema or product behavior changes.
- IPC, vendor, signing, notarization, or release redesign.
- Implementation order, commits, worker assignments, or exact commands.

## Planning Gate and Remaining Review Work

The atom/state text is synchronized, but its accepted review findings require
renewed review before that boundary is closed. The bounded precursor may be
planned and implemented independently after its own review passes. This parent
modularization specification remains a revised draft and is not planning-ready.
Before implementation planning it must independently resolve the remaining
accepted non-atom review findings:

- command and shortcut vocabulary currently owned under App but consumed by
  Core and Features;
- existing sibling-Feature capability edges;
- Infrastructure diagnostics that currently depend on Bridge telemetry types;
- test-lane build and selection parity after test redistribution.

The later plan must also inventory the substantial `package` annotation
cutover, replicate Swift 6 language settings per target and test target, and
measure release/runtime behavior across the realized module boundaries.
