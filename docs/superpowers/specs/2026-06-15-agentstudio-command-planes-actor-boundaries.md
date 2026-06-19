# AgentStudio Command Planes And Actor Boundaries

**Date:** 2026-06-15
**Scope:** `agent-studio.programatical-control`
**Status:** Implemented precursor architecture cleanup. This is the source
model for command-plane ownership before the next IPC runtime-lifecycle
implementation slice.

## Purpose

AgentStudio has app-level IPC, app command specs, workspace actions, pane
runtimes, and runtime events. Those systems are useful only if each plane keeps
a named owner. The risk is not that one method is wrong in isolation. The risk
is that future IPC, command-bar, runtime, and pane-agent work routes behavior
through whichever object is convenient.

This spec defines the implemented mental model and feature-parity cleanup for
command planes. It should make these questions boring:

- Is this a semantic app command, a workspace graph mutation, a pane runtime
  command, a UI presentation request, or a runtime event observation?
- Which owner is allowed to perform it?
- Which actor lane does it run on?
- Which boundaries are enforced by the compiler, by architecture lint, by tests,
  and by docs?

The IPC runtime lifecycle follow-up should use this vocabulary instead of the
older `ActionExecutor` / `RuntimeCommand` ambiguity.

## Current-State Evidence

The code has the necessary seams and the feature-parity rename has made their
jobs explicit:

- `AppCommand` is the dispatchable app command identity, but the current enum is
  a mixed identity space. It includes semantic commands, UI openers,
  command-bar drill-in placeholders, management navigation, and terminal-ish
  shortcuts. Public IPC must not expose that raw enum as an authority surface.
- `AppCommandSpec` is command metadata for command bar, shortcuts, labels, icons,
  and visibility. It is metadata for `AppCommand`, not a generic IPC/runtime/MCP
  command spec.
- `AppCommandDispatcher` routes `AppCommand` to app/window handlers or workspace
  handlers. It is not a generic command bus.
- `PaneTabViewController` owns many workspace command resolutions because it
  knows active pane, drawer focus, transient surfaces, and tab context.
- `WorkspaceActionCommand` is a resolved workspace mutation command. It includes
  tabs, arrangements, drawer operations, worktree opens, repo removal, orphaned
  pane pool operations, and repair actions.
- `WorkspaceCommandValidator` is a pure validation/canonicalization engine over
  `ActionStateSnapshot`.
- `WorkspaceActionExecutor` is a `@MainActor` app-facing gateway. It builds
  snapshots, validates `WorkspaceActionCommand`, delegates validated actions to
  `WorkspaceSurfaceCoordinator`, and exposes high-level workspace open helpers.
  It does not own pane runtime command dispatch.
- `PaneRuntimeCommand` is a pane-runtime command envelope payload. Commands route
  to one `PaneRuntime`.
- `PaneRuntime` is currently `@MainActor`; individual runtime implementations
  may still delegate expensive work to actors or services behind that contract.
- `AgentStudioAppIPC` is already a separate SwiftPM target. Concrete app
  adapters live in the executable target under `App/IPCComposition`.
- `AgentStudioIPCCommandAdapter` currently keeps `command.*` headless and
  rejects presentation-only command ids.
- `AgentStudioIPCLayoutAdapter` maps IPC layout methods to existing app focus
  and workspace action seams.
- `AgentStudioIPCRuntimeAdapter` maps IPC terminal methods to
  `RuntimeRegistry`, `PaneRuntime`, and `PaneRuntimeCommandDispatching`.
  Terminal-specific snapshot extras come from `TerminalRuntimeSnapshotFactProviding`
  instead of a concrete `TerminalRuntime` downcast in IPC composition.

The cleanup resolved this vocabulary drift:

```text
ActionExecutor
  became: WorkspaceActionExecutor
  why: main-actor workspace action gateway, not a generic app executor

PaneActionCommand
  became: WorkspaceActionCommand
  why: resolved workspace graph/action command across tabs, panes,
       drawers, arrangements, worktrees, and repair actions

RuntimeCommand
  became: PaneRuntimeCommand
  why: command payload for one targeted PaneRuntime

CommandSpec
  became: AppCommandSpec
  why: AppCommand metadata, not a generic command schema

CommandDispatcher
  became: AppCommandDispatcher
  why: AppCommand dispatcher, not a command bus

PaneCoordinator
  became: WorkspaceSurfaceCoordinator
  why: workspace surface coordinator for panes, tabs, drawers,
       view hosts, runtime registry, restore, repair, and undo
```

## Progressive Overview

### One Map

