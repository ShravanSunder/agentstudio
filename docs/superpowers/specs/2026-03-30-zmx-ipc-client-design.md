# ZmxIPCClient Design Spec

Direct IPC client for zmx daemon communication, replacing CLI shell-outs with binary socket protocol.

## Problem

Agent Studio communicates with zmx daemons by spawning `zmx kill`, `zmx list` as child processes and parsing their stdout. This is:
- **Slow** — process spawn overhead on every health check, kill, discovery operation
- **Fragile** — stdout parsing breaks if zmx changes output format
- **Limited** — can't access capabilities like on-demand terminal state snapshots (History)

zmx daemons already expose a binary IPC protocol over Unix sockets. The same protocol the zmx client process uses internally. We can speak it directly from Swift.

## Goals

1. Replace all CLI shell-outs in `ZmxBackend` with direct socket IPC
2. Add on-demand terminal state snapshot capability (History)
3. Improve health check reliability and speed
4. Make zmx integration testable with mock sockets

## Non-Goals

- Replacing the zmx attach flow (Ghostty owns the PTY process)
- Modifying the zmx daemon or its protocol
- Persistent socket connections (see Design Decisions)
- Implementing checkpoint/restore (future work)
- Direct resize control via IPC

## Design Decisions

### D1: One-shot connections, not persistent pool

**Why:** In zmx, every connected socket becomes a real session client. The daemon
broadcasts ALL PTY output to every connected client (vendor/zmx/src/main.zig:1452).
A persistent "control-only" connection would:
- Receive continuous PTY output it doesn't want
- Inflate `clients_len` in Info responses
- Require a background drain loop to prevent daemon buffer bloat
- Add concurrency complexity (no request IDs in the protocol)

zmx's own `probeSession()` (vendor/zmx/src/ipc.zig:181) uses connect → send → read → close.
We follow the same pattern. Unix socket connect is microseconds on localhost.

**Implication:** All IPC operations are stateless: connect, send request, read response, close.
No connection pool. No drain loop. No concurrency hazards.

### D2: IPC client in Infrastructure, event integration in SessionRuntime

The IPC client is a pure protocol speaker — it knows sockets and bytes. Session
lifecycle semantics (health transitions, debounce, event emission) belong in
`SessionRuntime` which already owns session status tracking. The IPC client
provides data; `SessionRuntime` interprets it and feeds the event bus.

### D3: Events follow existing pane runtime architecture

zmx session facts are pane-scoped (one session per pane) and flow through the
existing three data flow planes:

- **Event plane:** `SessionRuntime` detects state transitions → wraps in `PaneEnvelope` → posts to `PaneRuntimeEventBus`
- **Command plane:** Kill/History are direct calls via `ZmxBackend`. Commands never go through the bus.
- **UI plane:** `SessionRuntime.statuses` is `@Observable`. Health transitions update `@Observable` first (synchronous), then post to bus (async). Follows the multiplexing rule.

### D4: No new command abstractions needed

The existing `RuntimeCommand.requestSnapshot` covers the one command-plane case
(requesting a terminal state snapshot). Kill and health operations are internal
to `ZmxBackend`/`SessionRuntime` — no external part of the system sends commands
for these. New zmx session facts use the existing `PaneRuntimeEvent` discriminated union.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Agent Studio                             │
│                                                                 │
│  SessionRuntime (@MainActor, @Observable)                       │
│    ├─ health check timer (30s)                                  │
│    ├─ compares current vs previous probe results                │
│    ├─ debounces unhealthy transitions (15s)                     │
│    ├─ updates @Observable state (UI plane, synchronous)         │
│    └─ posts SessionBackendEvent to PaneRuntimeEventBus          │
│         │                                                       │
│         ▼                                                       │
│  PaneRuntimeEventBus ──► WorkspaceCacheCoordinator              │
│                      ──► PaneCoordinator (repair flows)         │
│                      ──► NotificationReducer                    │
│                      ──► Future agent orchestrator              │
│                                                                 │
│  ZmxBackend (Core/Stores/)                                      │
│    ├─ attachCommand() → string (unchanged)                      │
│    ├─ kill() → ZmxIPCClient.kill(socketPath:)                   │
│    ├─ healthCheck() → ZmxIPCClient.info(socketPath:)            │
│    ├─ discover() → enumerate zmxDir + ZmxIPCClient.probe()      │
│    └─ history() → ZmxIPCClient.history(socketPath:, format:)    │
│                        │                                        │
│                        ▼                                        │
│              ZmxIPCClient (Infrastructure/ZmxIPC/)              │
│                Static one-shot methods                          │
│                connect → send → read → close                    │
│                                                                 │
└────────────────────────┼────────────────────────────────────────┘
                         │  Unix socket (one-shot)
                         ▼
                  ┌────────────┐
                  │ zmx daemon │
                  └────────────┘
