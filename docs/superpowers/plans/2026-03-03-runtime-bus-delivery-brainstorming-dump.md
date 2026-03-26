# NOT A PLAN - BRAINSTORMING ONLY

# Runtime Bus Delivery Brainstorming Dump

Date: 2026-03-03
Status: Brainstorming only. This is a scratchpad, not an implementation plan.
Purpose: Capture a code-grounded mental model of the current runtime bus, the real problems in the current design, and the smaller set of solution shapes that still seem worth discussing.

## Most Important Points

Ranked for architectural importance:

1. Keep command plane and fact plane separate.
   - Tell actors to do work through direct async methods.
   - Tell the rest of the system what happened through fact emission on the bus.
   - Do not turn the bus into a command router.

2. Keep concrete types at the composition root.
   - Construct concrete actors and pipelines in app bootstrap.
   - Pass protocol-shaped capability slices to everyone else.
   - Do not add escape hatches back to the concrete type.

3. Fix the current mismatch between desired critical delivery and actual buffering.
   - The code currently uses bounded newest buffering for important global consumers.
   - Any future "critical" lane is not credible unless its delivery and recovery semantics are explicit.

4. Do not blur pane-local reliability with app-wide bus reliability.
   - Pane runtimes currently have stronger local replay semantics than the app-wide bus.
   - A good design should name that difference clearly instead of pretending one model covers everything.

5. Keep the next step small.
   - The most grounded starting point is tightening policy and boundaries around the existing bus.
   - New actors or split buses should only happen if the simpler path proves insufficient.

## What This Document Is

- A discussion artifact.
- Grounded in the current codebase, not a greenfield redesign.
- Future ideas are allowed, but they should be labeled clearly.

## Ground Rules

- The bus carries facts, not commands.
- Stores mutate through their own methods.
- Coordinators sequence cross-store work; they do not own domain state.
- If an actor needs to be told to do something, use a direct async command method on that actor.
- If the rest of the system needs to learn that something happened, emit a fact on the bus.

## Command Plane vs Fact Plane

This distinction still looks right in the codebase.

```text
Need an actor to do work now?
  -> direct async method call

Need other parts of the system to react to a completed fact?
  -> emit a fact on the bus
```

Current actor command surfaces already follow this model:

- `FilesystemActor.register(worktreeId:repoId:rootPath:)`
- `FilesystemActor.unregister(worktreeId:)`
- `FilesystemActor.updateWatchedFolders(_:)`
- `FilesystemActor.setActivity(worktreeId:isActiveInApp:)`
- `GitWorkingDirectoryProjector.start()`
- `GitWorkingDirectoryProjector.shutdown()`
- `ForgeActor.start()`
- `ForgeActor.register(repo:remote:)`
- `ForgeActor.unregister(repo:)`
- `ForgeActor.refresh(repo:correlationId:)`
- `ForgeActor.shutdown()`

So yes: actors that need to be told to do something should expose direct async command methods. The important limit is that those commands stay direct and request/response-ish, while the bus stays facts-only.

## Keep The Concrete Actor From Leaking

If we lean further into actor command surfaces, we also need to keep the concrete type from leaking everywhere. The current code already points in this direction.

Use these three practices together:

### 1. Store narrow protocol-shaped dependencies

Fields, constructor parameters, and long-lived properties should prefer protocol slices over concrete types.

Good shape:

```swift
private let filesystemSource: any PaneCoordinatorFilesystemSourceManaging
```

Leaky shape:

```swift
private let filesystemPipeline: FilesystemGitPipeline
```

Code-grounded example:

- `PaneCoordinator` already stores `filesystemSource` as `any PaneCoordinatorFilesystemSourceManaging`.

### 2. Construct concrete types only at the composition root

The composition root can know the concrete type. Most other code should not.

Current code-grounded picture:

```text
AppDelegate boot
  |
  +-> make FilesystemGitPipeline
  |
  +-> pass to PaneCoordinator as PaneCoordinatorFilesystemSourceManaging
  +-> keep using it concretely for some boot chaining / scope plumbing
```

That split is useful because one concrete object can implement multiple capabilities, while each consumer only sees the slice it needs.

This also highlights a current boundary smell:

- `PaneCoordinator` already consumes a protocol slice.
- `AppDelegate` still stores and threads `FilesystemGitPipeline` concretely during boot.

That may be acceptable at the composition root, but it should stay there.

### 3. Do not add convenience escape hatches back to the concrete type

Avoid patterns like:

```swift
var pipeline: FilesystemGitPipeline
var actor: FilesystemActor
func asConcretePipeline() -> FilesystemGitPipeline
```

Those undo the boundary immediately.

Practical rule:

- One concrete object can implement multiple protocols.
- Each consumer should receive only the protocol slice it needs.
- The composition root can know the concrete type.
- Everyone else should not.

## Swift 6.2 Grounding

This discussion should stay anchored to the Swift 6.2 concurrency model the project is already using.

