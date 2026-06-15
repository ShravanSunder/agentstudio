# AgentStudio IPC Debug Auth And Pane-Agent Bootstrap Plan

Date: 2026-06-15
Status: Milestone A implemented and live-tested for title-change readback;
Milestone B fd bootstrap/helper implemented at the launch-owner seam; machine-
checked debug smoke implemented with render/runtime readiness proof. Real
pane-close/child-exit lifecycle wiring remains open.
Branch: `programatical-control`

## Current Checkpoint: 2026-06-15

Implemented and covered by focused tests:

- Debug unsafe no-auth, gated to debug runtime channel composition.
- Debug token escrow, gated to debug runtime channel composition, owner-only
  token file, real `auth.login`, and post-login token removal.
- `command.list` and `command.execute` over the four public command-spec ids:
  quick find, command palette, pane picker, and repo/worktree picker.
- CLI verbs for `auth-status`, `command-list`, `command-execute`, and
  `terminal-status`.
- Debug launcher forwarding for IPC debug env vars.
- Owner-only debug data/zmx/socket roots and a short trusted socket directory to
  avoid Darwin Unix-domain socket path limits.
- DEBUG-only `ipc-terminal-smoke` startup diagnostic that opens a real floating
  terminal through `PaneCoordinator.openFloatingTerminal(...)` and restores
  views so a runtime becomes IPC-addressable.

Live debug app proof captured under
marker `debug-observability-wpzc-1781540889-8300`:

- unsafe no-auth can call `auth.status`, `system.identify`,
  and `pane.list`;
- debug token escrow can authenticate through `auth.login` and then call
  authenticated methods; the debug token file is mode `0600` before login and
  removed after login;
- `ipc-terminal-smoke` creates ready terminal panes visible through
  `terminal.status`;
- `terminal.send` accepts input against a ready runtime;
- `terminal.wait(titleChanged, afterSequence:)` observes the resulting runtime
  event after accepted input;
- `terminal.wait(afterSequence:)` uses runtime-owned replay plus live
  subscription, treats `afterSequence` as a strict floor, and fails fast on
  replay gaps so callers refresh snapshots;
- `mise run verify-debug-observability` now requires `ipc-terminal-smoke`
  startup diagnostic telemetry and fails if the smoke pane count is absent,
  not exactly one, or lacks terminal view/surface/valid-geometry render proof.

Open gates before this plan can be called complete:

- `terminal.wait(commandFinished)`, cwd/readback, and prompt-readiness proof
  remain open runtime-fact work.
- The production-shaped pane-agent fd spawn adapter is implemented:
  `PaneAgentLaunchOwner` remaps exactly one bootstrap fd into
  `agentstudio-pane-agent`, and the helper authenticates against a local IPC
  server through the fd path.
- Bound-principal invalidation closes authenticated socket sessions in focused
  server tests. Real pane-close/child-exit lifecycle wiring and live
  stale-principal smoke remain open.
- OTLP debug proof exports `agentstudio.startup_diagnostic.created_pane.count`
  plus render-proof counts for machine checking, while raw pane UUIDs remain
  scrubbed.

## Goal

Make AgentStudio IPC useful enough to live-control a debug app while preserving
the production authority model for pane agents.

The slice ships four connected outcomes:

1. Debug unsafe no-auth for explicit local live-control proof.
2. Debug token escrow for exercising the real `auth.login` path from an
   external client.
3. Production-shaped app-spawned pane-agent bootstrap with secure fd remapping.
4. A narrow command-spec control surface that proves `AppCommand` /
   `CommandSpec` / `CommandDispatcher` are controllable through IPC without
   creating a parallel command system.

## Source Coverage

Read in full:

- `tmp/spec-workflows/2026-06-15-agentstudio-ipc-debug-auth-pane-agent-bootstrap/design-addendum.md`: 627 lines.
- `docs/architecture/agentstudio_ipc_architecture.md`: current phase-1
  architecture and already-landed foundation.