```

## Components

### ZmxIPCClient (`Infrastructure/ZmxIPC/ZmxIPCClient.swift`)

Single responsibility: speak the zmx binary protocol over one-shot Unix socket connections.

**All methods are static, async, and `@concurrent nonisolated`** — no instance state, no
shared socket, no concurrency hazards. Each call opens its own connection.

```swift
enum ZmxIPCClient {
    /// Kill a zmx session. Daemon shuts down, socket closes.
    static func kill(socketPath: String) async throws

    /// Query session metadata. Returns parsed Info struct.
    static func info(socketPath: String, timeout: Duration = .seconds(1)) async throws -> ZmxSessionInfo

    /// Request terminal state snapshot.
    static func history(socketPath: String, format: ZmxHistoryFormat, timeout: Duration = .seconds(5)) async throws -> Data

    /// Quick liveness check. Returns true if daemon responds to Info.
    static func probe(socketPath: String, timeout: Duration = .seconds(1)) async -> Bool

    /// Discover all live sessions in a directory.
    static func probeAll(directory: String, prefix: String) async -> [String: ZmxSessionInfo]
}
```

**Concurrency model:** Each method does its own connect → send → read → close.
`@concurrent nonisolated` ensures blocking socket I/O runs on the cooperative thread pool,
not the caller's actor. No shared state means no races.

### ZmxIPCProtocol (`Infrastructure/ZmxIPC/ZmxIPCProtocol.swift`)

Binary encoding/decoding for the zmx wire format.

```swift
/// 5-byte header: tag (u8) + length (u32 LE). Zig packed struct, no padding.
struct ZmxIPCHeader { ... }

/// Message tags matching vendor/zmx/src/ipc.zig:6-21
enum ZmxIPCTag: UInt8 { ... }

/// Parsed Info response matching vendor/zmx/src/ipc.zig:45-55
struct ZmxSessionInfo: Sendable {
    let clientsLen: Int
    let pid: Int32
    let cmd: String
    let cwd: String
    let createdAt: UInt64
    let taskEndedAt: UInt64
    let taskExitCode: UInt8
}

enum ZmxHistoryFormat: UInt8 {
    case plain = 0
    case vt = 1
    case html = 2
}
```

### SessionBackendEvent (new case in `PaneRuntimeEvent`)

```swift
// Added to existing PaneRuntimeEvent discriminated union:
enum PaneRuntimeEvent: Sendable {
    case lifecycle(PaneLifecycleEvent)
    case terminal(GhosttyEvent)
    case session(SessionBackendEvent)    // ← new
    ...
}

enum SessionBackendEvent: Sendable {
    case healthChanged(healthy: Bool, info: ZmxSessionInfo?)
    case cwdChanged(cwd: String)
    case taskCompleted(exitCode: UInt8)
    case sessionLost
    case sessionRestored
}
```

### ZmxBackend changes (`Core/Stores/ZmxBackend.swift`)

Replace internals, keep public API unchanged.

| Method | Before | After |
|--------|--------|-------|
| `destroyPaneSession` | `ProcessExecutor` → `zmx kill` | `ZmxIPCClient.kill(socketPath:)` |
| `healthCheck` | `ProcessExecutor` → `zmx list` + parse | `ZmxIPCClient.probe(socketPath:)` |
| `discoverOrphanSessions` | `ProcessExecutor` → `zmx list` + parse | `ZmxIPCClient.probeAll(directory:prefix:)` |
| `destroySessionById` | `ProcessExecutor` → `zmx kill` | `ZmxIPCClient.kill(socketPath:)` |
| `sessionExists` | calls `healthCheck` | `ZmxIPCClient.probe(socketPath:)` |
| `attachCommand` | string construction | **unchanged** |
| `createPaneSession` | builds handle | **unchanged** |

**Removed:** `ProcessExecutor` dependency, `executeWithRetry`, `ZmxCommandRetryPolicy`.

### SessionRuntime changes (`Core/Stores/SessionRuntime.swift`)

Health check loop gains richer data from `ZmxSessionInfo`:

```
Timer fires (30s)
  │
  for each tracked session:
  │  info = await ZmxIPCClient.info(socketPath)
  │  compare with previousInfo:
  │    ├─ was healthy, now unreachable → start 15s debounce timer
  │    ├─ debounce expired, still unreachable → emit .sessionLost
  │    ├─ was unhealthy, now responds → emit .sessionRestored (immediate)
  │    ├─ cwd changed → emit .cwdChanged
  │    └─ taskExitCode changed → emit .taskCompleted
  │
  │  update @Observable statuses (UI plane, synchronous)
  │  post PaneEnvelope to bus (event plane, async)
