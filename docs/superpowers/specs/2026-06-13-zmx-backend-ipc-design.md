# zmx Backend IPC Design

**Date:** 2026-06-13
**Scope:** internal backend transport behind Agent Studio terminal sessions
**Status:** Future/backend design track. Agent Studio app IPC ships first.

## Status And Relationship To App IPC

This spec refreshes the useful design from the older `agent-studio.zmx-ipc`
worktree against the current Agent Studio architecture. It is not a public API
spec.

The public control surface is the Agent Studio app IPC service described in
`2026-06-10-agentstudio-ipc-design.md`. That service exposes app-level handles,
terminal commands, snapshots, waits, and events. It must not expose zmx daemon
socket paths, zmx session names, binary tags, `Info` bytes, history payloads, or
any public method named `zmx.*`.

This backend spec belongs below that boundary:

```text
Agent Studio app IPC / CLI / future MCP
  -> app semantic method registry
  -> app/workspace/runtime owners
  -> PaneCoordinator / RuntimeRegistry / PaneRuntime
  -> TerminalRuntime / SessionRuntime / ZmxBackend
  -> internal zmx daemon IPC
```

Agent Studio app IPC is the first implementation target. zmx backend IPC is a
later transport replacement track for removing CLI shell-outs and improving
backend observability.

## Goal

Replace selected `ZmxBackend` shell-outs with direct one-shot IPC calls to the
zmx daemon, without changing the public Agent Studio IPC contract.

The backend track should:

- replace `zmx list` and `zmx kill` stdout/process parsing with typed backend
  calls;
- keep zmx IPC hidden behind `ZmxBackend` and `SessionRuntime`;
- preserve pane-first public identity, where `PaneId` is canonical and zmx
  session names are derived backend data;
- make zmx backend behavior testable with protocol fixtures or mock sockets;
- leave terminal output, scrollback, and zmx history out of phase-1 public app
  IPC unless a separate security/backpressure design promotes them.

## Non-Goals

- Do not implement this before the Agent Studio app IPC slice.
- Do not expose zmx daemon IPC as public Agent Studio API.
- Do not add public `zmx.*` methods.
- Do not route app commands through the zmx daemon.
- Do not change zmx daemon protocol in this spec.
- Do not replace the Ghostty attach flow.
- Do not add remote zmx, TCP zmx, or SSH socket forwarding in this slice.
- Do not persist app IPC tokens or credentials in zmx state.
- Do not make zmx history/scrollback part of public `terminal.snapshot`.

## Current Grounding In This Branch

Current verified facts:

- `ZmxBackend` lives at
  `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift`.
- `SessionRuntime` lives at
  `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift`.
- `SessionConfiguration.detect()` gets `zmxDir` from
  `AppDataPaths.zmxDirectory()`.
- `AppDataPaths.zmxDirectory()` resolves to `<app-root>/z`, with the app root
  selected by channel and `AGENTSTUDIO_DATA_DIR`.
- `ZmxBackend` still owns `ProcessExecutor`, retry policy, and shell-outs for
  `zmx list` / `zmx kill`.
- `SessionRuntime` currently tracks a simple `SessionRuntimeStatus` map and
  marks running panes unhealthy when the registered backend reports not alive.
- `vendor/zmx` is not initialized in this checkout, so low-level binary
  protocol claims from the older zmx spec are unverified here.

The current architecture means the first backend IPC implementation should be a
transport swap inside `ZmxBackend`, not a public method-surface change.

## Current Owners

```text
ZmxBackend
  deterministic zmx session id derivation
  zmx directory creation and environment scoping
  attach command construction
  current list/kill/discover shell-out transport

SessionRuntime
  runtime status map
  periodic health check scheduling
  backend registration and pane health interpretation

SessionConfiguration / AppDataPaths
  zmx binary discovery
  channel-aware app root
  zmx directory path

TerminalRuntime / PaneRuntime
  public runtime command and snapshot contract above zmx
```

`ZmxIPCClient`, if implemented, should be an internal transport helper owned by
infrastructure-level socket/protocol mechanics. It should not import AppKit,
SwiftUI, atoms, stores, coordinators, or public IPC method contracts.

## Preserved Design Inputs From The Old zmx Spec

The older worktree captured valuable backend design constraints:

- One-shot zmx IPC calls are preferred over persistent control connections.
  Persistent control sockets can become real daemon clients and may receive PTY
  output broadcasts.
- Direct backend IPC can remove process-spawn overhead and stdout parsing from
  `zmx list` and `zmx kill`.
- Socket path length remains a real Darwin constraint because zmx socket paths
  are derived from `zmxDir + "/" + sessionId`.
- zmx daemon socket permissions are the daemon access boundary.
- Future remote zmx should prefer SSH Unix-socket forwarding over raw TCP if it
  is ever designed, because SSH owns authentication/encryption and preserves the
  Unix-socket access model.

These inputs are design constraints. They are not public API commitments.

## Claims Blocked On Vendor Verification

The old spec included concrete wire details such as message tag values, header
layout, `Info` struct offsets, history formats, and read-loop handling for
unsolicited output frames. Those must not be treated as current truth until a
checkout with `vendor/zmx` initialized verifies the exact files for the pinned
submodule revision.

Before implementation planning for this backend track, verify:

```text
vendor/zmx/src/ipc.zig
vendor/zmx/src/main.zig
vendor/zmx/src/socket.zig or the current equivalent socket file
```

The verification pass must answer:

- exact request/response tags and payload encodings;
- whether `Info` is fixed-size or versioned and how strings are encoded;
- whether history payloads are stable enough to consume;
- whether one-shot `Info` / kill flows can receive output or ack frames first;
- timeout behavior and daemon failure modes;
- socket permission and ownership behavior;
- compatibility with the zmx binary bundled by Agent Studio.

