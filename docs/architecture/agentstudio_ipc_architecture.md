# AgentStudio App IPC Architecture

AgentStudio app IPC is the app-level programmatic-control boundary for local
automation, pane agents, and future MCP adapters. It exposes semantic app
methods over local transports without exposing zmx daemon IPC as a public API.

## Status

The phase-1 foundation currently owns:

- SwiftPM target split for transport, public contracts, and app IPC services.
- JSON-RPC 2.0 request/response and server-notification codec over
  newline-delimited JSON frames.
- Unix-domain socket transport primitives and peer-credential checks.
- Socket path and runtime metadata trust checks.
- Subject-token authentication, principal registry, and redaction helpers.
- Phase-1 method catalog, handle parsing, authorization, grant ledger, and
  permission broker policy/delegation primitives.
- Concrete app query adapter for system/window/workspace/pane read snapshots.
- Concrete layout adapter for `pane.focus` through the existing focus owner
  chain.
- Concrete terminal runtime adapter for `terminal.status`,
  `terminal.snapshot`, and `terminal.send`.
- Public event-name contracts and permission-event DTOs for phase-1 exported
  notifications.
- Permission recovery queries for requester-owned request/grant state and
  delegated approval visibility.
- Event broker subscription state, notification encoding, visibility filtering,
  inbound server-event rejection, and slow-subscriber ejection.

Follow-up implementation slices still own socket-server lifecycle wiring,
CLI/client commands, and promotion of completed design material from the
temporary spec/plan docs.

## Target Ownership

```
AgentStudioIPCTransport
  Owns:     Unix socket primitives, NDJSON framing, JSON-RPC codec,
            peer-credential lookup.
  Imports:  Foundation, Darwin.
  Must not: Import AgentStudio, app state, runtime owners, or product models.

AgentStudioProgrammaticControl
  Owns:     Public semantic contracts: handles, principals, scopes,
            method metadata, permission DTOs, schema descriptions.
  Imports:  Foundation.
  Must not: Import SwiftUI/AppKit, AgentStudio, app state, or concrete runtime
            owners.

AgentStudioAppIPC
  Owns:     App IPC service shell, socket path trust, authentication,
            method registry, authorization, grant ledger, permission broker,
            event broker, and protocol ports into app/runtime owners.
  Imports:  Transport and ProgrammaticControl targets.
  Must not: Import concrete app/runtime owner types or read atoms directly.

AgentStudio/App/IPCComposition
  Owns:     Concrete port adapters from AgentStudioAppIPC protocols into
            PaneCoordinator, RuntimeRegistry, PaneRuntime, and app state
            owners.
  Imports:  AgentStudioAppIPC plus the concrete app modules it adapts.
```

The target split is intentionally stricter than the folder split. A file in
`AgentStudioProgrammaticControl` cannot accidentally call app code because the
compiler has no dependency edge for it. `AgentStudioAppIPC` can define ports and
own policy, but concrete behavior enters through protocol implementations in
the app target.

## Query Snapshot Boundary

Phase-1 read methods are served through `AgentStudioIPCQueryAdapter` in
`AgentStudio/App/IPCComposition`. The adapter does not read atoms directly. It
depends on two snapshot seams:

```
AppIPC query method
  -> AgentStudioIPCQueryAdapter
  -> WorkspaceStore.programmaticControlSnapshot()
       owns atom reads inside WorkspaceStore
  -> WorkspaceWindowLifecycleReading.snapshot()
       owns window lifecycle atom reads outside IPC composition
  -> AgentStudioProgrammaticControl DTO
```

The query adapter intentionally exposes a sanitized app-level view. Pane
snapshots include stable app identity facts such as pane id, title, content
kind, residency, active state, tab id, repo id, and worktree id. They do not
include raw URLs, cwd paths, command lines, terminal buffers, zmx session ids,
or backend daemon details. Terminal content requires the dedicated terminal
runtime adapter and stricter terminal privileges in later slices.

## Pane Focus Boundary

`pane.focus` is a layout/app-control method, not an atom mutation. Phase 1
routes it through two named seams:

```
AppIPC layout method
  -> AgentStudioIPCLayoutAdapter
       verifies active workspace window
       resolves pane handle by UUID or friendly ordinal
  -> PaneFocusAppControlling
  -> PaneTabViewControllerPaneFocusAppControl
       validates pane belongs to a tab
  -> PaneTabViewController.execute(.focusPane, target:targetType:)
  -> existing PaneFocusTrigger / PaneFocusOrchestrator / PaneFocusExecutor path
```

This split keeps IPC responsible for protocol concerns and keeps focus behavior
owned by the existing app focus pipeline. The adapter maps no-active-window,
missing-target, and validation-rejected outcomes into AppIPC layout errors so
the future JSON-RPC layer can publish stable error codes without reaching into
controller internals.

## Terminal Runtime Boundary

Terminal runtime methods are runtime/app-control methods, not shell-completion
or terminal-buffer APIs. Phase 1 routes them through `AgentStudioIPCRuntimeAdapter`:

```
terminal.status / terminal.snapshot
  -> AgentStudioIPCRuntimeAdapter
       resolves pane handle by UUID or friendly ordinal
       requires a terminal pane
  -> RuntimeRegistry.runtime(for:)
  -> PaneRuntime.snapshot()
  -> allowlisted AgentStudioProgrammaticControl DTO

terminal.send
  -> AgentStudioIPCRuntimeAdapter
       resolves pane handle by UUID or friendly ordinal
       requires a terminal pane and registered runtime
  -> ActionExecutorRuntimeCommandDispatcher
  -> ActionExecutor.dispatchRuntimeCommand(.terminal(.sendInput), correlationId:)
  -> PaneCoordinator.dispatchRuntimeCommand
  -> RuntimeRegistry.runtime(for:)
  -> PaneRuntime.handleCommand(...)

terminal.wait
  -> AgentStudioIPCRuntimeAdapter
       resolves pane handle by UUID or friendly ordinal
       requires a terminal pane and registered runtime
  -> EventBus<RuntimeEnvelope>.waitForFirst(...)
  -> allowlisted terminal wait result
```

`terminal.send` success means the runtime command path accepted the input bytes.
It does not mean the shell command completed, produced output, or reached a
particular prompt. Those higher-level observations belong to `terminal.wait`
conditions and runtime events.

`terminal.wait` resolves only stable exported facts. `attachReady` can be
satisfied immediately from a ready registered runtime. `commandFinished`,
`rendererHealthy`, `titleChanged`, `cwdChanged`, and `progressChanged` wait on
matching `RuntimeEnvelope.pane` terminal facts for the resolved pane. Wait
results carry command/correlation ids and safe scalar data such as exit code,
duration, and renderer health; they do not expose terminal titles, cwd paths, or
progress payload text.

The terminal DTOs intentionally omit terminal output, scrollback, raw PTY bytes,
cwd/launch paths, command lines, zmx session identifiers, raw runtime objects,
and content-bearing UI state such as search/progress details. The adapter maps
missing panes, missing runtimes, runtime-not-ready, unsupported command,
backend-unavailable, validation-rejected, and timeout outcomes into AppIPC
runtime errors for the future JSON-RPC layer.

## Event And Permission Recovery Boundary

Phase 1 exposes a stable event vocabulary in `AgentStudioProgrammaticControl`.
The exported names are semantic app/runtime facts, not internal enum cases:

```
permission.requestCreated
permission.requestResolved
permission.grantRevoked
permission.grantExpired
terminal.attachReady
terminal.commandFinished
terminal.rendererHealthy
terminal.titleChanged
terminal.cwdChanged
terminal.progressChanged
```

Live subscriptions are owned by `IPCEventBroker` in `AgentStudioAppIPC`:

```
events.subscribe
  -> authenticated connection principal
  -> AuthorizationService(eventsRead, target scope)
  -> IPCEventBroker.subscribe(...)
       stores subscription id, principal, allowed event names, subscriber sink

public app/runtime fact
  -> IPCEventNotification
  -> IPCEventBroker.publish(...)
       filters by event-name allowlist
       filters by principal visibility
       encodes JSON-RPC events.notification frame
       removes subscribers that report backpressure or delivery failure

events.unsubscribe
  -> authenticated connection principal
  -> IPCEventBroker.unsubscribe(...)
       succeeds only for a subscription owned by the same principal
```