- Boundary work lives behind `actor`s.
- UI and store mutation live on `@MainActor`.
- Event transport is `AsyncStream`, not Combine or NotificationCenter for new plumbing.
- `EventBus` fan-out is actor-isolated and uses per-subscriber `AsyncStream` continuations.
- `PaneRuntimeEventChannel.emit(...)` uses `Task { ... }` intentionally to keep pane-local emit paths responsive. That is unstructured work and should remain an explicit tradeoff, not an invisible assumption.

Primary grounding:

- Swift 6.2 supports the actor-isolation model the project is already relying on.
- Apple docs define `AsyncStream` and `AsyncStream.Continuation.BufferingPolicy.bufferingNewest(_:)`.
- The project's own architecture docs already standardize on Swift 6.2, `@MainActor`, actors, and `AsyncStream`.

## Current Code Reality

### 1. There is not one single emit path

The code currently has multiple emit shapes:

```text
Pane bus-posting runtime:
  local replay + local subscribers
  then Task { await paneEventBus.post(envelope) }

System/worktree actor:
  await runtimeBus.post(envelope)

Legacy runtime bridge:
  await paneEventBus.post(envelope)
```

So the "local lane then global lane" model is true for pane runtimes using `PaneRuntimeEventChannel`, but not for every runtime bus producer.

### 2. Current global consumers are still lossy under pressure

Important current-state fact:

- `EventBus.subscribe(...)` defaults to `.bufferingNewest(256)`.
- `PaneCoordinator` and `WorkspaceCacheCoordinator` subscribe with that default.
- `GitWorkingDirectoryProjector` and `ForgeActor` also subscribe with bounded newest buffering.

So important global consumers can currently drop events under pressure. That is part of the actual baseline.

### 3. Current classification is simpler than the brainstorm lanes

Today:

- Every `RuntimeEnvelope.system` is `.critical`.
- Every `RuntimeEnvelope.worktree` is `.critical`.
- Only `RuntimeEnvelope.pane` currently distinguishes `.critical` vs `.lossy(...)`.

So any `L1 / L2 / L3` discussion below is future-oriented. It is a design change, not just clearer naming for the current code.

### 4. Current replay semantics are split

Pane-local replay already has gap-aware semantics:

- `EventReplayBuffer.eventsSince(seq:)`
- `ReplayResult.gapDetected`

App-wide bus replay does not:

- `EventBus` can replay a subscribe-time snapshot.
- `EventBus` does not currently expose `eventsSince`, `nextSeq`, or `gapDetected`.

So any future "critical lane with reconcile on gap" would require new app-wide recovery semantics. That does not exist today.

## Current Emitted Envelope Shapes

This section is intentionally about actual bus shapes, not desired future lanes.

### RuntimeEnvelope.system

Observed / code-grounded:

- `topology.repoDiscovered`
- `topology.repoRemoved`
- `topology.worktreeRegistered`
- `topology.worktreeUnregistered`

Contract surface exists, but was not re-verified here as active traffic:

- `appLifecycle.*`
- `focusChanged.*`
- `configChanged.*`

### RuntimeEnvelope.worktree

Observed / code-grounded:

- `filesystem.filesChanged`
- `gitWorkingDirectory.snapshotChanged`
- `gitWorkingDirectory.branchChanged`
- `gitWorkingDirectory.originChanged`
- `gitWorkingDirectory.worktreeDiscovered`
- `gitWorkingDirectory.worktreeRemoved`
- `gitWorkingDirectory.diffAvailable`
- `forge.pullRequestCountsChanged`
- `forge.checksUpdated`
- `forge.refreshFailed`
- `forge.rateLimited`

Important shape corrections:

- `FilesystemEvent.worktreeRegistered` and `FilesystemEvent.worktreeUnregistered` are emitted onto the bus as `RuntimeEnvelope.system(.topology(...))`.
- `FilesystemEvent.gitSnapshotChanged`, `.branchChanged`, and `.diffAvailable` are remapped into `WorktreeScopedEvent.gitWorkingDirectory(...)` before posting.

### RuntimeEnvelope.pane

Observed / code-grounded contract surface:

- `lifecycle.*`
- `terminal.*`
- `browser.*`
- `diff.*`
- `editor.*`
- `plugin(kind:event)`
- `filesystem.*`
- `artifact.*`
- `security.*`
- `error.*`

Current pane-only lossy examples:

- `terminal.scrollbarChanged`
- `browser.consoleMessage`
- `editor.diagnosticsUpdated`

## What Still Feels Wrong In The Current Design

These feel like the real problems worth discussing:

1. The architecture prose says critical subscribers should be unbounded, but the current implementation uses bounded newest buffering for the main critical consumers.
2. Pane-local replay has better recovery semantics than the app-wide bus.
3. The pane-runtime path and the system/worktree actor paths do not share the same delivery model.
4. The code and docs have drifted enough that it is easy to mix current behavior with desired future semantics.
5. Some boundaries are already protocol-shaped, but the composition-root-only concrete ownership rule is not stated clearly enough.

## Proposed Lane Model (Future Discussion Only)

This is a design sketch, not current implementation.
It applies to fact-plane bus traffic, not to direct actor command methods.