```text
┌─ AgentStudio Command Planes ─────────────────────────────────────┐
│                                                                  │
│  app command plane                                               │
│    AppCommand + AppCommandSpec                                   │
│    identity, metadata, shortcuts, headless semantic verbs        │
│                                                                  │
│  workspace action plane                                          │
│    resolved workspace graph mutations                            │
│    tabs, panes, drawers, arrangements, worktrees, repairs        │
│                                                                  │
│  pane runtime command plane                                      │
│    one targeted PaneRuntime                                      │
│    terminal/browser/diff/editor/plugin operations                │
│                                                                  │
│  UI presentation plane                                           │
│    command bar, picker, sheet, panel presentation                │
│    explicit UI side effects only                                 │
│                                                                  │
│  runtime event plane                                             │
│    facts emitted after work happened                             │
│    waits, subscriptions, replay, observability                   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Mental Model

Commands ask owners to do work. Events report facts after work happened.
Presentation opens UI. IPC is an ingress and authority boundary, not a new
behavior owner.

```text
request/command path
  client or UI
    -> resolve authority and target
    -> call the owning command plane
    -> owner mutates state or asks runtime to act
    -> return accepted/rejected/result

event/wait path
  runtime or app owner
    -> publish fact
    -> replay/subscriber observes fact
    -> wait resolves or times out

forbidden path
  client or UI
    -> EventBus
    -> hidden command side effect
```

### Why This Comes Before IPC Follow-up

The next IPC lifecycle slice needs to prove pane-agent authority revocation,
terminal completion waits, and live control. If the command planes stay fuzzy,
IPC work will have to choose between:

- calling `AppCommand` and accidentally opening UI;
- calling `WorkspaceActionExecutor` and pretending it is a general app executor;
- calling `PaneRuntimeCommand` without a clear pane-runtime ownership boundary;
- adding one-off adapter methods that bypass the existing validation model.

The precursor cleanup should preserve behavior while making the command planes
explicit enough that IPC can compose them safely.

### Current Mixed AppCommand Classification

`AppCommand` is still the right name for the in-app identity enum, but not every
case is a public, headless command. The cleanup must classify the current enum
before exposing or routing any new headless IPC command catalog.

```text
semantic shell/app commands
  examples: newWindow, closeWindow, toggleSidebar, showInboxNotifications
  owner: AppDelegate / shell owner

workspace semantic commands
  examples: closeTab, splitRight, addDrawerPane, openPaneLocationInFinder
  owner: PaneTabViewController -> WorkspaceActionCommand path or focus owner

runtime commands
  examples: scrollToBottom, scrollPageUp, jumpToPreviousPrompt
  owner: PaneTabViewController -> PaneRuntimeCommand path

UI presentation commands
  examples: showCommandBarEverything, showCommandBarRepos
  owner: AppDelegate command-bar presenter

chooser / drill-in placeholders
  examples: selectTab, focusPane, movePaneToTab
  owner: command-bar data source and targeted command resolver, not raw IPC

keyboard naming debt
  AppShortcut.newTab currently dispatches AppCommand.showCommandBarRepos.
  That is documented behavior, but it must not become public IPC vocabulary.
```

The important rule: command metadata can be reused, but `AppCommand.rawValue` is
not the public IPC command contract.

## Target Vocabulary

### Names To Keep

```text
AppCommand
  Keep. It is the authoritative dispatchable app command identity.

WorkspaceCommandValidator
  Keep. It accurately describes validation of workspace command intent
  against a workspace snapshot.

PaneRuntime
  Keep. Runtime ownership is pane-scoped.

RuntimeCommandEnvelope
  Keep or rename later only if the payload is renamed. The envelope is
  already clearly a routed runtime command envelope.
```

### Names Changed In This Precursor

```text
ActionExecutor -> WorkspaceActionExecutor

  Why:
    It builds workspace snapshots, validates workspace graph actions, exposes
    workspace open helpers, and delegates workspace mutations to
    WorkspaceSurfaceCoordinator. It is not a generic app action executor. It is
    also not only pane-specific.

  Migration result:
    Hard cutover. No long-term typealias.

PaneActionCommand -> WorkspaceActionCommand

  Why:
    The enum covers more than pane actions. It is the resolved command language
    for workspace graph changes: tabs, panes, drawers, arrangements, worktrees,
    orphaned panes, and repairs.

  Why not WorkspacePaneActionCommand:
    That still suggests pane-first ownership and does not explain tab,
    arrangement, repo, worktree, or repair cases.

  Plane cleanup:
    Terminal runtime shortcut cases such as scrollToBottom, scrollPageUp, and
    jumpToPrompt do not belong in WorkspaceActionCommand. They now route through
    PaneRuntimeCommand instead.