```

## Binary Protocol

### Wire Format

From `vendor/zmx/src/ipc.zig`:

```
┌─────────┬──────────┬─────────────────────┐
│ Tag     │ Length   │ Payload             │
│ 1 byte  │ 4 bytes  │ Length bytes         │
│ u8      │ u32 LE   │ raw bytes            │
└─────────┴──────────┴─────────────────────┘

Header: 5 bytes (Zig packed struct, no padding)
Byte order: little-endian (native arm64 macOS)
```

### Message Tags

| Tag | Value | Direction | Payload |
|-----|-------|-----------|---------|
| Input | 0 | Client → daemon | Raw keystroke bytes |
| Output | 1 | Daemon → client | Raw PTY output (broadcast) |
| Resize | 2 | Client → daemon | rows: u16, cols: u16 |
| Detach | 3 | Client → daemon | empty |
| DetachAll | 4 | Client → daemon | empty |
| Kill | 5 | Client → daemon | empty |
| Info | 6 | Bidirectional | empty (request) / Info struct (response) |
| Init | 7 | Client → daemon | rows: u16, cols: u16 |
| History | 8 | Bidirectional | format: u8 (request) / terminal state (response) |
| Run | 9 | Client → daemon | command bytes |
| Ack | 10 | Daemon → client | empty |

### Message Flows (what we use)

**Kill (tag 5):**
```
Send:    Header(tag: 5, len: 0)
Receive: nothing — daemon shuts down, socket closes
         Client detects EOF
```

**Info (tag 6):**
```
Send:    Header(tag: 6, len: 0)
Receive: Header(tag: 6, len: sizeof(Info)) + Info struct bytes

Info struct (C ABI extern struct, arm64 macOS):
  Offset  Size   Field
  0       8      clientsLen  (usize)
  8       4      pid         (i32)
  12      2      cmdLen      (u16)
  14      2      cwdLen      (u16)
  16      256    cmd         ([256]u8)
  272     256    cwd         ([256]u8)
  528     8      createdAt   (u64)
  536     8      taskEndedAt (u64)
  544     1      taskExitCode (u8)
  545     7      padding     (struct alignment to 8)
  Total:  552 bytes (verify against real daemon in integration tests)
```

**History (tag 8):**
```
Send:    Header(tag: 8, len: 1) + format byte (0=plain, 1=VT, 2=HTML)
Receive: Header(tag: 8, len: N) + serialized terminal state (single message)
```

**Probe (Info with short timeout):**
```
Connect to socket → send Info → read with 1s timeout
  Success → alive, parse ZmxSessionInfo
  Timeout / refused / EOF → dead
Close socket either way
```

### Important Protocol Constraint

A one-shot connection may still receive Output messages (tag 1) between
connecting and receiving the Info/History response. The read loop must
skip Output messages until it finds the expected response tag:

```
Read message:
  if tag == expected response → return payload
  if tag == .output → discard, read next
  if tag == .ack → discard, read next
  if EOF → throw error
  if timeout → throw error
```

This only matters for the brief window between connect and response.
Since we close immediately after, no sustained drain is needed.

### Socket Path Construction

```
socketPath = zmxDir + "/" + sessionId

zmxDir: ~/.agentstudio/z  (ZmxBackend.defaultZmxDir)
sessionId: as-<repoKey16>-<wtKey16>-<pane16>

Max usable path payload: 103 bytes (104-byte sun_path minus trailing NUL)
```

## Event Integration

### Where zmx events fit in the existing architecture

```
Three Data Flow Planes (from pane_runtime_architecture.md):

EVENT PLANE:
  SessionRuntime detects state change from IPC probe
    → wraps in PaneEnvelope(paneId, .session(SessionBackendEvent))
    → posts to PaneRuntimeEventBus
    → consumed by WorkspaceCacheCoordinator, PaneCoordinator, etc.

COMMAND PLANE:
  Kill, History are direct calls: coordinator → ZmxBackend → ZmxIPCClient
  requestSnapshot already exists as RuntimeCommand (RuntimeCommand.swift:17)
  No new command types needed.

UI PLANE:
  SessionRuntime.statuses is @Observable
  @Observable updated FIRST (synchronous), bus post SECOND (async)
  Follows the multiplexing rule: UI is never stale relative to bus consumers.
