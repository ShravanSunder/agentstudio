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
4. Lay groundwork for future checkpoint/restore features
5. Make zmx integration testable with mock sockets

## Non-Goals

- Replacing the zmx attach flow (Ghostty owns the PTY process)
- Modifying the zmx daemon or its protocol
- Implementing checkpoint/restore (future work, stubs only)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Agent Studio                            │
│                                                             │
│  SessionRuntime ──► ZmxBackend (Core/Stores/)               │
│                       │                                     │
│                       ├─ attachCommand() → string (unchanged)│
│                       ├─ kill() ────────────┐               │
│                       ├─ healthCheck() ─────┤               │
│                       ├─ discover() ────────┤               │
│                       └─ history() ─────────┤               │
│                                             ▼               │
│                    ZmxIPCConnectionPool (@MainActor)         │
│                    (Infrastructure/ZmxIPC/)                  │
│                       │                                     │
│                       ├─ clients: [String: ZmxIPCClient]    │
│                       ├─ client(for:) → lazy connect        │
│                       ├─ disconnectAll()                    │
│                       └─ probeAll(in:) → discovery          │
│                              │                              │
│              ┌───────────────┼───────────────┐              │
│              ▼               ▼               ▼              │
│        ZmxIPCClient    ZmxIPCClient    ZmxIPCClient         │
│        (nonisolated)   (nonisolated)   (nonisolated)        │
│           │                │                │               │
└───────────┼────────────────┼────────────────┼───────────────┘
            │                │                │
            ▼                ▼                ▼
     ┌────────────┐   ┌────────────┐   ┌────────────┐
     │ zmx daemon │   │ zmx daemon │   │ zmx daemon │
     │ (Unix sock)│   │ (Unix sock)│   │ (Unix sock)│
     └────────────┘   └────────────┘   └────────────┘
```

## Components

### ZmxIPCClient (`Infrastructure/ZmxIPC/ZmxIPCClient.swift`)

Single responsibility: speak the zmx binary protocol over one Unix socket connection.

**Properties:**
- `socketPath: String` — path to the daemon's Unix socket
- `fd: Int32?` — connected socket file descriptor (nil when disconnected)
- `isConnected: Bool`

**Implemented methods:**
- `connect()` — open Unix socket, establish persistent connection
- `disconnect()` — close fd
- `kill()` — send Kill message, expect socket closure
- `info() -> ZmxSessionInfo` — send Info, parse response struct
- `history(format: ZmxHistoryFormat) -> Data` — send History, read response payload
- `probe() -> Bool` — connect + info with short timeout, true if daemon responds

**Future stubs (not implemented):**
- `checkpoint() -> Data` — periodic state snapshot for crash recovery
- `resize(rows: UInt16, cols: UInt16)` — direct resize control

**Concurrency:** `nonisolated`, `Sendable`. All socket I/O uses `@concurrent` to avoid blocking the caller's actor. Methods are `async` and suspend while socket operations execute on the cooperative thread pool.

**Reconnection:** On unexpected disconnect, auto-reconnect with backoff:
- Immediate first retry
- Then 100ms, 250ms, 500ms delays
- After 3 failures: mark as dead, throw `.disconnected`
- No reconnect after `kill()` (disconnection is expected)

### ZmxIPCConnectionPool (`Infrastructure/ZmxIPC/ZmxIPCConnectionPool.swift`)

Owns all `ZmxIPCClient` instances. Provides lookup, lifecycle management, and bulk operations.

**Properties:**
- `clients: [String: ZmxIPCClient]` — keyed by session ID
- `zmxDir: String` — socket directory path

**Methods:**
- `client(for sessionId: String) -> ZmxIPCClient` — returns existing or creates new (lazy connect)
- `disconnect(sessionId: String)` — close and remove one client
- `disconnectAll()` — close all connections (app shutdown)
- `probeAll() -> [String: ZmxSessionInfo]` — enumerate socket dir, probe each, return live sessions
- `killOrphans(excluding: Set<String>)` — find and kill sessions not in known set

**Concurrency:** `@MainActor`. Dictionary operations are fast. Individual client calls go async to the thread pool.

### ZmxBackend changes (`Core/Stores/ZmxBackend.swift`)

Replace internals, keep public API unchanged.

| Method | Before | After |
|--------|--------|-------|
| `destroyPaneSession` | `ProcessExecutor` → `zmx kill` | `pool.client(for:).kill()` |
| `healthCheck` | `ProcessExecutor` → `zmx list` + parse | `pool.client(for:).probe()` |
| `discoverOrphanSessions` | `ProcessExecutor` → `zmx list` + parse | `pool.probeAll()` + filter prefix |
| `destroySessionById` | `ProcessExecutor` → `zmx kill` | `pool.client(for:).kill()` |
| `sessionExists` | calls `healthCheck` | `pool.client(for:).probe()` |
| `attachCommand` | string construction | **unchanged** |
| `createPaneSession` | builds handle | **unchanged** |

**Removed:** `ProcessExecutor` dependency, `executeWithRetry`, retry policy (reconnect handled by client).

## Binary Protocol

### Wire Format

All communication uses this framing (from `vendor/zmx/src/ipc.zig`):

```
┌─────────┬──────────┬─────────────────────┐
│ Tag     │ Length   │ Payload             │
│ 1 byte  │ 4 bytes  │ Length bytes         │
│ u8      │ u32 LE   │ raw bytes            │
└─────────┴──────────┴─────────────────────┘

