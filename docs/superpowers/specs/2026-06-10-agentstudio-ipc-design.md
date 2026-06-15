# AgentStudio IPC Design

**Date:** 2026-06-10
**Scope:** `agent-studio.programatical-control`
**Status:** Target design for the AgentStudio app-level IPC slice.

## Status And Document Lifecycle

This spec is the source of truth for the design and implementation plan. After
the implementation lands and the boundaries have been verified, the durable
decisions must move into `docs/architecture/`:

- IPC service ownership and module boundaries move into `directory_structure.md`
  and `appkit_swiftui_architecture.md`.
- IPC auth, subject-token, principal, grant, and approval-port boundaries move
  into the app/runtime architecture docs with the implemented file paths.
- Runtime command and event rules move into `pane_runtime_architecture.md` and
  `pane_runtime_eventbus_design.md`.
- Terminal-backend zmx IPC details remain in `session_lifecycle.md`,
  `zmx_terminal_integration_lessons.md`, or the backend-only design track in
  `2026-06-13-zmx-backend-ipc-design.md`.

Architecture promotion is part of the implementation closeout. This spec should
then become implementation history, not the permanent architecture entrypoint.

## Goal

Add an AgentStudio app-level IPC surface for local agents and CLI automation.

The first implementation slice exposes a local Unix-domain socket speaking
strict JSON-RPC 2.0. The service routes requests into existing AgentStudio
command and runtime owners instead of becoming a new mutation owner. The method
catalog is designed so a later MCP adapter can reuse the same semantic registry
and JSON schemas without making MCP the phase-1 wire protocol.

Phase 1 also defines the authority model for pane-local agents: authentication
resolves to a server-bound principal, baseline authority is represented as scoped
grants, and elevated authority is requested through explicit `permission.*`
methods. Permission events are observations only; they do not grant, deny,
revoke, or execute authority.

## Non-Goals

- Do not expose zmx daemon IPC as the public AgentStudio API.
- Do not implement MCP as a phase-1 transport.
- Do not implement TCP, WebSocket, or remote app-control transport in phase 1.
- Do not add a V1 line-oriented text protocol.
- Do not support JSON-RPC batch requests in phase 1.
- Do not stream terminal output as events in phase 1.
- Do not expose zmx history, scrollback, or terminal output payloads in phase 1.
- Do not add password auth in phase 1.
- Do not add an `allowAll` or world-writable production mode.
- Do not expose remote zmx sockets, SSH-forwarded zmx sockets, or raw zmx
  daemon transports in phase 1.
- Do not route commands through the EventBus.
- Do not expose arbitrary internal event names or raw runtime envelopes as the
  public event/wait contract.
- Do not mutate atoms directly from IPC methods.

## Grounding In The Current System

AgentStudio already has the internal seams needed for external control:

- `AppDataPaths` owns channel-aware roots for stable, beta, and debug state.
- `AppDelegate` composes app-wide services during workspace boot.
- `CommandDispatcher` is the shared entry point for app commands.
- `PaneTabViewController` owns the current validated pane action path.
- `PaneCoordinator.dispatchRuntimeCommand` routes runtime commands through
  `RuntimeRegistry` and returns structured `ActionResult`.
- `PaneRuntime` already exposes command, subscription, snapshot, and event
  methods.
- Bridge has useful JSON-RPC 2.0 parsing and typed method registration, but it
  is pane-local WebKit transport, not the app-level IPC service.

The existing runtime architecture separates three planes:

```text
event plane
  producers -> EventBus -> consumers
  one-way facts only

command plane
  user/system -> coordinator -> runtime
  request-response; never through EventBus

UI plane
  runtime -> SwiftUI view
  @Observable first, then optional bus post
```

AgentStudio IPC follows the same split. External requests enter through the
command plane or query/snapshot readers. Event subscriptions observe facts; they
do not execute commands.

## Layer Model

```text
external client / CLI / in-terminal agent
  |
  v
AgentStudio IPC service
  socket lifecycle
  metadata discovery
  auth and access-mode policy
  JSON-RPC 2.0 framing, parsing, encoding
  schema validation
  handle resolution
  connection limits and event subscriptions
  |
  v
App control method registry
  method name
  input and output schema
  privilege class
  execution owner
  result semantics
  |
  +--> app command adapter
  |     CommandDispatcher and app/window command owners
  |
  +--> workspace action adapter
  |     resolver, validator, and PaneCoordinator action seam
  |
  +--> runtime command adapter
  |     PaneCoordinator.dispatchRuntimeCommand(...)
  |
  +--> query adapter
  |     read-only workspace/window/pane/runtime snapshots
  |
  +--> event adapter
        subscriptions over existing authoritative facts
```

zmx IPC is below this model:

```text
AgentStudio public IPC
  panes, windows, workspaces, terminal operations, runtime snapshots

Terminal runtime backend
  ZmxBackend / SessionRuntime

zmx daemon IPC
  one terminal daemon/session
  binary protocol
  one-shot backend operations
```

Public IPC never exposes zmx binary tags, zmx socket paths, zmx `Info` bytes, or
the zmx trust model.

## Module Boundaries

The implementation should split generic transport mechanics from product
semantics with SwiftPM targets, not only folders. The goal is compile-time
pressure first, lint pressure second, and prose guidance third.

