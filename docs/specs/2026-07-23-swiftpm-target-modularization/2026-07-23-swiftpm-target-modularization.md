# AgentStudio Coarse SwiftPM Target Modularization

Date: 2026-07-23
Updated: 2026-07-27
Status: accepted; corrected ownership synchronized for plan update
Source version: `fix-tests` precursor at `daadf1a1135095749bbb4404008c6b94161ac915`

## Decision

Keep one Swift package and create:

- one `AgentStudioInfrastructure` target;
- one `AgentStudioSharedComponents` target;
- one coarse `AgentStudioCore` target;
- one target for each existing feature;
- the existing `AgentStudio` executable as the only App/composition target;
- one test-only `AgentStudioTestSupport` regular target shared by the package
  test process;
- one paired test target for every product source target;
- executable-level integration tests for assembled-app behavior.

`AgentStudio` continues to own every `App/**` subfolder, `main.swift`,
`AtomRegistry.swift`, and all resources. App subfolders do not become targets.
Core does not split into domain, state, persistence, or UI targets.

This creates compiler-enforced ownership boundaries. It does not promise faster
builds or tests until the resulting graph is measured.

The obsolete Worktrunk integration is removed rather than assigned to a target.
Its discovery, create, and remove operations have no production callers; the
only production behavior is a startup installation offer. Future worktree
product work uses the existing `agentstudio-git` library, but replacement
worktree UX is outside this modularization.

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
  behavior except for the explicitly retired Worktrunk startup offer;
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
target. `AgentStudioTestSupport` is outside the product DAG: it depends only on
`AgentStudioCore`, is imported only by test targets, and is not linked into the
executable.

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
| `AgentStudioInfrastructure` | Domain-agnostic utilities, generic integrations, shared presentation tokens/policies, generic atom primitives that name no product state, generic filesystem authority and runtime-delivery reporting, primitive trace storage, and the narrow telemetry wire schemas validated by its exporters |
| `AgentStudioSharedComponents` | Stateless reusable UI and reusable interaction primitives |
| `AgentStudioCore` | Shared workspace models, state, persistence, workspace UI, product-specific pane-focus decisions, contracts used by multiple features, and the concrete `CoreAtoms` / `CoreAtomScope` typed access surface |
| `AgentStudio<Feature>` | One feature's models, state, behavior, persistence, and UI |
| `AgentStudio` | All App subfolders, lifecycle, host assembly, cross-feature composition, the non-ambient concrete root `AtomRegistry`, resources, and distribution wiring |
| `AgentStudioTestSupport` | Test-only Core fixtures, the single process-wide Core fallback installer, and scoped Core override helpers; no product behavior or App-root fixture |

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
  |      |
  |      +-- typed Core lookup: KeyPath<CoreAtoms, Value>
  |
  +-- owns shared command, shortcut, and App-event vocabulary
  +-- owns Feature-free AppCommandDispatching contract

AgentStudioInfrastructure
  |
  +-- owns generic atom primitives
  +-- owns generic filesystem authority and runtime-delivery reporting
  +-- owns primitive trace storage
  +-- owns narrow telemetry wire schemas validated by its exporters

AgentStudio executable
  |
  +-- owns Core-model -> primitive-trace projection
  +-- owns concrete PaneFocus execution effects

Package test process
  |
  +-- paired test targets ------> AgentStudioTestSupport
                                     |
                                     +-- AgentStudioCore