RuntimeCommand -> PaneRuntimeCommand

  Why:
    A runtime command is always targeted through `RuntimeCommandTarget` to one
    `PaneRuntime`. The name should make confused-deputy checks easier: a
    command payload is meaningless until routed to the authorized pane runtime.

  Migration result:
    Hard cutover of the payload type. `TerminalCommand`, `BrowserCommand`,
    `DiffCommand`, and `EditorCommand` remain nested-by-domain names.

CommandSpec -> AppCommandSpec

  Why:
    The metadata belongs to AppCommand. The app now also has IPC method
    contracts, runtime commands, and future MCP command surfaces, so bare
    CommandSpec is too generic.

CommandDispatcher -> AppCommandDispatcher

  Why:
    The dispatcher routes AppCommand identities. The name must not imply a
    generic command bus for workspace actions, pane runtime commands, IPC
    methods, or events.

PaneCoordinator -> WorkspaceSurfaceCoordinator

  Why:
    The coordinator is not pane-only. It coordinates workspace surfaces:
    panes, tabs, drawers, view hosts, runtime registry routing, restore,
    repair, undo, and surface ordering. WorkspaceSurfaceCoordinator is broader
    without implying ownership of all workspace persistence or repo topology.
```

### Names To Clarify In Docs Before Renaming

```text
WorkspaceCommandResolver
  Keep. It describes the current resolver role, but it still depends on
  AppCommand. A future pure target split needs a command-intent seam before
  moving this type.

RuntimeCommandEnvelope
  Keep unless the implementation finds that PaneRuntimeCommandEnvelope makes
  the call sites clearer. The payload rename is the important boundary.
```

## Target Component Model

### Component Ownership

```text
┌─────────────────────────────┐
│ AppCommand + AppCommandSpec │
│ mixed identity + metadata   │
└──────────────┬──────────────┘
               │ dispatch app command
               ▼
┌─────────────────────────────┐
│ AppCommandDispatcher        │
│ chooses app vs workspace    │
└───────┬─────────────────────┘
        │
        ├─ app/window/sidebar shell action
        │      ▼
        │   AppDelegate / shell owner
        │
        └─ pane/tab/drawer/workspace action
               ▼
            PaneTabViewController
               │ resolves active tab/pane/drawer target
               ▼
            WorkspaceActionCommand
               ▼
            WorkspaceCommandValidator
               ▼
            WorkspaceActionExecutor
               ▼
            WorkspaceSurfaceCoordinator
```

This is not a claim that every `AppCommand` becomes a
`WorkspaceActionCommand`. Current reality has several legitimate bypasses:

- focus commands go through pane focus owners;
- terminal shortcuts go through the pane runtime command path;
- management-layer and arrangement presentation commands have their own
  app/workspace owners;
- targeted command-bar rows may construct workspace actions outside
  `WorkspaceCommandResolver`.

The cleanup should name those paths and preserve behavior. It should not pretend
there is one universal command pipeline.

### IPC Component Model

```text
┌──────────────────────────────┐
│ AgentStudioAppIPC target     │
│ socket, auth, registry,      │
│ authorization, ports         │
└──────────────┬───────────────┘
               │ protocol port call
               ▼
┌──────────────────────────────┐
│ App/IPCComposition           │
│ concrete adapters            │
└───┬──────────────┬───────────┘
    │              │
    │ layout       │ runtime
    ▼              ▼
 Workspace       PaneRuntimeCommand
 Action          via WorkspaceSurfaceCoordinator
 plane           + RuntimeRegistry

    │ command
    ▼
 Headless semantic AppCommand adapter
 or explicit semantic method

    │ ui
    ▼
 Explicit UI presentation adapter
```

The `App/IPCComposition` layer may translate public handles and DTOs into app
contracts. It must not become a new owner for pane graph mutation, runtime
execution, command-bar behavior, or permission policy.

The runtime adapter should also stop reaching through `PaneRuntime` into
concrete runtime classes for exported snapshot fields. Terminal-specific
snapshot extras should come from a terminal runtime snapshot provider or
runtime-owned protocol seam, not a downcast from IPC composition to
`TerminalRuntime`.

### Actor-Lane Model

```text
IPC socket task / server actor
  owns: bytes, JSON-RPC decode, connection state, auth, authorization,
        event subscription bookkeeping
  must not: touch AppKit, mutate atoms, own workspace behavior
        │
        │ hop only through typed port
        ▼
MainActor app gateway
  owns: window selection, workspace snapshots, pane/tab/drawer graph,
        focus routing, UI presentation, view registry ordering
  must not: perform long-running runtime or subprocess work inline
        │
        │ route runtime command
        ▼
Pane runtime owner
  owns: command handling for one pane runtime, lifecycle, snapshots,
        replayable events
  may: delegate expensive filesystem, process, browser, terminal, or diff work
       to actors/services behind the runtime contract
        │
        │ publish fact
        ▼
