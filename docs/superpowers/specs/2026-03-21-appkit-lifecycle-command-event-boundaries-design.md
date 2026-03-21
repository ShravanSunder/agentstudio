# AppKit Lifecycle And Command/Event Boundary Design

## Goal

Centralize AppKit lifecycle ingress behind a typed application/window lifecycle boundary, and restore a strict separation between commands and events so future work cannot quietly misuse `NotificationCenter`, `AppEventBus`, or the workspace/runtime command planes.

This is a hardening pass on the live system, not a docs-only cleanup. The deliverable includes implementation changes, boundary enforcement, hosting/placement cleanup where justified, and documentation updates for future contributors and agents.

## Scope

This work includes all of the following:

- implementing a dedicated lifecycle boundary in live code
- migrating current lifecycle consumers off scattered `NotificationCenter` usage
- reclassifying remaining command-shaped `AppEventBus` payloads
- preserving validator-gated workspace mutation flow
- preserving direct runtime command flow
- adding guardrails that make future misuse fail fast
- improving architecture legibility in file placement, hosting, and docs

This work is not complete if only one of those categories ships.

## Problem

The current architecture docs already define distinct planes:

- `AppCommand` for user-facing trigger vocabulary
- `PaneActionCommand` for workspace mutation commands
- `RuntimeCommand` for runtime-targeted commands
- `PaneRuntimeEventBus` for facts
- `AppEventBus` for app-level notifications that do not belong on the command planes

The codebase still has two forms of drift:

1. **Lifecycle ingress is scattered.**
   AppKit lifecycle currently enters through direct `NotificationCenter` listeners in multiple files:
   - `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
   - `Sources/AgentStudio/App/MainSplitViewController.swift`
   - `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
   - `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`

2. **Some app-level events are command-shaped.**
   The boundary is semantic, not timing-based:
   - command: asks the system to do work
   - event: reports that something already happened

   Under that rule, payloads such as `selectTabById` and `closeTabRequested` are commands, not events. A hypothetical `activeTabChanged` or `tabClosed` would be an event.

3. **Ghostty has a mixed coordination channel.**
   `GhosttyEventSignal` currently mixes command-shaped and event-shaped payloads:
   - command-shaped: `newWindowRequested`, `closeSurface(...)`
   - event-shaped: `rendererHealthUpdated(...)`, `workingDirectoryUpdated(...)`

   That mixed channel violates the same semantic boundary this spec is trying to enforce unless it is classified and migrated explicitly.

4. **Global post helpers are architectural escape hatches.**
   The free functions `postAppEvent(...)` and `postGhosttyEvent(...)` allow any file to publish into buses without going through a typed boundary. If those helpers remain, the repo can reintroduce command/event drift even after the enums are cleaned up.

5. **The current user-command routing chain is more indirect than the target architecture.**
   Today, some flows effectively do this:

```text
AppCommand
  -> CommandDispatcher
  -> handler.execute(...)
  -> postAppEvent(...)
  -> AppEventBus
  -> controller subscriber
  -> PaneCoordinator / PaneActionCommand
```

   The target architecture should cut that indirection so commands route directly to `PaneActionCommand` or `RuntimeCommand` instead of bouncing through an app-level event channel.

## Design Principles

1. **One ingress, many observers.**
   AppKit lifecycle should enter the app through exactly one owned boundary.

2. **Commands ask, events report.**
   No command-shaped payload should ride the event planes.

3. **Typed state lives in stores.**
   Lifecycle state should use the same `@Observable` + `private(set)` atomic-store model as the rest of the app. Monitors and adapters sequence ingress; stores own state.

4. **Misuse should be mechanically hard.**
   Architecture tests and documentation must prevent future contributors from choosing the wrong plane by accident.

5. **Prefer composition, protocols, and encapsulation over ambient access.**
   The lifecycle boundary should be owned by a focused type with a narrow public API. Consumers should depend on typed state or small protocols, not concrete AppKit notification plumbing.

6. **The structure should teach the architecture.**
   Folder placement, file hosting, and contributor docs should make the command/event/lifecycle boundaries understandable without requiring a deep archaeology pass through the repo.

## Target Architecture

### Lifecycle Boundary

Introduce a dedicated `ApplicationLifecycleMonitor` in `App/`.

Responsibilities:

- Own the sole ingress from AppKit lifecycle
- Translate AppKit callbacks/notifications into lifecycle store mutations
- Prevent direct lifecycle subscriptions in UI/runtime surfaces
- Stay a narrow ingress/coordinator type rather than becoming a second composition root

This monitor feeds two outward-facing lifecycle stores:

- `AppLifecycleStore`
  - `@Observable`
  - `private(set)`
  - owns app-wide lifecycle facts such as `isActive` and `isTerminating`

- `WindowLifecycleStore`
  - `@Observable`
  - `private(set)`
  - owns window lifecycle facts such as key/focused window identity, per-window activation, and visibility as needed

The monitor is the only boundary allowed to speak AppKit lifecycle. Everything else reads typed lifecycle state from stores.

### Composition Root Boundary

`AppDelegate` remains the composition root.

Target responsibilities:

- `AppDelegate` creates and owns `ApplicationLifecycleMonitor`
- `AppDelegate` injects `AppLifecycleStore` and `WindowLifecycleStore` where needed
- `ApplicationLifecycleMonitor` does not become an alternative app root or a broad owner of unrelated shutdown/domain concerns

Shutdown sequencing should remain coordinated from the app boundary. The monitor may translate termination ingress into store updates or narrow callbacks, but it should not accumulate unrelated domain ownership just because termination is involved.

### Encapsulation Strategy

The lifecycle system should be enforced in layers:

- **Encapsulation**
  `ApplicationLifecycleMonitor` is the only owner of AppKit lifecycle ingress.

- **Typed composition**
  Consumers receive lifecycle state through injected stores or narrow read-oriented protocols.

- **Soft guidance**
  Docs explain which coordination plane to use and why.

- **Hard guardrails**
  Architecture/source tests fail if new code bypasses the boundary.

### Command And Event Planes

The command/event split remains:

```text
User trigger
  -> AppCommand
  -> PaneActionCommand or RuntimeCommand
  -> validation / dispatch
  -> mutation or runtime effect

Observed fact
  -> PaneRuntimeEventBus
  -> coordinators / caches / projections / UI
```

Plane responsibilities:

- `AppCommand`
  User-facing trigger vocabulary only

  All user-triggered actions from menus, keyboard shortcuts, clicks, overlays, drawer controls, arrangement controls, and command-bar selections start here.

- `PaneActionCommand`
  Workspace mutation commands only

  Any user-triggered action that changes workspace structure must terminate in a validated `PaneActionCommand` path.

- `RuntimeCommand`
  Runtime-targeted commands only

  Any user-triggered action that asks a runtime to do work must terminate in a direct `RuntimeCommand` dispatch path, not an event bus.

- `PaneRuntimeEventBus`
  Facts only

- `AppEventBus`
  App-level notifications/facts only when they are not commands and do not belong on the runtime fact bus

- `NotificationCenter`
  Not an app-domain coordination mechanism

### State Management Fit

Lifecycle state must follow the existing store model:

- unidirectional flow via `@Observable` state with `private(set)`
- atomic stores with one reason to change
- no monitor-owned ambient mutable state
- no new god-store justified by convenience

This means the lifecycle boundary should be:

```text
AppKit ingress
  -> ApplicationLifecycleMonitor
  -> AppLifecycleStore / WindowLifecycleStore
  -> consumers observe state
```

not:

```text
AppKit ingress
  -> monitor-owned mutable state
  -> consumers
```

### Architecture Legibility

The implementation should improve not only correctness, but readability of the architectural model.

Specific legibility goals:

- a new contributor can locate the AppKit lifecycle ingress owner quickly
- a new contributor can distinguish user trigger commands, workspace mutation commands, runtime commands, and events from code layout plus docs
- app-level notifications are not hosted in a way that suggests they are part of the runtime fact plane
- lifecycle, command, and event responsibilities are named and hosted so future agents do not need to infer the model from scattered files

## Directory Structure Changes

This work should improve directory structure where current hosting materially obscures the architecture. The goal is not a wholesale reorganization. The goal is to make the existing planes legible from the tree.

### Required moves

#### 1. Give lifecycle a first-class home in `App/`

Add a focused lifecycle area under `App/`, for example:

```text
Sources/AgentStudio/App/Lifecycle/
  ApplicationLifecycleMonitor.swift
  AppLifecycleStore.swift
  WindowLifecycleStore.swift
  ApplicationLifecycleProviding.swift      // if a narrow protocol boundary is useful
  WindowLifecycleProviding.swift           // only if earned
```

Why:

- lifecycle ingress is an app-boundary concern, not a view concern
- future contributors should be able to find the lifecycle owner immediately
- typed lifecycle state should live next to its ingress owner, not scattered across controllers and views

#### 2. Move app-level events out of pane-runtime event hosting

Split `EventChannels.swift` rather than moving it wholesale:

- `PaneRuntimeEventBus` stays under `Core/PaneRuntime/Events/`
- `AppEvent` / `AppEventBus` move to `App/Events/`
- `GhosttyEventSignal` / `GhosttyEventBus` are reviewed and placed according to their post-classification ownership
- global post helpers are removed or replaced by owned boundary APIs

`AppEvent` and `AppEventBus` should no longer live in:

- `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`

They should move to an app-owned location, for example:

```text
Sources/AgentStudio/App/Events/
  AppEvent.swift
  AppEventBus.swift
```

or a single focused file if that is more consistent with the repo.

Why:

- app-level notifications are not pane-runtime events
- hosting them inside `Core/PaneRuntime/Events/` teaches the wrong mental model
- moving them makes the event planes readable from placement alone
- `App/Events/` wins over `Core/Events/` because the change driver is app coordination rather than reusable core domain logic, and the four-test framework from `directory_structure.md` favors the app boundary once pane-runtime facts are excluded

### Expected stays

These should remain where they are unless the implementation finds a stronger reason to move them:

- `Core/Actions/PaneActionCommand.swift`
- `Core/Actions/ActionResolver.swift`
- `Core/Actions/ActionValidator.swift`
- `Core/PaneRuntime/Contracts/RuntimeCommand.swift`
- runtime event bus infrastructure under `Core/PaneRuntime/`

Why:

- those locations already reinforce the distinction between workspace mutation commands and runtime contracts
- the biggest structural confusion is not those files themselves, but mixed hosting around lifecycle ingress and app-level events

### Hosting review, not automatic move

The implementation should explicitly review, but not blindly move:

- `AppCommand.swift`
- `GhosttyEventBus` and any Ghostty-specific signal types
- slice/projection-related types whose locations may be correct but under-documented

For each reviewed item, the implementation should either:

- keep it in place and document why the hosting still earns its keep
- or move it because the current location materially obscures the architecture

### Non-goals for this restructure

The spec does **not** call for:

- a large-scale rename/restructure of every command type
- moving stable store/cache/UI boundaries just to make the tree prettier
- introducing extra folders that do not earn a clearer reading path

## Intended Classification Rules

### Command

Use a command plane when the payload means:

> "Please make this happen."

Examples:

- select this tab
- close this tab
- open this worktree
- split this pane
- send input to this terminal runtime

### Event

Use an event plane when the payload means:

> "This already happened."

Examples:

- app became active
- active tab changed
- cwd changed
- branch changed
- bell rang
- tab closed

## Explicit Inventories

### AppEvent inventory

The implementation must classify every remaining `AppEvent` case, not just a hand-picked subset.

Likely command-shaped and expected to migrate off `AppEventBus`:

- `closeTabRequested`
- `undoCloseTabRequested`
- `selectTabById`
- `selectTabAtIndex`
- `extractPaneRequested`
- `movePaneToTabRequested`
- `repairSurfaceRequested`
- `refocusTerminalRequested`
- `showCommandBarRepos`
- `openWebviewRequested`
- `toggleSidebarRequested`
- `filterSidebarRequested`

Likely app-intent notifications or facts that may remain if they still earn the boundary:

- `addRepoRequested`
- `addFolderRequested`
- `addRepoAtPathRequested`
- `removeRepoRequested`
- `refreshWorktreesRequested`
- `signInRequested`

Likely fact/event-shaped and should be reviewed against the runtime fact plane:

- `terminalProcessTerminated`
- `worktreeBellRang`
- `managementModeChanged`

The implementation should not assume this list is final truth. It is the explicit audit surface the spec requires.

### GhosttyEventSignal inventory

The implementation must also classify every `GhosttyEventSignal` case.

Current explicit audit surface:

- command-shaped:
  - `newWindowRequested`
  - `closeSurface(surfaceViewId:processAlive:)`

- fact/event-shaped:
  - `rendererHealthUpdated(surfaceViewId:isHealthy:)`
  - `workingDirectoryUpdated(surfaceViewId:rawPwd:)`

Target rule:

- command-shaped Ghostty signals must move to an appropriate command boundary
- fact-shaped Ghostty signals may remain event-like, but should be reviewed for whether they belong on `PaneRuntimeEventBus`, lifecycle consumption, or a narrower typed boundary

### Free function escape hatches

The implementation must explicitly review and likely remove or replace:

- `postAppEvent(...)`
- `postGhosttyEvent(...)`

Target outcome:

- arbitrary files should not be able to publish into coordination buses through free global helpers
- posting should occur through owned boundaries or typed APIs with clear placement

## Lifecycle State Model

### AppLifecycleStore

