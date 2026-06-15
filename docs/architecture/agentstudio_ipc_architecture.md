# AgentStudio IPC Architecture

AgentStudio app IPC is the app-level programmatic-control boundary for local
automation, pane agents, and future MCP adapters. It exposes semantic app
methods over local transports without exposing zmx daemon IPC as a public API.

## Status

The phase-1 foundation currently owns:

- SwiftPM target split for transport, public contracts, and app IPC services.
- JSON-RPC 2.0 request/response codec over newline-delimited JSON frames.
- Unix-domain socket transport primitives and peer-credential checks.
- Socket path and runtime metadata trust checks.
- Subject-token authentication, principal registry, and redaction helpers.
- Phase-1 method catalog, handle parsing, authorization, grant ledger, and
  permission broker policy/delegation primitives.

Follow-up implementation slices still own concrete app adapters, socket-server
lifecycle wiring, CLI/client commands, event subscription delivery, runtime
terminal adapters, and promotion of completed design material from the
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
            and protocol ports into app/runtime owners.
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