```text
AgentStudioIPCTransport
  Sources/AgentStudioIPCTransport/
  Unix socket helpers, peer credentials, NDJSON framing, JSON-RPC codec
  no product imports

AgentStudioProgrammaticControl
  Sources/AgentStudioProgrammaticControl/
  method contracts, schema descriptions, handle model, privilege/data/target
  scope value types, permission DTOs
  no AppKit, view-controller, Feature, or App executable dependencies

AgentStudioAppIPC
  Sources/AgentStudioAppIPC/
  service lifecycle, metadata publication, subject-token minting, connection
  auth state, principal registry, GrantLedger, AuthorizationService, method
  registry assembly, and protocol ports
  no direct CommandDispatcher, PaneCoordinator, TerminalRuntime, SurfaceManager,
  Feature, or view-controller imports

AgentStudio executable target
  Sources/AgentStudio/App/IPCComposition/
  concrete port adapters into CommandDispatcher, ActionExecutor,
  WorkspaceCommandValidator, PaneCoordinator, RuntimeRegistry, PaneRuntime, and
  app-owned approval UI/queue
```

`Features/` is not the right home for the app-level service. Feature transport
such as Bridge belongs inside a feature because it is pane-local. App IPC is
cross-feature app composition.

`AgentStudioAppIPC` must define protocol ports instead of importing concrete app
owners. The executable target implements those ports. This prevents AppIPC from
becoming a god box: it can authenticate, authorize, route by registry metadata,
and ask ports to execute, but it cannot own product behavior or mutate app state
directly.

PR #175's SwiftLint/SwiftSyntax architecture runner is the substrate for
repository-specific enforcement. IPC-specific rules still need to be added.
Those rules should reject forbidden target imports, direct atom mutation from IPC
adapters, public registry methods under `zmx.*`, and public IPC DTOs containing
raw `RuntimeEnvelope`, raw `PaneRuntimeSnapshot`, raw `PaneMetadata`, or zmx
internals.

## Transport And Discovery

Phase 1 uses a local Unix-domain socket.

```text
root
  AppDataPaths.rootDirectory()

metadata
  <root>/ipc/runtime.json

socket
  <root>/ipc/agentstudio.sock
```

The `ipc` directory must be owner-only. The socket must be owner-only. The
metadata file must be owner-only. Socket paths must be derived from the
channel-aware app root, not from worktree or workspace paths, so they stay under
the macOS `sun_path` limit and never cross stable, beta, or debug channels.

The IPC service must fail closed when the filesystem boundary is not trustworthy:

- the app root, `<root>/ipc`, socket path, metadata path, and any future
  automation token file must be owned by the current uid;
- the IPC directory, socket, metadata file, and token file must not be group- or
  world-accessible;
- symlinked IPC paths are refused;
- metadata writes are atomic replace operations;
- `AGENTSTUDIO_DATA_DIR` is allowed only when the resolved root passes the same
  ownership and permission checks.

Metadata includes only non-secret discovery facts in `agentStudioOnly`:

```json
{
  "schemaVersion": 1,
  "runtimeId": "uuid",
  "pid": 12345,
  "channel": "stable",
  "socketPath": "/Users/name/.agentstudio/ipc/agentstudio.sock",
  "startedAt": "2026-06-10T12:00:00Z",
  "protocol": "agentstudio-ipc-jsonrpc-2"
}
```

In `automationSameUser`, metadata may include a token file pointer or a token
only if the mode explicitly accepts that every same-user process with file
access can use the app-control socket. This must not be described as
`agentStudioOnly`.

Stale socket behavior:

1. On startup, probe an existing socket.
2. If the socket responds with the same runtime identity, keep it.
3. If the socket is dead, unlink and bind.
4. If the socket belongs to a live different same-channel process, do not steal
   it silently.

## JSON-RPC 2.0 Wire Contract

The local socket uses newline-delimited JSON-RPC 2.0. Each frame is one UTF-8
JSON object followed by `\n`.

Valid request:

```json
{"jsonrpc":"2.0","id":"1","method":"system.identify","params":{}}
```

Valid success response:

```json
{"jsonrpc":"2.0","id":"1","result":{"runtimeId":"..."}}
```

Valid error response:

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "error": {
    "code": -32010,
    "message": "Authentication required",
    "data": {"method": "terminal.send"}
  }
}
```

Rules:

- Every request object must include `jsonrpc: "2.0"`.
- `params` must be an object when present.
- Notifications are allowed only for methods explicitly marked
  fire-and-forget.
- Batch arrays are rejected with invalid request.
- Responses use `result` xor `error`.
- Standard JSON-RPC error codes keep their standard meaning.
- AgentStudio-specific errors use a reserved app range.
- Tokens and other secrets must never appear in logs or error payloads.

Phase-1 error range:

```text
-32700  parse error
-32600  invalid request
-32601  method not found
-32602  invalid params
-32603  internal error

-32001  unauthenticated
-32002  unauthorized
-32003  unsupported capability
-32004  target not found
-32005  runtime not ready
-32006  no active window
-32007  validation rejected
-32008  request too large
-32009  server busy
-32010  stream gap or replay unavailable
```

## Auth And Access Modes

IPC is security-sensitive. Access to the socket can drive terminal input,
observe app/runtime state, mutate pane layout, and eventually control browser or
webview surfaces. The threat model is local by default, but local access is
still powerful.

Threat actors and entry points:

- the Agent Studio app process;
- Agent Studio-spawned terminal child processes and their descendants;
- arbitrary same-uid local processes;
- future external CLI clients;
- future MCP adapter or plugin host processes;
- future SSH-forwarded zmx paths and the remote host/user that owns them.

All app IPC requests, event subscriptions, handles, replay cursors, and zmx
response bytes are untrusted inputs until validated by the layer that receives
them.

Phase 1 uses cmux-shaped access modes with an Orca-style environment bootstrap,
adjusted so `agentStudioOnly` authenticates a specific spawned subject rather
than every process that knows a runtime-wide shared token.

```text
off
  no socket listener