- `docs/superpowers/plans/2026-06-13-agentstudio-ipc-implementation-plan.md`:
  current phase-1 plan record; this new plan is a focused follow-up, not a
  replacement.

Spec review lanes run:

- `contract-and-architecture-readiness`: accepted findings on command grant
  scoping, command postconditions, and command bridge ownership.
- `security-and-validation-readiness`: accepted findings on non-debug exclusion
  proof, hard pane-close revocation, and live negative revocation proof.
- `architecture lint/boundary analyst`: confirmed command adapter belongs in
  `App/IPCComposition`, process launch belongs in `App/PaneAgents`, and helper
  executable must model the existing CLI target split.

Plan review lanes run:

- `spec-compliance`: accepted findings on token metadata secrecy, spawned pane
  agent command denial, optional command target handles, pane lifecycle
  ownership, and non-debug smoke concreteness.
- `architecture-assumptions`: accepted findings on helper embedding/lookup,
  public IPC command identifiers, and explicit command-bar postcondition seam.
- `testability-validation`: accepted findings on required launcher env
  forwarding, repo-accurate validation commands, named red tests, and
  machine-checked smoke artifacts.
- `security-reliability-and-execution-scope`: accepted findings on
  per-principal connection/task cancellation, narrow bootstrap token revocation,
  command authorization scope, debug-token file removal after login, and
  milestone slicing.
- `Claude Code opus`: accepted findings on server-side runtime-channel debug
  gating, `.debugUnsafe` command privilege handling, explicit method-name
  unsafe allowlists, pane-close revocation wiring, fd spawn hardening, injected
  clocks, and slice boundaries.

Live repo evidence checked:

- `Package.swift` already has `AgentStudioIPCTransport`,
  `AgentStudioProgrammaticControl`, `AgentStudioAppIPC`,
  `AgentStudioIPCClientCore`, and `AgentStudioIPCClient` targets.
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift` already
  owns phase-one method registry, authorization, `GrantLedger`, and
  self-pane baseline privileges.
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift` already owns
  JSON-RPC request dispatch, auth/login/status, pre-auth gates, peer credential
  gate, active connections, and app/runtime port calls.
- `Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift` already owns
  subject tokens, principal registry, token replay prevention, and pane
  bootstrap descriptor/fd primitive.
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift` currently hard-codes
  `.agentStudioOnly` and composes query/layout/runtime/approval ports.
- `Sources/AgentStudio/App/IPCComposition/` already holds concrete query,
  layout, and terminal runtime adapters.
- `Sources/AgentStudio/App/Commands/AppCommand.swift` and
  `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift` already provide
  `AppCommand`, `CommandSpec`, and `CommandDispatcher`.
- Architecture lint is already wired through the repo-local SwiftPM/SwiftSyntax
  tool under `Tools/AgentStudioArchitectureLint`, `mise run lint`,
  `swift test --package-path Tools/AgentStudioArchitectureLint`, and
  `docs/architecture/architecture_lint_inventory.md`.

## Non-Goals

- No MCP transport in this slice.
- No password auth in this slice.
- No production same-user token file.
- No public `zmx.*` methods or zmx daemon IPC exposure.
- No arbitrary app command execution.
- No arbitrary in-terminal process authority claim.
- No command grants through `IPCPermissionScope`; command-specific grants need a
  future selector dimension in the permission contract.
- No debug approval authority.

## Architecture Shape

```text
debug client / CLI
  -> unsafe no-auth principal OR debug token escrow auth.login
  -> AgentStudioAppIPC JSON-RPC server
  -> method registry + authorization
  -> query/layout/runtime/command ports
  -> App/IPCComposition adapters
  -> existing app/runtime owners