Runtime event lane
  owns: immutable RuntimeEnvelope facts, replay, subscriptions, waits
  must not: execute commands
```

This model intentionally avoids a generic command actor. A generic actor would
hide ownership. The better rule is: command ingress is off-main by default, but
each command hops to the owning actor or owner-specific port.

## Command And Event Data Flow

### Workspace Layout Command

```text
IPC pane.split
  -> AppIPC authorization checks layout privilege
  -> IPC layout adapter resolves handle to pane UUID
  -> MainActor workspace gateway reads workspace snapshot
  -> WorkspaceActionCommand.insertPane(...)
  -> WorkspaceCommandValidator validates resolved command
  -> WorkspaceActionExecutor delegates validated action
  -> WorkspaceSurfaceCoordinator mutates workspace graph and view/runtime ordering
  -> result maps to IPC DTO
  -> runtime/app may later publish facts
```

The command path does not use EventBus. Events may describe the outcome later,
but they are not the execution mechanism.

### Pane Runtime Command

```text
IPC terminal.send
  -> AppIPC authorization checks terminal input privilege
  -> IPC runtime adapter resolves handle to terminal pane UUID
  -> MainActor runtime gateway checks RuntimeRegistry and lifecycle
  -> PaneRuntimeCommand.terminal(.sendInput)
  -> WorkspaceSurfaceCoordinator.dispatchRuntimeCommand
  -> RuntimeRegistry.runtime(for:)
  -> PaneRuntime.handleCommand(envelope)
  -> result means accepted/rejected by runtime path
```

`terminal.send` is not a promise that the shell command completed. Completion is
observed through runtime events and waits.

### Runtime Wait

```text
IPC terminal.wait(afterSequence)
  -> AppIPC authorization checks read/wait privilege
  -> IPC runtime adapter resolves terminal pane
  -> PaneRuntime.eventsSince(seq:) checks replay
  -> PaneRuntime.subscribe() observes live facts
  -> wait returns exported DTO or timeout/replay-gap
```

Event-backed waits use facts. They must not poll UI state on MainActor or sleep
for guessed durations. The current `attachReady` condition is lifecycle-backed,
not event-backed; changing it requires a separate runtime lifecycle contract or
an exported attach-ready fact and does not belong to the rename-only portion of
this precursor.

### UI Presentation

```text
IPC ui.commandBar.open
  -> AppIPC authorization checks uiPresent privilege
  -> UI presentation adapter resolves workspace window
  -> app presenter opens command-bar UI
  -> result means presenter accepted request