```

### Command, shortcut, and event vocabulary

Core owns the command and shortcut vocabulary consumed by App and Features:

- `AppCommand`, `SearchItemType`, and Feature-free `AppCommandSpec`
  presentation metadata: shortcut, label, icon, help, target applicability,
  focus visibility, grouping, priority, and command-bar visibility;
- `AppShortcut`, `AppShortcutSpec`, `ShortcutTrigger`, `ShortcutContext`, and
  the shared shortcut-dispatch policy;
- `AppEvent` and `AppEventBus`, which form a shared runtime event contract.

Core also owns one `@MainActor AppCommandDispatching` protocol. It is the
Feature-facing command seam and covers only the operations Features already
need:

- dispatch a contextual or UUID-targeted `AppCommand`;
- query contextual or targeted availability;
- dispatch explicit pane-move operations;
- query the Core-owned `BridgePaneCommandTarget`.

Features read the Feature-free presentation catalog directly from the
Core-owned static `AppCommand` definitions; catalog lookup is not part of the
dispatcher protocol.

The App-owned concrete `AppCommandDispatcher` conforms to this protocol. App
injects `any AppCommandDispatching` into CommandBar, Terminal, RepoExplorer,
and InboxNotification entry points that currently reference
`AppCommandDispatcher` or `.shared`; no Feature references the concrete
dispatcher singleton after the cutover.

App owns execution and host adaptation:

- `WorkspaceCommandHandling` and `ShellCommandHandling`;
- `AppCommandExecutionRequest`, `AppCommandExecutionContext`, and
  `AppCommandExecutionArguments`;
- decoding raw IPC arguments into concrete Feature-owned value types;
- AppKit menu/key-binding adaptation and concrete command dispatch.

IPC metadata is not part of Core's `AppCommandSpec`. App owns a separate
`AppCommandIPCSpec` overlay keyed by `AppCommand`, containing
`AppCommandIPCExposure`, `[IPCCommandArgumentSchema]`, argument decoding, and
Feature enum-derived allowed values. Feature-free presentation for enum-backed
commands is selected by the `AppCommand` case and contains no concrete Feature
enum value.

The Core protocol deliberately cannot carry `AppCommandExecutionRequest` or a
Feature-owned enum. RepoExplorer receives consumer-owned typed callbacks for
visibility mode, sort order, and refresh. InboxNotification receives
consumer-owned typed callbacks for row-state filter and content mode. App
implements those callbacks by constructing its Feature-typed execution
requests. This preserves compile-time typing without a command container,
resolver, service locator, or generalized dependency-injection system.

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

### Sibling-Feature capability seams

Features do not import sibling Features. The known capability edges close by
moving only their shared seam to an existing lower owner:

- the generic fuzzy-match primitive used by CommandBar and Webview belongs in
  Infrastructure; CommandBar retains its feature-specific search documents,
  sessions, filtering, and ranking;
- the default `WebPage.DialogPresenting` conformance used by Bridge and Webview
  belongs in Infrastructure; each Feature retains its navigation and product
  behavior;
- `BridgePaneCommandCandidate`, `BridgePaneCommandResolution`,
  `BridgePaneCommandTarget`, and the pure reuse-selection resolver belong in
  Core because they select among Core-owned pane identities for App,
  CommandBar, and RepoExplorer. Its contextual label mapping uses the
  Core-owned `AppCommand` vocabulary; the Core seam must not name the
  Bridge-owned `BridgeProductSurface`.

These corrections introduce no Feature registry, capability broker, or new
shared target.

### Residual Infrastructure and Core ownership

Infrastructure must compile without naming a Core product type. The known
reverse edges close under existing owners:

- `RuntimeDeliveryPerformanceReporter` is generic delivery instrumentation and
  belongs in Infrastructure;
- `FilesystemPathCanonicalizer`, `FilesystemSourceConfiguration`, and
  `FilesystemSourceTypes` are dependency-free filesystem authority primitives
  and belong in Infrastructure, allowing the existing scanner and executor
  closure to remain there;
- the primitive trace-identity store remains in Infrastructure, while the
  conversion from Core `Repo`, `Pane`, and enrichment models into primitive
  trace identities belongs in App.

The complete `Infrastructure/PaneFocus` surface models Agent Studio workspace
focus: terminal, Webview, Bridge, and CodeViewer focus, drawer selection,
management mode, command routing, and keyboard decisions. Those pure
product-specific decisions belong in Core. App retains `PaneFocusExecutor` and
the concrete AppKit, window, responder, and Feature-runtime effects it applies.
No focus target, protocol bridge, or generalized effects layer is introduced.

Core-to-Feature reverse edges close without moving Feature types into Core:

- Core calls the existing Core-owned `GitBranchStatus.status` directly;
- Core persistence stores validated raw tokens instead of RepoExplorer or
  Inbox enums;
- App-owned `WorkspaceSettingsStore` maps those tokens to concrete Feature
  enums and invokes named Feature atom mutations;
- Inbox owns conversion between its claim-lane enum and Core storage tokens.

### Retired Worktrunk integration

The Worktrunk integration is deleted, not moved:

- remove `Infrastructure/WorktrunkService.swift` and its two dedicated test
  files;
- remove the `.checkWorktrunkDependency` boot phase and dispatch;
- remove the AppDelegate Homebrew installation alert, AppleScript invocation,
  and copy-command path;
- remove architecture documentation and lint fixtures that claim Worktrunk is
  an owned runtime dependency.

There is no manifest or Homebrew application dependency to replace. Agent
Studio does not uninstall a user-installed `worktrunk` formula. Existing
`agentstudio-git` worktree discovery, creation, removal, pruning, locking, and
unlocking are the authority for future product work; this change adds no new
worktree operation or wiring.

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

### Telemetry wire schema

Infrastructure owns the controlled telemetry wire vocabulary required by its
OTLP projection and metrics exporter:

- `BridgeTelemetryPlane`;
- `BridgeTelemetryPriority`;
- `BridgeTelemetrySlice`;
- `BridgeTelemetryDropReason`;
- one immutable `BridgeTelemetryWireSchema`.

`BridgeTelemetryWireSchema` is the single owner of raw event names, required
attribute keys, allowed controlled string values, allowed numeric and Boolean
keys, and event-specific phase/plane/priority/slice/transport expectations. Its
Feature-free validation entry point accepts only the event name, optional
duration, and string/numeric/Boolean attribute dictionaries and returns an
optional `BridgeTelemetryDropReason`; it does not accept
`BridgeTelemetrySample`, scope, trace context, or a runtime object. Its nested
event-expectation and attribute-key value types reference only Swift primitives
and the four Infrastructure-owned wire enums. Both Infrastructure projection
and Bridge validation consume that schema, so the current raw-string allowlists
are not duplicated.

Bridge retains `BridgeTelemetryEventValidator`,
`BridgeTelemetryEventValidationResult`, `BridgeTelemetrySample`,
`BridgeTelemetryScope`, `BridgeTelemetryScopeGate`, `BridgeTraceContext`, and
all runtime enablement, admission, aggregation, orchestration, UI, and product
state. The validator first applies the Bridge-owned scope gate, then validates
the sample's wire fields against `BridgeTelemetryWireSchema`.

This split removes the Infrastructure-to-Bridge edge without moving
`AgentStudioTraceRuntime` or Bridge runtime behavior into Infrastructure and
without introducing an observability target or injected validator registry.

### Access control

Cross-target declarations use Swift `package` access by default. `public` is
reserved for APIs intentionally consumed outside this package. The split must
not broadly promote internal declarations to `public`.

### Delivery boundary

Move-heavy work has one required history boundary: create the exact move
inventory, perform only `git mv` operations, verify the move-only diff reports
`R100`, and commit it before any import, access-control, manifest, or semantic
edit. Worktrunk deletion is not a move and therefore lands with later semantic
changes. Other implementation ordering belongs to the plan.

## Test Boundary

Each product source target has one paired test target:

```text
AgentStudioInfrastructureTests -> AgentStudioInfrastructure
AgentStudioSharedComponentsTests -> AgentStudioSharedComponents
AgentStudioCoreTests -> AgentStudioCore
AgentStudioBridgeTests -> AgentStudioBridge
...
AgentStudioTerminalTests -> AgentStudioTerminal
```

`AgentStudioTestSupport` is a test-only regular target, not a product source
target, and therefore is the sole exception to paired-test-target symmetry. It
depends only on `AgentStudioCore` and owns:

- the shared default `CoreAtoms` fixture;
- the single process-wide fallback-installation guard;
- synchronous and asynchronous task-local Core override helpers.

Core tests, Feature tests, and executable integration tests that use Core scope
may depend on `AgentStudioTestSupport`; Infrastructure and SharedComponents
tests do not. No paired test target owns or copies another fallback installer.
The default aggregate SwiftPM test product remains mandatory; isolated
per-target test products are not part of this design.

A module test may depend on its owner and permitted lower targets. A Core-scope
consumer may also depend on `AgentStudioTestSupport`. It must not depend on:

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
  fresh child processes.

The current shared test-registry seam has 114 caller files outside its helper
definition when counting `installTestAtomRegistryIfNeeded`,
`makeInstalledTestAtomRegistry`, `withTestAtomRegistry`,
`withAsyncTestAtomRegistry`, and direct `AtomScope.$override` use. The plan must
partition those callers between Core-scope fixtures and complete App-root
fixtures; this is a substantial mechanical migration, not a fixture rename.
The current partition is 55 App, 18 Core, 37 Feature, and four integration
files.

Tests requiring cross-feature composition, the root registry, application
resources, pane hosting, WebKit product integration, zmx, signing, or packaged
behavior remain executable-level integration tests.

Paired tests improve ownership, not ordinary root test selection. A normal
same-package `swift test --filter` still compiles the aggregate test product.

## Requirements

| ID | Requirement |
| --- | --- |
| TM-01 | AgentStudio remains one package with the product target set defined in this spec plus the test-only `AgentStudioTestSupport` target. |
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
| TM-12 | Every product source target has a paired dependency-clean module test target. Core-scope test consumers may import the test-only `AgentStudioTestSupport`, which is the sole owner of the package-test-process Core fallback and task-local Core overrides; Infrastructure and SharedComponents tests do not import it. Isolated exit tests and executable integration prove production setup, the complete registry, and real cross-Feature wiring. |
| TM-13 | Architecture documentation and lint agree with the compiler-visible graph. |
| TM-14 | No performance improvement is claimed. The existing debug sidebar baseline/compare workload must show no regression beyond its accepted comparator threshold across the realized module boundaries, and the release/package build must pass. Debug workload evidence is not relabeled as release-runtime performance evidence, and no release-runtime speed claim is made. |
| TM-15 | Core owns shared command, shortcut, dispatch-policy, App-event, Feature-free presentation, and `AppCommandDispatching` vocabulary; App injects its concrete dispatcher, owns the IPC metadata overlay and Feature-typed execution, and supplies narrow typed Feature callbacks. |
| TM-16 | The known sibling-Feature edges close through the three existing-owner seams named in this spec, without a Feature dependency, registry, broker, or new target. |
| TM-17 | Infrastructure owns the complete Bridge wire vocabulary and one immutable schema consumed by exporters and Bridge validation; Bridge retains the validator, sample/scope/trace-context closure, runtime admission, and product state. |
| TM-18 | Existing test-lane behavior remains equivalent after redistribution: the aggregate prebuild covers every paired test target, suite-name filters select the same WebKit/E2E/zmx lanes, and `--skip-build` cannot silently omit a test target. |
| TM-19 | Generic filesystem authority, runtime-delivery reporting, and primitive trace storage belong to Infrastructure; Core-model trace projection belongs to App; all product-specific PaneFocus decisions belong to Core while App retains concrete execution effects. |
| TM-20 | The unused Worktrunk service, dedicated tests, startup dependency phase, installation prompt, and ownership documentation are removed without replacement wiring or uninstalling user software. |

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
- owner-partitioning the shared state test fixture across 114 current caller
  files;
- one test-only support target so aggregate test execution has exactly one Core
  fallback installer;
- moving seven concrete pane-host files to App while extracting four
  Feature-neutral declarations back to Core;
- aggregate root test compilation remains;
- Core remains a high-fan-out dependency.
- the obsolete Worktrunk startup installation offer is intentionally removed.

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
secret, or external-service surface. Removing Worktrunk also removes its unused
CLI wrapper and startup Homebrew/AppleScript installation surface.

Existing IPC authority, zmx isolation, resource integrity, signing,
notarization, debug/beta identity, and release-channel separation remain
invariants. Changing them exceeds this spec.

## Proof Expectations

The implementation plan must provide:

- static proof of the acyclic target/import graph;
- static proof that Infrastructure names no product state, Core names no
  Feature state, Features name no sibling Feature state, and lower targets
  contain no `KeyPath<AtomRegistry, ...>`;
- static proof that the generic filesystem and runtime-reporting primitives are
  Infrastructure-owned, Core-model trace projection is App-owned, Core owns the
  complete pure PaneFocus decision surface, and concrete focus execution stays
  in App;
- static proof that no Worktrunk service, boot phase, installation prompt,
  dedicated test, architecture claim, or production `wt`/Git CLI fallback
  remains;
- static proof that Core command vocabulary and presentation contain no IPC
  schema or concrete Feature-owned type, Features contain no concrete
  `AppCommandDispatcher` reference, and App retains IPC metadata plus concrete
  command execution;
- static proof that Infrastructure telemetry types recursively reference no
  Bridge-owned type, the OTLP projection uses `BridgeTelemetryWireSchema`, and
  Bridge retains the complete validator/sample/scope/trace-context runtime
  closure;
- static proof that canonical Core and Feature atom storage exposes no external
  setter or writable binding;
- architecture-lint good/bad fixtures that scope the canonical-mutation rule to
  atom-owner classes under `State/MainActor/Atoms`, excluding value snapshots,
  derived readers, and unrelated observable controllers;
- representative target-level build proof;
- module-test proof without App or sibling Feature dependencies, including the
  114-caller test-fixture partition and exactly one reachable fallback
  installer in `AgentStudioTestSupport`;
- test-lane parity proof that the aggregate prebuild includes every redistributed
  test target and the existing suite-name filters execute the same serialized
  and non-serialized lanes without silent under-selection;
- executable integration proof for exact Core/Feature atom identity,
  cross-Feature state facts, settings persistence, pane hosting, and resource
  injection;
- permanent Swift Testing exit-test proof that Core scope access before
  production setup fails, exact App Core installation succeeds, and a second
  setup fails in a fresh child process;
- packaged-product proof for resources, BridgeWeb, Ghostty, terminfo, signing,
  debug/beta identity, and release layout;
- one before/after comparison through the existing debug sidebar performance
  workload, using the same configuration and accepted comparator threshold;
- a successful release/package build, reported separately from the debug
  runtime comparison without a release-runtime performance claim.

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
- Persisted schema or product behavior changes beyond the explicitly retired
  Worktrunk startup offer.
- Replacement Worktrunk UX or migration of unrelated worktree behavior.
- IPC, vendor, signing, notarization, or release redesign.
- Implementation order, worker assignments, or exact commands beyond the
  required move-only `R100` commit before semantic edits.

## Planning Readiness

The known state and non-state ownership decisions are explicit, the single
focused review cycle has been incorporated, and the user-concurred ownership
correction is synchronized. The plan may be updated without reopening target
granularity, Core decomposition, state ownership, command dispatch, telemetry
ownership, PaneFocus ownership, Worktrunk removal, or package-wide test-support
ownership.

The implementation plan must then inventory the substantial `package`
annotation cutover, replicate Swift 6 language settings per target and test
target, map every source and test file to its target, and measure
release/runtime behavior across the realized module boundaries.