Total header: 5 bytes (Zig packed struct, no padding)
Byte order: little-endian (native arm64)
```

### Message Tags

```swift
enum ZmxIPCTag: UInt8 {
    case input     = 0   // Client → daemon: keystrokes
    case output    = 1   // Daemon → client: PTY output (broadcast to all)
    case resize    = 2   // Client → daemon: terminal dimensions
    case detach    = 3   // Client → daemon: disconnect
    case detachAll = 4   // Client → daemon: disconnect all
    case kill      = 5   // Client → daemon: terminate session
    case info      = 6   // Client → daemon: query metadata
    case initialize = 7  // Client → daemon: attach with dimensions
    case history   = 8   // Client → daemon: request terminal state
    case run       = 9   // Client → daemon: execute command
    case ack       = 10  // Daemon → client: acknowledge
}
```

### Message Payloads

**Kill (tag 5):**
```
Send:    Header(tag: 5, len: 0)
Receive: nothing — daemon shuts down, socket closes
         Client detects EOF on next read
```

**Info (tag 6):**
```
Send:    Header(tag: 6, len: 0)
Receive: Header(tag: 6, len: 552) + Info struct bytes
```

Info struct layout (C ABI extern struct, arm64 macOS):
```
Offset  Size   Type        Field
0       8      UInt64      clientsLen     (usize = 8 bytes on 64-bit)
8       4      Int32       pid
12      2      UInt16      cmdLen
14      2      UInt16      cwdLen
16      256    [UInt8]     cmd            (MAX_CMD_LEN = 256)
272     256    [UInt8]     cwd            (MAX_CWD_LEN = 256)
528     8      UInt64      createdAt      (unix timestamp)
536     8      UInt64      taskEndedAt    (0 if not applicable)
544     1      UInt8       taskExitCode   (0 if not applicable)
545     7      -           padding        (struct aligned to 8 bytes)
─────────────────────────────────────────
Total:  552 bytes (expected, verify at test time)

Note: The daemon validates `msg.payload.len == @sizeOf(Info)`. The exact
size depends on Zig's C ABI layout for arm64. Integration tests should
verify the expected size against a real daemon response before hardcoding.
```

**History (tag 8):**
```
Send:    Header(tag: 8, len: 1) + format byte
         format: 0 = plain text, 1 = VT sequences, 2 = HTML
Receive: Header(tag: 8, len: N) + serialized terminal state
         Single message with full state (can be large)
```

**Resize (tag 2):**
```
Send:    Header(tag: 2, len: 4) + Resize struct
         Resize: rows (u16 LE) + cols (u16 LE)
Receive: nothing (fire-and-forget)
```

### Output Message Handling

**Critical design constraint:** The daemon broadcasts ALL PTY output to ALL connected clients. There is no subscription filtering. A control-only client (our `ZmxIPCClient`) will receive a continuous stream of Output messages (tag 1) containing terminal bytes.

**Our approach:** The client must read and discard Output messages to prevent the daemon's per-client write buffer from growing unbounded. The read loop:

```
Read message from socket:
  if tag == .info    → parse Info struct, deliver to caller
  if tag == .history → deliver payload to caller
  if tag == .output  → discard (drain the pipe)
  if tag == .ack     → discard
  if EOF             → connection closed
