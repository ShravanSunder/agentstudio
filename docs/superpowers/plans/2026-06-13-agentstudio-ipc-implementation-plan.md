# AgentStudio IPC Implementation Plan

**Date:** 2026-06-13
**Status:** Phase-1 foundation implemented on the `programatical-control`
branch, with review-driven contract fixes and live app listener wiring applied.
T1-T10 target split, contracts, auth/permission foundations, app adapters,
CLI/client core, architecture docs, app-owned socket server lifecycle, and
fd-based pane bootstrap primitive have landed. The remaining follow-up is
concrete child-process fd remapping in the future pane-agent spawn adapter; the
current terminal/zmx launch path does not yet pass the bootstrap fd into a
child process. A new corrective slice is also required for command/UI separation:
the current `command.*` debug allowlist opens command-bar UI surfaces, while the
target contract requires headless semantic command execution under `command.*`
and explicit UI presentation under `ui.*`.
**Primary spec:** `docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md`
**Related backend spec:** `docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md`

## Goal

Implement the first Agent Studio app-level IPC slice: local Unix-domain socket,
strict JSON-RPC 2.0 framing, `agentStudioOnly` subject-token auth, principal
binding, scoped grants, permission requests, method registry, pane-first handles,
read/query methods, pane focus, terminal status/snapshot/send/wait, event
subscriptions, and a dedicated local CLI executable target for smoke/use.
Correct the command surface so command-spec-backed semantic execution and UI
presentation do not share one ambiguous `command.execute` method.

The implementation must route through existing app and runtime owners. It must
not introduce a new mutation owner, command bus, public zmx API, or phase-1 MCP
transport.

## Source Coverage

Read in full before planning:

- `docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md`: 1613 lines,
  chunks `1-360`, `361-760`, `761-1160`, `1161-1613`.
- `docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md`: 322 lines,
  chunk `1-322`.

Live repo evidence checked:

- `AppDataPaths.rootDirectory()` and `zmxDirectory()` already provide channel-aware
  roots and `<app-root>/z`: `Sources/AgentStudio/Infrastructure/AppDataPaths.swift`.
- `AppDelegate` is the app composition root and creates shared services before
  showing the main window: `Sources/AgentStudio/App/Boot/AppDelegate.swift`.
- `ActionExecutor` is the app-facing command entry point and delegates runtime
  command dispatch to `PaneCoordinator`: `Sources/AgentStudio/App/Commands/ActionExecutor.swift`.
- `PaneCoordinator.dispatchRuntimeCommand` resolves targets, gates runtime
  readiness, attaches correlation ids, and calls `PaneRuntime.handleCommand`:
  `Sources/AgentStudio/App/Coordination/PaneCoordinator+RuntimeDispatch.swift`.
- `RuntimeRegistry` owns pane runtime lookup and uniqueness:
  `Sources/AgentStudio/Core/RuntimeEventSystem/Registry/RuntimeRegistry.swift`.
- `PaneRuntime` exposes command handling, subscription, snapshots, and replay:
  `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntime.swift`.
- `TerminalRuntime` maps `.terminal(.sendInput(...))` to `SurfaceManager.sendInput`
  and already emits replayable terminal facts:
  `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`.
- `EventBus.waitForFirst` and `EventReplayBuffer` provide bounded wait/replay
  primitives but expose internal envelopes that must be mapped to public DTOs:
  `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus+WaitForFirst.swift`,
  `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift`.
- Bridge `RPCRouter` and tests prove useful JSON-RPC prior art, but the router is
  pane-local and MainActor-bound; app IPC needs its own generic codec/registry:
  `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`,
  `Tests/AgentStudioTests/Features/Bridge/RPCRouterTests.swift`.
- `Package.swift` currently has one executable target (`AgentStudio`) and one
  test target. The IPC module split requires explicit SwiftPM target changes even
  if the CLI is deferred; adding a CLI remains a separate package/product
  decision.

## Non-Goals

- No MCP implementation in phase 1.
- No V1 line protocol, JSON-RPC batches, TCP, WebSocket, or remote app-control
  transport.
- No password mode, world-writable socket, or production `allowAll`.
- No terminal output streaming, scrollback, zmx history, raw PTY bytes, raw
  runtime envelopes, or raw zmx protocol details.
- No public `zmx.*` namespace.
- No direct atom mutation from IPC methods.
- No implicit command-bar, picker, sheet, or prompt presentation through
  `command.execute`; UI surfaces are explicit `ui.*` methods.
- No zmx backend IPC transport swap in this plan. The zmx backend spec remains
  a later internal implementation plan after vendor verification.

## Architecture Shape

```text
external agent / CLI
  -> AgentStudioIPCTransport
       Unix socket, peer credentials, NDJSON, JSON-RPC codec
  -> AgentStudioProgrammaticControl
      method contracts, schemas, privileges, grant scopes, handles,
      command execution modes, UI presentation contracts, public events/waits
  -> AgentStudioAppIPC
       service lifecycle, auth, principals, GrantLedger, AuthorizationService,
       registry assembly, protocol ports
  -> AgentStudio executable / App/Boot + App/IPCComposition
      app listener lifecycle, concrete policy, approval, query/action/runtime,
      command, and UI-presentation adapters
  -> existing owners
       CommandDispatcher / ActionExecutor / WorkspaceCommandValidator
       PaneCoordinator / RuntimeRegistry / PaneRuntime
```

This plan intentionally keeps three boundaries separate:

1. Generic transport mechanics do not import app/product types.
2. Programmatic-control contracts define product semantics but are not
   socket-specific.
3. `AgentStudioAppIPC` owns auth, authorization, ledger, registry, and protocol
   ports but does not import app/feature/runtime owners directly.
4. The executable target implements concrete ports into existing app/runtime
   owners.

The folder layout is not sufficient by itself. T1 must first add the SwiftPM
target graph that makes these boundaries compile-time-visible:

```text
AgentStudioIPCTransport
  no AgentStudio product dependencies

AgentStudioProgrammaticControl
  no AppKit, SwiftUI, AgentStudio executable, Feature, or runtime-owner deps

AgentStudioAppIPC
  depends on AgentStudioIPCTransport and AgentStudioProgrammaticControl
  exposes ports, auth, grants, registry assembly, and service lifecycle only

AgentStudio executable
  depends on AgentStudioAppIPC
  composes the live server under Sources/AgentStudio/App/Boot/
  implements concrete app/runtime ports under Sources/AgentStudio/App/IPCComposition/

AgentStudioIPCClient, if T9 remains in phase 1
  executable target for local CLI/smoke use
  depends only on AgentStudioIPCTransport and AgentStudioProgrammaticControl
  never imports AgentStudioAppIPC or the AgentStudio executable target
```

The architecture lint layer then guards the edges SwiftPM cannot express: no
direct atom mutation from IPC adapters, no `zmx.*` public registry methods, no
raw runtime/zmx DTO leakage, no AppKit/SwiftUI or app/feature/runtime-owner
imports from `AgentStudioProgrammaticControl`, no concrete
app/feature/runtime-owner imports from `AgentStudioAppIPC`, and concrete AppIPC
composition only under the app target.