Minimum initial surface:

- `isActive`
- `isTerminating`

Optional future extension points:

- launch phase / readiness if lifecycle ownership expands

### WindowLifecycleStore

Minimum initial surface:

- window identity registry
- key/focused window identity
- per-window active/inactive state

Optional future extension points:

- visibility / occlusion
- ordering / frontmost rank if product features need it

### AppKit Ingress Mapping

This spec should absorb concrete AppKit lifecycle ingress, not just speak abstractly about "lifecycle."

Minimum app-level ingress to absorb:

- app became active
- app resigned active
- app will terminate

Minimum window-level ingress to absorb:

- window became key/focused
- window resigned key/focus
- additional window visibility/ordering hooks only if the current app behavior actually depends on them

The implementation may choose notification-based or delegate-based AppKit ingress at the monitor boundary, but that choice must remain encapsulated inside the lifecycle boundary.

Termination ingress has an additional constraint:

- the current `willTerminate` path is synchronous, and the migrated lifecycle boundary must preserve that guarantee
- if termination work must happen inline before process exit, the monitor boundary must keep a synchronous ingress path rather than relying on async stream resumption timing

### Protocol Shape

The design should prefer small read-oriented protocols for lifecycle consumption, for example:

- a protocol for reading app lifecycle state
- a protocol for reading window lifecycle state

This keeps consumers decoupled from the concrete ingress owner while preserving a single implementation boundary. The goal is not protocol proliferation; the goal is to prevent ambient access to AppKit lifecycle APIs outside the owned boundary.

### Consumption Model

Consumers react to lifecycle state through typed observation.

Examples:

- Ghostty focus integration reads `AppLifecycleStore.isActive`
- split/drawer drag state clears when app/window lifecycle state indicates deactivation
- window-scoped UI concerns read `WindowLifecycleStore`, not AppKit notifications directly
- Ghostty and webview remain downstream consumers for now; they do not become lifecycle owners

## Migration Plan

### Phase 1: Establish Lifecycle Boundary

1. Add `ApplicationLifecycleMonitor`, `AppLifecycleStore`, and `WindowLifecycleStore` in `App/`.
2. Wire AppKit lifecycle ingress into the monitor.
3. Ensure the monitor mutates lifecycle stores instead of owning mutable lifecycle state directly.
4. Expose lifecycle state to consumers through injected stores or narrow read-only protocols, not direct notifications.
5. Place the new lifecycle types in a first-class lifecycle area under `App/`.

### Phase 2: Migrate Existing NotificationCenter Consumers

Move the current direct listeners behind the lifecycle monitor:

- `Ghostty.swift`
- `MainSplitViewController.swift`
- `TerminalSplitContainer.swift`
- `DrawerPanel.swift`

Target outcome:

- no scattered `NotificationCenter` lifecycle listeners remain outside the monitor boundary
- terminate/save behavior is owned at the lifecycle boundary, not a random controller
- termination handling preserves the existing synchronous delivery guarantee

### Phase 2a: Reclassify Ghostty Event Channel

Inventory and classify every `GhosttyEventSignal` case.

Expected outcomes:

- command-shaped Ghostty signals stop living on a mixed event channel
- fact-shaped Ghostty signals are routed to the correct fact/state boundary
- Ghostty continues as a consumer of lifecycle and runtime facts; it does not become the lifecycle owner

### Phase 3: Reclassify Remaining AppEventBus Cases

Inventory every remaining `AppEvent` case and classify it as:

- `PaneActionCommand`
- `RuntimeCommand`
- true app-level event/notification
- stale and removable

Expected high-priority migrations:

- `selectTabById` -> command path
- `closeTabRequested` -> command path
- `undoCloseTabRequested` -> likely command path
- `extractPaneRequested` -> command path
- `movePaneToTabRequested` -> command path
- `repairSurfaceRequested` -> command path
- `refocusTerminalRequested` -> command path or direct focus boundary
- `showCommandBarRepos` -> command path or direct UI coordination boundary
- `openWebviewRequested` -> command path
- `toggleSidebarRequested` -> command path or direct controller boundary
- `filterSidebarRequested` -> command path or direct UI coordination boundary

Other current `AppEvent` cases should be reviewed under the same semantic rule instead of preserving them by habit.

### Phase 3a: Review Hosting And Placement

The migration must explicitly review whether current hosting locations reinforce or obscure the architecture.

At minimum, review:

- moving `AppEvent` / `AppEventBus` out of runtime event hosting
- where `GhosttyEventSignal` and any retained Ghostty-specific coordination types live
- where lifecycle ingress types live
- whether command vocabularies are placed and named clearly enough to distinguish:
  - `AppCommand`
  - `PaneActionCommand`
  - `RuntimeCommand`