agentStudioOnly
  recommended phase-1 default
  socket and metadata are owner-only
  peer uid must match the app owner
  subject tokens are memory-only
  subject token and socket path are injected into AgentStudio-spawned sessions
  no token is written to disk

automationSameUser
  explicit opt-in mode for external local CLI/tools
  socket and metadata are owner-only
  peer uid must match the app owner
  token can be discoverable through owner-only metadata or a token file
  the mode honestly grants same-user automation to any same-uid process that can
  obtain the bootstrap material

password
  reserved follow-up mode
  persistent user-configured secret
  not phase 1

unsafeDebug
  debug/env-only escape hatch
  never a normal production setting
```

`agentStudioOnly` requires memory-only token custody. If the token is written to
disk, any same-user process can read it and the mode collapses into
`automationSameUser`.

In `agentStudioOnly`, the exported bearer value is an opaque subject token. The
environment variable name stays `AGENTSTUDIO_IPC_TOKEN`, but the token's phase-1
meaning is per spawned subject, not one shared app-runtime token. AppIPC mints
the token before terminal/session environment construction, records it in private
runtime memory, and maps it to one `IPCPrincipal`.

```text
Subject token
  opaque bearer token injected into one spawned pane/session
  stored only in AppIPC runtime memory
  maps to one IPCPrincipal
  rotates with listener/runtime identity changes
  never logged, persisted, echoed, or trusted because of caller-supplied params
```

Subject-token minting is eager:

```text
pane/session spawn begins
  -> AgentStudioAppIPC mints subject token
  -> AgentStudioAppIPC records token -> principalId + boundPaneId in memory
  -> AgentStudioAppIPC returns env vars to the app's terminal spawn seam
  -> terminal/session process inherits token
```

`auth.login` only looks up the supplied token in this private registry. It never
accepts a caller-supplied pane hint, friendly ref, active focus, or environment
value as the source of principal binding.

The app injects the token and socket path into spawned terminal sessions:

```text
AGENTSTUDIO_IPC_SOCKET=<socket path>
AGENTSTUDIO_IPC_TOKEN=<opaque subject token>
AGENTSTUDIO_IPC_RUNTIME_ID=<runtime id>
```

Optional non-secret diagnostics may include
`AGENTSTUDIO_IPC_PRINCIPAL_HINT=<principal id>`, but the hint is never trusted.
Only the token lookup inside AppIPC binds the principal.

The first client request on a connection must authenticate:

```json
{
  "jsonrpc": "2.0",
  "id": "auth-1",
  "method": "auth.login",
  "params": {"token": "subject-token"}
}
```

The server stores authenticated principal state per connection. Before
successful authentication, only `auth.login` and an explicitly pre-auth
`system.ping` are allowed. That `system.ping` response must return no runtime
metadata. All other methods fail with `-32001 unauthenticated`. `auth.login` is
retained as the stable method name so a later password mode does not require a
wire-protocol break.

Peer credential checks run before token validation. Same-uid checks are required
in every enabled mode. `agentStudioOnly` may additionally use peer PID ancestry
when available, but the subject token remains the primary capability for spawned
agents. If peer credentials cannot be obtained, the connection is rejected before
JSON-RPC dispatch. Repeated authentication failures or malformed authentication
frames close the connection.

### Principals

```text
IPCPrincipal
  principalId: UUID
  runtimeId: UUID
  accessMode: off | agentStudioOnly | automationSameUser | unsafeDebug
  kind:
    spawnedPaneAgent(boundPaneId: PaneId, boundWorkspaceId: UUID?)
    automationClient
    futureMCPClient
    unsafeDebugClient
  approvalAuthority:
    none
    policyConfigured(scopes)
    delegatedApprover(scopes)
```

`selfPane` means the canonical `boundPaneId` attached to the authenticated
principal by the server. It is not:

- the currently focused pane;
- a caller-supplied pane id;
- a friendly ordinal;
- a value read from an environment variable;
- a runtime target resolved after focus changes.

Principal lifetime is tied to the bound pane and app runtime. When a bound pane
closes, AppIPC invalidates that pane's subject tokens, removes the principal,
revokes baseline and elevated grants for that principal, and rejects future
`auth.login` attempts with `-32001 unauthenticated`. Runtime id changes, listener
restart, and token rotation also invalidate principals and grants.

The subject token stays opaque. Approval authority is attached to the
server-side principal record and app-owned policy records, not encoded as claims
inside the bearer token. This keeps the token lookup as the trust boundary and
prevents leaked environment tokens from becoming self-describing authority blobs.

## Privilege Classes

Every method declares a privilege class:

```text
systemRead
  identify, ping, version, capabilities

workspaceRead
  list/current windows, workspaces, tabs, panes, and runtime summaries

paneContextRead
  pane identity, focus, runtime attachment status, and redacted pane context

layoutMutate
  focus, split, close, select, move

terminalRead
  reserved broad terminal read class; phase-1 grants should prefer the narrower
  terminalStatusRead, terminalSnapshotRead, and terminalWait classes