app-spawned pane agent
  -> App/PaneAgents launch owner
  -> AgentStudioAppIPCServer.makePaneBootstrap(...)
  -> remap exactly one token fd into child
  -> agentstudio-pane-agent reads fd once
  -> child calls auth.login
  -> spawnedPaneAgent principal
  -> same method registry + authorization path
```

Boundary rules:

- `AgentStudioProgrammaticControl` owns public DTOs only.
- `AgentStudioAppIPC` owns auth, method routing, authorization, command port
  protocol, registry, and server mechanics.
- `App/IPCComposition` owns concrete adapters to app types.
- `App/PaneAgents` owns child process launch, fd remap, lifecycle, cleanup, and
  diagnostics.
- `agentstudio-pane-agent` imports `AgentStudioIPCClientCore`,
  `AgentStudioIPCTransport`, and `AgentStudioProgrammaticControl` only.

Debug authority gate:

```text
debug env vars
  -> App/Boot may parse under #if DEBUG
  -> AgentStudioAppIPC server still honors them only when channel == .debug
  -> beta/stable server instances refuse unsafe principals and escrow tokens
```

`#if DEBUG` is defense in depth. The authoritative, testable gate lives at the
server/configuration boundary so tests can construct `.beta` and `.stable`
servers inside the test build.

Implementation is sliced into useful gates:

```text
Milestone A
  T1 + T2 + T3 + debug launcher support + machine-checked unsafe/escrow smoke
  -> proves live debug app control, auth.login escrow, command-spec control

Milestone B
  T4 + T5 + T6 + pane-agent/revocation smoke
  -> proves production-shaped pane-agent fd bootstrap and stale authority teardown

Milestone C
  T8 docs maintenance
  -> promotes implemented architecture and removes stale future-only language
```

This session should pursue the milestones in order and stop only at a real
blocker or after the relevant proof gates pass. Milestone A is the first useful
gate; Milestone B is required before claiming the pane-agent product path is
done.

## Requirements And Proof Matrix

| Requirement | Task | Proof gate | Layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| Debug no-auth is honored only when server channel is `.debug` and creates an explicit `.unsafeDebugClient` principal | T1 | `AgentStudioAppIPCTests` for env/channel matrix | Unit/integration | beta/stable server with env vars set still reports unauthenticated/no unsafe principal | Yes |
| Unsafe no-auth is default-deny outside the exact method and command allowlists | T1/T3 | authorization tests for allowed and denied methods | Unit | test includes an existing non-allowlisted method with reused privilege and a fake future method | Yes |
| Debug token escrow writes one-shot token to owner-only `<data-root>/ipc/debug-token` and exercises real `auth.login` | T2 | path/mode/symlink/token replay tests plus socket auth test | Unit/integration | token sentinel absent from metadata/env/log DTOs/proof artifacts and file is removed/rotated after successful login | Yes |
| Beta/release ignore both debug env vars | T1/T2/T7 | server-channel exclusion test plus non-debug smoke/config proof | Integration/smoke | env vars set while asserting no token file, no unsafe auth.status, no debug-only capabilities | Yes |
| `command.list` and `command.execute` are narrow phase-1 IPC methods backed by `CommandDispatcher` only | T3 | command DTO/adapter/registry tests | Unit/integration | command list returns only four public IPC command ids and denies spawned pane agents | Yes |
| `command.execute(commandPalette)` rejects without real window preconditions and proves `CommandBarSurfaceAtom.activeSurface` postcondition | T3 | adapter tests plus live smoke | Integration/smoke | result includes verifier-visible workspace window id and scope ordered after dispatch | Yes |
| Command execution is not grantable via `IPCPermissionScope` in phase 1 | T3 | permission/authorization negative tests | Unit | `permission.request` for command execution fails closed | Yes |
| Pane-agent fd bootstrap remaps exactly one inheritable fd and rewrites child env to the post-remap fd number | T4 | `PaneAgentLaunchOwnerTests` | Integration | spawn request uses `POSIX_SPAWN_CLOEXEC_DEFAULT` and one explicit fd action | Yes |
| `agentstudio-pane-agent` reads fd once, closes it, calls `auth.login`, then identifies as `.spawnedPaneAgent` | T5 | `PaneAgentLaunchOwnerTests` plus `AgentStudioIPCBootstrapTokenReaderTests` | Integration | helper subprocess authenticates against a local IPC server through fd bootstrap | Yes |
| Unused pane-agent tokens are canceled on spawn failure, exec failure, auth timeout, and server stop | T4/T5 | launch-owner spawn-failure cancellation test plus server stop tests | Integration | auth-timeout and child-exit cancellation still open | Partial |
| Pane close synchronously revokes active principals by closing connections and canceling waits/streams | T6 | server/principal registry tests | Integration/smoke | bound-principal sockets close; in-flight wait cancellation and live replacement-pane smoke still open | Partial |
| Debug app can be live-controlled through both debug auth surfaces | T7 | `run-debug-observability` plus machine-checked IPC smoke verifier | Smoke | proof records PID, runtime id, socket path, debug root, correlation id and raw responses with tokens redacted | Yes |
| Terminal command proof observes runtime effect, not just non-unauthenticated response | T7 | `terminal.send` + `terminal.wait(commandFinished)` or exported runtime fact | Smoke/manual | unique correlation id per run | Yes |
| Docs are promoted after implementation | T8 | architecture docs and lint inventory updated | Docs/lint | docs use implemented paths and remove stale open decisions | No |

