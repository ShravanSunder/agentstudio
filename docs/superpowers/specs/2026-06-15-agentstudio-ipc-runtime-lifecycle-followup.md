# AgentStudio IPC Runtime Lifecycle Follow-up

## Purpose

AgentStudio IPC phase 1 is merged and released. It provides the app-level
socket server, JSON-RPC method registry, auth primitives, debug control modes,
pane-agent fd bootstrap, query/layout/terminal adapters, event broker, and
permission DTOs. This follow-up closes the remaining usefulness gaps without
expanding the public API into zmx daemon IPC, raw WebKit transport, or broad MCP
surface area.

The goal of this slice is to make IPC reliable enough for an automation loop to
start a pane-scoped agent, prove its authority is revoked when the pane dies,
send terminal work, and observe completion/readback facts through exported app
runtime contracts.

## Progressive Overview

Start here before reading the requirements. The phase-1 work created the local
IPC foundation; this follow-up is about making that foundation trustworthy for a
real automation loop.

### One Map

```text
┌─ AgentStudio IPC Follow-up ───────────────────────────────────────┐
│                                                                  │
│  external/client automation                                      │
│      │                                                           │
│      ▼                                                           │
│  AgentStudio app IPC                                             │
│      │ owns auth, handles, method registry, events, permissions  │
│      ▼                                                           │
│  app/workspace/runtime owners                                    │
│      │ own pane lifecycle, process lifecycle, terminal facts     │
│      ▼                                                           │
│  real proof loop                                                 │
│      ├─ pane agent starts with scoped authority                  │
│      ├─ terminal work can be sent and observed                   │
│      └─ stale authority dies when pane/process dies              │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

The important boundary is not the socket. The important boundary is ownership:
IPC owns protocol and authority; the app owns lifecycle decisions; runtimes own
facts about terminal work.

### What Is Done

```text
done       app-level Unix socket JSON-RPC server
done       same-user peer checks, auth.login, debug no-auth, token escrow
done       permission scopes, grant ledger, delegated approval primitives
done       pane-agent fd bootstrap and agentstudio-pane-agent helper
done       query/layout/terminal method shells
done       pane split, close, drawer add/toggle through app owners
done       terminal status, snapshot, send, and wait plumbing
done       event broker and permission/terminal event DTO contracts
done       debug launcher forwarding for IPC auth modes
done       ipc-terminal-smoke render/runtime observability proof
```

These are release-complete. This follow-up should not redesign them unless code
evidence shows a specific defect.

### What Is Left

```text
left       pane close must revoke pane-bound principals in the real app path
left       pane-agent child exit must revoke the helper's authority
left       auth timeout diagnostics must be owned by app lifecycle code
left       terminal.wait(commandFinished) needs product proof, not just DTOs
left       cwd/prompt/readback need a safe exported-fact decision
left       live debug smoke must prove stale-principal denial after close
```

This is not a broad IPC v2. It is a closure slice for runtime lifecycle and
automation proof.

### Selected Slice: Authority Lifecycle

```text
pane agent bootstrap
  -> token is delivered over close-on-exec fd
  -> helper authenticates with auth.login
  -> principal is bound to one pane
  -> pane closes or child exits
  -> app lifecycle owner calls invalidatePrincipals(boundToPaneId:)
  -> tokens, grants, and authenticated sockets are revoked
  -> stale auth/request attempts fail closed
```

This slice proves a pane-scoped agent cannot keep authority after the pane it
belongs to has gone away.

### Selected Slice: Terminal Runtime Proof

```text
terminal.snapshot
  -> client records lastSequence
  -> terminal.send(input, correlationId)
  -> runtime accepts command path
  -> runtime emits exported RuntimeEnvelope facts
  -> terminal.wait(condition, afterSequence)
  -> client receives a bounded IPC DTO or a stable timeout/replay-gap error
```

This slice keeps the promise clean: `terminal.send` means accepted by the
runtime path; `terminal.wait` is where observable runtime effects are proven.

### Scope Fence

```text
in         pane lifecycle revocation
in         child process exit cleanup
in         commandFinished/cwd/prompt exported-fact proof
in         live debug IPC smoke and Victoria proof