terminalWrite
  reserved broad terminal write class; phase-1 grants should prefer the narrower
  terminalInputWrite class

terminalStatusRead
  terminal/runtime status without terminal output

terminalSnapshotRead
  bounded redacted snapshots without raw output, scrollback, zmx, paths, URLs, or
  secrets unless explicitly redacted

terminalInputWrite
  send input bytes or supported input-like terminal runtime commands

terminalWait
  wait on exported terminal condition enum values

eventsRead
  subscribe to lifecycle/status event streams

permissionRequest
  create scoped permission requests

permissionRead
  read the caller's own permission requests and grants

grantApprove
  approve or deny delegated permission requests within an explicitly configured
  approval scope, and list pending requests routed to the approver

debugUnsafe
  debug-only operations
```

Phase 1 must separate terminal read and terminal write. Future scoped tokens can
grant subsets of these classes without changing method definitions.

Grants refine privilege classes with target and data scopes:

```text
targetScope
  selfPane
  pane:<uuid>
  workspace:<uuid>
  appGlobal, reserved for high-risk approvals

dataScope
  runtimeMetadata
  paneContext
  terminalStatus
  terminalSnapshotRedacted
  terminalInput
```

Data scopes are allowlists, not aliases for current internal structs. Phase-1
redacted DTOs must exclude cwd, title text, note text, repo/worktree paths,
launch directory, command text, prompt text, terminal rows, scrollback, raw
`PaneRuntimeSnapshot`, raw `PaneMetadata`, zmx socket paths, zmx session names,
and zmx history unless a later method contract explicitly promotes and redacts a
field.

### Baseline Grants

After authentication, AppIPC derives baseline grants from the principal. These
are not approved per request, but they are checked by the same authorization
path as elevated grants.

Recommended baseline for `spawnedPaneAgent(boundPaneId: A)`:

```text
targetScope
  selfPane(A)

privileges
  systemRead
  paneContextRead
  terminalStatusRead
  terminalSnapshotRead
  terminalInputWrite
  terminalWait
  eventsRead
  permissionRequest
  permissionRead

dataScope
  runtimeMetadata
  paneContext
  terminalStatus
  terminalSnapshotRedacted
```

This is an intentional trust decision: a process spawned inside pane A may send
input to pane A without a later approval prompt. Approval is required for
authority outside the bound pane and for future high-risk actions that are not in
the baseline set.

Denied by default for a spawned pane principal:

```text
window.list
workspace.list
global pane.list
terminal.send to another pane
pane.focus to another pane
pane.close / pane.split
raw terminal output / scrollback
zmx.*
debugUnsafe
```

The method surface is per principal, not only per protocol. A method can be
phase-1 available while still denied to a narrow spawned-pane principal.

`automationSameUser`, future MCP clients, and future plugin principals require
explicit baseline tables before they are enabled. They must not inherit the
spawned-pane baseline or broad app authority by default.

### Grant Ledger And Authorization

`GrantLedger` is the authoritative in-memory state ledger for permission
requests and active grants. It does not own app behavior, target resolution, or
feature-specific policy.

```text
AgentStudioProgrammaticControl
  IPCPrincipal value contracts
  IPCPrivilege / IPCDataScope / IPCTargetScope
  PermissionRequestParams / PermissionRequestResult
  PermissionEvent DTOs
  registry metadata

AgentStudioAppIPC
  subject-token minting and lookup
  connection auth state
  GrantLedger runtime state
  PermissionBroker
  AuthorizationService
  PermissionScopeCanonicalizer
  PermissionApprovalPort protocol
  ApprovalPolicyStore protocol

AgentStudio executable / App/IPCComposition
  concrete PermissionApprovalPort implementation
  concrete ApprovalPolicyStore implementation
  human approval UI / queue
  delegated-principal delivery
  adapters to existing app owners
```

`AuthorizationService` checks method metadata, authenticated principal, resolved
canonical target, baseline grants, and active grants. Existing app/runtime
owners still validate and execute behavior.

`PermissionScopeCanonicalizer` is the single owner of grant target/scope
normalization. Permission issuance and permission consumption both use this same
canonicalizer before touching `GrantLedger`.

```text
permission.request
  -> canonicalize requested scope
  -> store canonical pending request

privileged method call
  -> canonicalize resolved method target
  -> compare against canonical active grants
```

`GrantLedger` stores only canonical grant keys. It does not resolve friendly
refs, read active focus, inspect UI state, or call feature/runtime owners.

### Permission Requests And Approval Routes

`permission.request` is a JSON-RPC method. It belongs to the command plane.

```text
Pane Agent
  -> permission.request
       privilege: terminalInputWrite
       target: pane:B
       dataScope: terminalInput
       reason: "run tests in paired build pane"
       requestedDuration: 15m
       approvalRoute: appPolicy | humanPrompt | delegatedPrincipal
  -> AppIPC validates and canonicalizes requested scope
  -> GrantLedger records pending request
  -> PermissionBroker resolves the approval route
```

Approval is policy-routed, not always human-in-the-loop:

```text
appPolicy
  app-owned rule decides approve, deny, or ask
  rules are configured by the user or trusted app settings beforehand

humanPrompt
  app presents the request to the user and records the decision

delegatedPrincipal
  request is directed to an authenticated principal that has grantApprove for
  the requested canonical scope