## Task Sequence

### T0. Plan Review

Use `shravan-dev-workflow:plan-review-swarm` before code.

Review focus:

- Does the task split keep AppIPC out of app-owned concrete types?
- Is phase-1 command control scoped enough?
- Are debug auth gates enough to prove live usefulness without leaking into
  beta/release?
- Is pane-agent revocation proof strong enough?
- Are proof gates sized so implementation can complete in this session?

Exit:

- Accepted findings are patched into this plan.

### T1. Debug Access Mode Configuration And Unsafe No-Auth

Write surfaces:

- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `Tests/AgentStudioAppIPCTests/`
- `Tests/AgentStudioTests/App/ApplicationEntrypointArchitectureTests.swift`

Implement:

- `#if DEBUG` boot parsing for `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1`.
- Debug-only server configuration that can synthesize
  `.unsafeDebugClient` per connection after same-UID and filesystem trust pass.
- Server-side runtime-channel gate: unsafe no-auth is honored only when
  `AgentStudioAppIPCServer.channel == .debug`. `.beta` and `.stable` server
  instances must ignore the env var even inside test/debug builds.
- `auth.status` returns authenticated unsafe debug status in unsafe mode.
- Unsafe debug authorization allowlist for:
  `system.ping`, `auth.status`, `system.identify`, `system.version`,
  `system.capabilities`, window/workspace/pane query methods, `pane.focus`,
  `pane.snapshot`, terminal status/snapshot/send/wait. T3 appends
  `command.list` and the allowlisted command execution methods.
- Deny permission methods, event methods, and every future method by default.
- Enforce unsafe/escrow authority through an explicit method-name allowlist
  keyed by `accessMode == .unsafeDebug`, not through broad privilege grants.

Proof:

- Red test: `terminal.send` without auth fails when unsafe no-auth is absent.
- Green test: same request succeeds only with debug unsafe mode enabled.
- Red test: `.beta` and `.stable` servers with the env var set still reject
  unauthenticated non-preauth methods.
- Non-debug exclusion test proves env var ignored outside `.debug` channel.
- `auth.status` exact principal/result tests.

### T2. Debug Token Escrow

Write surfaces:

- `Sources/AgentStudioAppIPC/AgentStudioIPCPaths.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `Tests/AgentStudioAppIPCTests/`

Implement:

- `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1` parsed only in debug channel/build.
- Server-side runtime-channel gate: escrow is honored only when
  `AgentStudioAppIPCServer.channel == .debug`.
- Owner-only token file path `<data-root>/ipc/debug-token`.
- Atomic token write, `0600` mode, symlink refusal, owner/mode checks using the
  existing `AgentStudioIPCFilesystem` trust helpers where possible.
- Escrow principal:
  `.unsafeDebug`, `.automationClient`, `.noApprovalAuthority`.
- Cleanup on server stop, token rotation, debug shutdown, and immediately after
  successful `auth.login` consumes the escrow token.
- Token replay failure after first `auth.login`.
- Debug token must never appear in runtime metadata, state files, launcher logs,
  smoke proof artifacts, env, argv, or public DTOs. Client/smoke auth must use
  stdin/file-read paths that never echo the token.

Proof:

- Red test: replayed debug-token login succeeds before token consumption and
  cleanup are implemented.
- Path/mode/symlink tests.
- Same-socket escrow `auth.login` + `auth.status` exact principal test.
- Token sentinel absent from metadata, env, public auth status, launcher logs,
  and smoke proof artifacts.
- Second read after successful login does not yield a reusable token.
- Beta/release config with env var set creates no debug-token file.

### T3. Command-Spec IPC Control Surface

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/` for command DTOs.
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift` for
  `AppIPCCommandPort`.
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `Tests/AgentStudioProgrammaticControlTests/`
- `Tests/AgentStudioAppIPCTests/`
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- DTOs for command list entries and command execution results.
- Define a dedicated public IPC command identifier value set in
  `AgentStudioProgrammaticControl` instead of exposing raw `AppCommand` names:
  `quickFind`, `commandPalette`, `panePicker`, `repoWorktreePicker`.
- `command.list` returns only:
  `quickFind`, `commandPalette`, `panePicker`, `repoWorktreePicker`.
- `command.execute` accepts only those public IPC command identifiers plus an
  optional target handle.
- AppIPC owns `AppIPCCommandPort`; app adapter translates to
  `CommandDispatcher` / `AppCommand` / `CommandSpec`.
- Reject if the command owner lacks a usable active window/workspace window.
- Resolve optional target handles and prove the returned `workspaceWindowId`
  matches the requested target in multi-window tests.
- Result includes postcondition fact: active command-bar `workspaceWindowId` and
  scope when presentation succeeds.
- Postcondition reader/observer is a planned app-owned seam, not a fallback:
  add the necessary app-side reader in `App/IPCComposition` so the adapter can
  read `CommandBarSurfaceAtom.activeSurface` after dispatch without direct atom
  access from `AgentStudioAppIPC`.
- The dispatch/read must be ordered without wall-clock sleeps. Either dispatch
  completes the command-bar surface mutation synchronously on MainActor before
  returning, or the adapter awaits an explicit state transition.
- Use `.debugUnsafe` as the command method privilege. `AuthorizationService`
  must satisfy command methods only through the explicit `.unsafeDebug`
  method-name allowlist; baseline and `GrantLedger` grants do not authorize
  command execution.
- `permission.request` for `.debugUnsafe` or command execution fails closed.
- `command.list` and `command.execute` are allowed only for unsafe-debug
  principals (`.unsafeDebugClient` and debug-escrow `.automationClient`) and are
  denied for `.spawnedPaneAgent` in phase 1.

Proof:

- `CommandSpecContractTests` still pass.
- Red test: `command.execute(commandPalette)` succeeds with no usable window.
- Red test: `.spawnedPaneAgent` can call `command.execute` with self-pane
  baseline grants.
- Red test: a `permission.request` for command execution succeeds.
- DTO and registry tests.
- Adapter tests for list allowlist, invalid raw value, hidden/not allowlisted
  command rejection, no-window rejection, explicit target handle resolution, and
  `commandPalette` postcondition.
- Permission test proves command execution cannot be requested/granted through
  `IPCPermissionScope`.
- Authorization test proves an existing non-allowlisted method with an
  allowlisted privilege is still denied to unsafe-debug principals.

### T4. Pane-Agent Launch Owner And FD Remap

Write surfaces:

- `Sources/AgentStudio/App/PaneAgents/`
- `Sources/AgentStudio/App/IPCComposition/` for any thin bootstrap adapter.
- `Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift` if token
  cancellation hooks are missing.
- `Tests/AgentStudioTests/App/PaneAgents/`
- `Tests/AgentStudioAppIPCTests/`

Implement:

- `PaneAgentLaunchOwner` under `App/PaneAgents`.
- Request bootstrap descriptor from `AgentStudioAppIPCServer`.
- Add a named bootstrap cancellation API to the registry/server, such as
  `cancelBootstrap` / `revokeSubjectToken`, keyed by bootstrap record or token.
- State ownership: `PaneAgentLaunchOwner` owns the spawn/auth deadline and
  cancels that deadline when the helper authenticates successfully.
- Duplicate descriptor read fd into a child fd.
- Rewrite `AGENTSTUDIO_IPC_BOOTSTRAP_FD` to the child fd number.
- Keep original parent read fd `FD_CLOEXEC`; clear close-on-exec only on the
  child fd.
- Use `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT` and a single explicit
  `posix_spawn_file_actions_adddup2` action for the bootstrap fd so unrelated
  non-CLOEXEC fds do not leak to the helper.
- Close parent descriptors on all success/failure paths.
- Auth timeout default: 10 seconds from successful child launch unless an
  existing policy constant is found.
- Inject `any Clock<Duration>` into the launch owner for auth deadlines; no
  wall-clock sleeps in tests.
- Token cancellation on spawn/exec/auth timeout.
- Bind child lifetime to the pane lifecycle and add explicit child-exit cleanup
  diagnostics. Name the concrete pane close/teardown seam during implementation
  before wiring revocation.

Proof:

- Red test: sibling subprocess can still read inherited bootstrap fd.
- Red test: auth timeout requires a real 10-second sleep.
- FD remap tests prove exactly one inheritable fd.
- Failure-path tests for spawn failure, exec failure, timeout, and cleanup.
- Captured token fails `auth.login` after spawn failure or auth timeout.
- Successful auth cancels the timeout task.
- Unrelated subprocess inheritance probe cannot read token fd.

### T5. `agentstudio-pane-agent` Helper

Write surfaces:

- `Package.swift`
- `Sources/AgentStudioPaneAgent/`
- `Sources/AgentStudioIPCClientCore/` for reusable bootstrap-fd client helpers.
- `Tests/AgentStudioIPCClientTests/`

Implement:

- New executable product `agentstudio-pane-agent`.
- Add explicit helper embedding and lookup:
  - debug: locate the helper from the current SwiftPM build products or copied
    debug app bundle path used by `scripts/run-debug-observability.sh`;
  - beta/stable packaging: embed the helper in the app bundle's executable
    helper location before production use;
  - smoke must prove it launched the bundled/debug-resolved helper path, not an
    ad hoc raw `.build` binary unless the debug resolver explicitly points
    there.
- Helper reads `AGENTSTUDIO_IPC_BOOTSTRAP_FD` once, trims token, closes fd, and
  calls `auth.login` over `AGENTSTUDIO_IPC_SOCKET`.
- Helper exits non-zero on missing fd, empty token, auth failure, or runtime id
  mismatch.
- Helper can call `system.identify` after auth for proof.
- Helper imports client core/transport/contracts only.

Proof:

- Red test: app launch owner has no deterministic helper path outside raw build
  products.
- Client-core tests for fd token read/close behavior.
- Helper subprocess integration test against a temp test IPC server.
- SwiftPM target graph test proves no `AgentStudio` or `AgentStudioAppIPC`
  dependency.

### T6. Principal Revocation And Connection Teardown

Write surfaces:

- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCEventBroker.swift`
- The concrete app pane teardown integration point selected during T6. The
  expected owner is the pane close/teardown path in `PaneCoordinator`, but T6
  must verify the exact symbol before wiring revocation.