Boundary tests must also use the target graph. Do not prove transport/contracts
with only the broad `AgentStudioTests` target, because that target can see the
executable target. T1 adds narrow test targets for transport, contracts, and
AppIPC service logic; the existing broad test target remains for executable
composition/integration tests.

## Requirements And Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green required | Sized to pass? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Unix socket JSON-RPC accepts one newline-delimited request per frame and rejects invalid JSON, missing `jsonrpc`, non-object params, oversize frames, and batch arrays | T1 | `AgentStudioIPCTransport` tests | Focused Swift tests for codec/framer/listener fakes | Unit/integration | Tests use real newline chunking and malformed fixtures, not Bridge router assumptions | Yes | Yes |
| `Package.swift` declares the IPC target graph before implementation code lands, and the executable/test targets depend on the new modules deliberately | T1 | SwiftPM package graph and build | `swift package describe`, package compile, targeted tests | Compile | The CLI target decision is separate; the library target split is mandatory for AppIPC boundaries | No | Yes |
| `AgentStudioIPCTransport` has no product imports and target edges prevent transport from depending on contracts/app/features | T1 | SwiftPM target graph plus architecture lint | Package compile and IPC-specific architecture lint rules | Lint/compile | PR #177 repo-local architecture linter owns IPC rules instead of shell/rg guards or external SwiftLint forks | No | Yes |
| IPC-specific SwiftSyntax architecture rules are added to the repo-local AgentStudio architecture linter, verified by fixtures, and documented in the architecture lint inventory | T1/T10 | `Tools/AgentStudioArchitectureLint` fixtures/tests and inventory docs | `swift test --package-path Tools/AgentStudioArchitectureLint`, `mise run lint`, inventory diff review | Lint/docs | Rule source lives in this repo; update the local tool, fixtures, rule inventory tests, and docs together | No | Yes |
| Narrow IPC test targets prove transport/contracts/AppIPC boundaries without depending on the AgentStudio executable target | T1/T4 | SwiftPM test target graph | `swift test --filter` or targeted test run for dedicated IPC test targets | Compile/test | Existing `AgentStudioTests` remains for executable integration only, not boundary proof | No | Yes |
| App IPC metadata and socket paths are derived from `AppDataPaths.rootDirectory()` under `<root>/ipc` | T2 | `AgentStudioAppIPC` service tests | Unit tests with injected environment/root/channel | Unit | Tests assert stable/beta/debug/env override paths and owner-only metadata mode | Yes | Yes |
| Filesystem trust fails closed for symlinks, wrong owner, group/world access, and stale live socket ownership | T2 | `AgentStudioAppIPC` filesystem trust tests | Temp-dir tests with permission fixtures where platform allows | Integration | Permission checks skipped only when Darwin cannot set a mode, with explicit assertions for supported paths | Yes | Yes |
| `agentStudioOnly` subject tokens are memory-only, minted before session spawn, and map to server-bound principals | T3 | Auth service and spawn-bootstrap tests | Unit tests for subject-token registry plus environment-construction tests | Unit/integration | Tests scan metadata and env output for token absence, assert env contains only non-secret socket/runtime id routing data, and assert bootstrap pipe descriptors are close-on-exec until a spawn adapter deliberately remaps the read end; `auth.login` never trusts caller pane hints | Yes | Yes |
| Same-uid peer credential check runs before token auth and auth failures close/reject as specified | T3 | Transport/auth tests | Peer credential abstraction fake tests plus live same-uid happy path if feasible | Unit/integration | Peer credential abstraction is injectable so behavior is not dependent on CI socket support | Yes | Yes |
| Principal lifetime follows bound pane and runtime identity | T3 | Principal registry tests | Unit tests over pane-close, listener restart, runtime-id change, token rotation | Unit | Closed-pane subject token returns `-32001 unauthenticated` and grants are revoked | Yes | Yes |
| Method registry requires schemas, privilege class, execution owner, result semantics, and principal availability metadata for every phase-1 method | T4 | Registry tests | Reflection/table tests over registered methods | Unit | Test fails on missing metadata, deferred namespace registration, or method exposure to a principal without a matching grant path | Yes | Yes |
| Public handles are pane-first, UUID-canonical, and friendly refs are runtime-local conveniences | T4 | Handle resolver tests | Unit tests with stable fake app snapshot | Unit | Tests prove ordinals are not persisted, responses echo canonical UUID targets, and terminal methods authorize friendly ordinals as the same concrete pane that execution will use | Yes | Yes |
| Baseline grants permit a spawned pane agent to operate on selfPane without interactive approval and deny cross-pane/global authority by default | T4 | Authorization tests | Unit tests over principals, grants, canonical targets, and focus changes | Unit | `selfPane` is principal-bound, not active focus or caller params | Yes | Yes |
| Permission requests are commands and approval is policy-routed through app policy, human prompt, or delegated principals with `grantApprove` | T4/T8 | PermissionBroker and GrantLedger tests | Unit/integration tests over appPolicy, humanPrompt fake, delegated approver, denial paths | Unit/integration | Event notifications cannot approve/deny/revoke; `permission.resolveRequest` requires `grantApprove` for canonical scope | Yes | Yes |
| Delegated approval is recoverable after missed events without granting observer access to unrelated principals | T4/T8 | Permission query and visibility tests | `permission.pendingApprovals` tests plus permission event tests | Unit/integration | Requester status methods return own state; delegated approver query returns only routed pending requests within `grantApprove` scope | Yes | Yes |
| Subject tokens are never persisted, logged, traced, echoed, or serialized in public DTOs/errors/events | T3/T8 | Auth/redaction tests | Metadata, error, audit/log sink, DTO, and event serialization tests | Unit/integration | Tests use a sentinel token value and scan emitted payloads/log test sinks for absence | Yes | Yes |
| Query methods read snapshots without mutating atoms | T5 | Query adapter tests | Snapshot tests over `WorkspaceStore` fixtures | Unit | Tests use read-only fixtures and no mutation method calls in adapter | Yes | Yes |
| `pane.focus` routes through a deliberate app-control seam rather than private view-controller methods | T6 | Layout adapter tests | Focused tests on action seam and no-active-window error | Unit/integration | Task cannot pass until seam has a named owner chain and no-direct-atom-mutation proof | Yes | Yes |
| `terminal.send` routes through `ActionExecutor -> PaneCoordinator -> RuntimeRegistry -> PaneRuntime` and means bytes accepted by surface, not shell completion | T7 | Runtime adapter tests | Existing coordinator dispatch tests plus new IPC adapter tests | Unit/integration | Test maps `ActionResult` to JSON-RPC and does not wait for shell output | Yes | Yes |
| `terminal.status` and `terminal.snapshot` expose allowlisted DTOs only, with no raw TerminalRuntime, output, scrollback, zmx, paths, URLs, or secrets unless explicitly redacted | T7 | DTO/schema tests | Snapshot serialization tests and sensitive-field denylist tests | Unit | Tests include terminal title/cwd/search/progress examples and assert redaction/omission policy | Yes | Yes |
| `terminal.wait` accepts only exported condition enum values and uses bounded waits/admission limits | T8 | Wait adapter tests | Fake event stream tests with injected clock/bounded timeout | Unit/integration | Tests reject arbitrary event names and prove timeout cleanup | Yes | Yes |
| `events.subscribe` streams only allowlisted public event DTOs and disconnects/errs slow subscribers | T8 | Event broker tests | Fake subscriber/backpressure tests | Integration | Tests assert no raw `RuntimeEnvelope`, terminal output payload, permission token, grant secret, or zmx internal is serialized | Yes | Yes |
| Permission events are visibility-scoped and status methods recover missed permission events | T8 | Permission event/status tests | Fake subscriber tests plus request/grant status queries | Unit/integration | Requesting principal, app approval surface, delegated approver, and unrelated principal visibility are tested separately | Yes | Yes |
| CLI can discover socket metadata, authenticate, call read methods, send terminal input, and subscribe/unsubscribe | T9 | CLI smoke tests | CLI unit tests plus local smoke against test IPC server | Smoke | Smoke uses isolated `AGENTSTUDIO_DATA_DIR` and does not touch user's running app | Yes | Yes |
| If the local CLI ships in phase 1, it is a dedicated executable target with no dependency on `AgentStudioAppIPC` or the AgentStudio executable target | T9 | SwiftPM target graph and CLI tests | `swift package describe`, CLI target build, CLI smoke | Compile/smoke | No committed support client outside a target unless T9 is explicitly removed from phase 1 | No | Yes |
| `command.execute` means headless semantic execution and never opens command bar, picker, sheet, or prompt UI implicitly | T11 | Command contract and adapter tests | Red/green IPC command adapter tests plus registry tests | Unit/integration | Tests fail on current `showCommandBar*` mapping, then pass only when UI openers move to `ui.*` | Yes | Yes |
| UI presentation commands remain exposed because they are useful, but they live under `ui.*` with `uiPresent` privilege and presentation postconditions | T11 | UI-presentation adapter tests | `ui.commandBar.open` tests for each scope and no-active-window behavior | Unit/integration | Tests assert UI method returns command-bar postcondition and does not claim selected command/action completion | Yes | Yes |
| Create/split/close/drawer operations are classified by semantic effect, not by whether a keyboard shortcut currently opens a chooser | T11 promoted expansion | Method registry, layout adapter, and command exposure tests | Registry metadata tests over execution mode, required parameters, target kinds, and owner chain | Unit/integration | `tab.create`/`pane.split`/`pane.close`/`drawer.toggle`/`drawer.addPane` require explicit owner chains and arguments; `ui.commandBar.open(scope: repos)` is the chooser path | Yes | Yes |
| Phase-1 implementation does not expose zmx public methods or zmx internals | T4/T7/T8 | Registry/schema tests | Namespace denylist and snapshot/event sensitive-field tests | Unit | Tests explicitly deny `zmx.*`, socket path, session name, history, raw `Info` bytes | Yes | Yes |
| Architecture docs are promoted after implementation and spec becomes history | T10 | Docs proof | `rg` checks plus docs diff review | Docs/lint | Docs reference real implemented file paths and remove stale open decisions | No | Yes |