```

This drain loop runs on a background thread as part of the persistent connection, not on-demand per request.

### Socket Path Construction

```
socketPath = zmxDir + "/" + sessionId

zmxDir: ~/.agentstudio/z  (from ZmxBackend.defaultZmxDir)
sessionId: agentstudio--<repoKey16>--<wtKey16>--<pane16>

Example:
  ~/.agentstudio/z/agentstudio--809c4428faf0d071--809c4428faf0d071--84806b4385774da7
```

Maximum path length: 104 bytes (platform sockaddr_un.sun_path - 1).

## Data Flow

### Health Check (replaces `zmx list` + parse)

```
SessionRuntime timer fires
  │
  ▼
ZmxBackend.healthCheck(handle)
  │
  ▼
pool.client(for: handle.id)
  │
  ├─ client exists and connected → reuse
  └─ client missing → create, lazy connect
  │
  ▼
client.probe()  [async, @concurrent, off main actor]
  │
  ├─ send Header(tag: 6, len: 0)
  ├─ read response (1s timeout)
  │    ├─ got Info response → return true
  │    ├─ timeout → return false
  │    └─ connection refused → return false
  │
  ▼
SessionRuntime updates status
```

### Kill Session (replaces `zmx kill <session>`)

```
User closes pane → undo TTL expires
  │
  ▼
ZmxBackend.destroyPaneSession(handle)
  │
  ▼
pool.client(for: handle.id).kill()  [async, @concurrent]
  │
  ├─ send Header(tag: 5, len: 0)
  ├─ daemon shuts down, socket closes
  ├─ client detects EOF
  │
  ▼
pool.disconnect(sessionId: handle.id)
```

### Orphan Discovery (replaces `zmx list` + prefix filter)

```
App startup or periodic cleanup
  │
  ▼
ZmxBackend.discoverOrphanSessions(excluding: knownIds)
  │
  ▼
pool.probeAll()  [async]
  │
  ├─ enumerate zmxDir for socket files
  ├─ for each socket file:
  │    ├─ filename starts with "agentstudio--" ? → probe it
  │    └─ connect, send Info, parse response
  │
  ▼
filter: sessions NOT in knownIds → orphans
  │
  ▼
kill each orphan via pool.client(for:).kill()
```

### Terminal State Snapshot (new capability)

```
Agent orchestrator or checkpoint timer
  │
  ▼
ZmxBackend.history(handle, format: .vt) → Data
  │
  ▼
pool.client(for: handle.id).history(format: .vt)  [async, @concurrent]
  │
  ├─ send Header(tag: 8, len: 1) + [0x01]
  ├─ read History response
  │    └─ payload = VT escape sequences (full terminal state)
  │
  ▼
return Data  (caller can inspect, save to disk, or replay)
```

## Error Handling

```swift
enum ZmxIPCError: Error {
    case notAvailable        // socket file missing or connection refused
    case timeout             // read timed out after all retries
    case protocolError       // malformed response (wrong size, unexpected tag)
    case disconnected        // daemon gone after reconnect attempts
}
```

**Reconnect policy:**

```
Attempt 1: immediate retry
Attempt 2: wait 100ms, retry
Attempt 3: wait 250ms, retry
Attempt 4: wait 500ms, retry (final)
  │
  └─ all failed → throw .disconnected
     pool marks client as dead
     next access creates fresh client
```

**Error mapping to existing API:**

| ZmxIPCError | SessionBackendError |
|-------------|-------------------|
| `.notAvailable` | `.notAvailable` |
| `.timeout` | `.timeout` |
| `.protocolError` | `.operationFailed(detail)` |
| `.disconnected` | `.notAvailable` |

Consumers of `ZmxBackend` see the same error types as before. The transport change is invisible.

## Testing Strategy

### Unit Tests (fast, no zmx process)

**Protocol encoding/decoding:**
```
ZmxIPCProtocolTests
  ├─ test_encodeHeader_correctBytes
  ├─ test_decodeHeader_fromBytes
  ├─ test_encodeResize_littleEndian
  ├─ test_decodeInfoStruct_correctFieldOffsets
  ├─ test_decodeInfoStruct_extractsCmdAndCwd
  ├─ test_decodeInfoStruct_handlesMaxLengthStrings
  └─ test_decodeInfoStruct_handlesTruncatedCmd