- `Tests/AgentStudioAppIPCTests/`
- `Tests/AgentStudioTests/App/IPC/`

Implement:

- Registry exposes active-principal invalidation events or a server method that
  returns invalidated principal ids.
- Server maintains a per-principal connection registry and per-connection
  request task handles so invalidation can cancel in-flight waits/streams, not
  merely close the socket before the next receive.
- Pane invalidation closes authenticated connections for that principal and
  cancels outstanding request tasks/subscriptions for the connection.
- If a response can race with invalidation, revalidate principal active state
  before reply delivery.
- Name and wire the concrete app pane teardown owner before implementation. The
  initial expected owner is the pane close/teardown path in `PaneCoordinator`;
  implementation must decide and document revocation timing relative to the
  undo window instead of attaching to a non-authoritative close path.
- Revocation negative proof targets `.spawnedPaneAgent` only. Unsafe no-auth
  and debug-escrow principals are debug-global and intentionally not revoked by
  closing an individual pane.
- Child exit and runtime rotation revoke the pane-agent principal and produce
  app-owned diagnostics.

Proof:

- Red test: authenticated `terminal.wait` survives pane invalidation until
  timeout.
- Integration test authenticates, starts a wait/stream, invalidates pane, and
  observes request cancellation and connection close before later pane events
  are published.