```

The human/user is the policy author and fallback approver. They do not have to be
in every request path unless the selected policy says to ask.

Events can announce state changes after the command path updates the ledger.
Events do not grant, deny, revoke, execute, or acknowledge authority transitions.

Phase 1 adds the `permission.*` namespace to the registry:

```text
permission.request
  create a pending permission request

permission.requestStatus
  read the caller's own request state by requestId

permission.grantStatus
  read the caller's own active/expired/revoked grants

permission.pendingApprovals
  list pending requests routed to this delegated approver
  allowed only for principals with grantApprove over the returned canonical scope

permission.resolveRequest
  approve or deny a delegated request
  allowed only for principals with grantApprove over the requested scope
```

`permission.pendingApprovals` and `permission.resolveRequest` are not general
admin methods. They expose only requests routed to the authenticated approver and
only when that approver has `grantApprove` over the canonical requested scope.
Approval through preconfigured app policy and human prompt still flows through
the app-owned `PermissionApprovalPort`.

`permission.request` has `accepted` result semantics because the requested grant
may resolve after policy or delegated approval. The immediate response returns
enough information to correlate later events:

```json
{
  "requestId": "uuid",
  "state": "pending",
  "principalId": "uuid",
  "requestedScope": {},
  "approvalRoute": "appPolicy",
  "expiresAt": null
}
```

Immediate auto-deny or auto-grant is allowed when app policy can decide without
interactive mediation. It must still return a request id and emit the same public
permission event shape.

Because events are non-durable, request and grant status must also be queryable.
A client that disconnects after `permission.request` can later authenticate as
the same principal and call `permission.requestStatus(requestId)` or
`permission.grantStatus(...)`. These methods return only the caller's own
permission state unless a future privileged observer model is explicitly added.
Delegated approvers recover missed routed requests with
`permission.pendingApprovals`, which returns only pending requests that are
routed to that authenticated principal and covered by its `grantApprove` scope.

Grant lifetime is split by risk:

```text
baseline selfPane grants
  principal-bound
  valid while the subject token, bound pane, and app runtime remain valid

read-only elevated grants
  may be principal-bound with a short TTL if explicitly approved

cross-pane or global mutating grants
  connection-bound by default
  one-shot when the method can naturally consume one grant
  never reconnectable unless a later spec explicitly chooses that risk
```

Subject-token theft is principal impersonation for the lifetime of that token and
any principal-bound grants. This is an accepted local threat in
`agentStudioOnly`, not a property the grant system can make impossible. The
phase-1 design narrows the blast radius by keeping elevated mutating grants
connection-bound or one-shot by default.

Phase-1 enum defaults:

```text
DelegationPolicy
  none
    grant is usable only by the authenticated principal and current connection
  principalBearer
    grant is usable by any connection authenticated as the same principal
    allowed only for baseline or explicitly approved read-only grants
  oneShot
    grant is consumed by the first authorized matching command

RevocationTrigger
  ttlExpired
  connectionClosed
  paneClosed
  targetDisappeared
  listenerRestarted
  runtimeIdChanged
  tokenRotated
  explicitRevoke
  consumed
```

## Method Registry

The method registry is the shared semantic contract. It is not tied to the
local socket adapter or MCP.

Each method definition contains:

```text
method name
  dot namespace, for example terminal.send

params schema
  machine-readable JSON schema or equivalent schema source

result schema
  machine-readable JSON schema or equivalent schema source

privilege class
  one or more declared classes

execution owner
  app command, workspace action, runtime command, query reader, event reader

result semantics
  applied or accepted

correlation
  whether request id or explicit correlationId appears in emitted events
```

Result semantics:

```text
applied
  the requested state change is complete when the RPC returns

accepted
  the request passed validation and was handed to an async owner
  completion or failure is observed later through an event carrying correlationId
```

Phase-1 methods default to `applied`. A method may declare `accepted` only when
its execution owner is actually asynchronous and can emit a later exported
completion/failure event. `terminal.send` is `applied` when bytes are accepted by
the terminal surface; shell command completion is observed separately through
`terminal.wait` or exported terminal events.

The registry must not route raw requests directly into atoms. It must not invent
a generic command bus. It binds external methods to focused existing
capabilities.

## Handles And Targeting

Canonical identity is UUID-based. Friendly refs exist for CLI and agent
ergonomics.

```text
window:1
workspace:1
tab:1
pane:1
```

Rules:

- UUIDs are canonical in state, responses, and event payloads.
- Friendly refs are session-local conveniences.
- Friendly refs are never persisted.
- Ordinals are not reused during a server runtime.
- Responses include the resolved canonical target when a friendly ref or active
  target was used.
- Methods with implicit active targets must say so in the registry.
- Phase 1 is pane-first. `surface:*` handles are deferred until Agent Studio has
  a public surface-level contract distinct from `PaneId`.

This keeps future remote zmx placement from leaking transport-specific terminal
identity into public app control.

## Phase-1 Method Surface

Phase 1 is intentionally small and pane-first. The first implementation slice
ships the app IPC transport, auth, registry, read/query surface, pane focus,
terminal send/status/snapshot/wait, and event subscriptions. Broader layout
mutation is still Agent Studio app control, but it is gated on an explicit
app-control action adapter rather than hidden access to private view-controller
methods.

```text
system.ping
system.identify
system.version
system.capabilities

auth.login
auth.status

window.list
window.current

workspace.list
workspace.current

pane.list
pane.current
pane.focus
pane.snapshot

terminal.status
terminal.send
terminal.snapshot
terminal.wait