out        public zmx daemon IPC
out        MCP adapter implementation
out        raw WebKit / Bridge Web transport
out        raw terminal buffer readback without a secret-bearing permission
```

## Current State

The merged phase-1 IPC foundation already owns these working surfaces:

- App-level Unix socket JSON-RPC server with same-user peer checks.
- Subject-token authentication, debug unsafe no-auth, and debug token escrow.
- Permission scopes, grant ledger, delegated approval policy primitives, and
  permission event DTOs.
- Pane-agent fd bootstrap and `agentstudio-pane-agent` helper authentication.
- Query methods for system/window/workspace/pane snapshots.
- Layout methods for `pane.focus`, `pane.split`, `pane.close`,
  `drawer.addPane`, and `drawer.toggle`.
- Terminal methods for `terminal.status`, `terminal.snapshot`,
  `terminal.send`, and `terminal.wait`.
- Event subscription infrastructure and server-originated event contracts.
- Debug observability launcher support and `ipc-terminal-smoke` startup proof.

The current architecture docs accurately name two remaining integration gaps:

1. `PaneAgentLaunchOwner` can launch/authenticate a pane agent and
   `AgentStudioAppIPCServer.invalidatePrincipals(boundToPaneId:)` can revoke
   bound principals, but real pane close and child-process exit owners do not
   yet call that lifecycle seam.
2. Live proof covers debug runtime identification, command/UI split behavior,
   layout control, drawer control, terminal status, terminal send, and
   title-change wait. It does not yet prove shell command completion, shell
   output/readback, cwd changes, or prompt readiness through exported IPC
   facts.

## Requirements

### R1. Pane-Bound Principal Revocation

When a pane-bound principal is invalidated, all authority for that pane-bound
principal must be revoked consistently:

- unconsumed subject tokens are removed;
- active authenticated principals are removed;
- grants for those principals are revoked;
- authenticated sockets for those principals are closed;
- future `auth.login` attempts with a stale bootstrap token fail;
- future requests on an already-authenticated stale socket fail because the
  socket is closed.

The revocation trigger must be owned by the app/runtime lifecycle owner that
knows the pane is gone, not by generic IPC routing code.

### R2. Pane Close Lifecycle Wiring

Closing a pane through normal app paths must invalidate any IPC principals bound
to that pane. This includes:

- pane close through IPC `pane.close`;
- pane close through user action / command action paths;
- drawer child pane close;
- parent pane close that also tears down drawer child panes.

The close owner should invalidate the closing pane and any owned drawer child
pane ids after the app has decided the pane is genuinely closing, and before a
new pane with the same durable identity could be considered active again.

### R3. Pane-Agent Child Exit Lifecycle Wiring

If AgentStudio spawns a pane-agent helper and the child process exits, the app
must invalidate that pane-agent principal unless the pane has already been
closed and invalidated. The lifecycle owner must own:

- process exit observation;
- auth-timeout diagnostics when a helper never successfully authenticates;
- idempotent cleanup if close and child-exit race.

This should be a small app-owned lifecycle coordinator around
`PaneAgentLaunchOwner`, not a new responsibility inside
`AgentStudioAppIPCServer`.

### R4. Terminal Completion Facts

`terminal.wait(commandFinished)` must be product-proven end to end for real
terminal runtime events. After `terminal.send` with a correlation id, a client
must be able to wait for a matching command-finished fact and receive:

- pane id;
- event name `terminal.commandFinished`;
- command id when available;
- correlation id when available;
- exit code;
- duration;
- event sequence ordering through the existing `afterSequence` rule.

If the runtime cannot reliably attach the correlation id to shell command
completion, the spec must shrink the public promise to command-finished facts
without correlation matching and require clients to use `afterSequence`.

### R5. Terminal CWD And Readback Facts

IPC must define the minimum safe readback surface for automation. Phase 2 should
prefer explicit runtime facts over raw terminal buffers:

- `terminal.wait(cwdChanged)` proves cwd change events when shell integration
  emits them.
- `terminal.snapshot` remains metadata-only unless a separate content-read
  permission and bounded DTO are added.
- Any terminal text/readback API must be treated as secret-bearing and require
  an explicit permission distinct from `terminalInputWrite`.

If bounded terminal output readback cannot be implemented safely in this slice,
the implementation plan should leave output readback out and document the
missing proof rather than exporting a leaky buffer API.

### R6. Prompt Readiness

Prompt readiness should not be guessed with wall-clock sleeps. The design should
choose one of these outcomes:

- map existing shell-integration prompt facts into an exported
  `terminal.promptReady` / `terminal.wait(promptReady)` condition; or
- explicitly defer prompt readiness and require automation to wait on
  command-finished, cwdChanged, titleChanged, or attachReady facts only.

The first implementation plan must not invent a fake prompt-ready fact unless
the runtime already emits a durable prompt boundary.

### R7. Manual Debug Control Proof

The implementation is not complete until a debug app can be controlled through
IPC in a real loop:

1. launch debug app with the canonical debug observability runner;
2. authenticate through debug token escrow or explicitly unsafe debug mode;
3. identify runtime and list panes;
4. create/split/focus a terminal pane;
5. send a unique command;
6. wait for an exported runtime fact using `afterSequence`;
7. prove stale pane-bound authority is revoked after pane close;
8. verify marker-scoped observability through Victoria;
9. optionally capture Peekaboo visual proof only for UI/render assertions.

## Non-Goals

- Do not expose public `zmx.*` methods.
- Do not implement MCP in this slice.
- Do not expose raw WebKit or Bridge Web transport through IPC.
- Do not route commands through `EventBus`.
- Do not mutate atoms directly from IPC methods.
- Do not use environment variables to carry pane-agent subject tokens.
- Do not add public terminal buffer/readback APIs without a separate
  secret-bearing permission decision.
- Do not make `command.execute` present the command bar or picker UI.

## Architecture

### Ownership Map

```
Pane close / child process exit
  -> App-owned lifecycle coordinator
  -> AgentStudioAppIPCServer.invalidatePrincipals(boundToPaneId:)
  -> principal registry removes tokens/principals
  -> grant ledger revokes grants
  -> server closes matching authenticated sockets
  -> permission/revocation events are emitted when exported