- Event broker/subscription state drops back to baseline on invalidation.
- Pane close and child exit both revoke authority and produce expected cleanup
  diagnostics.
- Replacement pane with same friendly ordinal cannot be controlled by stale
  `.spawnedPaneAgent` connection.

### T7. Debug App Live-Control Smoke

Write surfaces:

- `scripts/run-debug-observability.sh` for required debug IPC env forwarding.
- New machine-checked IPC smoke script and verifier under `scripts/`.
- `Tests/AgentStudioTests/Scripts/` for script contract tests if adding script.

Implement:

- Launch through:
  `mise run observability:up`
  `mise run run-debug-observability -- --detach`
- Pass `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH` and
  `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW` through the canonical debug launcher in a
  controlled way. Add script contract tests proving both LaunchServices
  `open --env` and direct-executable fallback receive the vars.
- Discover socket/runtime id from runtime metadata. Derive/read the escrow token
  only from `<data-root>/ipc/debug-token`; metadata must not contain the token
  or token path.
- Define a machine-checked smoke artifact schema and verifier. The artifact must
  capture exact JSON-RPC request/response pairs with bearer token fields
  redacted, runtime id, PID, socket path, command correlation id, command-bar
  `workspaceWindowId` and scope, and post-pane-close denial for stale
  pane-agent principals.
- T7 uses the real `agentstudio-ipc` client when possible. Extend
  `AgentStudioIPCClientCore` / CLI for `auth.status`, `command.list`, and
  `command.execute`. If a lower-level raw JSON-RPC harness is still needed for
  one assertion, document that as harness-only and do not substitute it for CLI
  proof.
- Exercise unsafe no-auth:
  `system.identify`, `system.capabilities`, `workspace.list`, `pane.list`,
  `command.list`, `command.execute(commandPalette)`,
  `terminal.send`, `terminal.wait`.
- Exercise escrow:
  read debug token, `auth.login`, same query/control calls.
- Exercise pane-agent child auth through production launch owner.
- Exercise negative pane-close revocation live.
- Run a non-debug exclusion smoke/config proof with both debug env vars set:
  beta/stable server or artifact must produce no unsafe principal, no
  debug-token file, and no debug-only capabilities.

Proof:

- Red test: canonical debug launcher drops the new IPC env vars.
- Red test: smoke artifact/verifier passes while omitting exact auth status,
  command-bar postcondition, terminal wait result, or stale-principal denial.