```

This is separate from `command.execute`. If a command requires a chooser,
prompt, sheet, command bar, or palette, it is not headless until there is an
explicit semantic method with explicit parameters.

## Requirements

### R1. Feature-Parity Refactor First

The first implementation slice must be a feature-parity architecture cleanup.
It may rename types, update docs, update tests, and add architecture lint
guards. It must not add new IPC product capabilities or broaden authority.

Behavior before and after the cleanup must remain equivalent for:

- keyboard shortcuts;
- command bar dispatch;
- app/window shell commands;
- app command metadata and dispatch;
- workspace pane/tab/drawer commands;
- arrangement commands;
- terminal runtime shortcuts;
- IPC layout methods;
- IPC terminal status/snapshot/send/wait methods;
- IPC command/UI presentation separation.

### R2. Rename `ActionExecutor` To `WorkspaceActionExecutor`

`ActionExecutor` is renamed to `WorkspaceActionExecutor`.

The renamed type owns the app-facing workspace action gateway:

- constructing the action validation snapshot;
- invoking `WorkspaceCommandValidator`;
- delegating validated workspace graph changes to `WorkspaceSurfaceCoordinator`;
- preserving high-level workspace open helpers during the feature-parity pass.

The implementation should avoid a long-lived typealias. If a temporary alias is
needed for a mechanical migration, remove it before completion.

### R3. Rename `PaneActionCommand` To `WorkspaceActionCommand`

`PaneActionCommand` becomes `WorkspaceActionCommand` because the enum is the
resolved command language for the workspace graph, not only pane actions.

The rename must include:

- `ValidatedAction.action`;
- validator tests;
- resolver tests;
- IPC layout adapter protocols and tests;
- docs and architecture test string fixtures;
- comments that currently imply pane-only ownership.

The command still carries concrete target IDs. It must not reintroduce
unresolved active-pane or current-tab references.

Terminal runtime shortcut cases must not remain in the workspace action plane.
`scrollToBottom`, `scrollPageUp`, and `jumpToPrompt` should route through
`PaneRuntimeCommand.terminal(...)` only. If that extraction is deferred, the
implementation must leave an explicit failing architecture/behavior test and a
same-branch follow-up plan; otherwise the rename is cosmetic.

### R4. Rename `PaneRuntimeCommand` To `PaneRuntimeCommand`

`PaneRuntimeCommand` should become `PaneRuntimeCommand` because it is always handled
by one targeted `PaneRuntime`.

The rename must include:

- `RuntimeCommandEnvelope.command`;
- `WorkspaceSurfaceCoordinator.dispatchRuntimeCommand`;
- runtime adapters;
- runtime tests;
- terminal/browser/diff/editor runtime command handlers;
- docs and architecture tests.

This rename does not change the public IPC method namespace. Public methods
remain semantic app IPC names such as `terminal.send`, not internal Swift type
names.

### R5. Rename `AppCommandSpec` To `AppCommandSpec`

`AppCommandSpec` should become `AppCommandSpec` because it is the metadata catalog
for `AppCommand`, not a generic spec for IPC, runtime, MCP, or future command
surfaces.

The rename must include:

- `AppCommand.definition`;
- command bar data source references;
- tooltip/control presentation helpers;
- command-spec contract tests;
- architecture docs that describe the command and shortcut system.

### R6. Rename `AppCommandDispatcher` To `AppCommandDispatcher`

`AppCommandDispatcher` should become `AppCommandDispatcher` because it dispatches
`AppCommand` identities only. It must not read as a generic bus for workspace
actions, pane runtime commands, IPC methods, or event facts.

The rename must include:

- dispatcher singleton and handler protocol call sites;
- `AppDelegate` shell command routing;
- `PaneTabViewController` workspace command routing;
- command-bar and menu dispatch call sites;
- tests that assert app command routing order.

### R7. Rename `WorkspaceSurfaceCoordinator` To `WorkspaceSurfaceCoordinator`

`WorkspaceSurfaceCoordinator` should become `WorkspaceSurfaceCoordinator`.

The renamed type owns coordination of workspace surfaces:

- pane/tab/drawer graph mutations;
- view host and placeholder-host ordering;
- runtime registry routing;
- restore, repair, undo, and close sequencing.

The rename must not imply ownership of all workspace persistence, repo topology,
or app-wide lifecycle. Those remain separate owners.

### R8. Command Planes Must Stay Separate

The cleanup must preserve these rules:

- `command.*` is headless semantic app command execution only.
- `command.*` must not expose raw `AppCommand.rawValue` as a blanket public API.
- `command.execute` may stay empty/debug-only until a curated headless catalog
  and command-specific sub-authorization exist.
- `command.execute` must preserve the current public error contract: open string
  command ids decode, presentation-backed ids fail with `requiresPresentation`,
  unknown ids fail with `unsupportedCommand`, and no new `targetHandle`
  semantics are added in this cleanup.
- `ui.*` is explicit presentation.
- `pane.*` and `drawer.*` are structured layout/control methods with explicit
  targets.
- `terminal.*`, `browser.*`, `diff.*`, and `editor.*` are runtime-control
  methods with runtime privileges.
- runtime events and waits observe facts and do not execute commands.
- EventBus is not a command bus.
- IPC methods do not mutate atoms directly.
- zmx daemon IPC remains internal and is not exposed as public app IPC.

Static method-level authorization is not enough for a broad `command.execute`
surface. If future `command.execute` supports multiple headless commands, the
implementation must add command-specific privilege checks or prefer explicit
domain methods such as `pane.*`, `tab.*`, `terminal.*`, and `workspace.*`.

### R9. MainActor Hops Must Be Named

IPC transport/auth/decode should remain off the UI actor. Hops to MainActor
must happen only through named app gateway protocols or concrete adapters that
own app state reads/writes.

Allowed MainActor work:

- active workspace/window resolution;
- workspace snapshot reads through existing store seams;
- pane/tab/drawer graph mutation through workspace action owners;
- focus routing and UI presentation;
- runtime registry lookup while the registry contract is MainActor;
- view registry ordering and placeholder-host creation.

Disallowed MainActor work:

- JSON-RPC parsing or framing;
- socket read/write loops;
- authorization policy bookkeeping that has no app-state dependency;
- long-running terminal/browser/filesystem/process work;
- wall-clock polling for event-backed waits.

### R10. Runtime Work Must Have A Runtime Owner

The feature-parity cleanup does not need to redesign all runtimes, but it must
document and preserve the rule that expensive runtime work belongs behind the
runtime contract, not in IPC adapters or workspace action executors.

If a runtime command requires subprocess, filesystem, browser, diff, or terminal
backend work, the command path may enter through MainActor for routing, then the
runtime implementation must own any further actor/service delegation.

Terminal runtime snapshot details are part of this ownership rule. IPC adapters
may map exported DTOs, but runtime-specific health/read-only/secure-input facts
must come through runtime-owned snapshot contracts rather than concrete runtime
class casts.

### R11. Remove Concrete Runtime Knowledge From IPC Composition

The current `AgentStudioIPCRuntimeAdapter` knows about `TerminalRuntime` for
terminal snapshot extras. That should be treated as a feature-parity cleanup
item, not as a permanent pattern.

Target shape:

```text
IPC runtime adapter
  -> resolves pane handle
  -> asks runtime-owned snapshot provider for exported terminal facts
  -> maps provider output to AgentStudioProgrammaticControl DTO
