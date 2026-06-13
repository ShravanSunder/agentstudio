# AgentStudio IPC Implementation Plan

**Date:** 2026-06-13
**Status:** Draft implementation plan from approved design direction. Requires plan review before execution.
**Primary spec:** `docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md`
**Related backend spec:** `docs/superpowers/specs/2026-06-13-zmx-backend-ipc-design.md`

## Goal

Implement the first Agent Studio app-level IPC slice: local Unix-domain socket,
strict JSON-RPC 2.0 framing, `agentStudioOnly` auth, method registry,
pane-first handles, read/query methods, pane focus, terminal status/snapshot/send/wait,
event subscriptions, and a local CLI client.

The implementation must route through existing app and runtime owners. It must
not introduce a new mutation owner, command bus, public zmx API, or phase-1 MCP
transport.

## Source Coverage

Read in full before planning:

- `docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md`: 945 lines,
  chunks `1-240`, `241-520`, `521-760`, `761-945`.
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
  test target; adding a CLI requires an explicit package/product decision.

## Non-Goals

- No MCP implementation in phase 1.
- No V1 line protocol, JSON-RPC batches, TCP, WebSocket, or remote app-control
  transport.
- No password mode, world-writable socket, or production `allowAll`.
- No terminal output streaming, scrollback, zmx history, raw PTY bytes, raw
  runtime envelopes, or raw zmx protocol details.
- No public `zmx.*` namespace.
- No direct atom mutation from IPC methods.
- No zmx backend IPC transport swap in this plan. The zmx backend spec remains
  a later internal implementation plan after vendor verification.

## Architecture Shape

```text
external agent / CLI
  -> Infrastructure/IPC
       Unix socket, peer credentials, NDJSON, JSON-RPC codec
  -> Core/ProgrammaticControl
       method contracts, schemas, privileges, handles, public events/waits
  -> App/IPC
       service lifecycle, auth, registry assembly, query/action/runtime adapters
  -> existing owners
       CommandDispatcher / ActionExecutor / WorkspaceCommandValidator
       PaneCoordinator / RuntimeRegistry / PaneRuntime
```

This plan intentionally keeps three boundaries separate:

1. Generic transport mechanics do not import app/product types.
2. The method registry is product semantics but not socket-specific.
3. App adapters bridge public methods into existing app/runtime owners.