```text
L0 Local Immediate
  - pane-local replay + pane-local subscribers
  - strict per-runtime ordering
  - protects pane responsiveness

L1 Global Critical
  - facts that must converge globally
  - should not silently diverge
  - would need explicit recovery support

L2 Global Coalesced
  - latest-wins global state
  - bounded and keyed
  - acceptable only when newer state subsumes older state

L3 Global Telemetry
  - observability/debug/high-volume noise
  - intentionally lossy
```

## Proposed Lane Assignments Worth Discussing

These are intentionally future-facing.

### Candidate `L1` facts

- `topology.repoDiscovered`
- `topology.repoRemoved`
- `topology.worktreeRegistered`
- `topology.worktreeUnregistered`
- `gitWorkingDirectory.branchChanged`
- `gitWorkingDirectory.originChanged`
- `gitWorkingDirectory.worktreeDiscovered`
- `gitWorkingDirectory.worktreeRemoved`
- `forge.rateLimited`
- `pane.lifecycle.*`
- `pane.artifact.*`
- `pane.security.*`
- `pane.error.*`

### Candidate `L2` facts

- `filesystem.filesChanged`
- `gitWorkingDirectory.snapshotChanged`
- `gitWorkingDirectory.diffAvailable`
- `forge.pullRequestCountsChanged`
- `forge.checksUpdated`
- `forge.refreshFailed`
- maybe `appLifecycle.tabSwitched`
- maybe `focusChanged.*`

### Candidate `L3` facts

- `terminal.scrollbarChanged`
- `browser.consoleMessage`
- `editor.diagnosticsUpdated`
- any future analytics-only or debug-only traffic

## Solution Shapes That Still Seem Worth Talking About

Everything below is meant to stay close to the current architecture.

### Option A: Tighten the current model without adding a new actor

Shape:

- Keep one app-wide `EventBus`.
- Make subscriber buffering choices explicit instead of default-driven.
- Decide which consumers are truly allowed to be lossy.
- Add app-wide gap/reconcile semantics if we want critical lanes to mean anything stronger than today.
- Keep dependencies protocol-shaped outside the composition root.
- Keep actor commands direct; do not route commands through the bus.

Why it still earns discussion:

- Lowest structural risk.
- Best fit if the main problem is policy drift and doc drift.
- Preserves the current mental model.

Main downside:

- Reliability logic stays somewhat distributed.

### Option B: Add a delivery outbox actor for global posting

Shape:

- Keep direct actor commands.
- Keep facts on the bus.
- Add one actor responsible only for fact delivery policy, queueing, and visibility into lag and drops.
- Most plausible first target is pane-originated global posting, because that is where local-vs-global semantics already differ today.
- If introduced, expose it through narrow protocols rather than letting the concrete delivery actor leak everywhere.

Why it still earns discussion:

- Centralizes fact-delivery reliability without turning the bus into a command bus.
- Lets pane-local responsiveness stay fast while giving the global path stronger semantics.

Main downside:

- Adds a new moving part and another place where semantics can sprawl.

### Option C: Split critical and telemetry buses only if pressure proves it

Shape:

- Keep one critical fact bus.
- Move obviously lossy fact-plane observability traffic onto a separate channel.
- Keep actor commands direct and separate.

Why it still earns discussion:

- Clean isolation if telemetry pressure turns out to be the real source of pain.

Main downside:

- More wiring, more subscription surfaces, and harder correlation.
- Probably premature unless metrics show one noisy class of events is actually harming important consumers.

### Option that currently feels least earned

- A large reusable "full lane runtime composable" does not yet feel justified.
- It risks building a framework before the real boundaries are stable.
- It also risks hiding the distinction between direct actor commands and fact-plane delivery.

## Recommendation For Discussion Order

This still seems like the right order:

1. Decide whether we actually want stronger guarantees for global critical consumers, or just clearer naming.
2. Decide whether the first fix is policy-only (`Option A`) or a new delivery layer (`Option B`).
3. Only consider split buses (`Option C`) if metrics show telemetry pressure is the real problem.

## Questions That Matter

- For global critical facts, is "recoverable by reconcile" enough, or do we want "never silently dropped" as the target?
- Should the first improvement apply only to pane-originated global posting, or to all bus producers?
- Which current subscribers are actually allowed to be lossy?
- Are `forge.refreshFailed` and similar status events product-state important, or mostly observability?
- Is the bigger problem drop risk, or the fact that the current mental model is too easy to misstate?
- Where do we want to draw the line for "composition root may know the concrete type, everyone else gets a protocol slice"?

## Code Anchors

- `Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeCore.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeMetadata.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Sources/ForgeActor.swift`
- `Sources/AgentStudio/App/PaneCoordinator.swift`
- `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`

## Swift 6.2 Reference Anchors

- `https://developer.apple.com/documentation/swift/asyncstream`
- `https://developer.apple.com/documentation/swift/asyncstream/continuation/bufferingpolicy/bufferingnewest(_:)`
- `docs/architecture/appkit_swiftui_architecture.md`
- `docs/architecture/pane_runtime_eventbus_design.md`