## Task Sequence

### T0. Plan Review And Scope Lock

Purpose: validate this plan before code.

Actions:

- Run `shravan-dev-workflow:plan-review-swarm` against this plan and both specs.
- When external Claude review is requested and the CLI model is available, run it
  through the Claude Code CLI with Opus-level review; do not use Anthropic API
  calls.
- Keep phase-1 expansion methods (`workspace.select`, `pane.split`, `pane.close`,
  `drawer.toggle`, `drawer.addPane`, `terminal.interrupt`) out unless review
  identifies a complete owner chain. T11 promotes the methods whose owner chain
  is already complete and testable through `ActionExecutor`.
- Decide CLI packaging before code: add a Swift executable target or defer the
  installable CLI while still shipping test/support client code.

Exit proof:

- Accepted review findings are applied to the plan.
- Open questions below are either answered or explicitly moved to implementation
  gates.

### T1. SwiftPM Target Split And Generic Unix JSON-RPC Transport

Write surfaces:

- `Package.swift`
- `Sources/AgentStudioIPCTransport/`
- `Tests/AgentStudioTests/Infrastructure/IPC/`
- `Tests/AgentStudioTests/Scripts/ArchitectureSwiftLintRulesTests.swift`
- `Tools/AgentStudioArchitectureLint/` whenever IPC architecture rules or
  fixtures change
- `docs/architecture/architecture_lint_inventory.md`

Prerequisite:

- Land or update the IPC-specific SwiftSyntax rules in the repo-local
  `Tools/AgentStudioArchitectureLint` package before implementing IPC code in
  this repo. Update fixtures, `RuleInventoryTests`,
  `ArchitectureSwiftLintRulesTests.swift`, and
  `docs/architecture/architecture_lint_inventory.md` together.

Implement:

- Add the library target graph for `AgentStudioIPCTransport`,
  `AgentStudioProgrammaticControl`, and `AgentStudioAppIPC` before placing
  implementation code in those folders.
- Update the `AgentStudio` executable target dependency list so concrete
  composition code can import `AgentStudioAppIPC`.
- Add dedicated narrow test targets with minimal dependencies:
  - `AgentStudioIPCTransportTests` depends only on `AgentStudioIPCTransport`.
  - `AgentStudioProgrammaticControlTests` depends only on
    `AgentStudioProgrammaticControl`.
  - `AgentStudioAppIPCTests` depends on `AgentStudioAppIPC`,
    `AgentStudioIPCTransport`, and `AgentStudioProgrammaticControl`, but not the
    `AgentStudio` executable target.
  - Existing `AgentStudioTests` may depend on `AgentStudio` for executable
    composition/integration tests only.
- `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError`, and `JSONRPCIdentifier`.
- Strict JSON-RPC 2.0 codec with app error-code range support.
- NDJSON frame reader/writer with max frame size and invalid UTF-8 handling.
- Unix socket listener/client primitives with injectable clock and test socket
  endpoint.
- Peer credential abstraction for Darwin same-uid checks.
- No product method registry in this layer.
- Consume the repo-local SwiftSyntax architecture rules that cover IPC
  target edges, forbidden AppKit/SwiftUI and app/feature/runtime imports from
  `AgentStudioProgrammaticControl`, forbidden concrete imports from
  `AgentStudioAppIPC`, AppIPC port implementations outside
  `Sources/AgentStudio/App/IPCComposition/`, public `zmx.*` denial, no direct atom
  mutation from IPC adapters, and no raw runtime/zmx DTO exposure. If those
  rules are not available in the local tool, stop before implementation and
  split the tooling prerequisite explicitly.

Proof:

- `swift package describe` shows the intended IPC target graph and no accidental
  CLI executable target unless the CLI decision has been made.
- Unit tests for valid/invalid JSON-RPC, batch rejection, params-object rule,
  response `result` xor `error`, request-size bounds, and chunked NDJSON frames.
- Integration tests for connect/send/read/close against a temp Unix socket.
- SwiftPM target edges and architecture lint prove no product imports.
- `swift test --package-path Tools/AgentStudioArchitectureLint` proves the local
  SwiftSyntax rules reject IPC boundary violations, and
  `docs/architecture/architecture_lint_inventory.md` lists the rule ids.
- `ArchitectureSwiftLintRulesTests.swift` asserts `mise`, CI, stock SwiftLint,
  and the local architecture tool expose the IPC-specific rule ids.