```

IPC owns principal invalidation mechanics. The app owns the decision that a pane
or child process has ended. The lifecycle coordinator is the seam between them.

```
terminal.send
  -> AgentStudioIPCRuntimeAdapter
  -> PaneRuntimeCommandDispatching
  -> WorkspaceSurfaceCoordinator.dispatchRuntimeCommand
  -> RuntimeRegistry / PaneRuntime
  -> runtime emits RuntimeEnvelope facts
  -> terminal.wait replays/subscribes through PaneRuntime.eventsSince/subscribe
  -> AgentStudioIPCRuntimeAdapter maps allowlisted facts to IPC DTOs
```

Terminal command acceptance and runtime completion remain different promises.
`terminal.send` means bytes or commands were accepted by the runtime dispatch
path. `terminal.wait` is the proof path for observable runtime effects.

### Proposed New App Composition Seam

Add a small app-owned coordinator under `Sources/AgentStudio/App/PaneAgents/`
or `Sources/AgentStudio/App/IPCComposition/`:

```
PaneAgentLifecycleCoordinator
  owns:
    - active pane-agent process handles keyed by pane id
    - auth timeout timer or async task
    - process-exit observation callback
    - idempotent invalidate-on-close/exit cleanup

  depends on:
    - PaneAgentLaunchOwner
    - AgentStudioAppIPCServer invalidation port
    - app logging / diagnostics

  must not:
    - parse JSON-RPC
    - own permission policy
    - mutate workspace atoms
    - know terminal runtime internals