This review does not require a large directory restructure by default. It does require one of two outcomes for each confusing placement:

- move it because the current hosting actively obscures the model
- or document why it remains in place for now

### Phase 4: Guardrails

Add architecture/source tests and documented review rules. The spec must distinguish between **mechanical** guardrails and **review-enforced semantic** guardrails.

Mechanical guardrails should fail when:

- `NotificationCenter` is used outside the lifecycle ingress allowlist during migration
- `NotificationCenter` remains outside `ApplicationLifecycleMonitor` after migration completes
- `postAppEvent(...)` / `postGhosttyEvent(...)` survive or reappear outside approved boundaries
- workspace mutations bypass validated `PaneActionCommand`
- runtime commands are routed through event infrastructure
- user-triggered workspace actions bypass `ActionValidator`

Review-enforced semantic guardrails should cover:

- whether a payload is command-shaped or event-shaped
- whether something truly belongs on `AppEventBus`
- whether a Ghostty signal belongs on a fact plane, a command plane, or a narrower typed boundary

Durable source guards should also assert that known command-shaped `AppEvent` cases do not reappear on the enum once migrated, for example:

- `selectTabById`
- `closeTabRequested`
- `undoCloseTabRequested`
- `extractPaneRequested`
- `movePaneToTabRequested`
- `repairSurfaceRequested`

## Documentation Requirements

This cleanup is incomplete unless contributor-facing docs are updated.

Update at least:

- `AGENTS.md`
- `docs/architecture/README.md`
- any architecture doc sections that currently blur commands and events

Required documentation outcomes:

- an explicit "which coordination plane do I use?" decision table
- a short "how to read this architecture" map for future agents
- lifecycle ingress ownership documented in one obvious place
- directory placement rationale for lifecycle ingress and app-level events
- explicit explanation of the current bad `AppCommand -> AppEventBus -> controller -> PaneActionCommand` conversion chain and the target replacement
- explicit explanation of lifecycle stores as `@Observable` atomic stores with `private(set)`
- command vs event semantics documented in terms of intent vs fact, not timing folklore
- any retained exceptions called out explicitly instead of left implicit

The docs should do two jobs:

1. **Explain the architecture clearly for future agents and contributors.**
2. **Act as the soft system that reinforces the hard boundaries in code and tests.**

Required guidance for future agents:

- Asking the workspace to change -> `PaneActionCommand`
- Asking a runtime to do work -> `RuntimeCommand`
- Reporting a runtime/system fact -> `PaneRuntimeEventBus`
- Reporting an app-level notification that is not a command -> `AppEventBus`
- Handling AppKit/macOS lifecycle ingress -> `ApplicationLifecycleMonitor`
- User-triggered workspace actions from menus, clicks, overlays, and command bar must remain validator-gated
- Do not use `NotificationCenter` for app-domain coordination

## Acceptance Criteria

This design is complete only when all of the following are true:

1. AppKit lifecycle enters the app through one owned boundary.
2. UI/runtime surfaces no longer subscribe directly to lifecycle notifications.
3. Command-shaped `AppEventBus` payloads have been removed or migrated.
4. Workspace mutations remain validator-gated through `PaneActionCommand`.
5. Runtime commands remain direct through `RuntimeCommand`.
6. `NotificationCenter` cannot be reintroduced for app-domain coordination without failing guard tests.
7. `AGENTS.md` and `docs/architecture/README.md` contain a coordination-plane decision table covering at least:
   - workspace mutation
   - runtime command
   - runtime fact
   - app-level notification
   - AppKit/macOS lifecycle ingress
   - UI-only local state
8. Hosting/placement decisions no longer materially obscure the command/event/lifecycle model.
9. The implementation ships both code changes and documentation changes together.
10. Lifecycle ingress has a first-class home under `App/`, and app-level events are no longer hosted as pane-runtime events.
11. Lifecycle state is owned by `@Observable` atomic stores, not by the lifecycle monitor itself.
12. Ghostty's mixed command/event channel has been classified and cleaned up or explicitly justified.
13. User-triggered workspace actions from menus, clicks, overlays, drawer controls, arrangement controls, and command bar remain validator-gated.

## Out Of Scope

These items are intentionally excluded from this design:

- further renaming of `PaneActionCommand` beyond this cleanup
- broader store-boundary refactors unrelated to lifecycle or command/event separation
- changing the underlying workspace/event architecture away from the documented command and event planes