- Dedicated IPC test targets compile without any dependency on the AgentStudio
  executable target.

### T2. IPC Service Paths, Metadata, And Filesystem Trust

Write surfaces:

- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/`
- `Tests/AgentStudioTests/App/IPC/`
- Possibly `Sources/AgentStudio/Infrastructure/AppDataPaths.swift` only for an
  `ipcDirectory()` helper if keeping path derivation centralized earns it.

Implement:

- `AgentStudioIPCPathResolver` for `<root>/ipc/runtime.json` and socket path.
- Owner-only directory/socket/metadata creation.
- Atomic metadata writes with non-secret discovery fields.
- Stale socket probe/unlink/keep behavior.
- Filesystem trust checks: same owner, no group/world access, no symlinked IPC
  paths, env override root must pass the same checks.

Proof:

- Temp-root tests for stable/beta/debug/env path derivation.
- Permission/symlink tests for fail-closed behavior.
- Metadata serialization test proves no subject token in `agentStudioOnly`.

### T3. Auth, Access Modes, Subject Tokens, And Principals

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/`
- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/` for concrete spawn-env wiring.
- Terminal spawn environment construction seam where Agent Studio launches
  spawned sessions, if required by current launch code.
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- `IPCAccessMode`: `off`, `agentStudioOnly`, `automationSameUser`,
  reserved `password`, `unsafeDebug`.
- Subject-token generation before session env construction, token rotation,
  per-connection authenticated state, and pre-auth method allowlist.
- In-memory token-to-principal registry.
- `IPCPrincipal` with `spawnedPaneAgent(boundPaneId:)`, future automation/MCP
  kinds, and server-side approval authority metadata.
- `auth.login` and `auth.status`.
- Peer credential gate before token validation.
- Token/socket/runtime-id injection for Agent Studio-spawned terminal sessions.
- Principal invalidation on bound pane close, listener restart, runtime id change,
  and token rotation.
- Audit logging that records method, target, privilege class, and correlation id
  without token or sensitive payload values.
- Token redaction policy for logs, traces, telemetry, audit payloads, JSON-RPC
  errors, `auth.status`, and all public DTO/event serialization.

Proof:

- Auth unit tests for unauthenticated rejection, invalid token, repeated failure
  close/reject, token rotation, and pre-auth `system.ping` with no metadata.
- Subject-token tests prove `auth.login` binds only through the in-memory token
  registry and ignores caller-supplied pane hints.
- Principal lifetime tests prove bound pane close invalidates future auth and
  revokes grants.
- Env injection tests prove the spawned session environment receives only
  non-secret routing metadata such as `AGENTSTUDIO_IPC_SOCKET` and
  `AGENTSTUDIO_IPC_RUNTIME_ID`.
- Spawn-bootstrap tests prove the subject token is delivered through a
  non-enumerable, close-on-exec channel, not an environment variable or metadata
  file.
- Metadata tests prove the subject token is not persisted in `agentStudioOnly`.
- Redaction tests use a sentinel token and prove it is absent from logs, traces,
  telemetry/audit payloads, JSON-RPC errors, `auth.status`, and events.

### T4. Programmatic Control Contracts, Registry, Handles, Capabilities

Entry gate:

- Decide the phase-1 approval-policy storage home before implementing
  `ApprovalPolicyStore`: settings-backed persistence, workspace-local config, or
  runtime-only developer config. The chosen home must be app-owned/user-configured
  and must not be encoded inside bearer tokens or zmx state.
- Delegated approval is in phase 1. If this becomes too large during execution,
  stop and replan instead of silently unregistering `permission.resolveRequest`.

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/`
- `Sources/AgentStudioAppIPC/`
- `Tests/AgentStudioProgrammaticControlTests/`
- `Tests/AgentStudioAppIPCTests/`
- `Tests/AgentStudioTests/App/IPC/` for executable composition only

Implement:

- Phase-1 method definitions and schemas:
  `system.*`, `auth.*`, `window.*`, `workspace.*`, `pane.*`,
  `terminal.*`, `permission.*`, `events.*`.
- Privilege classes, target/data scopes, and execution-owner metadata.
- Finer-grained phase-1 privilege vocabulary from the spec:
  `paneContextRead`, `terminalStatusRead`, `terminalSnapshotRead`,
  `terminalInputWrite`, `terminalWait`, and `grantApprove`, in addition to the
  broader registry classes.
- Result semantics metadata (`applied` default, `accepted` only when justified).
- Handle model: canonical UUIDs plus runtime-local friendly refs for
  `window:*`, `workspace:*`, `tab:*`, `pane:*`.
- Baseline selfPane grant derivation for spawned pane principals.
- Exact selfPane allowed/denied method table so baseline authorization does not
  depend on broad terminal read/write interpretation.
- `GrantLedger`, `PermissionBroker`, `AuthorizationService`, and
  `PermissionScopeCanonicalizer`.
- Grant lifetime policies for baseline principal-bound grants, read-only elevated
  grants, connection-bound elevated mutating grants, and one-shot elevated
  mutating grants.
- Approval routes:
  `appPolicy`, `humanPrompt`, and `delegatedPrincipal`.
- `ApprovalPolicyStore` and `PermissionApprovalPort` protocols, with concrete
  implementations in `App/IPCComposition`.
- `permission.request`, `permission.requestStatus`, `permission.grantStatus`,
  `permission.pendingApprovals`, and `permission.resolveRequest`.
- Registry capability export for future MCP mapping without implementing MCP.
- Namespace denylist for deferred groups, especially `zmx.*`.

Symbol ownership:

```text
AgentStudioProgrammaticControl
  IPCMethodDefinition
  IPCMethodRegistryDescription
  JSON-schema descriptions or schema source metadata
  IPCPrivilege
  IPCDataScope
  IPCTargetScope
  IPCTargetRef
  IPCHandle
  IPCPrincipalKind / principal DTOs that contain no bearer token material
  PermissionRequestParams
  PermissionRequestResult
  PermissionStatusResult
  PermissionEvent DTOs
  public result/error DTOs

AgentStudioAppIPC
  IPCService
  IPCConnectionAuthState
  SubjectTokenRegistry
  PrincipalRegistry
  GrantLedger
  PermissionBroker
  AuthorizationService
  PermissionScopeCanonicalizer
  AppIPCMethodRegistry assembly
  ApprovalPolicyStore protocol
  PermissionApprovalPort protocol
  query/layout/runtime/event port protocols

AgentStudio executable / App/IPCComposition
  concrete ApprovalPolicyStore implementation
  concrete PermissionApprovalPort implementation
  concrete query/layout/runtime/event port implementations
  adapters to CommandDispatcher / ActionExecutor / WorkspaceCommandValidator
  adapters to PaneCoordinator / RuntimeRegistry / PaneRuntime
```

Stateful auth, ledger, authorization, and approval routing must not live in
`AgentStudioProgrammaticControl`. Concrete app-owner adapters must not live in
`AgentStudioAppIPC`.

Proof:

- Registry completeness test: every method has params schema, result schema,
  privilege class, principal availability metadata, execution owner, and result
  semantics.