Until then, this spec intentionally avoids hard-coding the binary layout.

## Target Backend Architecture

```text
SessionRuntime
  health scheduling and status interpretation
  |
  v
ZmxBackend
  session id/path derivation
  attach command
  backend operation semantics
  |
  v
Zmx IPC transport helper
  one-shot Unix socket calls
  protocol encode/decode
  timeout and error mapping
  |
  v
zmx daemon socket
```

The transport helper may use lower-level socket APIs, but its public Swift API
should be backend-semantic, not daemon-public:

```text
probeSession(socketPath) -> alive/info
listSessions(zmxDir, prefix) -> session ids or typed info
killSession(socketPath or session id) -> success/failure
```

`history` is intentionally not in the first backend slice unless a later design
decides who can consume it and how secrets/backpressure are handled.

## Operation Scope

First backend slice:

- probe one known session;
- list or discover Agent Studio sessions under `<app-root>/z`;
- kill one known Agent Studio session;
- map backend errors to existing `SessionBackendError` cases;
- preserve current `ZmxBackend` public API.

Deferred backend operations:

- zmx history or terminal state snapshots;
- richer session lifecycle events;
- remote zmx over SSH-forwarded sockets;
- daemon protocol extensions;
- persistent control connections;
- public terminal output streaming.

## Event Integration Options

Current `SessionRuntime` does not emit `SessionBackendEvent` onto
`PaneRuntimeEventBus`. The old zmx IPC spec assumed such an event path existed,
but this branch does not yet have it.

The refreshed design keeps two options open:

```text
Option A: transport-only first
  ZmxBackend uses direct IPC for probe/list/kill.
  SessionRuntime keeps current status behavior.
  No new pane runtime event cases.

Option B: richer backend facts later
  SessionRuntime compares typed probe info over time.
  It emits explicitly designed runtime facts for session lost/restored or task
  completion.
  Event payloads are redacted and mapped to public app IPC event names only if
  the app IPC spec exposes them.
```

Option A is the default for the first backend implementation plan because it
reduces blast radius and proves the transport swap before changing event
semantics.

## Security Boundary

zmx daemon IPC is a privileged backend seam. Any process that can open the zmx
daemon socket can potentially drive or observe terminal session data according
to the daemon protocol. Agent Studio must therefore treat zmx sockets as
secret-bearing local resources.

Rules:

- zmx IPC remains internal to Agent Studio.
- Public app IPC tokens must never be accepted by or stored in zmx.
- Public app IPC responses and events must not include zmx socket paths, raw zmx
  session ids, binary tags, `Info` bytes, or history payloads.
- `ZmxBackend` must only operate on Agent Studio-owned sessions in the
  channel-aware `<app-root>/z` directory.
- Backend discovery must filter to Agent Studio session prefixes and must not
  affect user-owned zmx sessions outside the app root.
- zmx history and output-bearing payloads are terminal secret material.
- Remote zmx is a separate security design because SSH custody, remote socket
  permissions, and remote host trust change the boundary.

## Testing Strategy

Protocol tests after vendor verification:

- encode/decode the verified header and messages;
- reject malformed/truncated messages;
- parse verified `Info` payloads;
- skip or handle unsolicited daemon frames according to verified behavior.

Transport tests:

- one-shot connect/send/read/close behavior;
- timeout and connection-refused mapping;
- kill request maps to existing `SessionBackendError` semantics;
- list/probe ignore sessions outside the Agent Studio prefix;
- socket path length budget is enforced.

Integration tests:

- run against the bundled or test zmx binary with isolated `AGENTSTUDIO_DATA_DIR`;
- verify probe/list/kill without shelling out for the operation under test;
- verify no public app IPC schema exposes zmx internals.

Architecture tests or review checks:

- `ZmxBackend` public API remains backend-agnostic;
- app IPC method registry contains no `zmx.*` namespace;
- app IPC terminal snapshots do not depend on zmx history payloads.

## Coarse Work Breakdown

```text
1. Vendor truth refresh and protocol fixture capture
2. zmx backend IPC transport helper and protocol tests
3. ZmxBackend probe/list/kill transport swap
4. SessionRuntime health proof with unchanged public status semantics
5. Optional richer backend facts design, if needed later
6. Architecture-doc promotion after implementation lands
```

These are coarse backend deliverables. They should become separate planning
items after the Agent Studio app IPC plan is approved.

## Open Decisions

- Should the first zmx backend slice be transport-only, or should it also add
  new session backend events?
- Should `history` remain completely deferred, or should it become an internal
  debugging-only operation before any public terminal output design?
- Should backend discovery enumerate sockets directly, call a verified zmx list
  IPC operation, or support both?
- What exact failure mode should replace current retry behavior around `zmx
  list` and `zmx kill`?
- Should a refreshed `session_lifecycle.md` become the durable home for verified
  zmx IPC details after implementation?

## References

- [AgentStudio IPC Design](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/superpowers/specs/2026-06-10-agentstudio-ipc-design.md)
- [ZmxBackend.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift)
- [SessionRuntime.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift)
- [SessionConfiguration.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Core/Models/SessionConfiguration.swift)
- [AppDataPaths.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/Sources/AgentStudio/Infrastructure/AppDataPaths.swift)
- [session_lifecycle.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/architecture/session_lifecycle.md)
- [zmx_terminal_integration_lessons.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.programatical-control/docs/architecture/zmx_terminal_integration_lessons.md)
- [Older zmx IPC spec in sibling worktree](/Users/shravansunder/Documents/dev/project-dev/agent-studio.zmx-ipc/docs/superpowers/specs/2026-03-30-zmx-ipc-client-design.md)