The broker does not approve grants, mutate app state, or inspect raw runtime
envelopes. It receives already-projected public DTOs and an explicit visibility
predicate from the owning projector. Client-sent `events.notification` frames
and frames whose method is a server event name are rejected as reserved inbound
notifications; event notifications are server-to-client facts only.

Permission event payloads are built from broker records and scoped through
`PermissionEventProjector`. Visibility is intentionally narrower than ordinary
event subscription:

```
permission record
  -> PermissionEventProjector
  -> requester principal
       always sees its own request/grant events
  -> delegated approver principal
       sees routed requests only when token authority covers the full scope
  -> app/policy approval principal
       sees app/human approval requests only when policy authority covers scope
  -> unrelated principal
       sees nothing
```

Missed permission events are recoverable through explicit queries rather than a
durable event log. Requesters recover their own state through
`permission.requestStatus` and `permission.grantStatus`; delegated approvers
recover routed pending requests through `permission.pendingApprovals`.

## Request Authority Path

```
local client
  -> Unix socket + NDJSON frame
  -> JSON-RPC request
  -> peer credential gate
  -> auth.login / subject token check
  -> IPCPrincipal
  -> AppIPCMethodRegistry
  -> target handle canonicalization
  -> AuthorizationService
       baseline self-pane privileges
       + GrantLedger elevated grants
  -> AppIPC port protocol
  -> App/IPCComposition adapter
  -> app/runtime owner
```

IPC methods are not command-bus messages. The app IPC layer validates method
identity, principal authority, target scope, and grants before calling the
smallest app-owned protocol port that can satisfy the operation.

## Auth And Permissions

Authentication and authorization are separate:

- Authentication proves the caller is a known local principal.
- Authorization decides whether that principal can use a method against a
  target and data scope.

Phase 1 uses opaque subject tokens issued by the app. Spawn environments may
carry non-secret routing metadata such as socket path and runtime id, but they
must not carry bearer tokens. A spawned pane agent receives its pane-bound
credential through a non-enumerable bootstrap channel owned by the app spawn
adapter. `auth.login` binds the token to the principal recorded in the registry;
the caller cannot upgrade itself by passing a different pane hint.

Baseline authority is intentionally small. A pane-bound agent gets self-pane
authority for low-risk introspection and scoped terminal operations. Anything
outside that baseline requires an explicit grant.

Permission requests flow through the permission broker:

```
permission.request
  -> canonical permission scope
  -> policy store
       approve | deny | ask
  -> optional human approval port or delegated approver principal
  -> GrantLedger state transition
  -> permission event notification
```

Delegated approval is part of the configured authority model, not a loophole in
the request path. A principal may approve only when its token/policy gives it
approval authority for the full requested scope: privilege, target, and data
scope. Self-approval fails closed unless a future design explicitly adds and
audits that policy.

Permission data scope is derived server-side from the requested privilege during
canonicalization. Clients may ask for a scope, but they do not get to choose a
grant key that differs from the authorization key the server will later check.

Human approval is app-owned through `AppIPCPermissionApprovalPort`. The broker
can route a `.humanPrompt` request to that port, but the port implementation
belongs in `AgentStudio/App/IPCComposition` so the reusable AppIPC target does
not import concrete UI owners.

## Boundary Rules

- Do not expose public `zmx.*` methods from AgentStudio app IPC.
- Do not route IPC commands through `EventBus`; events remain facts and
  notifications.
- Do not mutate atoms directly from IPC services or composition adapters.
- Do not put concrete app/runtime owner imports in `AgentStudioAppIPC`.
- Do not implement MCP in the phase-1 IPC server. MCP should be an adapter over
  the same semantic method registry after the local RPC contract is stable.

## Enforcement

Compile-time target boundaries provide the first guardrail:

- `AgentStudioIPCTransport` has no product dependency.
- `AgentStudioProgrammaticControl` has no app dependency.
- `AgentStudioAppIPC` depends on ports, not concrete app/runtime owners.

Architecture lint provides the second guardrail:

- `agentstudio_ipc_programmatic_control_boundary`
- `agentstudio_appipc_port_boundary`
- `agentstudio_ipc_composition_location`
- `agentstudio_ipc_public_surface_sanitization`
- `agentstudio_ipc_no_direct_atom_access`

Design docs and specs are the third guardrail. They should explain intent and
tradeoffs, but compile-time dependencies and lint rules are the blocking
controls.