- Deferred namespace test: no `zmx.*`, `mcp.*`, `browser.*`, `webview.*`,
  `bridge.*`, or phase-1 expansion methods unless explicitly promoted.
- Handle tests for UUID canonicalization, friendly ref resolution, no reuse
  during a runtime, and error mapping for missing targets.
- Authorization tests prove selfPane is principal-bound, focus changes do not
  affect selfPane, cross-pane send is denied without an active grant, and
  canonicalization happens before grant comparison.
- Permission tests prove app-policy auto-approve/deny/ask behavior, delegated
  approval with `grantApprove`, `permission.pendingApprovals` recovery for
  delegated approvers, rejected self/unauthorized approval, requester status
  recovery, TTL/close/restart revocation, connection-close revocation,
  one-shot-consumption, reconnect denial for elevated mutating grants, and
  non-persistence.
- Target-specific tests prove contract DTOs compile without AppIPC, AppIPC tests
  compile without the AgentStudio executable target, and executable adapter tests
  are the only tests that import concrete app/runtime owners.

### T5. App Query And Snapshot Adapters

Write surfaces:

- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/`
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- Query adapters for `system.identify`, `system.version`, `system.capabilities`.
- Window/workspace/pane list/current methods over existing app state.
- `pane.snapshot` DTO from current workspace and runtime metadata.
- JSON-RPC error mapping for no active window and target not found.
- Redaction policy for titles, paths, URLs, cwd, command lines, progress text,
  search state, and future content-bearing fields.

Proof:

- Snapshot fixture tests over isolated `WorkspaceStore` state.
- No-active-window tests.
- Sensitive-field tests: public DTOs contain only allowed fields and either omit
  or explicitly redact secret-bearing values.

### T6. Pane Focus App-Control Seam

Write surfaces:

- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/`
- Possibly a small `App/Commands` or `App/Coordination` seam if current focus
  behavior is too private to expose safely.
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- A deliberate app-control seam for `pane.focus`.
- Target resolution through the handle resolver.
- Validation through existing command/focus owners, not direct atom mutation.
- `-32006 no active window`, `-32004 target not found`, and
  `-32007 validation rejected` mapping.

Proof:

- Tests prove focus uses named owner chain.
- Tests prove missing active window and missing target errors.
- No direct atom mutation from IPC adapter.

Split/replan trigger:

- If the only workable implementation needs private `PaneTabViewController`
  methods or direct `WorkspaceFocusOwnerAtom` mutation, stop and redesign the
  app-control seam before shipping `pane.focus`.

### T7. Terminal Runtime Adapter

Write surfaces:

- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/`
- `Tests/AgentStudioTests/App/IPC/`
- Existing terminal/runtime tests only if new public DTO behavior belongs there.

Implement:

- `terminal.status` from runtime lifecycle/capabilities/backend status.
- `terminal.snapshot` from `PaneRuntimeSnapshot` plus allowlisted
  `TerminalRuntime` fields.
- `terminal.send` as `.terminal(.sendInput(...))` through
  `ActionExecutor.dispatchRuntimeCommand`.
- Error mapping from `ActionResult` to JSON-RPC app errors.
- Correlation id handling in request/result and emitted events.

Proof:

- Fake runtime tests for success, unresolved pane, no runtime, runtime not
  ready, unsupported command, and backend unavailable.
- Terminal send test proves RPC success means SurfaceManager accepted bytes, not
  shell command completion.
- Snapshot tests prove no output, scrollback, zmx history, socket path, raw PTY
  bytes, or raw runtime object is serialized.

### T8. Events, Permission Events, And Terminal Waits

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/`
- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudio/App/IPCComposition/`
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- Public exported event names and payload DTOs.
- `events.subscribe` / `events.unsubscribe` over authenticated connection state.
- JSON-RPC `events.notification` notifications.
- Permission event DTOs:
  `permission.requestCreated`, `permission.requestResolved`,
  `permission.grantRevoked`, and `permission.grantExpired`.
- Permission event visibility for requesting principal, app approval surface,
  delegated approving principal, and unrelated principals.
- Permission recovery semantics:
  - requesters recover their own request/grant state through
    `permission.requestStatus` and `permission.grantStatus`;
  - delegated approvers recover routed pending requests through
    `permission.pendingApprovals`;
  - unrelated principals recover nothing by default.
- Rejection of inbound client notifications that pretend to be server events.
- Bounded non-durable replay only when a source supports it; replay gap maps to
  `-32010`.
- Slow subscriber policy and close/error behavior.
- `terminal.wait` condition enum. Initial candidate set:
  `attachReady`, `commandFinished`, `rendererHealthy`, `titleChanged`,
  `cwdChanged`, `progressChanged`.
- Admission limits so long waits do not starve short RPCs.

Proof:

- Event subscribe/unsubscribe tests.
- Allowlist tests for event names and payloads.
- Permission event visibility tests.
- Status-query tests prove requester-owned missed permission events are
  recoverable through `permission.requestStatus` and `permission.grantStatus`.
- Approver-query tests prove missed delegated approval events are recoverable
  through `permission.pendingApprovals` only for routed requests covered by
  `grantApprove`.
- Inbound `events.notification` / `permission.requestResolved` frames cannot
  mutate grants.
- Slow subscriber/backpressure tests.
- Wait tests with fake runtime events and injected clocks.
- Rejection tests for arbitrary internal event names/predicates.

Split/replan trigger:

- If a wait condition cannot map to an exported stable fact, remove it from
  phase 1 rather than exposing raw internal runtime predicates.

### T9. CLI Client And Smoke Harness

Entry gate:

- T9 remains in phase 1 only as a dedicated Swift executable target. If that is
  too much for the first implementation slice, remove CLI from phase 1 and keep
  only test-owned smoke clients.

Write surfaces:

- `Package.swift` for the dedicated CLI executable target and product.
- `Sources/AgentStudioIPCClient/`
- `Tests/AgentStudioIPCClientTests/`
- README/guide snippets only after behavior exists.

Implement:

- Socket discovery from explicit flag, `AGENTSTUDIO_IPC_SOCKET`, and metadata.
- Auth from a non-enumerable app bootstrap credential or explicit token input.
- Commands for identify/capabilities/list/current/pane focus/terminal send/wait.
- Machine-readable output by default; optional human output can follow later.
- No imports of `AgentStudioAppIPC` or the AgentStudio executable target. The CLI
  depends only on transport/client mechanics and public programmatic-control
  contracts.

Proof:

- CLI unit tests for discovery and request serialization.
- SwiftPM target graph proves the CLI target depends only on
  `AgentStudioIPCTransport` and `AgentStudioProgrammaticControl`.
- Smoke test against an isolated test IPC server.
- Optional app smoke only if a safe debug/beta app instance can be launched
  without disturbing the user's running app.

### T10. Architecture Promotion And Spec Retirement

Write surfaces:

- `docs/architecture/directory_structure.md`
- `docs/architecture/appkit_swiftui_architecture.md`
- `docs/architecture/pane_runtime_architecture.md`
- `docs/architecture/pane_runtime_eventbus_design.md`
- `docs/architecture/session_lifecycle.md` only for zmx boundary notes, not app
  IPC method details.

Implement:

- Promote implemented module ownership, method registry rules, auth defaults,
  subject-token/principal/grant rules, approval policy/delegation rules,
  event/wait public contract, and app/runtime routing rules.
- Mark the spec as implementation history after code lands.
- Keep zmx backend IPC doc separate and still future-facing until implemented.

Proof:

- `rg` confirms architecture docs point to implemented files.
- `rg` confirms no durable docs describe public `zmx.*` app methods.
- `rg` confirms durable docs describe app-level grants/approval as AppIPC state,
  not zmx or EventBus state.
- `mise run lint` includes markdown/boundary checks as repo tooling defines.

### T11. Command/UI Namespace Split And Headless Command Execution

Purpose: correct the command surface so IPC can use the command-spec system
without pretending that opening command palette UI is headless command execution.

Entry gate:

- Keep the current `AppCommand` / `CommandSpec` identity model as the metadata
  source. Do not fork a second command catalog.
- Treat this as a contract correction, not a debug-smoke proof. The current live
  proof that dispatches `showCommandBar*` commands is useful evidence that UI
  presentation can work, but it is not proof of headless semantic command
  execution.

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift`
- `Sources/AgentStudioProgrammaticControl/IPCContracts.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCLayoutAdapter.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
- New or renamed `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCUIPresentationAdapter.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioIPCRegistryAuthorizationTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCLayoutAdapterTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
- New or renamed `Tests/AgentStudioTests/App/IPC/AgentStudioIPCUIPresentationAdapterTests.swift`
- `Tests/AgentStudioIPCClientTests/` if the CLI exposes the new methods.
- `docs/architecture/agentstudio_ipc_architecture.md` after implementation proof.