```

The adapter may still check that the pane is a terminal pane and that the
runtime is registered. It must not own terminal implementation details.

### R12. Architecture Enforcement Must Be Layered

The cleanup must enforce the model in this order:

```text
compile-time target boundaries
  strongest: missing import edges make violations impossible

architecture lint
  second: SwiftSyntax rules catch forbidden dependencies and call patterns

unit / integration / architecture tests
  third: prove behavior and fixture the intended contracts

docs / AGENTS guidance
  weakest: explain the model for humans and agents
```

Required enforcement checks:

- `AgentStudioAppIPC` must not import the executable target, AppKit, SwiftUI, or
  concrete runtime/app owners.
- `AgentStudioProgrammaticControl` must remain product-contract DTOs only.
- `App/IPCComposition` may import `AgentStudioAppIPC`, but must route through
  explicit adapters and must not mutate atoms directly.
- `AgentStudioIPCCommandAdapter` must not call command-bar presentation seams or
  know `AgentStudioIPCUIPresenting`.
- IPC command handlers must not publish EventBus commands.
- IPC runtime adapters should not downcast to concrete runtime classes for
  exported runtime facts.
- workspace validators must not import AppKit/SwiftUI or read atoms.
- event-backed runtime waits must use replay/subscription facts, not sleeps or
  UI polling.
- architecture lint inventory must list any new rule ids and fixtures.

### R13. Existing IPC Follow-up Spec Must Be Rewritten After Cleanup

Once this precursor spec is implemented, update
`2026-06-15-agentstudio-ipc-runtime-lifecycle-followup.md` so it uses:

- `WorkspaceActionExecutor`;
- `WorkspaceActionCommand`;
- `PaneRuntimeCommand`;
- `AppCommandSpec`;
- `AppCommandDispatcher`;
- `WorkspaceSurfaceCoordinator`;
- command-plane diagrams from this spec;
- explicit command-vs-event-vs-presentation boundaries;
- actor-lane proof expectations;
- explicit security language that ordinals are convenience references, UUID
  handles are the durable authority target, and pane-bound principals are
  pane-lifetime rather than socket-lifetime.

The rewritten follow-up should then focus only on pane-agent lifecycle
revocation and terminal runtime fact proof.

## Security Context

This design is security-sensitive because IPC accepts local external requests
that can manipulate app state, send terminal input, present UI, and later spawn
pane-bound agents.

Assets and privileges:

- workspace pane/tab/drawer graph;
- terminal input authority;
- browser/diff/editor runtime commands;
- UI presentation authority;
- pane-agent subject tokens and grants;
- runtime events that may reveal sensitive metadata;
- future terminal output/readback, which is secret-bearing.

Entry points and untrusted inputs:

- Unix-domain socket JSON-RPC requests;
- CLI arguments converted into JSON-RPC;
- pane-agent helper auth bootstrap;
- method params containing handles, ordinals, UUIDs, paths, URLs, command ids,
  text input, and timeouts.

Trust boundaries:

- IPC transport/auth boundary before any app method executes;
- app IPC target boundary before concrete app owners;
- MainActor app-state boundary;
- pane runtime boundary;
- event publication boundary;
- future MCP/remote adapter boundary.

Security rules:

- target-sensitive methods must authenticate, canonicalize handles against the
  current app snapshot, authorize against the canonical target, then dispatch;
- pane-scoped principals must not use friendly ordinals as durable authority;
- a pane-bound principal must not be able to use `pane:N` ordinals to reach
  another pane without an explicit grant;
- pane-bound token, grant, and authenticated socket revocation is a current
  invariant and must stay green through this cleanup;
- headless command execution must not implicitly open UI;
- broad headless command execution requires command-specific sub-authorization;
- UI presentation requires an explicit presentation privilege;
- terminal input and terminal output/readback require different privileges;
- raw zmx IPC and zmx socket paths are not public authority surfaces;
- approval and grants remain app/authorization-owned, not event-owned.

Auth assumptions:

- callers are local same-user peers before app methods execute;
- subject tokens are single-use;
- pane-agent bootstrap tokens are bound to runtime id and pane identity;
- debug unsafe no-auth and debug token escrow remain debug-channel only;
- pane-agent bearer tokens are not passed through argv or durable environment
  variables;
- pane-bound principals and grants live for pane authority, not for the socket
  connection alone, and must be invalidated when the owning pane authority dies.

Security non-goals for this precursor:

- no new remote transport;
- no MCP implementation;
- no password auth;
- no arbitrary public `AppCommand` execution lane;
- no raw terminal output/readback API;
- no new pane-agent spawn behavior beyond vocabulary and architecture
  preparation;
- no zmx public IPC exposure.

Ordinals such as `pane:1` are human-friendly discovery references, not durable
authority. Automation that will mutate state should resolve and pin canonical
UUID handles before acting, because pane order can change between discovery and
mutation.

## Architecture Lint And Test Strategy

### Compile-Time Boundaries

The existing SwiftPM split already gives compile-time protection for:

- `AgentStudioIPCTransport`;
- `AgentStudioProgrammaticControl`;
- `AgentStudioAppIPC`;
- `AgentStudioIPCClientCore`;
- `AgentStudioIPCClient`;
- `AgentStudioPaneAgent`;
- executable-target app adapters.

This precursor does not require a new SwiftPM target. A future target split may
be useful for workspace action core, but it is not required for the feature-
parity rename.

Inside the executable target, folder boundaries are not compile-time
boundaries. The compiler cannot currently prevent `PaneTabViewController`,
`AppDelegate`, `AppCommandDispatcher`, `WorkspaceActionExecutor`, and the pure
workspace action files from referencing each other if they are all inside
`Sources/AgentStudio`. That is why this slice relies on hard renames, tests,
and SwiftSyntax tripwires for the in-app command plane while leaving larger
target extraction as a later decision.

A future compile-time split should target the pure workspace action layer first:

```text
candidate future target
  WorkspaceActionCommand
  ActionStateSnapshot
  ResolvableTab
  WorkspaceCommandValidator