```

The coordinator should talk to the IPC server through a narrow protocol, for
example:

```swift
@MainActor
protocol PaneBoundIPCPrincipalInvalidating: Sendable {
    func invalidatePrincipals(boundToPaneId paneId: String)
}
```

This keeps pane lifecycle decisions in the app while keeping auth state inside
`AgentStudioAppIPC`.

### Pane Close Integration Point

`WorkspaceSurfaceCoordinator.executeClosePane` is the current concrete close
owner for app pane close mutations. The follow-up should add an app composition
seam that can observe the final set of pane ids being closed:

- closing main pane id;
- drawer child pane ids owned by that main pane;
- drawer child pane id when closing only the drawer child.

The implementation should avoid coupling `WorkspaceSurfaceCoordinator` directly to
`AgentStudioAppIPC` if a small app protocol can be injected instead.

### Terminal Runtime Fact Mapping

The current exported wait enum already includes:

- `attachReady`;
- `commandFinished`;
- `rendererHealthy`;
- `titleChanged`;
- `cwdChanged`;
- `progressChanged`.

The follow-up must verify which of those are product-backed by real
`PaneRuntimeEvent` emissions and which are only contract-ready. If a condition
is not product-backed, the implementation should either wire the runtime fact
or remove/defer the public condition before claiming support.

## Security Context

This design is security-sensitive. It touches local socket auth, subject tokens,
pane-bound principals, terminal input, terminal metadata, process spawning, and
potential terminal output.

Rules:

- Pane-agent tokens stay single-use and fd-delivered.
- Stale pane tokens must fail closed.
- Stale authenticated sockets must be closed on pane invalidation.
- Terminal output/readback is secret-bearing.
- CWD paths can reveal private project names; expose only when explicitly
  permissioned and necessary.
- Debug unsafe no-auth remains debug-only and allowlisted.
- Beta/stable releases must not enable unsafe debug access.

## Validation Strategy

### Unit And Contract Tests

- principal invalidation removes tokens, active principals, grants, and closes
  socket principals;
- pane-agent lifecycle coordinator invalidates on close, child exit, and auth
  timeout;
- double close/exit cleanup is idempotent;
- terminal wait maps commandFinished, cwdChanged, and prompt facts only when
  runtime events exist;
- unsupported/deferred wait conditions fail with stable errors rather than
  timing out ambiguously;
- terminal readback APIs, if added, require a secret-bearing permission.

### Integration Tests

- app close path calls pane-bound invalidation for main panes and drawer child
  panes;
- pane-agent helper subprocess authenticates through fd bootstrap and is
  invalidated on lifecycle end;
- `terminal.send` followed by `terminal.wait` observes replayed and live facts
  using `afterSequence`;
- event subscription receives server-originated terminal/permission
  notifications and rejects inbound forged notifications.

### Smoke And Manual Proof

Use the canonical debug proof path:

```bash
mise run observability:up
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
  mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Add a focused IPC live-control smoke that drives the debug app through
`agentstudio-ipc` or the shared client core:

- auth status / login;
- system identify;
- pane list/current;
- pane split/drawer add/toggle;
- terminal status/snapshot/send/wait;
- pane close;
- stale principal denial after close.

Victoria proof should remain marker-scoped. Peekaboo should be used only for
visual proof that a pane/drawer/window rendered; it is not a replacement for IPC
runtime assertions.

## Definition Of Done

- Spec and implementation plan exist on this branch.
- Follow-up implementation has focused red/green tests for lifecycle and wait
  behavior.
- `mise run lint` passes.
- Relevant focused IPC/app tests pass.
- `mise run test` passes or any unrelated failure is reported separately with
  evidence.
- Live debug IPC smoke proves app control and stale-principal revocation.
- `mise run verify-debug-observability` proves marker-scoped debug telemetry.
- Architecture docs and `AGENTS.md` are updated only after implementation proof
  is real.

## Open Decisions

1. Should output readback be part of this slice, or should this slice stop at
   command-finished/cwd/prompt facts?
2. Should prompt readiness be exported only if existing shell integration emits
   a stable prompt boundary?
3. Should child process exit observation live in a new
   `PaneAgentLifecycleCoordinator`, or should it be attached directly to the
   component that first creates real pane agents?

## Recommendation

Implement this as two milestones:

1. Lifecycle closure:
   pane close, child exit, auth timeout, stale-principal smoke.
2. Runtime proof closure:
   commandFinished/cwd/prompt wait semantics, bounded live-control smoke, and
   observability proof.

Do not add terminal output readback until the permission and redaction model is
designed as a separate, secret-bearing capability.