Implement:

- Add a public execution-mode model, for example:
  `headless`, `uiPresentation`, and future `requiresInteractiveInput`.
- Add `uiPresent` privilege and a `uiPresentation` execution owner to the public
  contract metadata.
- Change `command.list` so it lists headless-capable semantic commands, with
  execution modes, target kinds, required privileges, and required parameters.
- Hard-cut the DTO shape. Headless `command.*` descriptors/results and
  UI-presentation `ui.commandBar.open` params/results are separate public DTO
  families. Do not keep a compatibility shim where command results carry
  command-bar postconditions.
- Change `command.execute` so it rejects commands whose current implementation
  requires presentation or missing user input. It must not call
  `showCommandBarEverything`, `showCommandBarCommands`, `showCommandBarPanes`, or
  `showCommandBarRepos`.
- Add `ui.commandBar.open` with params:
  `scope: everything | commands | panes | repos` and optional correlation id.
  Phase 1 deliberately omits `targetWindow`; the method presents in the resolved
  current workspace window only. Window-scoped UI grants require a future
  `window` target scope plus canonicalization and wrong-window denial tests.
- Route `ui.commandBar.open` through an explicit UI-presentation port. The
  executable target may use command-bar presentation machinery, but the port must
  return a presenter-owned result object. Do not prove presentation by dispatching
  a shell command and then inspecting global `CommandBarSurfaceAtom` state.
- Return presentation postconditions such as workspace window id and active
  command-bar scope. Do not report command/action completion.
- Keep create/split/close semantics in domain namespaces. `tab.create` and
  `pane.split` are semantic methods when explicit arguments are available;
  `ui.commandBar.open(scope: repos)` is the chooser/picker affordance.
- Promote the first useful layout-control methods in this slice because they
  already have a stable owner chain: `pane.split`, `pane.close`,
  `drawer.toggle`, and `drawer.addPane` route through
  `AgentStudioIPCLayoutAdapter -> ActionExecutor -> WorkspaceCommandValidator ->
  PaneCoordinator`. IPC owns handle/parameter translation only.
- Treat drawer control as pane-layout control, not UI presentation. Opening,
  closing, or adding drawer panes must use explicit `drawer.*` methods with pane
  handles; showing a picker or command bar to choose a drawer target remains
  `ui.*`.
- Update CLI/client command names only after the server contract and tests pass.

Proof:

- Red test first: existing `command.execute(commandPalette)` / command-bar opener
  tests must fail under the new expectation or be replaced by explicit
  `ui.commandBar.open` tests.
- Registry tests prove `command.execute` is not registered with `debugUnsafe` as
  the only practical access path for UI presentation, and `ui.commandBar.open`
  declares `uiPresent`.
- Command adapter tests prove `command.execute` rejects UI-opening commands with
  `requiresPresentation` / `unsupportedCommand` and does not mutate command-bar
  surface state. Unknown command ids must decode as open strings and return
  `unsupportedCommand` / `unsupported capability`, not `invalid params`.
- Registry/auth tests prove `command.list` is a non-debug discovery method
  (`systemRead` unless implementation review chooses a narrower command-read
  privilege) and that `command.execute` cannot be used as a broad replacement for
  method-specific privileges.
- UI adapter and authorization tests prove `ui.commandBar.open` presents through
  the presentation owner, returns the postcondition for the resolved workspace
  window, and is authorized at app scope until a public window target exists.
- Layout adapter tests prove `pane.split`, `pane.close`, `drawer.toggle`, and
  `drawer.addPane` resolve handles and delegate to the action owner seam without
  direct atom mutation. They must report owner-chain validation rejection instead
  of optimistic success, and drawer parent handles must reject drawer-child
  panes unless a later design explicitly canonicalizes them to parents.
- Concrete layout-owner tests prove split/drawer actions register placeholder
  hosts before exposing newly-created terminal panes to visible tab or drawer
  layouts. Live debug proof must also run against a restored debug root without
  crashing on recoverable missing-host state.
- Permission broker tests prove `layoutMutate` grants are not requestable through
  the current principal-bound grant ledger; non-debug mutating grants need a
  later connection-bound or one-shot grant model.
- Live debug proof must exercise at least one split and one drawer command
  through IPC, then query `pane.list` or `pane.snapshot` to prove the app state
  changed.
- Manual debug proof for this slice must capture exact JSON-RPC requests and
  responses for:
  `command.execute(commandPalette)` failing with `requiresPresentation` or
  `unsupportedCommand`, `ui.commandBar.open(scope: commands)` succeeding with a
  presentation-only postcondition, `pane.split` changing the pane graph,
  `drawer.addPane` changing drawer/pane state, and `drawer.toggle` applying to
  the requested parent pane. The proof must leave the debug app process alive
  after the sequence.
- No-active-window tests map to `-32006`.
- Authorization tests prove spawned pane agents do not get `uiPresent` by
  baseline and pane-scoped `uiPresent` does not authorize app/window
  presentation, while unsafe debug can still use `ui.commandBar.open` for local
  smoke proof.
- CLI/client tests, if updated in this slice, prove method serialization for
  `ui.commandBar.open` and do not send bearer tokens in argv.
- `swift test --package-path Tools/AgentStudioArchitectureLint`
- Focused Swift tests for `IPCContractsTests`,
  `AgentStudioIPCRegistryAuthorizationTests`,
  `AgentStudioIPCCommandAdapterTests`, `AgentStudioIPCUIPresentationAdapterTests`,
  and CLI client tests if touched.
- `mise run lint`

Split/replan trigger:

- If no stable headless owner exists for a desired `AppCommand`, do not expose it
  through `command.execute`. Either add a domain method with explicit parameters
  and owner chain, or leave it out of phase 1.