permission.request
permission.requestStatus
permission.grantStatus
permission.pendingApprovals
permission.resolveRequest

events.subscribe
events.unsubscribe
```

Phase-1 expansion methods may be added before implementation planning only after
the spec names their exact execution owner, active-window behavior, validation
errors, and no-direct-atom-mutation proof:

```text
workspace.select
pane.split
pane.close
terminal.interrupt
```

`permission.resolveRequest` is not part of the broad expansion list. It is a
guarded approval method and may be registered only when the principal/approval
policy system can prove the caller has `grantApprove` over the canonical request
scope.

Deferred method groups:

```text
browser.*
webview.*
bridge.*
worktree mutation
orchestration.*
mcp.*
zmx.*
terminal output streaming
password management
remote app control
```

Terminal method semantics:

```text
terminal.status
  live in-memory runtime/backend status only
  no terminal output, scrollback, zmx history, or raw PTY bytes

terminal.snapshot
  exported DTO composed from PaneRuntimeSnapshot plus allowlisted terminal
  runtime fields
  not a raw dump of TerminalRuntime, Ghostty, or zmx state

terminal.send
  applied when bytes are accepted by the terminal surface
  does not mean the shell command completed

terminal.wait
  bounded wait over exported terminal conditions
  not arbitrary internal event predicates
  not durable replay
```

Allowed phase-1 wait conditions must be a small enum such as attach-ready,
command-finished, renderer-healthy, title-changed, or cwd-changed. The
implementation plan may shrink this list further after mapping each condition
to current runtime facts.

## Execution Ownership

Every method must name its execution owner.

```text
system.* / auth.*
  AgentStudioAppIPC service and auth gate

window.* / workspace.* reads
  AgentStudioAppIPC query port implemented by App/IPCComposition over
  app/workspace state

pane.focus / future pane structural mutations
  AgentStudioAppIPC layout port implemented by App/IPCComposition
    -> ActionExecutor.execute(...)
    -> WorkspaceCommandValidator
    -> PaneCoordinator

app and shell commands, if exposed later
  CommandDispatcher
    -> appCommandRouter or active workspace handler

terminal.* runtime commands
  AgentStudioAppIPC runtime port implemented by App/IPCComposition
    -> PaneCoordinator.dispatchRuntimeCommand(...)
    -> RuntimeRegistry
    -> PaneRuntime.handleCommand(...)

events.*
  event adapter over authoritative runtime/app facts

permission.*
  AppIPC PermissionBroker / GrantLedger / AuthorizationService
    -> ApprovalPolicyStore for preconfigured rules
    -> PermissionApprovalPort for human/app and delegated-principal routing
    -> public permission events after ledger transitions
```

The current `PaneTabViewController` validated action path is private. The
implementation plan should introduce a deliberate app-control capability seam
instead of making the public IPC adapter depend on private view-controller
methods. Window-specific methods may still require an active/key workspace
window and must return `-32006 no active window` when unavailable.

No IPC method may mutate atoms directly. A method that has no named owner chain
is not ready for phase-1 registration.

## Events And Waits

Phase 1 events carry only exported lifecycle, topology, focus, terminal status,
command-completion, and permission-state facts. They do not carry terminal output
bytes, scrollback, zmx history, raw runtime envelopes, or arbitrary internal event
payloads.

The observer model is snapshot plus live stream:

1. call a snapshot/read method,
2. subscribe to exported events,
3. optionally request bounded in-memory replay when the implementation supports
   it for that source,
4. refresh from snapshot after a gap, app restart, runtime restart, or replay
   miss.

Replay is not durable. There is no global event sequence. External cursors are
scoped to the subscription/source that issued them.

The event model uses subscriptions over the authenticated socket connection:

```json
{
  "jsonrpc": "2.0",
  "id": "sub-1",
  "method": "events.subscribe",
  "params": {
    "names": ["pane.focused", "terminal.statusChanged"],
    "targets": ["pane:1"]
  }
}
```

After subscription, the server sends JSON-RPC notifications:

```json
{
  "jsonrpc": "2.0",
  "method": "events.notification",
  "params": {
    "subscriptionId": "sub-1",
    "seq": 42,
    "runtimeId": "...",
    "name": "terminal.statusChanged",
    "correlationId": "cmd-7",
    "payload": {}
  }
}
```

Rules:

- Events are observations only.
- Commands never enter through event subscriptions.
- Inbound client notifications named `events.notification`,
  `permission.requestResolved`, or any other server-originated event name are
  rejected and leave `GrantLedger` unchanged.
- Phase 1 does not promise durable replay.
- The server may keep a bounded in-memory buffer for active subscribers.
- Slow subscribers are disconnected with a terminal error notification.
- Event names and payloads are allowlisted public contracts, not mirrors of
  internal enum cases.
- Event payloads must be scoped and must not include terminal output, scrollback,
  zmx history, raw PTY bytes, or full paths/URLs unless the method contract
  explicitly includes and redacts them.
- Methods that return `accepted` must emit a later completion/failure event when
  the underlying owner can observe one.

Permission events are scoped public DTOs:

```text
permission.requestCreated
permission.requestResolved
permission.grantRevoked
permission.grantExpired
```

Minimum permission event payload:

```text
requestId
grantId?
principalId
state
requestedScope or grantedScope
approvalRoute?
expiresAt?
reasonCode?
correlationId?
```

Permission event visibility:

```text
requesting principal
  may observe status for its own requests and grants