candidate only after command-intent seam exists
  WorkspaceCommandResolver, because it currently resolves from AppCommand

not first candidate
  AppCommand.swift as it exists today, because it mixes command identity,
  AppKit shortcut types, AppCommandSpec metadata, handler protocols, and
  AppCommandDispatcher in one file.
```

### Architecture Lint Candidates

Add or update repo-local SwiftSyntax architecture lint only where a rule catches
a real failure mode:

```text
ipc_no_eventbus_command_dispatch
  App/IPCComposition must not publish command-like EventBus payloads.

ipc_no_direct_atom_mutation
  App/IPCComposition must route app-state mutation through ports/owners.

workspace_validator_pure
  WorkspaceCommandValidator must not import AppKit, SwiftUI, or app owners.

event_backed_runtime_wait_replay_or_subscribe
  IPC event-backed runtime waits must use PaneRuntime replay/subscription
  contracts. Lifecycle-backed attachReady is excluded until it has an exported
  fact contract.

command_plane_name_guard
  Block reintroduction of WorkspaceActionExecutor, WorkspaceActionCommand, PaneRuntimeCommand,
  AppCommandSpec, AppCommandDispatcher, and WorkspaceSurfaceCoordinator after the hard rename,
  except in changelog/history docs if needed.

ipc_command_ui_separation
  AgentStudioIPCCommandAdapter must not reference command-bar presenters,
  IPCCommandBarOpenParams, IPCCommandBarScope, or UI presentation ports.

ipc_runtime_no_concrete_runtime_downcast
  IPC runtime adapters should not downcast PaneRuntime to TerminalRuntime,
  BridgeRuntime, WebviewRuntime, or other concrete runtime classes.
```

If a rule cannot be expressed accurately in SwiftSyntax without false positives,
use architecture tests or docs instead of a brittle lint.

### Pyramid Proof Gates

The implementation plan should prove the cleanup in layers:

```text
unit
  WorkspaceCommandValidator tests
  WorkspaceCommandResolver tests
  AppCommand / AppCommandSpec contract tests
  PaneRuntime command contract tests

integration
  WorkspaceActionExecutor tests
  WorkspaceSurfaceCoordinator runtime dispatch tests
  IPC layout adapter tests
  IPC runtime adapter tests
  IPC command/UI adapter tests

architecture
  AgentStudioArchitectureLint tests
  architecture fixture failures
  docs architecture tests that guard command-plane wording

smoke
  existing debug IPC smoke remains passing
  no new product capability proof required for the feature-parity rename
  live IPC smoke is required only if the implementation changes runnable IPC
  behavior beyond naming/adapters

repo gate
  mise run build
  mise run lint
  swift test --package-path Tools/AgentStudioArchitectureLint
  relevant AgentStudio tests for touched command/runtime/IPC slices