- If `ui.commandBar.open` requires direct command-bar atom mutation, stop and route
  through the app-owned presentation controller/port instead.

## Write Surface Summary

Expected new areas:

- `Sources/AgentStudioIPCTransport/`
- `Sources/AgentStudioProgrammaticControl/`
- `Sources/AgentStudioAppIPC/`
- `Sources/AgentStudioIPCClient/` if T9 remains in phase 1
- `Sources/AgentStudio/App/IPCComposition/`
- `Tests/AgentStudioIPCTransportTests/`
- `Tests/AgentStudioProgrammaticControlTests/`
- `Tests/AgentStudioAppIPCTests/`
- `Tests/AgentStudioIPCClientTests/` if T9 remains in phase 1
- `Tests/AgentStudioTests/App/IPC/` for executable composition/integration only

Expected existing areas touched narrowly:

- `Package.swift` for required IPC library target split and test-target
  dependencies. If T9 remains in phase 1, it also adds a dedicated CLI executable
  target; otherwise no committed non-target CLI client is allowed.
- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift` for optional
  `ipcDirectory()` / `ipcRuntimeMetadataURL()` helpers.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift` or an extension for service
  lifecycle wiring.
- Existing terminal session environment construction path for IPC env injection.
- Existing IPC command adapter/contracts for the T11 command/UI split.
- `Tools/AgentStudioArchitectureLint/`,
  `Tests/AgentStudioTests/Scripts/ArchitectureSwiftLintRulesTests.swift`, and
  `docs/architecture/architecture_lint_inventory.md` when IPC SwiftSyntax rules
  change. The local rule implementation, fixtures, rule inventory tests, app
  wiring tests, and inventory rule ids must move together.

No expected changes:

- zmx daemon protocol or vendored zmx sources.
- Public Bridge/Webview method surfaces.
- Atom write-owner boundaries.
- EventBus command routing semantics.
- Existing `AppCommand` / `CommandSpec` catalog identity. T11 consumes it; it does
  not fork it.

## Validation Gates

Required during implementation slices:

1. `git diff --check`
2. Compile/lint architecture gates:
   - `swift package describe` for target graph inspection after T1
   - package compile or targeted Swift tests for the new IPC modules
   - dedicated IPC test targets compile without depending on the AgentStudio
     executable target
   - CLI target graph/build proves CLI depends only on transport/contracts if T9
     remains in phase 1
   - `swift test --package-path Tools/AgentStudioArchitectureLint` after adding
     or updating IPC SwiftSyntax rules
   - `ArchitectureSwiftLintRulesTests.swift` asserts the new IPC rule ids appear
     in the local architecture tool output
3. Focused unit tests for each slice:
   - IPC codec/framer/listener
   - filesystem trust/auth/principals
   - method registry/handles/schemas/grants
   - approval policy, delegated approval, and permission status
   - app query adapters
   - pane focus seam
   - terminal adapter
   - events/permission events/waits
   - CLI discovery/client
   - command/UI namespace split and presentation adapter