```

### Event consumers

| Consumer | Event | Action |
|----------|-------|--------|
| PaneCoordinator | `.sessionLost` | Trigger repair/placeholder flow |
| PaneCoordinator | `.sessionRestored` | Remove placeholder, resume |
| WorkspaceCacheCoordinator | `.cwdChanged` | Update worktree associations |
| NotificationReducer | `.taskCompleted` | Show completion notification |
| Future agent orchestrator | `.taskCompleted` | Workflow sequencing |

### Health transition debounce

```
Probe succeeds after failure:
  → emit .sessionRestored immediately (good news travels fast)

Probe fails after success:
  → start 15s debounce timer
  → if still failing after 15s → emit .sessionLost
  → if recovers during debounce → cancel timer, no event emitted
```

This prevents UI churn from transient daemon busy states.

## Error Handling

```swift
enum ZmxIPCError: Error {
    case notAvailable      // socket missing or connection refused
    case timeout           // read timed out
    case protocolError     // malformed response (wrong size, unexpected tag)
}
```

Error mapping to existing API:

| ZmxIPCError | SessionBackendError |
|-------------|-------------------|
| `.notAvailable` | `.notAvailable` |
| `.timeout` | `.timeout` |
| `.protocolError` | `.operationFailed(detail)` |

Consumers of `ZmxBackend` see the same error types as before.

## Testing Strategy

### Unit Tests (fast, no zmx process)

**Protocol encoding/decoding** (`ZmxIPCProtocolTests`):
- Encode/decode header bytes (tag + u32 LE length)
- Encode resize struct (2× u16 LE)
- Decode Info struct (verify field offsets, extract cmd/cwd strings)
- Handle truncated/empty cmd and cwd fields
- Handle max-length strings

**IPC client with mock socketpair** (`ZmxIPCClientTests`):

Use `socketpair(AF_UNIX, SOCK_STREAM, 0)` — one end is the mock daemon
(test controls it), the other is passed to `ZmxIPCClient`.

- `probe()` returns true when mock sends valid Info response
- `probe()` returns false on timeout (mock doesn't respond)
- `probe()` returns false when socket doesn't exist
- `kill()` sends Kill header, mock verifies bytes
- `info()` parses mock Info response correctly
- `history()` reads VT payload from mock
- Output messages between connect and response are skipped
- Connection refused → `.notAvailable`
- Malformed response → `.protocolError`

### Integration Tests (real zmx daemon)

Replace current flaky E2E tests that shell out to `zmx` CLI.

- Connect to real daemon, verify `info()` returns valid PID
- `history(format: .vt)` returns non-empty VT state
- `kill()` terminates daemon process
- `probeAll()` discovers running sessions
- Probe dead socket returns false

### What becomes testable that wasn't before

- Health check is a typed struct parse, not stdout string matching
- Kill is a socket write, not process exit code
- Discovery is socket enumeration, not CLI output parsing
- History is binary response, not previously untested

## Migration Plan

1. Implement `ZmxIPCProtocol` and `ZmxIPCClient` in `Infrastructure/ZmxIPC/`
2. Add unit tests with mock socketpair
3. Add `SessionBackendEvent` to `PaneRuntimeEvent` enum
4. Migrate `ZmxBackend` operations one at a time: probe → kill → discover
5. Add integration tests against real zmx daemons
6. Remove `ProcessExecutor` from `ZmxBackend`
7. Wire up History for on-demand inspection via `RuntimeCommand.requestSnapshot`
8. Add health transition debounce and event emission to `SessionRuntime`

## File Inventory

| File | Location | Purpose |
|------|----------|---------|
| `ZmxIPCClient.swift` | `Infrastructure/ZmxIPC/` | One-shot socket operations |
| `ZmxIPCProtocol.swift` | `Infrastructure/ZmxIPC/` | Header/tag/struct encode/decode |
| `ZmxIPCError.swift` | `Infrastructure/ZmxIPC/` | Error types |
| `ZmxIPCProtocolTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Protocol encode/decode |
| `ZmxIPCClientTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Client with mock socketpair |
| `ZmxIPCIntegrationTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Real daemon tests |
| `ZmxBackend.swift` | `Core/Stores/` | Modified — swap transport |
| `SessionRuntime.swift` | `Core/Stores/` | Modified — richer health, event emission |
| `PaneRuntimeEvent.swift` | `Core/PaneRuntime/Contracts/` | Modified — add `.session(SessionBackendEvent)` |

## Constraints

- **macOS 26+ arm64 only** — usize is always 8 bytes
- **Unix socket path limit** — 103 usable bytes max
- **No zmx protocol changes** — we speak the existing protocol exactly
- **One-shot connections only** — avoid Output broadcast drain obligation
- **Swift 6.2 concurrency** — `@concurrent nonisolated` for blocking socket I/O
- **Multiplexing rule** — `@Observable` updated before bus post, always