human/app approval surface
  may observe pending requests routed to human/app approval

delegated approving principal
  may observe pending requests routed to it, limited to the canonical scope it
  is allowed to approve

other principals
  observe nothing by default

future privileged observer
  requires an explicit observer privilege and separate threat model
```

Permission events must not include tokens, terminal input payloads, terminal
output, scrollback, raw paths, URLs, prompts, browser contents, zmx socket paths,
zmx session ids, zmx history, or zmx protocol details.

`terminal.wait` is a request/response method with a bounded timeout. It must use
admission limits so long waits cannot starve short RPC calls. It waits on a
small exported condition enum, not arbitrary internal event names or payload
predicates.

## MCP Compatibility

MCP is a future adapter over the method registry. It is not the local socket
wire protocol.

```text
local JSON-RPC
  terminal.send(params)

future MCP
  tools/call
    name: agentstudio_terminal_send
    arguments: params

shared registry
  TerminalSendParams
  TerminalSendResult
  privilege class
  schema
  executor
```

MCP adds initialization, capability negotiation, tools, resources, prompts,
transport rules, and security semantics. AgentStudio keeps its app-native method
catalog and later maps registry entries into MCP tools/resources/prompts.

Phase 1 preserves future MCP compatibility only by requiring machine-readable
schemas, explicit privilege metadata, and stable semantic method definitions. It
does not let MCP tool/resource/prompt modeling choose the phase-1 local method
surface. A future MCP adapter is a separate trust boundary and must map
privilege classes explicitly instead of inheriting broad app IPC authority by
default.

## zmx IPC Reconciliation

The old `agent-studio.zmx-ipc` worktree contains a valuable design for replacing
`ZmxBackend` CLI shell-outs with one-shot zmx daemon socket calls. That worktree
is stale relative to current AgentStudio and must not be git-merged wholesale.
The refreshed backend-only design lives in
`docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md`.

zmx IPC refresh is a separate internal backend task. It is not a prerequisite
for phase-1 public app IPC planning except to prove that no zmx protocol details
leak into public schemas.

The new IPC spec keeps the valid design idea but changes placement:

```text
public AgentStudio IPC
  app-level control
  panes, windows, workspaces, runtimes, terminal operations

future/internal zmx IPC
  backend transport behind ZmxBackend and SessionRuntime
  one zmx daemon/session
  binary protocol
  local or SSH-forwarded Unix socket
```

Valid zmx design inputs to preserve:

- One-shot zmx IPC calls are safer than persistent control connections because
  zmx broadcasts PTY output to every connected client.
- zmx daemon socket permissions are the daemon access boundary.
- Future remote zmx likely uses SSH socket forwarding so the Swift client still
  speaks the same zmx protocol through a local forwarded socket.
- `ZmxIPCClient` should replace `zmx list` and `zmx kill` shell-outs when that
  backend track is implemented.

Details that stay out of public AgentStudio IPC:

- zmx binary header and tag values
- zmx socket paths
- zmx session naming
- zmx `Info` struct layout
- zmx history and scrollback payload formats
- raw PTY output broadcast semantics
- any public method named `zmx.*`

All concrete zmx wire-layout claims remain unverified in this checkout while
`vendor/zmx` is uninitialized. The zmx backend implementation plan must first
verify the current pinned vendor sources before carrying forward tag values,
struct offsets, history formats, or read-loop behavior from the old worktree.

## Security Context

Assets and privileges:

- terminal input and interruption
- terminal status and snapshots
- workspace/window/pane structure
- focus and selection
- app runtime events
- future browser/webview controls
- future remote terminal routing

Trust boundaries:

- local Unix socket client to AgentStudio app
- AgentStudio-spawned terminal process to app IPC service
- future external same-user automation client to app IPC service
- future MCP client to AgentStudio MCP adapter
- future AgentStudio to remote zmx daemon through SSH/socket forwarding

Security rules:

- No production world-writable socket mode.
- Same-uid peer credential check before token validation.
- Memory-only subject tokens for `agentStudioOnly`.
- Redact tokens in logs, traces, telemetry, and errors.
- Treat subject-token leakage as principal impersonation for that token's
  lifetime.
- Keep approval authority server-side on principals, grants, and app-owned policy
  records; do not encode self-describing authority claims into bearer tokens.
- App policy may pre-approve, deny, or ask for grants according to user-configured
  rules. Human prompt is a route, not the only approval mechanism.
- Delegated approval requires `grantApprove` over the canonical requested scope.
- Audit mutating methods with method name, target, privilege class, and
  correlation id, without sensitive payload values.
- Bound frame size, request duration, open connection count, and long waits.
- Treat terminal snapshots and future output streams as secret-bearing.
- Phase-1 methods and events are allowlist-based. Internal runtime envelopes are
  not public payload schemas.
- Treat cwd, window/title text, command lines, search query/state, progress text,
  secure-input transitions, paths, URLs, terminal output, scrollback, zmx
  history, prompts, and browser/webview content as sensitive by default.
- Do not put app-control tokens, principals, grants, or approval policies into zmx
  daemon state.
- Do not proxy or expose remote zmx sockets in phase 1. Future SSH-forwarded zmx
  support changes authentication, custody, audit, and failure semantics.
- Future plugin or MCP hosts must receive explicitly scoped privileges and must
  not inherit broad app IPC authority by default.

## Testing Strategy

The implementation plan should cover:

```text
codec tests
  valid JSON-RPC request/response/error
  invalid JSON
  missing jsonrpc
  batch rejected
  invalid params