4. Existing relevant suites:
   - `Tests/AgentStudioTests/Infrastructure/AppDataPathsTests.swift`
   - `Tests/AgentStudioTests/App/ActionExecutorTests*.swift`
   - `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Replay/EventReplayBufferTests.swift`
   - `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
   - `Tests/AgentStudioTests/Features/Bridge/RPCRouterTests.swift` only as
     prior-art regression for JSON-RPC behavior, not as app IPC proof.
5. `mise run lint`
6. `mise run test`
7. Smoke gate:
   - local IPC smoke against an isolated test listener;
   - app-level smoke only in a separate debug/beta instance if the running user
     app must not be disturbed.

Current tooling proof from this planning pass after merging PR #175:

- `mise run lint` completed successfully: swift-format OK, AgentStudio SwiftLint
  found 0 violations in 1131 Swift files, and release script verification passed.
  If this regresses during implementation, separate changed-surface proof from
  unrelated tooling blockers before editing release tooling.

Current implementation proof after the T8 event/wait slice:

- Focused IPC test gate:
  `swift test --filter 'IPCContractsTests|JSONRPCCodecTests|AgentStudioIPCEventBrokerTests|AgentStudioIPCPermissionBrokerTests|AgentStudioIPCRuntimeAdapterTests|AgentStudioAppIPCServiceTests|AgentStudioIPCRegistryAuthorizationTests'`
  passed with 48 tests in 7 suites.
- Full lint gate: `mise run lint` passed with swift-format OK, AgentStudio
  SwiftLint 0 violations across 1166 Swift files, and release script
  verification passed.

Current implementation proof after the T9 CLI/smoke slice:

- CLI/client test gate:
  `swift test --filter 'AgentStudioIPCClientCoreTests|JSONRPCCodecTests'`
  passed with 16 tests in 2 suites, including a real Unix-socket request/response
  smoke against a test listener.
- CLI product build gate: `swift build --product agentstudio-ipc` passed.
- SwiftPM target graph check confirmed `agentstudio-ipc`,
  `AgentStudioIPCClient`, and `AgentStudioIPCClientCore` are package targets, and
  the client core depends on transport/contracts rather than `AgentStudioAppIPC`.

Implementation proof after the T10 docs-maintain pass:

- Full repo test gate: `mise run test` passed after fixing IPC-introduced
  parallel-test hazards in the terminal wait adapter test and Unix socket
  transport SIGPIPE test.
- Full lint gate: `mise run lint` passed with swift-format OK, pinned
  AgentStudio SwiftLint 0 violations across 1170 Swift files, and release script
  verification passed.
- Diff hygiene gate: `git diff --check` passed.
- Architecture docs now describe the implemented target split, request authority
  path, terminal runtime waits, event broker, CLI boundary, auth/permission
  model, and zmx separation in `docs/architecture/agentstudio_ipc_architecture.md`.
- Directory and architecture index docs now reference the implemented IPC targets
  and `agentstudio-ipc` CLI target.

Review-driven contract fixes after implementation review:

- CLI auth no longer accepts bearer tokens in argv. Token input is explicit
  `--token-stdin`, and authenticated calls send `auth.login` plus the command on
  the same Unix socket connection.
- `events.subscribe` is a streaming command in the client core. The CLI keeps
  the socket open after the subscribe acknowledgement and prints later
  `events.notification` frames from the same connection.
- Subject tokens are one-shot and connection-bound in phase 1; token rotation
  and pane invalidation revoke pending/active principal grants.
- Permission resolution is atomic in the grant ledger, so a later denial cannot
  overwrite an already approved request or leave a contradictory grant.
- Delegated approvers see only requests routed to their delegated approval
  authority. App-policy and human-prompt events stay app/human-owned.
- `terminal.wait` for `attachReady` now waits for the runtime to become ready
  after the wait starts instead of sampling only the initial lifecycle snapshot.
- Pane query DTOs omit titles as well as cwd, URL, command line, terminal output,
  zmx ids, and backend internals.

Focused proof for the review-driven fixes:

- `swift test --filter 'AgentStudioIPCClientCoreTests|AgentStudioIPCAuthenticationTests|AgentStudioIPCPermissionBrokerTests|AgentStudioIPCQueryAdapterTests|AgentStudioIPCRuntimeAdapterTests|IPCContractsTests' --build-path .build-agent-1`
  passed with 52 tests in 6 suites.

Implementation proof for the live app listener/bootstrap slice:

- `swift test --filter 'AgentStudioAppIPCServiceTests|AgentStudioIPCAuthenticationTests|AgentStudioIPCPermissionBrokerTests|AgentStudioIPCRegistryAuthorizationTests|ApplicationEntrypointArchitectureTests|AgentStudioIPCLayoutAdapterTests|AgentStudioIPCQueryAdapterTests|AgentStudioIPCRuntimeAdapterTests|AgentStudioIPCClientCoreTests|IPCContractsTests' --build-path .build-agent-1`
  passed with 75 tests in 10 suites.
- `SWIFT_TEST_TIMEOUT_SECONDS=120 mise run test` passed after the
  attach-ready wait loop and review-driven socket/auth fixes. The captured log
  had no Swift Testing failure markers; WebKit serialized suites passed, while
  `E2ESerializedTests` and `ZmxE2ETests` were skipped by the repo-default
  environment (`SWIFT_TEST_INCLUDE_E2E=0`,
  `SWIFT_TEST_INCLUDE_ZMX_E2E=0`).
- `mise run format && mise run lint && swift build --product AgentStudio
  --build-path .build-agent-1 && git diff --check` passed. The lint gate used
  the pinned AgentStudio SwiftLint architecture runner and reported 0
  violations across 1172 Swift files.
- `AgentStudioAppIPCServiceTests` covers a live Unix socket server for
  pre-auth `system.ping`, same-connection `auth.login` plus
  `system.identify`, pre-login rejection, delegated permission request/list/
  resolve/grant-status flow over authenticated sockets, friendly-ordinal
  terminal authorization against the resolved concrete pane, shutdown of
  existing authenticated socket sessions, and fd-based pane bootstrap token
  delivery with no env bearer token and close-on-exec custody.
- `ApplicationEntrypointArchitectureTests` covers `AppDelegate` server storage,
  boot order after lifecycle consumers, `AppDelegate+IPC.swift` composition,
  pane focus control exposure, and shutdown before termination persistence
  drains.
- `AgentStudioIPCRuntimeAdapterTests` covers `terminal.wait attachReady` both
  when the runtime is already ready and when readiness appears after the wait
  starts. The adapter checks the readiness fact before timing out on each
  resume so scheduler delay cannot hide an already-ready runtime.

Remaining follow-up before claiming pane-agent child-process bootstrap:

- The server can mint pane-bound principals and deliver one-shot subject tokens
  through `AgentStudioIPCPaneBootstrapFactory`, but no current pane-agent spawn
  adapter deliberately remaps that fd into a child process. Keep this as an
  app-spawn integration follow-up rather than re-opening the public IPC protocol
  design.

## Rollout And Recovery

- Default target mode is `agentStudioOnly` with memory-only subject tokens.
- `off` mode must exist for recovery and testing.
- `automationSameUser` remains opt-in and must be honestly documented as
  same-user local automation if token bootstrap material is discoverable.
- Startup must not steal a live socket from a different same-channel process.
- Stale dead sockets can be unlinked after probe.
- Listener shutdown removes runtime metadata and closes connections.
- Event subscriptions are non-durable; clients recover by refreshing snapshots.
- Permission events are non-durable; requesters recover through
  `permission.requestStatus` / `permission.grantStatus`, while delegated
  approvers recover routed pending approvals through `permission.pendingApprovals`.

## Risks

- Peer PID ancestry is weaker and more platform-specific than token custody.
  Keep same-uid plus memory-only subject token as the actual phase-1 enforcement
  model.
- Subject-token leakage is principal impersonation. Keep elevated mutating grants
  connection-bound or one-shot by default, and keep approval authority server-side
  on principals/policies rather than inside bearer-token claims.
- Preconfigured app policy can silently approve too much if its scope language is
  vague. Canonicalize scopes before issuing and consuming grants, and prefer short
  TTLs for elevated read grants.
- Delegated approval can become ambient authority if `grantApprove` is broad.
  Require canonical target/data scope checks and explicit tests for unauthorized
  `permission.resolveRequest`.
- `pane.focus` may require a new app-control seam because current focus behavior
  is partly controller/private. Do not bypass this with direct atom writes.
- Terminal snapshots can leak secrets through titles, cwd, progress, search
  query/state, or future fields. Treat the DTO as an allowlist, not a mirror.
- Event subscriptions can become an accidental raw runtime-envelope API. Keep
  public event DTOs separate.
- CLI packaging may force package/product changes; decide before coding.
- Command identity can become a semantic trap: a single `AppCommand` may currently
  be used by keyboard/UI affordances that gather missing input. IPC must classify
  the exposed method by effect and execution mode, not by shortcut label.
- UI presentation authority can become a covert automation path if it is granted
  broadly. Keep `uiPresent` separate from `layoutMutate` and deny it from spawned
  pane baseline grants unless explicitly approved.
- Full `mise run lint` now passes in this worktree after PR #175. Future failures
  should still distinguish changed-surface proof from unrelated tooling blockers.

## Follow-Up Decisions

1. Decide whether `system.ping` should become a pre-auth content-free health
   check or whether `auth.login` remains the only pre-auth method.
2. Decide whether `automationSameUser` graduates from opt-in follow-up into a
   default local automation mode after `agentStudioOnly` has real app boot
   coverage.
3. Choose durable storage for user-configured approval policy:
   settings-backed persistence, workspace-local config, or runtime-only
   developer config.
4. Choose the first headless semantic command allowlist for `command.execute`.
   Recommended default: start with commands whose owner chain already has explicit
   target/argument semantics, and keep create/split/close domain methods separate
   when a clearer `pane.*`, `tab.*`, or `terminal.*` method exists.

## Implementation Decisions Resolved

- `terminal.wait` supports `attachReady`, `commandFinished`,
  `rendererHealthy`, `titleChanged`, `cwdChanged`, and `progressChanged`. These
  map to stable exported runtime facts and return allowlisted scalar payloads
  only.
- `terminal.snapshot` remains an allowlisted DTO and omits terminal output,
  scrollback, raw PTY bytes, cwd/title/search/progress content, zmx identifiers,
  and raw runtime objects.
- Event subscription ownership lives in `IPCEventBroker`, which stores
  principal-bound subscriptions, encodes JSON-RPC `events.notification` frames,
  filters by public event name and visibility predicate, rejects inbound
  server-event impersonation, and removes slow subscribers that report
  backpressure.
- T9 remains in phase 1 as a dedicated Swift executable product named
  `agentstudio-ipc`, backed by `AgentStudioIPCClientCore`. The client target
  graph intentionally excludes `AgentStudioAppIPC` and the AgentStudio
  executable target.
- UI-opening command-bar scopes remain exposed because they are useful for
  automation and live debugging, but the target contract exposes them as explicit
  `ui.commandBar.open` presentation methods rather than `command.execute`.

## Next Workflow

Use implementation review / PR wrap-up before merging this branch. Future work
should plan from the durable architecture docs first, then use this file only as
historical proof for what landed in the phase-1 IPC foundation.