## Requirements And Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green required | Sized to pass? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Unix socket JSON-RPC accepts one newline-delimited request per frame and rejects invalid JSON, missing `jsonrpc`, non-object params, oversize frames, and batch arrays | T1 | `Infrastructure/IPC` tests | Focused Swift tests for codec/framer/listener fakes | Unit/integration | Tests use real newline chunking and malformed fixtures, not Bridge router assumptions | Yes | Yes |
| Generic IPC infrastructure has no Core/App/Feature imports | T1 | Boundary check plus test compile | Existing boundary lint plus targeted import check if needed | Lint | New `Infrastructure/IPC` files are scanned in lint | No | Yes |
| App IPC metadata and socket paths are derived from `AppDataPaths.rootDirectory()` under `<root>/ipc` | T2 | `App/IPC` service tests | Unit tests with injected environment/root/channel | Unit | Tests assert stable/beta/debug/env override paths and owner-only metadata mode | Yes | Yes |
| Filesystem trust fails closed for symlinks, wrong owner, group/world access, and stale live socket ownership | T2 | `App/IPC` filesystem trust tests | Temp-dir tests with permission fixtures where platform allows | Integration | Permission checks skipped only when Darwin cannot set a mode, with explicit assertions for supported paths | Yes | Yes |
| `agentStudioOnly` token is memory-only and injected only into Agent Studio-spawned sessions | T3 | Auth service and session env tests | Unit tests for auth state plus environment-construction tests | Unit/integration | Tests scan metadata output for token absence and assert env contains socket/token/runtime id | Yes | Yes |
| Same-uid peer credential check runs before token auth and auth failures close/reject as specified | T3 | Transport/auth tests | Peer credential abstraction fake tests plus live same-uid happy path if feasible | Unit/integration | Peer credential abstraction is injectable so behavior is not dependent on CI socket support | Yes | Yes |
| Method registry requires schemas, privilege class, execution owner, and result semantics for every phase-1 method | T4 | Registry tests | Reflection/table tests over registered methods | Unit | Test fails on missing metadata or deferred namespace registration | Yes | Yes |
| Public handles are pane-first, UUID-canonical, and friendly refs are runtime-local conveniences | T4 | Handle resolver tests | Unit tests with stable fake app snapshot | Unit | Tests prove ordinals are not persisted and responses echo canonical UUID targets | Yes | Yes |
| Query methods read snapshots without mutating atoms | T5 | Query adapter tests | Snapshot tests over `WorkspaceStore` fixtures | Unit | Tests use read-only fixtures and no mutation method calls in adapter | Yes | Yes |
| `pane.focus` routes through a deliberate app-control seam rather than private view-controller methods | T6 | Layout adapter tests | Focused tests on action seam and no-active-window error | Unit/integration | Task cannot pass until seam has a named owner chain and no-direct-atom-mutation proof | Yes | Yes |
| `terminal.send` routes through `ActionExecutor -> PaneCoordinator -> RuntimeRegistry -> PaneRuntime` and means bytes accepted by surface, not shell completion | T7 | Runtime adapter tests | Existing coordinator dispatch tests plus new IPC adapter tests | Unit/integration | Test maps `ActionResult` to JSON-RPC and does not wait for shell output | Yes | Yes |
| `terminal.status` and `terminal.snapshot` expose allowlisted DTOs only, with no raw TerminalRuntime, output, scrollback, zmx, paths, URLs, or secrets unless explicitly redacted | T7 | DTO/schema tests | Snapshot serialization tests and sensitive-field denylist tests | Unit | Tests include terminal title/cwd/search/progress examples and assert redaction/omission policy | Yes | Yes |
| `terminal.wait` accepts only exported condition enum values and uses bounded waits/admission limits | T8 | Wait adapter tests | Fake event stream tests with injected clock/bounded timeout | Unit/integration | Tests reject arbitrary event names and prove timeout cleanup | Yes | Yes |
| `events.subscribe` streams only allowlisted public event DTOs and disconnects/errs slow subscribers | T8 | Event broker tests | Fake subscriber/backpressure tests | Integration | Tests assert no raw `RuntimeEnvelope` or terminal output payload is serialized | Yes | Yes |
| CLI can discover socket metadata, authenticate, call read methods, send terminal input, and subscribe/unsubscribe | T9 | CLI smoke tests | CLI unit tests plus local smoke against test IPC server | Smoke | Smoke uses isolated `AGENTSTUDIO_DATA_DIR` and does not touch user's running app | Yes | Yes |
| Phase-1 implementation does not expose zmx public methods or zmx internals | T4/T7/T8 | Registry/schema tests | Namespace denylist and snapshot/event sensitive-field tests | Unit | Tests explicitly deny `zmx.*`, socket path, session name, history, raw `Info` bytes | Yes | Yes |
| Architecture docs are promoted after implementation and spec becomes history | T10 | Docs proof | `rg` checks plus docs diff review | Docs/lint | Docs reference real implemented file paths and remove stale open decisions | No | Yes |

## Task Sequence

### T0. Plan Review And Scope Lock

Purpose: validate this plan before code.

Actions:

- Run `shravan-dev-workflow:plan-review-swarm` against this plan and both specs.
- Keep phase-1 expansion methods (`workspace.select`, `pane.split`, `pane.close`,
  `terminal.interrupt`) out unless review identifies a complete owner chain.
- Decide CLI packaging before code: add a Swift executable target or defer the
  installable CLI while still shipping test/support client code.

Exit proof:

- Accepted review findings are applied to the plan.
- Open questions below are either answered or explicitly moved to implementation
  gates.

### T1. Generic Unix JSON-RPC Transport

Write surfaces:

- `Sources/AgentStudio/Infrastructure/IPC/`
- `Tests/AgentStudioTests/Infrastructure/IPC/`

Implement:

- `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError`, and `JSONRPCIdentifier`.
- Strict JSON-RPC 2.0 codec with app error-code range support.
- NDJSON frame reader/writer with max frame size and invalid UTF-8 handling.
- Unix socket listener/client primitives with injectable clock and test socket
  endpoint.
- Peer credential abstraction for Darwin same-uid checks.
- No product method registry in this layer.

Proof:

- Unit tests for valid/invalid JSON-RPC, batch rejection, params-object rule,
  response `result` xor `error`, request-size bounds, and chunked NDJSON frames.
- Integration tests for connect/send/read/close against a temp Unix socket.
- Lint/boundary check proves no product imports.

### T2. IPC Service Paths, Metadata, And Filesystem Trust

Write surfaces:

- `Sources/AgentStudio/App/IPC/`
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
- Metadata serialization test proves no token in `agentStudioOnly`.

### T3. Auth, Access Modes, Runtime Token Custody

Write surfaces:

- `Sources/AgentStudio/Core/ProgrammaticControl/`
- `Sources/AgentStudio/App/IPC/`
- Terminal spawn environment construction seam where Agent Studio launches
  spawned sessions, if required by current launch code.
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- `IPCAccessMode`: `off`, `agentStudioOnly`, `automationSameUser`,
  reserved `password`, `unsafeDebug`.
- Runtime token generation, rotation, per-connection authenticated state, and
  pre-auth method allowlist.
- `auth.login` and `auth.status`.
- Peer credential gate before token validation.
- Token/socket/runtime-id injection for Agent Studio-spawned terminal sessions.
- Audit logging that records method, target, privilege class, and correlation id
  without token or sensitive payload values.

Proof:

- Auth unit tests for unauthenticated rejection, invalid token, repeated failure
  close/reject, token rotation, and pre-auth `system.ping` with no metadata.
- Env injection tests prove the spawned session receives
  `AGENTSTUDIO_IPC_SOCKET`, `AGENTSTUDIO_IPC_TOKEN`, and
  `AGENTSTUDIO_IPC_RUNTIME_ID`.
- Metadata tests prove the runtime token is not persisted in `agentStudioOnly`.

### T4. Programmatic Control Contracts, Registry, Handles, Capabilities

Write surfaces:

- `Sources/AgentStudio/Core/ProgrammaticControl/`
- `Tests/AgentStudioTests/Core/ProgrammaticControl/`

Implement:

- Phase-1 method definitions and schemas:
  `system.*`, `auth.*`, `window.*`, `workspace.*`, `pane.*`,
  `terminal.*`, `events.*`.
- Privilege classes and execution-owner metadata.
- Result semantics metadata (`applied` default, `accepted` only when justified).
- Handle model: canonical UUIDs plus runtime-local friendly refs for
  `window:*`, `workspace:*`, `tab:*`, `pane:*`.
- Registry capability export for future MCP mapping without implementing MCP.
- Namespace denylist for deferred groups, especially `zmx.*`.

Proof:

- Registry completeness test: every method has params schema, result schema,
  privilege class, execution owner, and result semantics.
- Deferred namespace test: no `zmx.*`, `mcp.*`, `browser.*`, `webview.*`,
  `bridge.*`, or phase-1 expansion methods unless explicitly promoted.
- Handle tests for UUID canonicalization, friendly ref resolution, no reuse
  during a runtime, and error mapping for missing targets.

### T5. App Query And Snapshot Adapters

Write surfaces:

- `Sources/AgentStudio/App/IPC/`
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

- `Sources/AgentStudio/App/IPC/`
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

- `Sources/AgentStudio/App/IPC/`
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

### T8. Events And Terminal Waits

Write surfaces:

- `Sources/AgentStudio/Core/ProgrammaticControl/`
- `Sources/AgentStudio/App/IPC/`
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- Public exported event names and payload DTOs.
- `events.subscribe` / `events.unsubscribe` over authenticated connection state.
- JSON-RPC `events.notification` notifications.
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
- Slow subscriber/backpressure tests.
- Wait tests with fake runtime events and injected clocks.
- Rejection tests for arbitrary internal event names/predicates.

Split/replan trigger:

- If a wait condition cannot map to an exported stable fact, remove it from
  phase 1 rather than exposing raw internal runtime predicates.

### T9. CLI Client And Smoke Harness

Write surfaces:

- Package-level CLI target if approved, or a temporary-but-committed support
  client under a repo-owned test/support location until packaging is decided.
- `Tests/AgentStudioTests/App/IPC/` or CLI-specific test target if added.
- README/guide snippets only after behavior exists.

Implement:

- Socket discovery from explicit flag, `AGENTSTUDIO_IPC_SOCKET`, and metadata.
- Auth from `AGENTSTUDIO_IPC_TOKEN` or explicit token input.
- Commands for identify/capabilities/list/current/pane focus/terminal send/wait.
- Machine-readable output by default; optional human output can follow later.

Proof:

- CLI unit tests for discovery and request serialization.
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
  event/wait public contract, and app/runtime routing rules.
- Mark the spec as implementation history after code lands.
- Keep zmx backend IPC doc separate and still future-facing until implemented.

Proof:

- `rg` confirms architecture docs point to implemented files.
- `rg` confirms no durable docs describe public `zmx.*` app methods.
- `mise run lint` includes markdown/boundary checks as repo tooling defines.

## Write Surface Summary

Expected new areas:

- `Sources/AgentStudio/Infrastructure/IPC/`
- `Sources/AgentStudio/Core/ProgrammaticControl/`
- `Sources/AgentStudio/App/IPC/`
- `Tests/AgentStudioTests/Infrastructure/IPC/`
- `Tests/AgentStudioTests/Core/ProgrammaticControl/`
- `Tests/AgentStudioTests/App/IPC/`

Expected existing areas touched narrowly:

- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift` for optional
  `ipcDirectory()` / `ipcRuntimeMetadataURL()` helpers.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift` or an extension for service
  lifecycle wiring.
- Existing terminal session environment construction path for IPC env injection.
- `Package.swift` only if the CLI ships as a Swift executable target in phase 1.

No expected changes:

- zmx daemon protocol or vendored zmx sources.
- Public Bridge/Webview method surfaces.
- Atom write-owner boundaries.
- EventBus command routing semantics.

## Validation Gates

Required during implementation slices:

1. `git diff --check`
2. Focused unit tests for each slice:
   - IPC codec/framer/listener
   - filesystem trust/auth
   - method registry/handles/schemas
   - app query adapters
   - pane focus seam
   - terminal adapter
   - events/waits
   - CLI discovery/client
3. Existing relevant suites:
   - `Tests/AgentStudioTests/Infrastructure/AppDataPathsTests.swift`
   - `Tests/AgentStudioTests/App/ActionExecutorTests*.swift`
   - `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift`
   - `Tests/AgentStudioTests/Core/PaneRuntime/Replay/EventReplayBufferTests.swift`
   - `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
   - `Tests/AgentStudioTests/Features/Bridge/RPCRouterTests.swift` only as
     prior-art regression for JSON-RPC behavior, not as app IPC proof.
4. `mise run lint`
5. `mise run test`
6. Smoke gate:
   - local IPC smoke against an isolated test listener;
   - app-level smoke only in a separate debug/beta instance if the running user
     app must not be disturbed.

Known current tooling note from this planning pass:

- `mise run lint` reached swift-format, swiftlint, and boundary checks
  successfully, then hung inside `scripts/verify-release-scripts.sh` while
  rendering the Homebrew cask. Treat that as a repo tooling blocker to report
  separately if it reproduces during implementation; do not edit release tooling
  as part of IPC unless explicitly scoped.

## Rollout And Recovery

- Default target mode is `agentStudioOnly` with memory-only runtime token.
- `off` mode must exist for recovery and testing.
- `automationSameUser` remains opt-in and must be honestly documented as
  same-user local automation if token bootstrap material is discoverable.
- Startup must not steal a live socket from a different same-channel process.
- Stale dead sockets can be unlinked after probe.
- Listener shutdown removes runtime metadata and closes connections.
- Event subscriptions are non-durable; clients recover by refreshing snapshots.

## Risks

- Peer PID ancestry is weaker and more platform-specific than token custody.
  Keep same-uid plus memory-only token as the actual phase-1 enforcement model.
- `pane.focus` may require a new app-control seam because current focus behavior
  is partly controller/private. Do not bypass this with direct atom writes.
- Terminal snapshots can leak secrets through titles, cwd, progress, search
  query/state, or future fields. Treat the DTO as an allowlist, not a mirror.
- Event subscriptions can become an accidental raw runtime-envelope API. Keep
  public event DTOs separate.
- CLI packaging may force package/product changes; decide before coding.
- Full `mise run lint` currently has a release-script hang unrelated to the docs
  change. Implementation must distinguish changed-surface proof from unrelated
  tooling blockers.

## Open Questions

1. Should the first committed CLI be a Swift executable target in `Package.swift`,
   or should phase 1 ship the app service plus a test/support client first?
2. Is `system.ping` pre-auth allowed with a content-free response, or should
   `auth.login` be the only pre-auth method?
3. Which exact `terminal.wait` conditions earn phase-1 support after mapping to
   current runtime facts?
4. What is the minimum useful `terminal.snapshot` DTO for the first consumer?
5. Is `automationSameUser` included in phase 1, or kept as a follow-up after
   `agentStudioOnly` works for spawned agents?

## Next Skill

Use `shravan-dev-workflow:plan-review-swarm` before implementation. After review
findings are resolved, use `shravan-dev-workflow:implementation-execute-plan`.
