# Swift ↔ React Bridge Architecture

> **Target**: macOS 26 (Tahoe) · Swift 6.2 · WebKit for SwiftUI
> **Pattern**: Three-stream architecture with push-dominant state sync
> **First use case**: Diff viewer and code review with Pierre (@pierre/diffs, @pierre/file-tree)
> **Status**: Design spec

---

## 1. Overview

Agent Studio embeds React-based UI panels inside webview panes alongside native terminal panes. The bridge connects Swift (domain truth) to React (view layer) through three distinct data streams:

1. **State stream** (Swift → React): Small state pushes via `callJavaScript` into Zustand stores. Status updates, comments, file metadata, review state. Revision-stamped, ordered, stale-dropped.
2. **Data stream** (bidirectional): Large payloads via `agentstudio://` URL scheme. File contents fetched on demand by React when files enter the viewport. Pull-based, cancelable, priority-queued.
3. **Agent event stream** (Swift → React): Append-only activity events via batched `callJavaScript`. Sequence-numbered, batched at 30-50ms cadence. Agent started, file completed, task done.

React sends commands to Swift via `postMessage` (JSON-RPC 2.0 notifications with idempotent command IDs).

The diff viewer and code review system (powered by Pierre) is the first panel. It supports reviewing diffs from git commits, branch comparisons, and agent-generated snapshots. Future panels reuse the same bridge.

---

## 2. Architecture Principles

1. **Three tiers of state** — Swift domain state (authoritative), React mirror state (derived, normalized for UI), React local state (ephemeral: drafts, selection, scroll). Local state can be optimistic; domain state is confirmed by Swift.
2. **Three streams, not one pipe** — State stream for small pushes, data stream for large payloads, agent event stream for append-only activity. Each stream has different ordering, delivery, and backpressure characteristics.
3. **Metadata push, content pull** — Swift pushes file manifests (metadata) immediately. React pulls file contents on demand via the data stream when files enter the viewport. This keeps the state stream fast and memory bounded.
4. **Idempotent commands with acks** — React sends commands with a `commandId` (UUID). Swift deduplicates and acknowledges via state push. Enables optimistic local UI with rollback on rejection.
5. **Revision-ordered pushes** — Every push envelope carries a monotonic `revision` per store. React drops pushes with `revision <= lastSeen`. Combined with `epoch` for load cancellation.
6. **Testable at every layer** — Transport, protocol, push pipeline, stores — each layer has a clear contract and can be tested in isolation.

---

## 3. State Ownership Model

### 3.1 Three Tiers

```
┌──────────────────────────────────────────────────────┐
│  Tier 1: Swift Domain State (authoritative)           │
│  @Observable models, Codable, persisted               │
│                                                        │
│  • DiffManifest: file paths, sizes, hunk summaries    │
│  • File contents (served via data stream on demand)   │
│  • ReviewThread, ReviewComment, ReviewAction           │
│  • AgentTask: status, completed files, output refs     │
│  • TimelineEvent: immutable audit log                  │
│  • Observations AsyncSequence drives state stream     │
└──────────────┬─────────────────────────────────────────┘
               │
               │  STATE STREAM: callJavaScript → Zustand (small, frequent)
               │  DATA STREAM: agentstudio:// scheme (large, on demand)
               │  AGENT EVENTS: callJavaScript batched (append-only)
               │  COMMANDS: postMessage JSON-RPC (React → Swift)
               │
┌──────────────▼─────────────────────────────────────────┐
│  Tier 2: React Mirror State (derived from Swift)        │
│  Zustand stores, normalized for UI rendering            │
│                                                          │
│  • DiffManifest mirror (file list, statuses)            │
│  • File content LRU cache (~20 files in memory)         │
│  • Review threads + comments (normalized by ID)          │
│  • Agent task status                                     │
│  • Derived selectors (filtered files, comment counts)    │
│  • Revision-tracked: each store knows its last revision  │
└──────────────┬───────────────────────────────────────────┘
               │
               │  React components subscribe via selectors + useShallow
               │
┌──────────────▼───────────────────────────────────────────┐
│  Tier 3: React Local UI State (ephemeral)                 │
│  Component state, not persisted, not pushed to Swift      │
│                                                            │
│  • Draft comment text, cursor position                    │
│  • File tree expanded/collapsed nodes                     │
│  • Scroll position, selection, hover state                │
│  • Search/filter query (applied locally to manifest)      │
│  • Optimistic UI state (pending comment, pending action)   │
│  • Pierre rendering state (virtualizer, height caches)    │
└────────────────────────────────────────────────────────────┘
```

### 3.2 State Flow Rules

**Domain mutations flow through Swift**: React sends commands → Swift mutates domain state → state stream pushes update → React mirror updates → UI rerenders.

**Local state is optimistic**: When user adds a comment, React immediately shows it in the UI (tier 3, status: `pending`). When Swift confirms via state push, it moves to tier 2 (status: `committed`). If Swift rejects, React rolls back the optimistic state.

**Mirror state is derived, never mutated directly**: Zustand stores only update through the bridge receiver (state stream) or content loader (data stream). Components never call `setState` on mirror stores directly.

### 3.3 XPC Latency Characteristics

`callJavaScript` uses XPC (Mach message passing, same machine):