```

**Client with mock socketpair:**
```
ZmxIPCClientTests
  ├─ test_probe_returnsTrue_whenDaemonResponds
  ├─ test_probe_returnsFalse_onTimeout
  ├─ test_probe_returnsFalse_onConnectionRefused
  ├─ test_kill_closesConnection
  ├─ test_info_parsesResponse
  ├─ test_history_returnsVTData
  ├─ test_reconnect_onUnexpectedDisconnect
  ├─ test_reconnect_givesUpAfterMaxAttempts
  ├─ test_outputMessages_areDrained
  └─ test_concurrentRequests_dontCorrupt
```

Mock approach: use `socketpair(AF_UNIX, SOCK_STREAM, 0)` to create a connected pair. One end is the "daemon" (test controls it), the other is passed to `ZmxIPCClient`.

**Connection pool:**
```
ZmxIPCConnectionPoolTests
  ├─ test_clientFor_createsOnFirstAccess
  ├─ test_clientFor_reusesExistingClient
  ├─ test_disconnect_removesClient
  ├─ test_disconnectAll_closesEverything
  ├─ test_probeAll_enumeratesSocketDir
  └─ test_killOrphans_killsUnknownSessions
```

### Integration Tests (real zmx daemon)

```
ZmxIPCIntegrationTests
  ├─ test_connectToRealDaemon
  ├─ test_infoFromRealDaemon_returnsPid
  ├─ test_historyFromRealDaemon_returnsVTState
  ├─ test_killRealDaemon_terminatesProcess
  ├─ test_probeAll_findsRunningSessions
  └─ test_reconnectAfterDaemonRestart
```

These replace the current flaky E2E tests that shell out to `zmx` and parse stdout with timing-dependent waits.

## Future Capabilities (Stubs Only)

These methods will exist on `ZmxIPCClient` with `fatalError("not implemented")` bodies:

**Checkpoint/Restore:**
- `checkpoint() -> Data` — snapshot terminal state to disk periodically
- Could enable visual restoration after computer restart
- The History VT format provides the raw data; checkpoint adds scheduling and persistence

**Direct Resize:**
- `resize(rows: UInt16, cols: UInt16)` — send resize directly to daemon
- Could improve resize coordination, but has double-SIGWINCH concern
- Current SIGWINCH relay path works after the redraw=0 fix

## Migration Plan

1. Implement `ZmxIPCClient` and `ZmxIPCConnectionPool` in `Infrastructure/ZmxIPC/`
2. Add unit tests with mock socketpair
3. Add `ZmxIPCConnectionPool` to `ZmxBackend` alongside `ProcessExecutor`
4. Migrate operations one at a time: probe first, then kill, then discover
5. Add integration tests against real zmx daemons
6. Remove `ProcessExecutor` from `ZmxBackend` after all operations migrated
7. Wire up History capability for on-demand inspection

## File Inventory

| File | Location | Purpose |
|------|----------|---------|
| `ZmxIPCClient.swift` | `Infrastructure/ZmxIPC/` | Binary protocol, socket I/O, reconnect |
| `ZmxIPCConnectionPool.swift` | `Infrastructure/ZmxIPC/` | Connection lifecycle, bulk operations |
| `ZmxIPCProtocol.swift` | `Infrastructure/ZmxIPC/` | Header/tag/struct types, encode/decode |
| `ZmxIPCError.swift` | `Infrastructure/ZmxIPC/` | Error types |
| `ZmxIPCProtocolTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Protocol encode/decode tests |
| `ZmxIPCClientTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Client tests with mock socketpair |
| `ZmxIPCConnectionPoolTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Pool lifecycle tests |
| `ZmxIPCIntegrationTests.swift` | `Tests/.../Infrastructure/ZmxIPC/` | Real daemon tests |
| `ZmxBackend.swift` | `Core/Stores/` | Modified — swap transport |

## Constraints

- **macOS 26+ arm64 only** — usize is always 8 bytes, alignment is natural
- **Unix socket path limit** — 104 bytes max (sockaddr_un.sun_path - 1)
- **No zmx protocol changes** — we speak the existing protocol exactly
- **Output drain required** — daemon broadcasts to all clients, we must read and discard
- **Swift 6.2 concurrency** — `@concurrent nonisolated` for blocking socket I/O