transport tests
  NDJSON framing
  max frame size
  idle timeout
  connection cap
  stale socket cleanup

auth tests
  unauthenticated command rejected
  invalid token rejected
  agentStudioOnly subject token is not written to disk
  spawned-session env contains socket/token
  same-uid/peer credential checks
  token rotates on runtime/listener restart
  repeated failed auth closes the connection
  automationSameUser bootstrap material is never present in agentStudioOnly
  subject token maps to a server-bound principal, never caller-supplied pane hints
  bound pane close invalidates the principal and future auth attempts
  subject token is absent from logs, traces, telemetry, errors, events, and public
  DTOs such as auth.status

grant tests
  baseline selfPane grants are derived after authentication
  selfPane remains stable when UI focus changes
  terminal.send to another pane is denied without a matching grant
  appPolicy can auto-approve, auto-deny, or ask according to configured rules
  delegated approval requires grantApprove over the canonical requested scope
  permission.pendingApprovals returns only routed pending requests within the
  delegated approver's grantApprove scope
  permission.resolveRequest cannot approve a request without grantApprove
  cross-pane/global mutating grants are connection-bound or one-shot by default
  grant state is not persisted in phase 1
  grants revoke on TTL, pane close, target disappearance, listener restart,
  runtime id change, token rotation, explicit revoke, or one-shot consumption

registry tests
  every method has params/result schema
  every method has privilege class
  every method has execution owner
  no deferred namespace is registered in phase 1
  no method is registered without a named owner chain

adapter tests
  pane target resolution
  validation rejection maps to JSON-RPC error
  runtime not ready maps to JSON-RPC error
  accepted commands expose correlationId
  no-active-window behavior maps to JSON-RPC error
  no adapter mutates atoms directly

event tests
  subscribe/unsubscribe
  status event delivery
  permission event visibility
  slow subscriber disconnect
  no terminal output in phase-1 events
  exported event allowlist blocks internal-only payloads
  inbound client notifications cannot mutate GrantLedger
  replay gap or restart requires snapshot refresh
  terminal.wait accepts only exported wait conditions
  terminal.send result is not shell command completion
```

## Coarse Work Breakdown

These are not implementation steps. They are the large deliverables that can
become Linear tickets after the spec and plan are approved.

```text
1. IPC architecture and contract spec
2. Generic Unix JSON-RPC transport and codec
3. Auth/access-mode service, subject-token minting, and principal binding
4. Method registry, schemas, capabilities, grants, permissions, and handles
5. App/workspace/pane query and command adapters
6. Terminal runtime adapter and bounded terminal methods
7. Event subscription, permission events, and wait model
8. CLI client for local agents
9. zmx backend IPC vendor verification and transport-swap plan
10. Future MCP adapter design and implementation
```

## Open Decisions

The current target default is `agentStudioOnly` enabled, with memory-only subject
tokens injected into AgentStudio-spawned sessions. `automationSameUser` is opt-in
for external local tools. Keep this as the default unless spec review changes
the threat model or first consumer.

Human-in-the-loop approval is not required for every permission request. The
target model allows user-configured app policy to auto-approve, auto-deny, or ask
for grants, and allows delegated approval by principals with `grantApprove` over
the requested canonical scope. Phase 1 includes delegated approval in the
contract: delegated approvers can list routed pending requests through
`permission.pendingApprovals` and resolve them through `permission.resolveRequest`.

Phase-1 expansion methods `workspace.select`, `pane.split`, `pane.close`, and
`terminal.interrupt` stay deferred until the spec names their exact owner chain
and no-active-window behavior. Otherwise, window-bound methods return `-32006 no
active window`.

If `terminal.snapshot` cannot be backed by an explicit exported DTO during
planning, shrink phase 1 to `terminal.status` plus `pane.snapshot` rather than
leaking raw runtime state.

If `terminal.wait` cannot be represented as a small exported condition enum,
remove it from phase 1 instead of exposing arbitrary internal event predicates.

If any phase-1 use case needs terminal output streaming, that should be a
separate explicit scope decision because it changes the security and backpressure
model.

If the first real consumer is an external same-user CLI rather than an
AgentStudio-spawned terminal agent, decide whether `automationSameUser` is part
of phase 1 or remains a follow-up mode.

## References

- [AppDataPaths.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Infrastructure/AppDataPaths.swift)
- [AppCommand.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/App/Commands/AppCommand.swift)
- [ActionExecutor.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/App/Commands/ActionExecutor.swift)
- [PaneCoordinator+RuntimeDispatch.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/App/Coordination/PaneCoordinator+RuntimeDispatch.swift)
- [RuntimeRegistry.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Core/RuntimeEventSystem/Registry/RuntimeRegistry.swift)
- [PaneRuntime.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntime.swift)
- [RPCRouter.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift)
- [pane_runtime_architecture.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/architecture/pane_runtime_architecture.md)
- [session_lifecycle.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/architecture/session_lifecycle.md)
- [remote_zmx_architecture_ideas.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/architecture/remote_zmx_architecture_ideas.md)
- [2026-06-13-zmx-backend-ipc-design.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md)
- [2026-03-30-zmx-ipc-client-design.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.zmx-ipc/docs/superpowers/specs/2026-03-30-zmx-ipc-client-design.md)
- JSON-RPC 2.0: https://www.jsonrpc.org/specification
- MCP 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