- Smoke output is saved under `tmp/debug-workflows/.../proofs/` and verified by
  the new verifier.
- Manual proof verifies visible terminal input and visible command-bar action in
  debug app; manual proof supplements but does not replace the machine verifier.
- `rg` or verifier checks prove the token sentinel is absent from runtime
  metadata, launcher logs, state files, and proof artifacts.
- `mise run verify-debug-observability` still passes.

### T8. Docs Maintenance

Write surfaces:

- `docs/architecture/agentstudio_ipc_architecture.md`
- `docs/architecture/directory_structure.md`
- `docs/architecture/architecture_lint_inventory.md` if lint rules or fixture
  expectations changed.
- Existing spec/plan docs only as history/handoff pointers.

Implement:

- Promote implemented debug auth, command control, pane-agent helper, and
  revocation model into architecture docs.
- Document `App/PaneAgents` as app-owned launch/lifecycle surface.
- Document command surface as phase-1 debug allowlist, non-grantable.
- Remove or update stale “remaining pane process-spawn fd handoff” language once
  implemented.

Proof:

- `rg` confirms docs point to real implemented files and do not describe the
  implemented slice as future-only.
- `mise run lint` includes architecture lint and release script checks.

## Validation Commands

Prerequisite: run `mise trust` if this checkout is not yet trusted locally. This
is setup, not validation.

Run in order as each layer becomes available. Use the repo harness rather than
raw `swift test` for focused proof:

```bash
mise run test-fast -- --filter 'IPCContractsTests|AgentStudioAppIPC(Service|Authentication|RegistryAuthorization|PathResolver)Tests'
mise run test-fast -- --filter 'AgentStudioIPCClientCoreTests'
mise run test-fast -- --filter 'AgentStudioIPC(Layout|Query|Runtime|Command)AdapterTests|ApplicationEntrypointArchitectureTests|CommandSpecContractTests'
mise run test-fast -- --filter 'ObservabilityDebugLaunchScriptsTests'
mise run test-fast -- --filter 'PaneAgent|AgentStudioPaneAgent|IPC.*Revocation'
mise run format
mise run lint
mise run test
mise run observability:up
mise run run-debug-observability -- --detach
scripts/verify-agentstudio-ipc-debug-smoke.sh <proof-artifact>
mise run verify-debug-observability
```

Manual/live proof requires controlling the launched debug app through IPC and
recording the exact commands and responses. A lower unit/integration pass does
not satisfy the smoke/manual layer.

## Risks And Replan Triggers

- If command execution requires a permission selector dimension, stop and
  replan; do not invent ad hoc grants.
- If command-bar postcondition cannot be observed by an app-owned
  `App/IPCComposition` seam ordered after dispatch, stop and redesign that seam;
  do not import app command types into `AgentStudioAppIPC`.
- If pane-agent fd remap cannot be implemented with current subprocess APIs,
  stop and redesign the launch owner; do not fall back to env tokens.
- If non-debug exclusion proof requires packaging rather than local config,
  split the proof gate but keep a release-config integration test in this slice.
- If debug app is already running, stop the stale debug process or use the
  launcher’s existing refusal path; do not share debug roots across runs.

## Next Step

Phase 1 can build on the current IPC usefulness gate. The remaining follow-ups
are narrower runtime/lifecycle work:

1. Add product proof for `terminal.wait(commandFinished)`, cwd/readback, and
   prompt-readiness if those stay in the public phase-1 wait enum.
2. Wire real pane-close and child-exit lifecycle events into
   `invalidatePrincipals(boundToPaneId:)`, then add a live stale-principal smoke.
3. Add a separate explicit keystroke/control-key IPC method only if automation
   needs key semantics beyond `terminal.send` text input.
4. Then continue to Milestone B: app-owned pane-agent fd spawn adapter,
   helper/client auth, and revocation smoke.