```

If a repo-wide validation failure is outside this cleanup path, report it as an
unrelated blocker and keep changed-surface proof separate.

## Migration Shape

This should be a hard cutover, not a compatibility layer.

```text
1. Rename type vocabulary
     AppCommandSpec             -> AppCommandSpec
     AppCommandDispatcher       -> AppCommandDispatcher
     WorkspaceActionExecutor          -> WorkspaceActionExecutor
     WorkspaceActionCommand       -> WorkspaceActionCommand
     PaneRuntimeCommand          -> PaneRuntimeCommand
     WorkspaceSurfaceCoordinator         -> WorkspaceSurfaceCoordinator

2. Update app adapters and tests
     IPC layout adapter
     IPC runtime adapter
     terminal snapshot provider / runtime-owned terminal fact seam
     terminal shortcut cases leave WorkspaceActionCommand
     command shortcut/runtime dispatch policy
     PaneTabViewController command paths

3. Update architecture docs and tests
     AGENTS.md
     docs/architecture/README.md
     commands_and_shortcuts.md
     agentstudio_ipc_architecture.md
     pane_runtime_architecture.md
     pane_runtime_eventbus_design.md
     component_architecture.md where command diagrams mention old names
     CoordinationPlaneArchitectureTests string fixtures
     architecture lint inventory if rules are added

4. Add/adjust enforcement
     SwiftSyntax lint rules only for real tripwires
     architecture test fixtures
     no stale type names outside intentional history

5. Rewrite IPC lifecycle follow-up spec
     remove old vocabulary
     import this command-plane model
     narrow it to lifecycle revocation and terminal fact proof
```

## Tradeoffs

```text
Gain
  clearer command ownership
  less chance of IPC becoming a god adapter
  clearer actor hops
  stronger future reviews because names encode boundaries
  easier specs/plans for pane-agent and terminal runtime proof

Pay
  broad mechanical rename across app, tests, and docs
  transient merge conflict risk with nearby command/runtime work
  architecture lint work may discover existing soft violations
  no new product capability until the cleanup lands
  names alone do not split PaneTabViewController's mixed workspace router

Rejected alternative: leave names as-is and document intent
  cheaper now, but keeps the exact confusion that caused this spec

Rejected alternative: generic command actor
  sounds neat, but hides ownership and risks becoming a command bus

Rejected alternative: expose raw AppCommand over IPC
  convenient reuse, but unsafe because the enum includes UI openers,
  chooser/drill-in placeholders, active-selection commands, and commands with
  different privilege requirements
```

## Definition Of Done

This precursor is complete when:

- old type names are removed from production Swift except intentional history;
- tests compile against `WorkspaceActionExecutor`,
  `WorkspaceActionCommand`, `PaneRuntimeCommand`, `AppCommandSpec`,
  `AppCommandDispatcher`, and `WorkspaceSurfaceCoordinator`;
- terminal runtime shortcuts are removed from `WorkspaceActionCommand` or are
  explicitly captured as a temporary mixed-plane exception with a failing
  follow-up test;
- `command.execute` preserves its current open-string id, `requiresPresentation`,
  `unsupportedCommand`, and no-new-`targetHandle` compatibility contract;
- pane-bound token, grant, and authenticated-socket revocation tests still pass;
- command/UI/runtime/event boundaries are documented in architecture docs;
- `AgentStudioIPCRuntimeAdapter` no longer downcasts to concrete runtime classes
  for terminal snapshot facts, or the implementation plan explicitly splits
  that as a first follow-up with a failing architecture test;
- architecture lint/tests enforce the new boundary where practical;
- feature-parity command and IPC tests pass for touched slices;
- the IPC runtime lifecycle follow-up spec is rewritten to use this vocabulary;
- no public IPC method contract is broadened by this cleanup.

## Follow-Up Decisions

1. Runtime dispatch ownership is no longer open in this precursor.
   Runtime IPC dispatch moved behind `PaneRuntimeCommandDispatching`, backed by
   `WorkspaceSurfaceCoordinator.dispatchRuntimeCommand`. `WorkspaceActionExecutor`
   no longer owns a runtime-command forwarding method.

2. Should command-plane name guards block stale names in docs too?

   Recommended default: block stale names in production Swift and architecture
   docs, but allow old names in historical specs only if they are explicitly
   marked as historical.

3. Should a future target split extract workspace action core?

   Recommended default: not in this slice. First finish the hard rename and lint
   tripwires. Revisit target extraction only if compile-time enforcement gaps
   remain material after the cleanup.

4. Should `command.execute` gain a curated headless catalog in this cleanup?

   Recommended default: no. Preserve the current narrow/empty command catalog
   during the feature-parity cleanup. Add curated headless commands only in a
   later capability slice with command-specific sub-authorization and explicit
   proof that no UI presentation path is reachable.