| Payload Size | Latency | Use Case |
|---|---|---|
| < 5 KB JSON | Sub-millisecond to ~1ms | Status updates, comment CRUD, file metadata |
| 5–50 KB | 1–5ms | DiffManifest (500 files ≈ 25KB), agent events batch |
| 50–500 KB | 5–20ms | Reserved for data stream (agentstudio://) |

A 60fps frame is 16.7ms. State stream payloads (<50KB) arrive within a single frame. File contents are pulled via the data stream, keeping the state stream fast.

> **Caveat**: These latency figures are estimates. Actual values must be validated during Phase 1 verification.

---

## 4. Transport Layer

### 4.1 Swift → JS: `callJavaScript`

Swift pushes into the **bridge content world**, which relays to the page world via `CustomEvent`:

```swift
// Swift calls into bridge world — page world cannot see this directly
try? await page.callJavaScript(
    "window.__bridgeInternal.merge(store, JSON.parse(data))",
    arguments: ["store": storeName, "data": jsonString],
    contentWorld: bridgeWorld   // WKContentWorld, NOT page world
)
```

- Async, returns `Any?`
- Arguments become JS local variables (safe — no string interpolation)
- `contentWorld: bridgeWorld` means this executes in the isolated bridge world
- The `in:` (frame) parameter defaults to main frame when omitted. Only specify it when targeting a specific sub-frame.
- Bridge world relays to page world (React) via `CustomEvent` (see §11.3)

**Important**: Swift never calls into the page world directly. All pushes go through bridge world → CustomEvent relay → page world Zustand stores.

### 4.2 JS → Swift: `postMessage` (via bridge world relay)

React (page world) **cannot** call `window.webkit.messageHandlers.rpc.postMessage()` directly — the handler is scoped to the bridge content world. Instead, React dispatches a `CustomEvent`, and the bridge world relays it:

```typescript
// Page world (React) — dispatches event with nonce
document.dispatchEvent(new CustomEvent('__bridge_command', {
    detail: { jsonrpc: "2.0", method: "diff.requestFileContents", params: { fileId: "abc123" }, __nonce: bridgeNonce }
}));
```

```javascript
// Bridge world — validates nonce, relays to Swift
document.addEventListener('__bridge_command', (e) => {
    if (e.detail?.__nonce !== bridgeNonce) return;
    const { __nonce, ...payload } = e.detail;
    window.webkit.messageHandlers.rpc.postMessage(JSON.stringify(payload));
});
```

- `userContentController.add(handler, contentWorld: bridgeWorld, name: "rpc")` — handler only exists in bridge world
- Bridge world validates nonce before relaying (see §11.3)
- Handler receives `WKScriptMessage` with JSON body

### 4.3 Binary Channel: `agentstudio://` URL Scheme

For large payloads (file contents > 50KB) where JSON serialization overhead matters:

```swift
struct BinarySchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Guard against nil URL — URLRequest.url is Optional.
                    // Global invariant #5: no force-unwraps in bridge code.
                    guard let url = request.url else {
                        continuation.finish(throwing: BridgeError.invalidRequest("Missing URL"))
                        return
                    }

                    let (data, mimeType) = try await resolveResource(for: request)

                    // Check for cancellation before yielding — WebKit cancels scheme tasks
                    // on navigation, page close, or when the resource is no longer needed.
                    // Ignoring cancellation wastes I/O and memory on abandoned file loads.
                    try Task.checkCancellation()

                    continuation.yield(.response(URLResponse(
                        url: url,
                        mimeType: mimeType,
                        expectedContentLength: data.count,
                        textEncodingName: nil
                    )))
                    continuation.yield(.data(data))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()  // Clean exit on cancellation
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Wire up AsyncStream cancellation to Task cancellation
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
```

> **Note on full-buffer load**: The current design loads the entire file into memory before yielding. For files > 1MB, consider streaming via chunked yields (e.g., 64KB chunks with `Task.checkCancellation()` between each). This is a future optimization — the initial implementation uses full-buffer load, which is acceptable since content pull requests are serialized per file and LRU-bounded (~20 files in cache).

React consumes via standard `fetch()`:
```typescript
const content = await fetch(`agentstudio://resource/file/${fileId}`);
const text = await content.text();
```

### 4.4 Three Streams Mapped to Transport

| Stream | Transport | Direction | Payload Size | Frequency | Ordering |
|---|---|---|---|---|---|
| **State** | `callJavaScript` | Swift → React | 1-50KB | On mutation, debounced | Revision + epoch per store |
| **Data** | `agentstudio://` | React → Swift → React | 50KB-5MB | On demand (viewport) | Request/response |
| **Agent events** | `callJavaScript` (batched) | Swift → React | 0.1-5KB per event, batched | During agent work, 30-50ms cadence | Sequence number per task |
| **Commands** | `postMessage` | React → Swift | 0.1-2KB | On user action | commandId for idempotency |

### 4.5 Bridge Ready Handshake

Before any stream can operate, the bridge must complete initialization. The handshake prevents push-before-listener races:

```
1. Swift loads page (agentstudio://app/index.html)
2. Bridge bootstrap runs in bridge world (installs __bridgeInternal, nonces)
3. React app mounts, bridge receiver initializes, subscribes to events
4. React dispatches '__bridge_ready' CustomEvent
5. Bridge world captures it, relays to Swift via postMessage({ type: "bridge.ready" })
6. Swift starts observation loops + pushes initial DiffManifest
```

No state pushes or commands are allowed before step 6 completes. The `BridgeCoordinator` gates on receiving `bridge.ready` before starting observation loops.

---

## 5. Protocol Layer

### 5.1 Commands (JS → Swift): JSON-RPC 2.0

Commands use JSON-RPC 2.0 **notifications** (no `id` field) with an additional `commandId` for idempotency and ack tracking. Responses arrive through state push, not as JSON-RPC responses.

```json
{
    "jsonrpc": "2.0",
    "method": "diff.requestFileContents",
    "params": { "fileId": "abc123" },
    "__commandId": "cmd_a1b2c3d4"
}
```

The `__commandId` (UUID, generated by React) enables:
- **Idempotency**: Swift deduplicates commands with the same `commandId` within a sliding window (last 100 commands).
- **Ack tracking**: Swift pushes a `commandAck` event in the state stream: `{ commandId, status: "ok" | "rejected", reason? }`. React uses this to confirm or roll back optimistic local UI state.

For the rare case where JS needs a **direct response** (one-shot queries, validation), include an `id` and Swift sends a JSON-RPC response via `callJavaScript`:

```json
// Request (JS → Swift)
{ "jsonrpc": "2.0", "id": "req_001", "method": "system.health", "params": {} }

// Response (Swift → JS, via callJavaScript)
{ "jsonrpc": "2.0", "id": "req_001", "result": { "status": "ok" } }
```

### 5.2 Method Namespaces

| Namespace | Examples | Description |
|---|---|---|
| `diff.*` | `diff.requestFileContents`, `diff.loadDiff` | Diff operations |
| `review.*` | `review.addComment`, `review.resolveThread`, `review.deleteComment` | Review lifecycle |
| `agent.*` | `agent.requestRewrite`, `agent.cancelTask`, `agent.injectPrompt` | Agent lifecycle |
| `git.*` | `git.status`, `git.fileTree` | Git operations |
| `system.*` | `system.health`, `system.capabilities`, `system.resyncAgentEvents` | System info + recovery |

### 5.3 Standard Error Codes

| Code | Meaning |
|---|---|
| -32700 | Parse error (invalid JSON) |
| -32600 | Invalid request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |
| -32000 to -32099 | Application-defined errors |

### 5.4 State Push Format (Swift → JS)

State pushes are NOT JSON-RPC. They are `callJavaScript` calls into the **bridge content world**, which relays to the page world via `CustomEvent`:

```swift
// Swift pushes into bridge world — __bridgeInternal relays via CustomEvent to page world
try await page.callJavaScript(
    "window.__bridgeInternal.merge(store, JSON.parse(data))",
    arguments: ["store": "diff", "data": jsonString],
    contentWorld: bridgeWorld
)

// Replace entire store state
try await page.callJavaScript(
    "window.__bridgeInternal.replace(store, JSON.parse(data))",
    arguments: ["store": "diff", "data": jsonString],
    contentWorld: bridgeWorld
)
```

The bridge world's `__bridgeInternal.merge/replace` dispatches a `CustomEvent('__bridge_push', ...)` which the page world (React) listens for (see §7.2 and §11.3).

**Push envelope metadata**: Each push includes version, correlation ID, and ordering fields:
- `__v: 1` — Push envelope version (bump on shape changes)
- `__pushId: "<uuid>"` — Correlation ID for tracing a push from Swift observation through JS merge to React rerender
- `__revision: <int>` — Monotonic counter per store. React drops pushes with `revision <= lastSeen`. Prevents out-of-order delivery.
- `__epoch: <int>` — Load generation counter. Incremented when a new diff source is loaded. React discards pushes from stale epochs.

These are passed as additional arguments to `__bridgeInternal.merge/replace` and forwarded in the `CustomEvent` detail. The receiver uses `__revision` and `__epoch` for ordering/staleness; `__pushId` and `__v` are for debugging only.

### 5.5 JSON-RPC Batch Requests

The [JSON-RPC 2.0 spec](https://www.jsonrpc.org/specification) defines batch requests (array of request objects). This bridge does **not support batching** in the initial implementation:

- **Batch requests are rejected** with a single `-32600` (Invalid Request) error response
- **Rationale**: Our command channel is predominantly fire-and-forget notifications. The rare request/response path handles one request at a time. Batch support adds complexity (mixed request+notification handling, partial failure, notification-only batches returning no response) without clear benefit for the diff viewer use case
- **Future**: If a panel needs to send multiple related commands atomically, batch support can be added to `RPCRouter.dispatch()` by detecting array input and dispatching each element individually, collecting responses for requests and suppressing responses for notifications

```swift
// RPCRouter.dispatch — reject batches before full envelope decode.
// Use JSONSerialization to detect array (batch) vs object (single) reliably.
// This handles leading whitespace, BOM, etc. that hasPrefix("[") would miss.
if let rawData = json.data(using: .utf8),
   let parsed = try? JSONSerialization.jsonObject(with: rawData),
   parsed is [Any] {
    // Batch request detected — extract first id for the error response
    if let array = parsed as? [[String: Any]],
       let firstId = array.first?["id"] as? String {
        await coordinator.sendError(id: firstId, code: -32600, message: "Batch requests not supported")
    }
    // No id found → drop silently (batch of notifications)
    return
}
```

### 5.6 Agent Event Stream Protocol

Agent events use a separate relay path from state pushes. They are append-only (never merged or replaced) and carry sequence numbers for gap detection.

**Transport**: `callJavaScript` into bridge content world, relayed via `CustomEvent('__bridge_agent', ...)` to page world.

```swift
// Swift pushes agent events into bridge world
try await page.callJavaScript(
    "window.__bridgeInternal.appendAgentEvents(JSON.parse(data))",
    arguments: ["data": batchJsonString],
    contentWorld: bridgeWorld
)
```

**Envelope format**:
```json
{
    "__v": 1,
    "__pushId": "<uuid>",
    "__pushNonce": "<bootstrap-nonce>",
    "__epoch": 3,
    "events": [
        { "seq": 42, "kind": "fileCompleted", "taskId": "...", "payload": { "fileId": "abc" }, "timestamp": "..." },
        { "seq": 43, "kind": "taskProgress", "taskId": "...", "payload": { "completedFiles": 5, "currentFile": "src/foo.ts" }, "timestamp": "..." }
    ]
}
```

**Security**: Agent event envelopes include `__pushNonce` and are validated identically to state pushes (see §11.3). The bridge world's `__bridgeInternal.appendAgentEvents` validates the nonce before dispatching the `__bridge_agent` CustomEvent to the page world. This prevents page-world scripts from forging agent events.

**Ordering and delivery**:
- `seq` is a monotonic per-pane counter (atomically incremented on `@MainActor`). React tracks `lastSeq` and detects gaps.
- Events are batched at 30-50ms cadence on the Swift side before pushing. Multiple events within a batch window are sent in a single `callJavaScript` call.
- On gap detection (`incoming seq > lastSeq + 1`), React sends a `system.resyncAgentEvents` **request** (with JSON-RPC `id`) carrying `{ fromSeq: lastSeq + 1 }`. Swift responds with the missed events via the direct-response path (`__bridge_response` CustomEvent, see §7.4). This is one of the few methods that uses request/response instead of notification.
- On epoch mismatch, React clears its agent event store and resets `lastSeq = 0`.

**In-memory buffer**: Swift maintains a circular buffer of the last 10,000 agent events per pane. Oldest events are evicted on overflow (FIFO). If `fromSeq` falls outside the buffer range, the resync response includes `{ truncated: true }` and React resets to the earliest available event.

**Event kinds**: `taskStarted`, `taskProgress`, `fileCompleted`, `taskCompleted`, `taskFailed`, `agentMessage`.

---

## 6. State Push Pipeline

### 6.1 Observations AsyncSequence (Swift 6.2)

Swift 6.2's `Observations` type replaces the `withObservationTracking` re-register loop. Key behaviors:

- **Transactional coalescing**: Multiple synchronous mutations yield ONCE with the final value
- **Auto-re-registers**: No manual re-tracking needed
- **Multi-property tracking**: Any accessed property triggers a yield
- **No backpressure**: Slow consumers see latest value, skip intermediates

```swift
func watchDiffState() async {
    let changes = Observations { [weak self] in
        guard let self else { return nil as DiffState? }
        return self.domainState.diff
    }

    for await diffState in changes.compactMap({ $0 }) {
        await pushToJS(store: "diff", value: diffState)
    }
}
```

### 6.2 Push Coalescing Strategy

Even with `Observations` transactional coalescing, rapid async updates (status changes, review thread mutations) can produce many yields. Use frame-aligned debouncing:

```swift
func watchDiffState() async {
    let changes = Observations { [weak self] in
        self?.domainState.diff
    }

    // Debounce to ~1 frame (16ms) to batch rapid async updates
    for await diffState in changes.compactMap({ $0 }).debounce(for: .milliseconds(16)) {
        await pushToJS(store: "diff", value: diffState)
    }
}
```

> **Dependency**: `.debounce(for:)` is NOT built into `Observations` or the standard library `AsyncSequence`. It requires the **[swift-async-algorithms](https://github.com/apple/swift-async-algorithms)** package (`import AsyncAlgorithms`). Add this as a Package.swift dependency.

> **Intermediate state visibility**: Per [SE-0475](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md), `Observations` uses transactional coalescing — when the producer outpaces the consumer, intermediate states are skipped and only the latest value is yielded. This means rapid `.pending → .loading → .loaded` transitions on `DiffFile.status` may skip the `.loading` state in the push pipeline. **Mitigation**: Use a separate, non-debounced observation loop for status-only changes (see §6.3 granular observation), ensuring the UI can show loading indicators even during fast loads.

For hot scalar state (connection health, agent status), skip debouncing — push immediately:

```swift
func watchConnectionState() async {
    let changes = Observations { [weak self] in
        self?.domainState.connection
    }

    for await state in changes.compactMap({ $0 }) {
        await pushToJS(store: "connection", value: state)
    }
}
```

### 6.3 Granular Observation

Observe at the right granularity to avoid pushing the entire world on every change:

| What to observe | Push scope | Why |
|---|---|---|
| `diff.files` (the map) | Whole files map | Additions/removals affect file list |
| `diff.files[id].status` | Single file status | Loading indicator per file |
| `diff.files[id].oldContent` | Single file content | Large payload, push individually |
| `diff.comments` | All comments | Small, push whole |
| `agent.status` | Scalar | Hot state, no debounce |

Implementation uses multiple observation loops, each watching a specific slice:

```swift
func startObservationLoops() async {
    await withTaskGroup(of: Void.self) { group in
        // File list changes (additions, removals, reorders)
        group.addTask { await self.watchFileList() }

        // Per-file content loading (granular, debounced)
        group.addTask { await self.watchFileContents() }

        // Comments (small, push whole)
        group.addTask { await self.watchComments() }

        // Connection health (hot, no debounce)
        group.addTask { await self.watchConnectionState() }
    }
}
```

### 6.4 Push Serialization

```swift
private func pushToJS<T: Codable>(store: String, value: T) async {
    do {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            logger.error("[Bridge] Failed to encode \(store) state as UTF-8")
            return
        }

        // Push into bridge world → __bridgeInternal relays via CustomEvent to page world
        try await page.callJavaScript(
            "window.__bridgeInternal.merge(store, JSON.parse(data))",
            arguments: ["store": store, "data": json],
            contentWorld: bridgeWorld
        )
    } catch let encodingError as EncodingError {
        logger.error("[Bridge] Encoding failed for \(store): \(encodingError)")
    } catch {
        // callJavaScript failure — page may be unloaded or navigating
        logger.warning("[Bridge] Push to \(store) failed: \(error)")
        sharedState.connection.health = .error
    }
}
```

**Error strategy**: Encoding failures are logged and skipped (data model bug — should not happen in production). `callJavaScript` failures update connection health state, which React can display. No crashes.

### 6.5 Push Cost Considerations

The push pipeline involves three CPU-bound steps per push: (1) Swift `JSONEncoder.encode()`, (2) JS `JSON.parse()`, (3) JS `deepMerge()`. For large state (100+ file diff with contents), this can spike CPU and drive rerender fanout.

**Mitigations**:

| Strategy | When | Effect |
|---|---|---|
| **Metadata-only pushes** (§10.1) | Diff loaded | Push `DiffManifest` (file list + metadata), NOT file contents |
| **Content pull on demand** (§10.2) | File enters viewport | React fetches via `agentstudio://resource/file/{id}` — no state stream overhead |
| **Debounced observation** (§6.2) | Rapid mutations | Coalesce multiple changes into one push |
| **Batched agent events** (§4.4) | Agent activity | 30-50ms batching cadence, append-only |
| **LRU content cache** (§10.4) | Memory pressure | ~20 files in React memory, oldest evicted |

**Measurement requirement**: Phase 2 testing must include a benchmark: push a 100-file `DiffManifest` (metadata only, no file contents), measure end-to-end time from Swift mutation to React rerender. Target: < 32ms (2 frames). File contents are never pushed via the state stream — they're served on demand via the data stream.

---

## 7. React State Layer (Zustand)

### 7.1 Store Design

One Zustand store per domain. Each store mirrors its Swift `@Observable` counterpart:

```typescript
// stores/diff-store.ts
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

interface DiffFile {
    id: string;
    path: string;
    oldPath: string | null;
    changeType: 'added' | 'modified' | 'deleted' | 'renamed';
    status: 'pending' | 'loading' | 'loaded' | 'error';
    oldContent: string | null;
    newContent: string | null;
    size: number;
}

// Tier 2 mirror: DiffManifest store (pushed via state stream)
interface DiffStore {
    source: DiffSource | null;
    manifest: FileManifest[] | null;
    epoch: number;
    status: 'idle' | 'loadingManifest' | 'manifestReady' | 'error';
    error: string | null;
    lastRevision: number;           // tracks last accepted push revision
}

interface FileManifest {
    id: string;
    path: string;
    oldPath: string | null;
    changeType: 'added' | 'modified' | 'deleted' | 'renamed';
    loadStatus: 'pending' | 'loading' | 'loaded' | 'error';
    additions: number;
    deletions: number;
    size: number;
    contextHash: string;
    hunkSummary: HunkSummary[];
}

// Tier 2 mirror: Review store (pushed via state stream)
interface ReviewStore {
    threads: Record<string, ReviewThread>;
    viewedFiles: Set<string>;
    lastRevision: number;
}

interface ReviewThread {
    id: string;
    fileId: string;
    anchor: { side: 'old' | 'new'; line: number; contextHash: string };
    state: 'open' | 'resolved';
    isOutdated: boolean;
    comments: ReviewComment[];
}

interface ReviewComment {
    id: string;
    author: { type: 'user' | 'agent'; name: string };
    body: string;
    createdAt: string;
    editedAt: string | null;
}

export const useDiffStore = create<DiffStore>()(
    devtools(
        () => ({
            source: null,
            manifest: null,
            epoch: 0,
            status: 'idle',
            error: null,
        }),
        { name: 'diff-store' }
    )
);
```

```typescript
// stores/connection-store.ts
interface ConnectionStore {
    health: 'connected' | 'disconnected' | 'error';
    latencyMs: number;
}

export const useConnectionStore = create<ConnectionStore>()(
    devtools(
        () => ({
            health: 'connected',
            latencyMs: 0,
        }),
        { name: 'connection-store' }
    )
);
```

### 7.2 Bridge Receiver

React (page world) listens for `CustomEvent` dispatched by the bridge world relay. It does NOT access `window.__bridgeInternal` directly — that global exists only in the bridge content world.

Push events are authenticated via a **push nonce** delivered through a one-time handshake at bootstrap (see §11.3 for full security rationale).

```typescript
// bridge/receiver.ts — page world, listens for CustomEvents from bridge world
import { useDiffStore } from '../stores/diff-store';
import { useConnectionStore } from '../stores/connection-store';
import { deepMerge } from '../utils/deep-merge';

const stores: Record<string, { setState: (updater: (prev: any) => any) => void }> = {
    diff: useDiffStore,
    connection: useConnectionStore,
};

// Capture push nonce from one-time handshake (bridge world dispatches this at bootstrap)
let _pushNonce: string | null = null;
document.addEventListener('__bridge_handshake', ((e: CustomEvent) => {
    if (_pushNonce === null) {  // Accept only the first handshake
        _pushNonce = e.detail.pushNonce;
    }
}) as EventListener, { once: true });

// Listen for state pushes relayed from bridge world via CustomEvent
document.addEventListener('__bridge_push', ((e: CustomEvent) => {
    // Reject forged push events from page-world scripts
    if (e.detail?.__pushNonce !== _pushNonce) return;

    const { type, store: storeName, data } = e.detail;
    const store = stores[storeName];
    if (!store) {
        console.warn(`[bridge] Unknown store: ${storeName}`);
        return;
    }

    if (type === 'merge') {
        store.setState((prev) => deepMerge(prev, data));
    } else if (type === 'replace') {
        store.setState(() => data);
    }
}) as EventListener);

// Listen for direct JSON-RPC responses (rare path)
document.addEventListener('__bridge_response', ((e: CustomEvent) => {
    if (e.detail?.__pushNonce !== _pushNonce) return;  // Same nonce validation
    rpcClient.handleResponse(e.detail);
}) as EventListener);
```

### 7.3 Command Sender

Typed command functions that send JSON-RPC notifications to Swift via CustomEvent relay (page world cannot access `window.webkit.messageHandlers` directly — see §4.2):

```typescript
// bridge/commands.ts

// Lazy nonce reader — avoids startup race where bootstrap hasn't set the
// data-bridge-nonce attribute yet. Reads on first command, caches thereafter.
let _cachedNonce: string | null = null;
function getBridgeNonce(): string | null {
    if (_cachedNonce === null) {
        _cachedNonce = document.documentElement.getAttribute('data-bridge-nonce');
    }
    return _cachedNonce;
}

function sendCommand(method: string, params?: unknown): void {
    const nonce = getBridgeNonce();
    if (!nonce) {
        console.warn('[bridge] Nonce not available — command dropped:', method);
        return;  // Bridge not ready yet; caller should retry or queue
    }
    document.dispatchEvent(new CustomEvent('__bridge_command', {
        detail: { jsonrpc: "2.0", method, params, __nonce: nonce }
    }));
}

export const commands = {
    diff: {
        load: (source: DiffSource) =>
            sendCommand("diff.loadDiff", { source }),
        requestFileContents: (fileId: string) =>
            sendCommand("diff.requestFileContents", { fileId }),
    },
    review: {
        addComment: (fileId: string, lineNumber: number | null, side: 'old' | 'new', text: string) =>
            sendCommand("review.addComment", { fileId, lineNumber, side, text }),
        resolveThread: (threadId: string) =>
            sendCommand("review.resolveThread", { threadId }),
        unresolveThread: (threadId: string) =>
            sendCommand("review.unresolveThread", { threadId }),
        deleteComment: (commentId: string) =>
            sendCommand("review.deleteComment", { commentId }),
        markFileViewed: (fileId: string) =>
            sendCommand("review.markFileViewed", { fileId }),
        unmarkFileViewed: (fileId: string) =>
            sendCommand("review.unmarkFileViewed", { fileId }),
    },
    agent: {
        requestRewrite: (params: { source: { type: string; threadIds: string[] }; prompt: string }) =>
            sendCommand("agent.requestRewrite", params),
        cancelTask: (taskId: string) =>
            sendCommand("agent.cancelTask", { taskId }),
        injectPrompt: (text: string) =>
            sendCommand("agent.injectPrompt", { text }),
    },
    system: {
        health: () =>
            sendCommand("system.health"),
        resyncAgentEvents: (fromSeq: number) =>
            sendRequest("system.resyncAgentEvents", { fromSeq }),
    },
} as const;
```

### 7.4 RPC Client (for rare direct-response cases)

```typescript
// bridge/rpc-client.ts

interface PendingRequest {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
    timeout: ReturnType<typeof setTimeout>;
}

class RPCClient {
    private pending = new Map<string, PendingRequest>();
    private counter = 0;

    request<T>(method: string, params?: unknown, timeoutMs = 5000): Promise<T> {
        const id = `req_${++this.counter}`;
        const message = JSON.stringify({ jsonrpc: "2.0", id, method, params });

        return new Promise<T>((resolve, reject) => {
            const timeout = setTimeout(() => {
                this.pending.delete(id);
                reject(new Error(`RPC timeout: ${method}`));
            }, timeoutMs);

            this.pending.set(id, {
                resolve: resolve as (v: unknown) => void,
                reject,
                timeout,
            });

            // Use CustomEvent relay — page world cannot call postMessage directly
            // Reuse lazy nonce from commands.ts (getBridgeNonce)
            const nonce = getBridgeNonce();
            if (!nonce) {
                clearTimeout(timeout);
                this.pending.delete(id);
                reject(new Error('Bridge nonce not available'));
                return;
            }
            document.dispatchEvent(new CustomEvent('__bridge_command', {
                detail: { jsonrpc: "2.0", id, method, params, __nonce: nonce }
            }));
        });
    }

    handleResponse(raw: { id: string; result?: unknown; error?: { code: number; message: string } }) {
        const entry = this.pending.get(raw.id);
        if (!entry) return;
        this.pending.delete(raw.id);
        clearTimeout(entry.timeout);

        if (raw.error) {
            entry.reject(new Error(`[${raw.error.code}] ${raw.error.message}`));
        } else {
            entry.resolve(raw.result);
        }
    }
}

export const rpcClient = new RPCClient();
```

### 7.5 React Hooks

```typescript
// hooks/use-diff-files.ts
export function useDiffFiles() {
    return useDiffStore((s) => ({
        files: s.files,
        fileOrder: s.fileOrder,
        status: s.status,
    }));
}

// hooks/use-file-content.ts
export function useFileContent(fileId: string) {
    const file = useDiffStore((s) => s.files[fileId]);
    const status = file?.status;

    // Request content if not loaded
    useEffect(() => {
        if (status === 'pending') {
            commands.diff.requestFileContents(fileId);
        }
    }, [fileId, status]);

    return file;
}

// hooks/use-file-comments.ts
export function useFileComments(fileId: string) {
    return useDiffStore((s) => s.comments[fileId] ?? []);
}
```

### 7.6 External Store Rendering Caveats

Zustand is an external store relative to React's rendering cycle. Frequent bridge pushes create specific rendering risks:

1. **Unstable selectors cause rerender storms** — A selector like `useDiffStore((s) => s.files)` returns a new object reference on every push (even if the nested content is unchanged). Use `useShallow` from `zustand/react/shallow` for object/array selectors:
   ```typescript
   import { useShallow } from 'zustand/react/shallow';
   // Shallow-compare prevents rerenders when file references haven't changed
   const files = useDiffStore(useShallow((s) => s.files));
   ```

2. **Selector identity with dynamic keys** — `useDiffStore((s) => s.files[fileId])` creates a new selector function on every render if `fileId` changes. Memoize with `useCallback` or extract a stable selector factory.

3. **Transition tearing** — During React concurrent rendering, a push mid-render can cause tearing (different components reading different state versions). Zustand's `useSyncExternalStore` integration handles this, but custom subscription patterns (raw `store.subscribe()`) must return immutable snapshots. See [React useSyncExternalStore caveats](https://react.dev/reference/react/useSyncExternalStore).

4. **deepMerge must produce new references** — The `deepMerge` implementation must create new object references for changed branches (not mutate in place), or React won't detect changes. Use structural sharing: only clone paths that differ.

5. **CustomEvent typing** — Extend `DocumentEventMap` for type-safe event listeners. Without this, all `addEventListener('__bridge_push', ...)` calls need `as EventListener` casts:
   ```typescript
   // types/bridge-events.d.ts
   interface BridgePushDetail { type: 'merge' | 'replace'; store: string; data: unknown }
   interface BridgeResponseDetail { id: string; result?: unknown; error?: { code: number; message: string } }

   declare global {
       interface DocumentEventMap {
           '__bridge_push': CustomEvent<BridgePushDetail>;
           '__bridge_response': CustomEvent<BridgeResponseDetail>;
           '__bridge_command': CustomEvent<Record<string, unknown>>;
       }
   }
   ```

### 7.7 deepMerge Specification

The `deepMerge(target, source)` function used in the bridge receiver (§7.2) must satisfy these contracts:

```typescript
// utils/deep-merge.ts
function deepMerge<T extends Record<string, unknown>>(target: T, source: Partial<T>): T {
    // 1. Returns new root object (never mutates target)
    // 2. Recursively merges nested objects (creates new refs only for changed branches)
    // 3. Arrays are REPLACED, not merged (file list reorder = new array)
    // 4. null/undefined values in source DELETE the key from target
    // 5. Primitives are overwritten
}
```

**Implementation note**: Consider using a proven library like `immer` or `structuredClone` + manual merge rather than a custom implementation. Custom deepMerge is a common source of subtle bugs.

---

## 8. Swift Domain Model

### 8.1 State Scope: Per-Pane vs Shared

Domain state is split into two categories:

**Per-pane state** — Each webview pane gets its own instance. Two diff panes showing different branches have independent state:

```swift
@Observable
@MainActor
class PaneDomainState {
    var diff: DiffState = .init()
    var review: ReviewState = .init()
    var agentTasks: [UUID: AgentTask] = [:]
    var timeline: [TimelineEvent] = []    // in-memory v1, .jsonl v2
}
```

**Shared state** — Singleton, shared across all panes. Connection health, system capabilities:

```swift
@Observable
@MainActor
class SharedBridgeState {
    var connection: ConnectionState = .init()
}
```

**Ownership**: `BridgeCoordinator` owns one `PaneDomainState` and holds a reference to the singleton `SharedBridgeState`. Each pane's observation loops push both per-pane and shared state into their respective Zustand stores.

### 8.2 Diff Source and Manifest

The diff viewer supports three data sources, all producing the same review UI:

```swift
enum DiffSource: Codable {
    case none
    case agentSnapshot(taskId: UUID, timestamp: Date)  // agent produced this
    case commit(sha: String)                            // single commit review
    case branchDiff(head: String, base: String)         // branch comparison
}
```

The diff loading pipeline takes a `DiffSource` and produces a `DiffManifest` — lightweight file metadata pushed via the state stream. File contents are NOT included; they're fetched on demand via the data stream.

```swift
struct DiffManifest: Codable {
    let source: DiffSource
    let epoch: Int                          // incremented on new diff load
    let files: [FileManifest]               // ordered list of changed files
}

struct FileManifest: Codable, Identifiable {
    let id: String
    let path: String
    let oldPath: String?                    // for renames
    let changeType: FileChangeType
    var loadStatus: FileLoadStatus
    let additions: Int                      // line count
    let deletions: Int                      // line count
    let size: Int                           // bytes, for threshold decisions
    let contextHash: String                 // hash of file content for comment anchoring
    let hunkSummary: [HunkSummary]          // line ranges that changed
}

struct HunkSummary: Codable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String?                     // e.g., "func loadDiff()"
}

enum FileChangeType: String, Codable {
    case added, modified, deleted, renamed
}

enum FileLoadStatus: String, Codable {
    case pending     // metadata known, content not yet requested
    case loading     // content fetch in progress
    case loaded      // content available via data stream
    case error       // content fetch failed
}
```

### 8.3 Diff State

```swift
@Observable
class DiffState {
    var source: DiffSource = .none
    var manifest: DiffManifest? = nil       // pushed via state stream
    var status: DiffStatus = .idle
    var error: String? = nil
    var epoch: Int = 0                      // current load generation
}

enum DiffStatus: String, Codable {
    case idle
    case loadingManifest                    // computing file list from git
    case manifestReady                      // file list available, contents on demand
    case error
}
```

**Note**: File contents are NOT stored in `DiffState`. They're served on demand via `agentstudio://resource/file/{id}` and cached in React's tier 2 mirror state (LRU of ~20 files). This keeps the state stream fast and Swift memory bounded.

### 8.4 Review Domain Objects

```swift
/// A comment thread anchored to a specific location in the diff.
/// Anchored by content hash, not just line number, so comments survive line shifts.
struct ReviewThread: Codable, Identifiable {
    let id: UUID
    let fileId: String
    let anchor: CommentAnchor
    var state: ThreadState
    var isOutdated: Bool                    // true when contextHash no longer matches
    var comments: [ReviewComment]
}

struct CommentAnchor: Codable {
    let side: DiffSide                      // .old or .new
    let line: Int                           // line number at time of comment
    let contextHash: String                 // hash of surrounding ±3 lines
}

enum ThreadState: String, Codable {
    case open
    case resolved
}

struct ReviewComment: Codable, Identifiable {
    let id: UUID
    let author: CommentAuthor
    var body: String
    let createdAt: Date
    var editedAt: Date?
}

enum DiffSide: String, Codable { case old, new }

struct CommentAuthor: Codable {
    let type: AuthorType
    let name: String
    enum AuthorType: String, Codable { case user, agent }
}

/// User actions on review threads and files.
enum ReviewAction: Codable {
    case resolveThread(threadId: UUID)
    case unresolveThread(threadId: UUID)
    case markFileViewed(fileId: String)
    case unmarkFileViewed(fileId: String)
}

/// Aggregate review state for the pane.
@Observable
class ReviewState: Codable {
    var threads: [UUID: ReviewThread] = [:]
    var viewedFiles: Set<String> = []       // file IDs marked as viewed
}
```

### 8.5 Agent Task

```swift
/// A durable record of an agent task (e.g., "rewrite this function").
/// Created when user requests agent work, survives across pushes.
struct AgentTask: Codable, Identifiable {
    let id: UUID
    let source: AgentTaskSource
    let prompt: String
    var status: AgentTaskStatus
    var modifiedFiles: [String]             // file IDs the agent changed
    let createdAt: Date
    var completedAt: Date?
}

enum AgentTaskSource: Codable {
    case thread(threadId: UUID)             // spawned from a comment thread
    case selection(fileId: String, lineRange: ClosedRange<Int>)  // spawned from a selection
    case manual(description: String)        // user-initiated from command bar
}

enum AgentTaskStatus: Codable {
    case queued
    case running(completedFiles: [String], currentFile: String?)
    case done
    case failed(error: String)
}
```

### 8.6 Timeline Event

```swift
/// Immutable audit log entry. In-memory for v1, .jsonl persistence for v2.
struct TimelineEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: TimelineEventKind
    let metadata: [String: AnyCodableValue]  // flexible payload per event type
}

enum TimelineEventKind: String, Codable {
    case commentAdded
    case commentResolved
    case fileViewed
    case agentTaskQueued
    case agentTaskCompleted
    case agentTaskFailed
    case diffLoaded
    case reviewSubmitted
}
```

### 8.7 Connection State

```swift
@Observable
class ConnectionState: Codable {
    var health: ConnectionHealth = .connected
    var latencyMs: Int = 0
    enum ConnectionHealth: String, Codable { case connected, disconnected, error }
}
```

### 8.8 Codable Conformance

All domain types conform to `Codable` for JSON serialization across the bridge. `@Observable` classes use the macro's auto-generated `Codable` conformance. `AnyCodableValue` (existing in `PaneContent.swift`) is reused for flexible metadata fields.

---

## 9. Swift Bridge Coordinator

### 9.1 Bridge Coordinator

One coordinator per WebPage (per pane). Owns its `PaneDomainState`, holds a reference to shared state:

```swift
@Observable
@MainActor
class BridgeCoordinator {
    let page: WebPage
    let paneState: PaneDomainState
    let sharedState: SharedBridgeState
    private let router: RPCRouter
    private let encoder = JSONEncoder()
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    private var observationTask: Task<Void, Never>?

    init(sharedState: SharedBridgeState) {
        self.paneState = PaneDomainState()
        self.sharedState = sharedState

        var config = WebPage.Configuration()

        // Register message handler in bridge world only
        config.userContentController.add(RPCMessageHandler(coordinator: self),
                                         contentWorld: bridgeWorld,
                                         name: "rpc")

        // Register binary scheme handler
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BinarySchemeHandler()
        }

        self.page = WebPage(configuration: config)
        self.router = RPCRouter()

        Task { await registerHandlers() }
    }

    func loadApp() {
        let url = URL(string: "agentstudio://app/index.html")!
        page.load(URLRequest(url: url))

        // Start observation loops after page loads
        observationTask = Task {
            // Wait for page ready
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
            await startObservationLoops()
        }
    }

    func handleCommand(json: String) async {
        await router.dispatch(json: json, coordinator: self)
    }

    /// Send a JSON-RPC success response to JS (rare direct-response path)
    func sendResponse(id: String, result: Data) async {
        let json = """
        {"jsonrpc":"2.0","id":"\(id)","result":\(String(data: result, encoding: .utf8) ?? "null")}
        """
        try? await page.callJavaScript(
            "window.__bridgeInternal.response(JSON.parse(json))",
            arguments: ["json": json],
            contentWorld: bridgeWorld
        )
    }

    /// Send a JSON-RPC error response to JS
    func sendError(id: String, code: Int, message: String) async {
        let json = """
        {"jsonrpc":"2.0","id":"\(id)","error":{"code":\(code),"message":"\(message)"}}
        """
        try? await page.callJavaScript(
            "window.__bridgeInternal.response(JSON.parse(json))",
            arguments: ["json": json],
            contentWorld: bridgeWorld
        )
    }

    func teardown() {
        observationTask?.cancel()
    }

    // MARK: - Page Lifecycle

    /// Handle WebPage termination events (page close, web process crash, navigation failure).
    /// WebPage can terminate due to: pageClosed, provisional navigation failure, or
    /// web-content process termination. The bridge must detect these, update health state,
    /// and cleanly tear down observation loops.
    func handlePageTermination(reason: PageTerminationReason) {
        sharedState.connection.health = .disconnected
        observationTask?.cancel()
        observationTask = nil

        switch reason {
        case .webProcessCrash:
            logger.error("[Bridge] Web content process crashed — bridge disconnected")
            // Optionally trigger reload after delay
        case .pageClosed:
            logger.info("[Bridge] Page closed — bridge torn down")
        case .navigationFailure:
            logger.warning("[Bridge] Navigation failed — bridge disconnected")
        }
    }

    enum PageTerminationReason {
        case webProcessCrash
        case pageClosed
        case navigationFailure
    }

    /// Resume observation loops after page reload (e.g., after web process crash recovery).
    /// Re-pushes full state to ensure React is synchronized.
    func resumeAfterReload() {
        guard observationTask == nil else { return }
        sharedState.connection.health = .connected

        observationTask = Task {
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
            // Full state re-push on reload to sync React
            await pushFullState()
            await startObservationLoops()
        }
    }
}
```

### 9.2 RPC Router

```swift
actor RPCRouter {
    private var handlers: [String: AnyMethodHandler] = [:]

    func register<M: RPCMethod>(_ type: M.Type,
                                handler: @escaping (M.Params) async throws -> Void) {
        handlers[M.method] = AnyMethodHandler { paramsData in
            let params: M.Params
            if let paramsData {
                params = try JSONDecoder().decode(M.Params.self, from: paramsData)
            } else if M.Params.self == EmptyParams.self {
                params = EmptyParams() as! M.Params
            } else {
                throw DecodingError.valueNotFound(M.Params.self,
                    .init(codingPath: [], debugDescription: "Missing required params"))
            }
            try await handler(params)
            return nil  // Notification handler — no direct response data
        }
    }

    /// For methods that need a direct response (rare)
    func registerWithResponse<M: RPCMethod>(_ type: M.Type,
                                            handler: @escaping (M.Params) async throws -> M.Result) {
        handlers[M.method] = AnyMethodHandler { paramsData in
            let params: M.Params
            if let paramsData {
                params = try JSONDecoder().decode(M.Params.self, from: paramsData)
            } else if M.Params.self == EmptyParams.self {
                params = EmptyParams() as! M.Params
            } else {
                throw DecodingError.valueNotFound(M.Params.self,
                    .init(codingPath: [], debugDescription: "Missing required params"))
            }
            let result = try await handler(params)
            return try JSONEncoder().encode(result)
        }
    }

    func dispatch(json: String, coordinator: BridgeCoordinator) async {
        // Step 1: Try to extract `id` from raw JSON for error responses.
        // We need the id BEFORE full envelope decode so parse errors can still
        // produce a valid JSON-RPC error response (spec §5.1).
        let rawId = extractId(from: json)

        // Step 2: Parse JSON-RPC envelope
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RPCEnvelope.self, from: data) else {
            // Parse error — send -32700 if request had an id
            if let id = rawId {
                await coordinator.sendError(id: id, code: -32700, message: "Parse error")
            }
            // No id (notification or completely broken) → drop silently per spec
            return
        }

        // Step 3: Find handler
        guard let handler = handlers[envelope.method] else {
            // Method not found — send -32601 if request has id
            if let id = envelope.id {
                await coordinator.sendError(id: id, code: -32601, message: "Method not found: \(envelope.method)")
            }
            // No id → notification for unknown method, drop silently
            return
        }

        // Step 4: Execute handler
        do {
            // Handle missing params — valid per JSON-RPC 2.0 (params is optional).
            // When params is nil, pass nil to the handler. The AnyMethodHandler
            // checks for nil and uses the method's default (EmptyParams for no-param
            // methods, or throws DecodingError for methods requiring params).
            let paramsData: Data?
            if let params = envelope.params {
                paramsData = try JSONEncoder().encode(params)
            } else {
                paramsData = nil  // Distinct from Data("{}".utf8) — lets handler decide
            }
            let responseData = try await handler.handle(paramsData)

            // If request has id, send direct response
            if let id = envelope.id, let responseData {
                await coordinator.sendResponse(id: id, result: responseData)
            }
        } catch let error as DecodingError {
            // Invalid params — send -32602 if request has id
            if let id = envelope.id {
                await coordinator.sendError(id: id, code: -32602, message: "Invalid params: \(error.localizedDescription)")
            }
        } catch {
            // Internal error — send -32603 if request has id
            if let id = envelope.id {
                await coordinator.sendError(id: id, code: -32603, message: "Internal error")
            }
        }
    }

    /// Best-effort extraction of "id" from raw JSON string before full decode.
    /// Returns nil if the JSON doesn't contain a parseable "id" field.
    private func extractId(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] else { return nil }
        if let stringId = id as? String { return stringId }
        if let intId = id as? Int { return String(intId) }
        return nil
    }
}

struct RPCEnvelope: Codable {
    let jsonrpc: String
    let id: String?
    let method: String
    let params: AnyCodableValue?  // Reuses existing AnyCodableValue from PaneContent.swift
}

// AnyCodableValue already exists in Models/PaneContent.swift — a Codable enum over
// String/Int/Double/Bool/Array/Dict/null. Reuse it for the RPC envelope's params field.
// No external dependency needed. If it needs to move to a shared location, extract to
// a dedicated Models/AnyCodableValue.swift file.

protocol RPCMethod {
    associatedtype Params: Codable
    associatedtype Result: Codable
    static var method: String { get }
}

/// Marker type for methods that accept no parameters.
/// Decodes from both `{}` and nil (missing params field).
struct EmptyParams: Codable {
    init() {}
    init(from decoder: Decoder) throws {
        // Accept both {} and nil
        _ = try? decoder.container(keyedBy: CodingKeys.self)
    }
    private enum CodingKeys: CodingKey {}
}

struct AnyMethodHandler {
    /// Handler receives nil when JSON-RPC params field was omitted.
    /// Methods using EmptyParams should handle nil → EmptyParams().
    /// Methods requiring params should throw DecodingError on nil.
    let handle: (Data?) async throws -> Data?
}
```

### 9.3 Message Handler

```swift
class RPCMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var coordinator: BridgeCoordinator?

    init(coordinator: BridgeCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let json = message.body as? String else { return }
        Task { @MainActor in
            await coordinator?.handleCommand(json: json)
        }
    }
}
```

---

## 10. Content Delivery: Metadata Push + Content Pull

For large diffs (100+ files), content delivery separates metadata (state stream) from file contents (data stream).

### 10.1 Metadata Push (State Stream)

Swift computes the `DiffManifest` (file paths, sizes, hunk summaries, statuses) and pushes it via the state stream. No file contents cross this stream.

```swift
func loadDiff(source: DiffSource) async {
    paneState.diff.epoch += 1
    paneState.diff.source = source
    paneState.diff.status = .loadingManifest

    do {
        let changedFiles = try await gitService.listChangedFiles(source: source)
        paneState.diff.manifest = DiffManifest(
            source: source,
            epoch: paneState.diff.epoch,
            files: changedFiles.map { file in
                FileManifest(
                    id: file.id, path: file.path, oldPath: file.oldPath,
                    changeType: file.changeType, loadStatus: .pending,
                    additions: file.additions, deletions: file.deletions,
                    size: file.size, contextHash: file.contextHash,
                    hunkSummary: file.hunks
                )
            }
        )
        paneState.diff.status = .manifestReady
        // Observations triggers push → React renders file tree + diff list immediately
    } catch {
        paneState.diff.status = .error
        paneState.diff.error = error.localizedDescription
    }
}
```

### 10.2 Content Pull (Data Stream)

React fetches file contents on demand via the `agentstudio://` binary channel. Content is requested when files enter Pierre's viewport (see §12 for Pierre virtualization).

```typescript
// React: triggered by Pierre's virtualizer when a file becomes visible
async function loadFileContent(fileId: string): Promise<FileContents> {
    const response = await fetch(`agentstudio://resource/file/${fileId}`);
    if (!response.ok) throw new Error(`Failed to load file ${fileId}`);
    const data = await response.json(); // { oldContent, newContent }
    return data;
}
```

```swift
// Swift: BinarySchemeHandler serves file contents
// Path: agentstudio://resource/file/{fileId}
func resolveResource(for request: URLRequest) async throws -> (Data, String) {
    guard let url = request.url,
          let fileId = extractFileId(from: url) else {
        throw BridgeError.invalidRequest("Invalid resource URL")
    }

    // Epoch check: don't serve content from a stale diff
    guard paneState.diff.manifest?.epoch == paneState.diff.epoch else {
        throw BridgeError.staleRequest("Diff epoch has changed")
    }

    let contents = try await gitService.readFileContents(fileId: fileId)
    let json = try JSONEncoder().encode(contents)
    return (json, "application/json")
}
```

### 10.3 Priority Queue

React manages a priority queue for content requests:

| Priority | Trigger | Behavior |
|---|---|---|
| **High** | File enters viewport (Pierre visibility) | Fetch immediately |
| **Medium** | User clicks/hovers file in tree | Prefetch |
| **Low** | Neighbor files (±5 from viewport) | Idle-time prefetch |
| **Cancel** | File leaves viewport, new diff loaded | Abort in-flight fetch |

```typescript
// React: content loader with priority queue
const contentLoader = {
    queue: new Map<string, { priority: number; controller: AbortController }>(),

    request(fileId: string, priority: number) {
        // Cancel lower-priority request for same file
        const existing = this.queue.get(fileId);
        if (existing && existing.priority >= priority) return;
        existing?.controller.abort();

        const controller = new AbortController();
        this.queue.set(fileId, { priority, controller });

        fetch(`agentstudio://resource/file/${fileId}`, { signal: controller.signal })
            .then(res => res.json())
            .then(data => {
                fileContentCache.set(fileId, data); // LRU cache, max ~20 files
                this.queue.delete(fileId);
            })
            .catch(err => {
                if (err.name !== 'AbortError') this.queue.delete(fileId);
            });
    },

    cancelAll() {
        for (const [, { controller }] of this.queue) controller.abort();
        this.queue.clear();
    }
};
```

### 10.4 LRU Content Cache

File contents are cached in React's tier 2 mirror state with an LRU policy (~20 files). This keeps memory bounded while avoiding re-fetches for recently viewed files:

- **On viewport enter**: Check cache → cache hit = render immediately. Cache miss = fetch via data stream.
- **On cache full**: Evict least-recently-used file content.
- **On new diff load**: Clear entire cache (epoch change).

---

## 11. Security Model

### 11.1 Six-Layer Protection

| Layer | Mechanism | What It Protects |
|---|---|---|
| **1. Content World Isolation** | `WKContentWorld.world(name: "agentStudioBridge")` | Bridge JS globals (`window.__bridgeInternal`) are invisible to page scripts. **Note**: DOM is shared — DOM mutations by bridge scripts ARE visible to page world. Content world isolates JS namespaces only, not the DOM. |
| **2. Message Handler Scoping** | `userContentController.add(handler, contentWorld: bridgeWorld, name: "rpc")` | Only bridge-world scripts can post to the `rpc` handler. |
| **3. Method Allowlisting** | `RPCRouter` only dispatches registered methods | Unknown methods return `-32601`. No arbitrary code execution. |
| **4. Typed Params Validation** | `JSONDecoder` with concrete `Codable` types | Malformed params fail at decode, never reach business logic. |
| **5. URL Scheme Sandboxing** | `agentstudio://` with path validation | Binary handler rejects paths outside allowed resource types. |
| **6. Navigation Policy** | `WebPage.NavigationDeciding` protocol | Only `agentstudio://` and `about:blank` allowed. External URLs open in default browser. |

### 11.2 Content World Setup

```swift
private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")

// Bootstrap script — installs __bridgeInternal in the isolated world
// WKUserScript takes content world in its initializer, NOT in addUserScript
let bootstrapScript = WKUserScript(
    source: bridgeBootstrapJS,
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true,
    in: bridgeWorld  // Content world specified on WKUserScript init
)
config.userContentController.addUserScript(bootstrapScript)  // No content world param here
```

### 11.3 Bridge ↔ Page World Communication

Since content worlds isolate JavaScript namespaces, the bridge world and page world (React) communicate through DOM events:

**Bridge world → Page world (state push)** — includes a push nonce to prevent forgery from page-world scripts:
```javascript
// Bridge world receives callJavaScript from Swift, relays via CustomEvent
// pushNonce is a separate secret from bridgeNonce — only bridge world knows it
const pushNonce = crypto.randomUUID();

// Expose pushNonce to page world via a one-time handshake stored in a closure,
// NOT via a DOM attribute (unlike bridgeNonce, this must not be readable by
// arbitrary page-world scripts).
// The receiver captures it at initialization via a '__bridge_handshake' event.
document.dispatchEvent(new CustomEvent('__bridge_handshake', {
    detail: { pushNonce }
}));

window.__bridgeInternal = {
    merge(store, data) {
        document.dispatchEvent(new CustomEvent('__bridge_push', {
            detail: { type: 'merge', store, data, __pushNonce: pushNonce }
        }));
    },
    replace(store, data) {
        document.dispatchEvent(new CustomEvent('__bridge_push', {
            detail: { type: 'replace', store, data, __pushNonce: pushNonce }
        }));
    },
    response(payload) {
        // Relay JSON-RPC response (success or error) to page world
        document.dispatchEvent(new CustomEvent('__bridge_response', {
            detail: { ...payload, __pushNonce: pushNonce }
        }));
    },
};
```

**Page world (React) listens** — validates push nonce to reject forged events:
```typescript
// bridge/receiver.ts — installed in page world
// Capture push nonce from one-time handshake (bridge world dispatches this at bootstrap)
let _pushNonce: string | null = null;
document.addEventListener('__bridge_handshake', ((e: CustomEvent) => {
    if (_pushNonce === null) {  // Accept only the first handshake
        _pushNonce = e.detail.pushNonce;
    }
}) as EventListener, { once: true });

document.addEventListener('__bridge_push', ((e: CustomEvent) => {
    // Reject forged push events from page-world scripts
    if (e.detail?.__pushNonce !== _pushNonce) return;

    const { type, store, data } = e.detail;
    const zustandStore = stores[store];
    if (!zustandStore) return;

    if (type === 'merge') {
        zustandStore.setState((prev) => deepMerge(prev, data));
    } else if (type === 'replace') {
        zustandStore.setState(() => data);
    }
}) as EventListener);
```

**Page world → Bridge world (commands)**:

Since page-world scripts could forge `__bridge_command` events, commands include a **nonce token** generated at bootstrap. The bridge world validates the nonce before relaying to Swift:

```javascript
// Bridge world generates nonce at document start
const bridgeNonce = crypto.randomUUID();

// Bridge world injects nonce into page world via DOM attribute
document.documentElement.setAttribute('data-bridge-nonce', bridgeNonce);

// Bridge world validates nonce on command events
document.addEventListener('__bridge_command', (e) => {
    if (e.detail?.__nonce !== bridgeNonce) return; // reject forged events
    const { __nonce, ...payload } = e.detail;
    window.webkit.messageHandlers.rpc.postMessage(JSON.stringify(payload));
});
```

```typescript
// React reads nonce from DOM and includes it in commands
const bridgeNonce = document.documentElement.getAttribute('data-bridge-nonce');

export function sendCommand(method: string, params?: unknown): void {
    document.dispatchEvent(new CustomEvent('__bridge_command', {
        detail: { jsonrpc: "2.0", method, params, __nonce: bridgeNonce }
    }));
}
```

**Note**: This is defense-in-depth. Since we load our own React app (not untrusted content), the nonce prevents accidental cross-script interference rather than active attacks. A truly malicious script could read the DOM attribute. For stronger isolation, the nonce could be delivered via a one-time bridge-world → page-world handshake stored in a closure, not the DOM.

### 11.4 Navigation Policy

```swift
class AgentStudioNavigationDecider: WebPage.NavigationDeciding {
    private static let allowedSchemes: Set<String> = ["agentstudio", "about"]
    private static let blockedSchemes: Set<String> = ["javascript", "data", "blob", "vbscript"]

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url,
              let scheme = url.scheme?.lowercased() else { return .cancel }

        if Self.allowedSchemes.contains(scheme) {
            return .allow
        }

        if Self.blockedSchemes.contains(scheme) {
            return .cancel  // silently block dangerous schemes
        }

        // External URLs (http, https, etc.) — open in default browser
        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}
```

---

## 12. Diff Viewer Integration (Pierre)

### 12.1 Pierre Packages

The diff viewer uses two Pierre packages:

| Package | Purpose | Key Exports |
|---|---|---|
| **`@pierre/diffs`** | Diff rendering with syntax highlighting | `MultiFileDiff`, `VirtualizedFileDiff`, `Virtualizer`, `WorkerPoolManager`, `FileStream` |
| **`@pierre/file-tree`** | File tree sidebar with search | `FileTree` (React), `generateLazyDataLoader`, `onSelection` callback |

> **Import convention**: Pierre packages use `/react` sub-path for React components (e.g., `@pierre/diffs/react` for `MultiFileDiff`) and the bare package path for core utilities (e.g., `@pierre/diffs` for `Virtualizer`, `WorkerPoolManager`). Verify exact export paths against the installed package version — these are based on Pierre's current source structure.

### 12.2 Virtualized Diff Rendering

Pierre has **built-in virtualization** via `VirtualizedFileDiff`. No external virtualizer (React Window/Virtuoso) needed. The `Virtualizer` manages the scroll container; each file gets a `VirtualizedFileDiff` that renders only visible lines plus buffers.

```typescript
import { MultiFileDiff } from '@pierre/diffs/react';
import { Virtualizer, VirtualizedFileDiff, WorkerPoolManager } from '@pierre/diffs';

// Create shared instances for the diff panel
const virtualizer = new Virtualizer(scrollContainer);
const workerManager = new WorkerPoolManager();

function DiffFileView({ fileId }: { fileId: string }) {
    const manifest = useDiffManifest(fileId);
    const content = useFileContent(fileId); // LRU cached, fetched via data stream

    if (!content) {
        // File content not yet loaded — Pierre still renders with approximate height
        // Content loader triggers fetch when this file enters viewport
        return <DiffFileSkeleton manifest={manifest} />;
    }

    return (
        <MultiFileDiff
            oldFile={{
                name: manifest.oldPath ?? manifest.path,
                contents: content.oldContent ?? '',
                cacheKey: `${fileId}:old`,  // enables worker highlight caching
            }}
            newFile={{
                name: manifest.path,
                contents: content.newContent ?? '',
                cacheKey: `${fileId}:new`,
            }}
            options={{
                theme: 'pierre-dark',
                diffStyle: 'split',
            }}
        />
    );
}
```

**Key behaviors**:
- `VirtualizedFileDiff` computes approximate heights from metadata (additions, deletions) before content loads
- `setVisibility(true)` triggers the content loader to fetch via data stream
- `WorkerPoolManager` offloads syntax highlighting to web workers — critical for 500-file diffs
- `cacheKey` on `FileContents` enables worker-side AST caching; scrolling back to a file is instant

### 12.3 File Tree (Pierre)

Pierre's `@pierre/file-tree` provides a hierarchical file tree with search, expand/collapse, and lazy data loading for 500+ files:

```typescript
import { FileTree } from '@pierre/file-tree/react';
import { generateLazyDataLoader } from '@pierre/file-tree';

function DiffSidebar() {
    const manifest = useDiffManifest();
    const viewedFiles = useViewedFiles();

    const options = useMemo(() => ({
        files: manifest.files.map(f => f.path),
        dataLoader: generateLazyDataLoader(),  // on-demand node creation for 500+ files
        onSelection: ([selected]) => {
            if (!selected.isFolder) {
                scrollToFile(selected.path);    // navigate diff view to selected file
            }
        },
    }), [manifest]);

    return <FileTree options={options} />;
}
```

**Custom badges**: Pierre's file tree renders `Icon` + `itemName` per node. To show status badges (change type, comment count, viewed), extend the tree item rendering or overlay badges via CSS selectors on `data-file-tree-item` attributes.

**Search/filter**: Built-in via `fileTreeSearchFeature`. Supports `expand-matches` and `collapse-non-matches` modes. Bound to the search input with `data-file-tree-search-input`. Filtering 500 files is pure JS — <16ms, no bridge traffic.

### 12.4 Content Loading Lifecycle

```
1. Swift pushes DiffManifest via state stream (file paths, sizes, hunk summaries)
2. React passes manifest to Pierre FileTree + creates VirtualizedFileDiff per file
3. Pierre Virtualizer determines which files are in viewport
4. VirtualizedFileDiff.setVisibility(true) fires → content loader triggers
5. Content loader fetches via agentstudio://resource/file/{id} (data stream)
6. Content arrives → Pierre renders diff + WorkerPoolManager highlights
7. User scrolls → Pierre manages visibility transitions:
   - Files leaving viewport: DOM removed, height cached
   - Files entering viewport: content fetched (or LRU cache hit), rendered
```

### 12.5 Comment Integration

Pierre supports annotations via `lineAnnotations` and `renderAnnotation`. Review threads from the Zustand store map to Pierre's annotation API:

```typescript
function DiffFileWithComments({ fileId }: { fileId: string }) {
    const content = useFileContent(fileId);
    const threads = useFileThreads(fileId);

    const annotations = useMemo(() =>
        threads.map((thread) => ({
            line: thread.anchor.line,
            side: thread.anchor.side,
            data: {
                threadId: thread.id,
                isOutdated: thread.isOutdated,
                commentCount: thread.comments.length,
                state: thread.state,
            },
        })),
        [threads]
    );

    // ... render MultiFileDiff with annotations + renderAnnotation
}
```

### 12.6 Interaction Models and SLO Budgets

| Interaction | Transport | Local/RPC | Budget (p50/p95) | Optimistic? |
|---|---|---|---|---|
| **Draft comment** (typing) | None (tier 3 local) | Local | 16ms / 16ms | N/A |
| **Submit comment** | Command → state push | RPC | 100ms / 200ms | Yes (pending → committed) |
| **Resolve thread** | Command → state push | RPC | 50ms / 100ms | Yes |
| **Mark file viewed** | Command → state push | RPC | 25ms / 60ms | Yes |
| **Apply file** (accept agent changes) | Command → disk op → push | RPC | 200ms / 400ms | No |
| **Request agent rewrite** | Command → AgentTask | RPC | 60ms / 150ms | N/A (async) |
| **Filter files** | None (tier 3 local) | Local | 16ms / 16ms | N/A |
| **Search in diff** | None (Pierre built-in) | Local | 16ms / 16ms | N/A |
| **Scroll to file** | Content fetch if needed | Data stream | 50ms / 200ms | N/A |
| **File list load** | State stream push | Push | 50ms / 100ms | N/A |
| **Agent status update** | Agent event stream | Push | 32ms / 100ms | N/A |
| **Recovery resync** | Handshake + full push | Push | 500ms / 2000ms | N/A |

### 12.7 Sending Review to Agent

```typescript
function SendToAgentButton({ fileId }: { fileId: string }) {
    const threads = useFileThreads(fileId);

    const handleSend = () => {
        const threadIds = threads.map((t) => t.id);
        commands.agent.requestRewrite({
            source: { type: 'threads', threadIds },
            prompt: 'Address the review comments in these threads',
        });
    };

    return <button onClick={handleSend}>Send to Agent</button>;
}
```

Swift handler creates a durable `AgentTask` record and enqueues the work:

```swift
await router.register(Methods.AgentRequestRewrite.self) { params in
    let task = AgentTask(
        id: UUID(),
        source: .thread(threadId: params.threadIds.first!),
        prompt: params.prompt,
        status: .queued,
        modifiedFiles: [],
        createdAt: Date()
    )
    self.paneState.agentTasks[task.id] = task
    // Agent runtime picks up queued tasks and streams progress
}
```

---

## 13. Implementation Phases

Each phase is independently testable and shippable.

### Phase 1: Transport Foundation

**Goal**: `callJavaScript` and `postMessage` work bidirectionally.

**Deliverables**:
- `BridgeCoordinator` creates `WebPage` with configuration
- `BinarySchemeHandler` serves bundled React app from `agentstudio://app/*`
- React app loads and renders in `WebView`
- Bootstrap script installs `window.__bridgeInternal` in bridge content world
- Message handler receives `postMessage` from bridge world
- Round-trip test: Swift calls JS → JS posts message → Swift receives

**Tests**:
- Unit: `BinarySchemeHandler` returns correct MIME types and data for app resources
- Unit: `RPCMessageHandler` parses valid/invalid JSON correctly
- Integration: WebPage loads `agentstudio://app/index.html` and renders React
- Integration: Round-trip `callJavaScript` → `postMessage` → Swift handler fires

### Phase 2: State Push Pipeline

**Goal**: Swift `@Observable` changes arrive in Zustand stores via state stream and agent event stream.

**Deliverables**:
- Zustand stores for `diff`, `review`, `agent`, and `connection` domains
- Bridge receiver listens for `__bridge_push` and `__bridge_agent` CustomEvents relayed from `__bridgeInternal`, routes to correct Zustand store
- `Observations` AsyncSequence watches `PaneDomainState`
- Push envelope carries `__revision` (per store) and `__epoch` (load generation) — React drops stale pushes
- Push coalescing with debounce (state stream) and 30-50ms batching (agent event stream)
- Content world ↔ page world relay via CustomEvents

**Tests**:
- Unit: `deepMerge` correctly merges partial state
- Unit: Zustand store updates on `merge` and `replace` calls
- Unit: Bridge receiver routes `__bridge_push` to correct store by `store` field
- Unit: Stale push rejection — push with `revision <= lastSeen` dropped
- Unit: Epoch mismatch — push with wrong `epoch` triggers cache clear
- Integration: Mutate `@Observable` property in Swift → verify Zustand store updated
- Integration: Rapid mutations coalesce into single push (verify with push counter)
- Integration: Content world isolation — page world script cannot call `window.webkit.messageHandlers.rpc`

### Phase 3: JSON-RPC Command Channel

**Goal**: React can send typed commands to Swift with idempotent command IDs.

**Deliverables**:
- `RPCRouter` with typed method registration
- Method definitions for `diff.*`, `review.*`, and `agent.*` namespaces
- Command sender on JS side (`commands.diff.requestFileContents(...)`) with `__commandId` (UUID)
- Swift deduplicates commands by `commandId`, pushes `commandAck` via state stream
- Error handling (method not found, invalid params, internal error)
- Direct-response path for rare request/response needs

**Tests**:
- Unit: `RPCRouter` dispatches to correct handler
- Unit: Unknown methods return `-32601`
- Unit: Invalid params return `-32602`
- Unit: `RPCMethod` protocol correctly decodes typed params
- Unit: Duplicate `commandId` → idempotent (no double execution)
- Integration: JS sends command → Swift handler fires → commandAck pushed → state updates → push arrives in Zustand

### Phase 4: Diff Viewer & Content Delivery (Pierre Integration)

**Goal**: Full diff viewer renders in a webview pane using metadata push + content pull.

**Deliverables**:
- `DiffManifest` and `FileManifest` domain models (Swift, §8)
- `DiffSource` enum: `.agentSnapshot`, `.commit`, `.branchDiff`
- State stream: Swift pushes `DiffManifest` (file metadata only) into diff Zustand store
- Data stream: `BinarySchemeHandler` extended for `agentstudio://resource/file/{id}` — React pulls file contents on demand
- Priority queue on React side: viewport files (high), hovered files (medium), neighbor files (low), cancel when leaving viewport
- LRU content cache (~20 files) in React, cleared on epoch change
- Pierre `VirtualizedFileDiff` renders diffs with built-in `Virtualizer`
- Pierre `FileTree` with `generateLazyDataLoader` for file navigation and search
- Pierre `WorkerPoolManager` offloads syntax highlighting to web workers
- Path validation and security hardening for resource URLs

**Tests**:
- Unit: `DiffManifest` / `FileManifest` Codable round-trip
- Unit: `BinarySchemeHandler` validates allowed resource types and rejects forbidden paths
- Unit: Priority queue ordering logic (viewport > hover > neighbor)
- Unit: LRU cache evicts oldest entries beyond capacity, clears on epoch bump
- Unit: Pierre `VirtualizedFileDiff` renders with mock file contents
- Integration: Swift pushes `DiffManifest` → FileTree renders file list within 100ms
- Integration: React `fetch('agentstudio://resource/file/xyz')` returns correct file content
- Integration: Scroll file into viewport → content pull fires → diff renders within 200ms
- Integration: Epoch guard: start new diff during active load → stale results discarded
- Performance: Binary channel latency for 100KB, 500KB, 1MB files on target hardware
- E2E: Open diff pane → FileTree renders → select file → diff renders with syntax highlighting

### Phase 5: Review System & Agent Integration

**Goal**: Comment threads, review actions, and agent task lifecycle.

**Deliverables**:
- `ReviewThread`, `ReviewComment`, `ReviewAction` domain models (Swift, §8)
- `AgentTask` with per-file checkpoint status (`running(completedFiles:currentFile:)`)
- `TimelineEvent` append-only audit log (in-memory v1, designed for `.jsonl` v2)
- State stream: pushes review state (threads, viewed files) into review Zustand store
- Agent event stream: batched agent activity (started, fileCompleted, done) via `callJavaScript`
- Comment anchoring: content hash + line number, `isOutdated` flag when hash changes
- Comment UI: add, resolve, delete — optimistic local state with commandId acks
- "Send to Agent" creates durable `AgentTask` with review context, formats comments for terminal injection
- Agent event Zustand store with sequence-numbered append, gap detection

**Tests**:
- Unit: `ReviewThread` / `ReviewComment` Codable round-trip
- Unit: Comment anchor `contextHash` computation and `isOutdated` detection
- Unit: `AgentTask` state machine transitions
- Unit: Agent event sequence gap detection logic
- Integration: Add comment → command with commandId → Swift acks → Zustand thread updated
- Integration: Resolve thread → push updates thread state → UI reflects
- Integration: "Send to Agent" → `AgentTask` created → formatted text injected into terminal
- Integration: Agent event stream batching: 5 rapid events coalesce into 1-2 batched pushes
- E2E: Full review flow — open diff → add comment → send to agent → agent completes → timeline updated

### Phase 6: Security Hardening

**Goal**: All six security layers verified and hardened.

**Deliverables**:
- Content world isolation audit — verify page world cannot access bridge internals
- Navigation policy — verify all external URLs blocked
- Method allowlisting audit — verify only registered methods dispatch
- Path traversal tests for URL scheme handler
- Rate limiting on RPC methods (if needed)

**Tests**:
- Security: Inject script in page world → verify cannot call `window.webkit.messageHandlers.rpc`
- Security: Navigate to `https://evil.com` → verify blocked, opens in default browser
- Security: Send unknown method → verify `-32601` error
- Security: `agentstudio://../../etc/passwd` → verify rejected
- Security: Rapid command flooding → verify no resource exhaustion

### Global Design Invariants

These invariants are cross-cutting rules that apply to ALL phases. Every implementation task and code review must verify compliance.

| # | Invariant | Verification |
|---|---|---|
| **G1** | Swift is the single source of truth for domain state | No Zustand store mutates domain data without a push from Swift |
| **G2** | All cross-boundary messages are structured (JSON-RPC 2.0 or typed push envelope) | No raw string passing; every message has a defined schema |
| **G3** | Async lifecycles are explicit — every `Task` has a cancellation path | No fire-and-forget tasks; `observationTask?.cancel()` on teardown |
| **G4** | Correlation IDs (`__pushId`) trace pushes end-to-end | Every push from Swift observation through JS merge to React rerender is traceable |
| **G5** | No force-unwraps (`!`) in bridge code | All optionals use `guard let`, `if let`, or nil-coalescing |
| **G6** | Page lifecycle is first-class — web process crash, navigation failure, page close all handled | `handlePageTermination` covers all three; observation loops cancel; health state updates |
| **G7** | Performance is measured, not assumed | All latency claims backed by harness measurements (see below) |
| **G8** | Security is by configuration, not convention | Content worlds, navigation policy, nonce validation — all enforced in code, not docs |
| **G9** | Unsupported behavior is explicit | Batch rejection returns -32600; unknown methods return -32601; unknown stores log and drop |
| **G10** | Phases ship independently | Each phase has its own tests and exit criteria; no phase depends on a later phase's deliverables |

### Performance Measurement Harness

All timing metrics in exit criteria must be collected under a consistent harness:

| Parameter | Value | Rationale |
|---|---|---|
| **Warmup runs** | 3 | Eliminate JIT, caching, WebKit process spin-up variance |
| **Measured runs** | 10 | Enough for stable median; low overhead |
| **Reported metric** | p50 (median) | Resistant to outlier spikes from system load |
| **Variance gate** | p95 < 2× p50 | If variance exceeds 2×, flag for investigation before accepting |
| **Hardware** | Apple Silicon (M-series), macOS 26 | Target hardware; document exact chip in results |
| **Process state** | Cold WebPage per run (teardown + recreate) | Isolates runs from previous state |

Test code uses `ContinuousClock.measure {}` or `DispatchTime` for wall-clock timing. Results are logged as structured JSON for CI parsing.

### Phase Exit Criteria

Each phase requires explicit acceptance criteria before proceeding to the next. A phase is **complete** when all required tests pass and metrics meet thresholds (measured per the harness above).

#### Phase 1 Exit Criteria
- [ ] Round-trip latency benchmark: `callJavaScript` → `postMessage` → Swift handler < 5ms for < 5KB payload
- [ ] All unit + integration tests pass with 0 failures
- [ ] React app renders in WebView (verified visually with Peekaboo)
- [ ] Bootstrap script installs `__bridgeInternal` in bridge world (verified via `callJavaScript` return)
- [ ] Page world script CANNOT call `window.webkit.messageHandlers.rpc` (verified negative test)

#### Phase 2 Exit Criteria
- [ ] Mutate `@Observable` property → Zustand store updated within 1 frame (< 16ms)
- [ ] 10 rapid synchronous mutations coalesce into ≤ 2 pushes (verify with push counter)
- [ ] `deepMerge` produces correct structural sharing (unit test with reference equality checks)
- [ ] Push 100-file diff state: end-to-end < 32ms on target hardware
- [ ] Content world isolation verified: page world listener cannot forge `__bridge_push` events that bypass bridge world

#### Phase 3 Exit Criteria
- [ ] All registered methods dispatch correctly (positive tests)
- [ ] **Negative protocol tests**: parse error (-32700), invalid request (-32600), method not found (-32601), invalid params (-32602), internal error (-32603)
- [ ] Notification with no `id` produces NO response (verify with mock)
- [ ] Notification with no `params` field decodes correctly (EmptyParams path)
- [ ] Batch request `[...]` is rejected with -32600
- [ ] Direct-response path: request with `id` → response arrives via `__bridge_response` CustomEvent

#### Phase 4 Exit Criteria
- [ ] `DiffManifest` push → FileTree renders file list within 100ms (100 files)
- [ ] Content pull: scroll file into viewport → `fetch('agentstudio://resource/file/{id}')` → diff renders within 200ms
- [ ] Priority queue: viewport files load before neighbor files (verified with request ordering log)
- [ ] LRU cache: loading 25+ files evicts oldest, capacity stays at ~20
- [ ] Epoch guard: start new diff during active load → stale results discarded, cache cleared
- [ ] Cancellation: file leaves viewport during active fetch → request cancelled, no resource leak
- [ ] Path traversal: `../../etc/passwd` → rejected with error
- [ ] **Performance benchmarks** (measured on M-series Mac):
  - 100KB file: binary channel < 5ms
  - 500KB file: binary channel < 15ms
  - 1MB file: binary channel < 30ms
- [ ] Pierre `VirtualizedFileDiff` renders with syntax highlighting (WorkerPoolManager active)
- [ ] Pierre `FileTree` search/filter works on 500+ file manifest

#### Phase 5 Exit Criteria
- [ ] Comment add: optimistic local state appears immediately, confirmed by commandAck push
- [ ] Comment resolve/delete: round-trip correctly with optimistic UI + rollback on rejection
- [ ] Comment anchor: `contextHash` matches, `isOutdated` detects when file content changes
- [ ] "Send to Agent" creates `AgentTask`, injects formatted review context into terminal
- [ ] Agent event stream: batched at 30-50ms cadence, sequence numbers contiguous
- [ ] Agent event gap detection: missing sequence triggers re-sync request
- [ ] `AgentTask` status transitions: `pending` → `running(completedFiles:currentFile:)` → `completed`/`failed`
- [ ] `TimelineEvent` append-only: events cannot be mutated after creation

#### Phase 6 Exit Criteria
- [ ] Content world isolation: 5 specific attack vectors tested and blocked
- [ ] Navigation policy: `javascript:`, `data:`, `blob:`, `vbscript:` all blocked; `http/https` open in browser
- [ ] Handler name conflicts: verify no collision between bridge-world and page-world handler names per content world
- [ ] User-script scoping: bootstrap script runs ONLY in bridge world (verify via page-world `typeof __bridgeInternal === 'undefined'`)
- [ ] **Concurrency/lifecycle tests**:
  - Page navigation during active push → health state updated, no crash
  - URLSchemeHandler cancellation during file load → clean teardown
  - Observation consumer slower than producer → latest state delivered, no memory growth
  - Pane hide → show → observation loops resume, full state re-pushed

---

## 14. File Structure

```
Sources/AgentStudio/
├── Bridge/
│   ├── BridgeCoordinator.swift           # WebPage setup, observation loops, three-stream push
│   ├── RPCRouter.swift                   # Method registry + dispatch
│   ├── RPCMethod.swift                   # Protocol + type-erased handler
│   ├── RPCMessageHandler.swift           # WKScriptMessageHandler for postMessage
│   ├── BinarySchemeHandler.swift         # agentstudio:// URL scheme (app + resource)
│   ├── NavigationDecider.swift           # WebPage.NavigationDeciding
│   ├── BridgeBootstrap.swift             # JS bootstrap script for bridge world
│   └── Methods/                          # One file per namespace
│       ├── DiffMethods.swift             # diff.requestFileContents, diff.loadDiff
│       ├── ReviewMethods.swift           # review.addComment, review.resolveThread
│       ├── AgentMethods.swift            # agent.sendReview, agent.cancelTask
│       └── SystemMethods.swift           # system.ping, system.getCapabilities
├── Domain/
│   ├── BridgeDomainState.swift           # @Observable root: PaneDomainState
│   ├── DiffManifest.swift                # DiffManifest, FileManifest, HunkSummary, DiffSource
│   ├── ReviewState.swift                 # ReviewThread, ReviewComment, ReviewAction, CommentAnchor
│   ├── AgentTask.swift                   # AgentTask, AgentTaskStatus
│   ├── TimelineEvent.swift               # TimelineEvent, TimelineEventKind (in-memory v1)
│   └── ConnectionState.swift             # Connection health
└── (existing Sources structure unchanged)

WebApp/                                    # React app (Vite + TypeScript)
├── src/
│   ├── bridge/
│   │   ├── receiver.ts                   # __bridge_push/__bridge_agent CustomEvent → Zustand
│   │   ├── commands.ts                   # Typed command senders with commandId
│   │   ├── rpc-client.ts                 # Direct-response RPC (rare)
│   │   └── types.ts                      # Shared protocol types, push envelope
│   ├── stores/
│   │   ├── diff-store.ts                 # Zustand: DiffManifest, FileManifest, epoch, revision
│   │   ├── review-store.ts              # Zustand: ReviewThread, comments, viewed files
│   │   ├── agent-store.ts              # Zustand: AgentTask, TimelineEvent, sequence tracking
│   │   ├── content-cache.ts            # LRU cache (~20 files), priority queue, fetch manager
│   │   └── connection-store.ts          # Zustand: connection health
│   ├── hooks/
│   │   ├── use-file-manifest.ts         # Derived selectors on DiffManifest
│   │   ├── use-file-content.ts          # Content pull trigger + cache lookup
│   │   ├── use-review-threads.ts        # Threads for a file, filtered by state
│   │   └── use-agent-status.ts          # Current agent task progress
│   ├── components/
│   │   ├── DiffPanel.tsx                 # Layout: FileTree sidebar + VirtualizedFileDiff main
│   │   ├── FileTreeSidebar.tsx           # Pierre FileTree with lazy data loader
│   │   ├── FileDiffView.tsx              # Pierre VirtualizedFileDiff wrapper per file
│   │   ├── ReviewThreadOverlay.tsx       # Comment thread UI (add, resolve, delete)
│   │   ├── DiffHeader.tsx                # Status bar: source, file count, agent progress
│   │   └── SendToAgentButton.tsx         # Creates AgentTask with review context
│   ├── utils/
│   │   └── deep-merge.ts
│   └── App.tsx
├── vite.config.ts
└── package.json
```

---

## 15. Integration with Existing Pane System

The diff viewer lives as a regular webview pane in the existing tab/split system:

- `PaneContent.webview(WebviewState)` — already exists on `window-system-types` branch
- `WebviewPaneView` — currently a stub, will host the `WebView` + `BridgeCoordinator`
- **One `BridgeCoordinator` per webview pane** — each pane gets its own `WebPage`, `PaneDomainState`, and observation loops
- **`SharedBridgeState` is singleton** — injected into each `BridgeCoordinator`, provides connection health across all panes
- Pane creation: `ActionExecutor.openWebviewPane()` → creates `BridgeCoordinator(sharedState:)` + `WebView`
- Pane teardown: `BridgeCoordinator.teardown()` cancels observation tasks, releases `WebPage`

The existing `ViewRegistry`, `Layout`, drag/drop, and split system work unchanged — the webview pane is just another leaf in the layout tree.

---

## 16. Open Questions

### Resolved (in this document)

- ~~**Domain state scope**~~ → **Per-pane** `PaneDomainState` (diff, review, agent tasks, timeline). Shared state (`ConnectionState`) is singleton. See §8.1.
- ~~**CustomEvent command forgery**~~ → **Nonce token** generated at bootstrap, validated by bridge world. See §11.3.
- ~~**Push error handling**~~ → **do-catch** with logging and connection health state update. No force-unwraps. See §6.4.
- ~~**File loading race conditions**~~ → **Metadata push + content pull with priority queue, LRU cache, and epoch guard**. See §10.
- ~~**Large diff delivery**~~ → **Three-stream architecture**: metadata via state stream, file contents via data stream (pull-based), agent events via batched agent stream. See §1, §4.4, §10.
- ~~**Comment anchoring across line shifts**~~ → **Content hash + line number** with `isOutdated` flag. See §8, §12.5.
- ~~**Navigation policy edge cases**~~ → **Explicit blocklist** for `javascript:`, `data:`, `blob:`, `vbscript:`. See §11.4.

### Requires Verification Spike (before Phase 1)

1. **Swift 6.2 API surface** — Build a minimal test target in Xcode 26 that exercises:
   - `Observations` type creation and `for await` iteration
   - `.debounce(for:)` on `Observations` (requires `AsyncAlgorithms` package — confirmed)
   - `WKContentWorld.world(name:)` creation
   - `WebPage.Configuration` with `userContentController` and `urlSchemeHandlers`
   - `callJavaScript(_:arguments:in:contentWorld:)` — The `in:` frame parameter is optional (defaults to main frame). Omit it for main-frame calls. Verify the default behavior.
   - `WKUserScript(source:injectionTime:forMainFrameOnly:in:)` — This doc uses `in:` on the initializer. This is the chosen pattern. Verify exact parameter label.
   - `URLSchemeHandler` protocol conformance with `AsyncSequence` return

   If any APIs differ from this spec, update the design before Phase 1 implementation.

### Still Open

2. **React app bundling** — Vite build output bundled as app resources? Or served from disk via the scheme handler? Need to decide the build pipeline and how `BinarySchemeHandler` locates the built assets.
3. **WebPage lifecycle** — How does the WebPage behave when the pane is hidden (backgrounded via view switch)? Does it keep running JS? Do observation loops need to pause to avoid wasted work?
4. **Pierre license and bundle size** — Verify `@pierre/diffs` license compatibility and evaluate bundle size impact.
5. **Terminal injection mechanism** — What is the exact API for injecting text into a Ghostty terminal session? Need to trace through `SurfaceManager` → Ghostty C API.
