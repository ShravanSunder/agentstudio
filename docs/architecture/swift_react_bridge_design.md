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

### 3.3 Authority Matrix (Hard Boundary)

To prevent "local-first everywhere" complexity from leaking into this design, ownership is explicit:

| Concern | Owner | Persistence | Latency Target | Notes |
|---|---|---|---|---|
| Draft text, cursor, hover, selection, scroll, expanded tree nodes | React local (tier 3) | In-memory only | < 16ms | Never round-trip through Swift |
| Optimistic overlay (`pending` rows, temporary IDs) | React local (tier 3) | In-memory only | < 16ms | Overlay is reconciled or expired; not durable |
| Diff source, manifest metadata, review threads, command outcomes, agent task lifecycle | Swift domain (tier 1) | Durable/session durable | 50-300ms | Authoritative truth |
| File contents/buffers | Data stream (`agentstudio://`) | LRU in React mirror | On-demand | Not pushed via state stream |

**Non-goal**: This architecture does NOT implement offline-first durable operation logs, CRDT merge, or multi-writer conflict resolution. Swift remains the single writer for domain state.

### 3.4 XPC Latency Characteristics

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
struct BridgeSchemeHandler: URLSchemeHandler {
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

React consumes via standard `fetch()`, including the current epoch to prevent stale responses:
```typescript
const content = await fetch(`agentstudio://resource/file/${fileId}?epoch=${epoch}`);
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

No state pushes or commands are allowed before step 6 completes. The `BridgePaneController` gates on receiving `bridge.ready` before starting observation loops.

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

#### 5.1.1 Optimistic Mutation Contract (Comments, Resolve, Viewed)

Optimistic UX is required for interactive actions (for example: adding a comment). The browser must never wait for Swift round-trip before rendering visible intent.

**Required fields on every optimistic command**:

| Field | Source | Purpose |
|---|---|---|
| `__commandId` | React | Idempotency and end-to-end correlation |
| `tempId` | React | Reconcile temporary UI entity to canonical entity |
| `clientTimestamp` | React | TTL/expiry and debugging |
| `epoch` | React mirror state | Reject stale commands from previous loads |

**Lifecycle**:

```text
idle -> pending(local overlay) -> committed(canonical Swift push)
                               -> failed(rejected/timeout; retry allowed)
                               -> expired(TTL exceeded; prompt user action)
```

**Rules**:
- Swift acks every command with `{ commandId, status, reason?, canonicalId? }`.
- React reconciles by `commandId` first, then maps `tempId -> canonicalId` when present.
- Pending overlays have TTL (default 10s). On expiry, mark `failed` and surface retry.
- Overlay is in-memory only. It is never persisted as domain truth.

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
       let rawId = array.first?["id"] {
        let rpcId: RPCId
        if let s = rawId as? String { rpcId = .string(s) }
        else if let n = rawId as? Int { rpcId = .number(n) }
        else { return }  // No valid id → drop silently
        await coordinator.sendError(id: rpcId, code: -32600, message: "Batch requests not supported")
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

### 5.7 Protocol Invariants (Must Hold in Tests)

| Invariant | Enforcement |
|---|---|
| Monotonic `__revision` per store | Drop pushes with `revision <= lastSeen` |
| Monotonic `__epoch` for each diff load | Drop all stale epoch pushes and responses |
| Exactly-once command semantics at app level | Deduplicate by `__commandId` (sliding window) |
| No large file buffers on state stream | State stream is metadata-only; file buffers via data stream |
| Every cross-boundary payload is typed | Validate against shared contract fixtures in Swift + TS tests |
| Every async load is cancellable | Cancel on epoch change, viewport exit, pane teardown |

---

## 6. State Push Pipeline

### 6.1 Design Principles

State classes are **pure `@Observable`** — they hold domain data and nothing else. Push mechanics (observation, debounce, encoding, transport) are handled by a separate **declarative push infrastructure** (`PushPlan` + `PushEngine`). The two never mix.

This separation means:
- Adding a new state property requires zero push-infrastructure changes.
- Adding a new push slice is one declarative `Slice(...)` or `EntitySlice(...)` call.
- Observation scope is defined by capture closures, not by state class structure.
- The push engine is generic infrastructure, written once, never touched per state class.

> **Dependency**: `.debounce(for:)` is NOT built into `Observations` or the standard library `AsyncSequence`. It requires the **[swift-async-algorithms](https://github.com/apple/swift-async-algorithms)** package (`import AsyncAlgorithms`). Add this as a Package.swift dependency.

> **Intermediate state visibility**: Per [SE-0475](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md), intermediate values may be skipped when the producer outpaces the consumer. For `.hot` slices where transitions matter (`.loading` indicators, connection changes), keep observation loops separate and non-debounced. If every intermediate transition must be visible (not just the latest value), use the agent event stream (append-only, sequence-numbered) instead of the state stream.

### 6.2 Push Policy Levels (`.cold`, `.warm`, `.hot`)

Not all observed state should be pushed with the same cadence. This spec uses three explicit policy levels:

| Level | Typical Size | Typical Rate | Examples | Push Strategy |
|---|---|---|---|---|
| **`.hot`** | < 1KB | 5-60Hz bursts | `connection.health`, loading/status flags | No debounce, `replace` |
| **`.warm`** | 1-10KB | 1-20Hz | review thread updates, command acks, small task updates | 8-16ms debounce, `merge` (entity) or `replace` (scalar) |
| **`.cold`** | > 10KB | < 2Hz | `DiffManifest` snapshots for 100-500 files | 16-50ms debounce, `replace` |

**Policy rule**:
- Default every slice to `.cold`.
- Opt into `.warm` or `.hot` only when latency requires it.
- Debounce durations come from the `PushLevel` enum (single source of truth), not hardcoded per slice.

```swift
enum PushLevel: Sendable {
    case hot
    case warm
    case cold

    /// Debounce duration per level. Single source of truth for cadence policy.
    /// .hot: immediate (no debounce). .warm: 12ms. .cold: 32ms.
    var debounce: Duration {
        switch self {
        case .hot:  .zero
        case .warm: .milliseconds(12)
        case .cold: .milliseconds(32)
        }
    }
}

enum PushOp: String, Sendable, Encodable { case merge, replace }
enum StoreKey: String, Sendable, Encodable { case diff, review, agent, connection }
```

### 6.3 Observation Slices (Current Domain Shape)

Each slice is a capture closure that reads specific properties from an `@Observable` state object. `Observations` (SE-0475) tracks whatever properties the closure reads — this defines the observation scope. Separate closures = separate tracking = separate fire schedules.

| Slice name | Capture reads | Store | Level | Op | Notes |
|---|---|---|---|---|---|
| `diffStatus` | `.status`, `.error`, `.epoch` | `.diff` | `.hot` | `.replace` | immediate user feedback |
| `diffManifest` | `.manifest` | `.diff` | `.cold` | `.replace` | metadata only; no file contents |
| `reviewThreads` | `.threads` | `.review` | `.warm` | `.merge` | per-entity diff by thread version |
| `reviewViewedFiles` | `.viewedFiles` | `.review` | `.warm` | `.replace` | set comparison |
| `agentTasks` | `agentTasks` dict | `.agent` | `.warm` | `.merge` | per-entity diff by task version |
| `connectionHealth` | `.health`, `.latencyMs` | `.connection` | `.hot` | `.replace` | no debounce |

> **Property group isolation**: If a developer accidentally reads `.manifest` inside the `diffStatus` capture closure (e.g., in a log statement), the hot loop silently becomes hot+cold — it fires on manifest changes too. This is a maintenance fragility. Code review should enforce that each capture closure reads only its declared properties.

### 6.4 Push Infrastructure Types

#### 6.4.1 Shared RevisionClock

Revisions must be **monotonic per store across all slices in the pane** (§5.7 invariant). A single `RevisionClock` is owned by `BridgePaneController` and shared across all `PushPlan` instances for that pane.

> **Concurrency safety**: `RevisionClock` is `@MainActor`-isolated. All callers (`PushPlan.observe()`) must call `clock.next(for:)` on the main actor **before** detaching any encoding work (e.g., `.cold` payloads use `Task.detached` for JSON encoding). The revision value is captured as a `let` before the detached block, so no race is possible. This is a high-risk area for future refactoring — moving `next(for:)` into a detached context would break the monotonicity invariant.

```swift
/// Monotonic revision counter per store. Shared across all push plans
/// for a pane to ensure revision ordering per §5.7.
@MainActor
final class RevisionClock {
    private var counters: [StoreKey: Int] = [:]

    func next(for store: StoreKey) -> Int {
        let v = (counters[store] ?? 0) + 1
        counters[store] = v
        return v
    }
}
```

#### 6.4.2 EpochProvider

Each push must carry the real epoch for its domain (§5.7 stale-drop invariant). The `EpochProvider` closure reads the current epoch from the state at push time.

```swift
/// Reads the current epoch from domain state at push time.
/// Provided per-plan so each domain can define its own epoch source.
typealias EpochProvider = @MainActor () -> Int
```

#### 6.4.3 PushTransport

The transport protocol handles envelope stamping (revision, epoch, pushId, level, op) and the actual `callJavaScript` call. `BridgePaneController` conforms to this.

```swift
/// Responsible for stamping push envelopes (revision/epoch/pushId/level/op)
/// and calling into the bridge content world.
@MainActor
protocol PushTransport: AnyObject {
    /// Encode and push a JSON payload to the bridge.
    /// Transport stamps the envelope with revision, epoch, pushId, level, op.
    /// For .cold payloads, encoding happens off-main-actor.
    /// On failure, logs store/level/revision/epoch/pushId per §13.1.
    func pushJSON(
        store: StoreKey,
        op: PushOp,
        level: PushLevel,
        revision: Int,
        epoch: Int,
        json: Data
    ) async
}
```

**Transport implementation** (inside `BridgePaneController`):

```swift
extension BridgePaneController: PushTransport {
    func pushJSON(
        store: StoreKey,
        op: PushOp,
        level: PushLevel,
        revision: Int,
        epoch: Int,
        json: Data
    ) async {
        let pushId = UUID().uuidString
        // Build envelope: wrap payload JSON inside metadata envelope
        // Uses pre-encoded payload data to avoid double-encoding
        let envelopeJSON = buildEnvelopeJSON(
            v: 1, pushId: pushId, revision: revision, epoch: epoch,
            level: level.rawValue, store: store.rawValue, op: op.rawValue,
            payloadData: json
        )

        do {
            guard let jsonString = String(data: envelopeJSON, encoding: .utf8) else {
                throw BridgeError.encoding("UTF-8 conversion failed")
            }
            try await page.callJavaScript(
                "window.__bridgeInternal.applyEnvelope(JSON.parse(json))",
                arguments: ["json": jsonString],
                contentWorld: bridgeWorld
            )
        } catch {
            logger.warning(
                "[Bridge] push failed store=\(store.rawValue) rev=\(revision) "
                + "epoch=\(epoch) pushId=\(pushId) level=\(level): \(error)"
            )
            domainState.connection.health = .error
        }
    }
}
```

#### 6.4.4 Type-Erased Slice

Every `Slice` and `EntitySlice` erases to this type. The `makeTask` closure creates the observation loop task when the engine starts.

```swift
/// Type-erased push slice. Holds a closure that creates the observation
/// task for this slice when the engine starts.
/// Not marked Sendable — closures capture @MainActor state and transport.
struct AnyPushSlice<State: Observable & AnyObject> {
    let name: String
    let makeTask: @MainActor (
        State, PushTransport, RevisionClock, EpochProvider
    ) -> Task<Void, Never>
}
```

> **Sendable note**: `AnyPushSlice` is NOT `Sendable`. The `makeTask` closure captures `@MainActor`-isolated state and transport references. Marking it `Sendable` would require sendability constraints on all captured types, which is unnecessarily restrictive for a type that only lives on `@MainActor`.

### 6.5 Slice (Value-Level Observation)

For scalars and small structs where the whole snapshot is compared and replaced:

```swift
struct Slice<State: Observable & AnyObject, Snapshot: Encodable & Equatable> {
    let name: String
    let store: StoreKey
    let level: PushLevel
    let op: PushOp
    let capture: @MainActor @Sendable (State) -> Snapshot

    init(
        _ name: String,
        store: StoreKey,
        level: PushLevel,
        op: PushOp = .replace,
        capture: @escaping @MainActor @Sendable (State) -> Snapshot
    ) {
        self.name = name; self.store = store
        self.level = level; self.op = op; self.capture = capture
    }

    func erased() -> AnyPushSlice<State> {
        let capture = self.capture
        let level = self.level
        let op = self.op
        let store = self.store
        let name = self.name

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            Task { @MainActor in
                var prev: Snapshot? = nil
                let encoder = JSONEncoder()

                // Observations yields the capture result when any
                // property it reads changes. The capture closure
                // defines the tracking scope.
                let stream = Observations { capture(state) }

                // Debounce by level. Type-erase via for-await
                // to avoid conditional type mismatch (Observations
                // vs AsyncDebounceSequence are different types).
                if level == .hot {
                    for await snapshot in stream {
                        guard snapshot != prev else { continue }
                        prev = snapshot
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()
                        // .hot payloads are small — encode on main actor
                        guard let data = try? encoder.encode(snapshot) else {
                            logger.error("[PushEngine] encode failed slice=\(name) store=\(store)")
                            continue
                        }
                        await transport.pushJSON(
                            store: store, op: op, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                } else {
                    for await snapshot in stream.debounce(for: level.debounce) {
                        guard snapshot != prev else { continue }
                        prev = snapshot
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()

                        let data: Data
                        if level == .cold {
                            // .cold payloads may be large — encode off main actor
                            do {
                                data = try await Task.detached(priority: .utility) {
                                    try encoder.encode(snapshot)
                                }.value
                            } catch {
                                logger.error("[PushEngine] encode failed slice=\(name) store=\(store): \(error)")
                                continue
                            }
                        } else {
                            // .warm payloads are moderate — encode on main actor
                            guard let encoded = try? encoder.encode(snapshot) else {
                                logger.error("[PushEngine] encode failed slice=\(name) store=\(store)")
                                continue
                            }
                            data = encoded
                        }

                        await transport.pushJSON(
                            store: store, op: op, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                }
            }
        }
    }
}
```

### 6.6 EntitySlice (Keyed Collection Observation)

For dictionaries where one entity changes at a time and you need per-entity diffing. Only changed entities are pushed. Keys are normalized to `String` in wire payloads for safe JSON interop (e.g., `UUID` → `String`).

```swift
struct EntitySlice<
    State: Observable & AnyObject,
    Key: Hashable,
    Entity: Encodable
> {
    let name: String
    let store: StoreKey
    let level: PushLevel
    let capture: @MainActor @Sendable (State) -> [Key: Entity]
    let version: @Sendable (Entity) -> Int
    let keyToString: @Sendable (Key) -> String

    init(
        _ name: String,
        store: StoreKey,
        level: PushLevel,
        capture: @escaping @MainActor @Sendable (State) -> [Key: Entity],
        version: @escaping @Sendable (Entity) -> Int,
        keyToString: @escaping @Sendable (Key) -> String = { "\($0)" }
    ) {
        self.name = name; self.store = store; self.level = level
        self.capture = capture; self.version = version
        self.keyToString = keyToString
    }

    func erased() -> AnyPushSlice<State> {
        let capture = self.capture
        let version = self.version
        let keyToString = self.keyToString
        let level = self.level
        let store = self.store
        let name = self.name

        return AnyPushSlice(name: name) { state, transport, revisions, epochProvider in
            Task { @MainActor in
                var lastVersions: [Key: Int] = [:]
                let encoder = JSONEncoder()

                let stream = Observations { capture(state) }

                if level == .hot {
                    for await entities in stream {
                        let delta = Self.computeDelta(
                            entities: entities, lastVersions: &lastVersions,
                            version: version, keyToString: keyToString
                        )
                        guard !delta.isEmpty else { continue }
                        guard let data = try? encoder.encode(delta) else {
                            logger.error("[PushEngine] encode failed slice=\(name) store=\(store)")
                            continue
                        }
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()
                        await transport.pushJSON(
                            store: store, op: .merge, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                } else {
                    for await entities in stream.debounce(for: level.debounce) {
                        let delta = Self.computeDelta(
                            entities: entities, lastVersions: &lastVersions,
                            version: version, keyToString: keyToString
                        )
                        guard !delta.isEmpty else { continue }
                        guard let data = try? encoder.encode(delta) else {
                            logger.error("[PushEngine] encode failed slice=\(name) store=\(store)")
                            continue
                        }
                        let revision = revisions.next(for: store)
                        let epoch = epochProvider()
                        await transport.pushJSON(
                            store: store, op: .merge, level: level,
                            revision: revision, epoch: epoch, json: data
                        )
                    }
                }
            }
        }
    }

    /// Compute changed + removed entities. Keys normalized to String for JSON wire format.
    private static func computeDelta(
        entities: [Key: Entity],
        lastVersions: inout [Key: Int],
        version: (Entity) -> Int,
        keyToString: (Key) -> String
    ) -> EntityDelta<Entity> {
        var changed: [String: Entity] = [:]
        for (key, entity) in entities {
            let v = version(entity)
            if lastVersions[key] != v {
                changed[keyToString(key)] = entity
                lastVersions[key] = v
            }
        }
        let removed = lastVersions.keys
            .filter { entities[$0] == nil }
            .map { keyToString($0) }
        for key in lastVersions.keys where entities[key] == nil {
            lastVersions.removeValue(forKey: key)
        }
        return EntityDelta(changed: changed.isEmpty ? nil : changed,
                           removed: removed.isEmpty ? nil : removed)
    }
}

/// Wire format for entity deltas. Keys are always String (normalized from Key type).
/// Omits empty fields to minimize payload size.
struct EntityDelta<Entity: Encodable>: Encodable {
    let changed: [String: Entity]?
    let removed: [String]?

    var isEmpty: Bool { (changed?.isEmpty ?? true) && (removed?.isEmpty ?? true) }
}
```

### 6.7 PushPlan (Declarative Configuration)

A `PushPlan` groups slices for one state object. One plan per state class, one observation task per slice. The result builder provides clean declarative syntax.

```swift
@resultBuilder
struct PushPlanBuilder<State: Observable & AnyObject> {
    static func buildExpression<Snapshot: Encodable & Equatable>(
        _ slice: Slice<State, Snapshot>
    ) -> AnyPushSlice<State> {
        slice.erased()
    }

    static func buildExpression<Key: Hashable, Entity: Encodable>(
        _ slice: EntitySlice<State, Key, Entity>
    ) -> AnyPushSlice<State> {
        slice.erased()
    }

    static func buildBlock(_ slices: AnyPushSlice<State>...) -> [AnyPushSlice<State>] {
        Array(slices)
    }
}

/// Declarative push configuration for one state object.
/// Creates one observation task per slice. All slices share
/// the same RevisionClock (monotonic per store across the pane)
/// and EpochProvider (reads current epoch from domain state).
@MainActor
final class PushPlan<State: Observable & AnyObject> {
    private let state: State
    private let transport: PushTransport
    private let revisions: RevisionClock
    private let epochProvider: EpochProvider
    private let slices: [AnyPushSlice<State>]
    private var tasks: [Task<Void, Never>] = []

    init(
        state: State,
        transport: PushTransport,
        revisions: RevisionClock,
        epoch: @escaping EpochProvider,
        @PushPlanBuilder<State> slices: () -> [AnyPushSlice<State>]
    ) {
        self.state = state
        self.transport = transport
        self.revisions = revisions
        self.epochProvider = epoch
        self.slices = slices()
    }

    func start() {
        stop()
        tasks = slices.map { slice in
            slice.makeTask(state, transport, revisions, epochProvider)
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
```

### 6.8 Push Plan Configuration (Current Domain Shape)

State classes remain pure `@Observable` (see §8 for full definitions). Push configuration is declared separately:

```swift
// ── Snapshot types: small Encodable+Equatable structs ──────────
// These are the wire payloads pushed to React. They double as the
// cross-boundary contract — TypeScript stores expect these shapes.

struct DiffStatusSlice: Encodable, Equatable {
    let status: DiffStatus
    let error: String?
    let epoch: Int
}

struct ConnectionSlice: Encodable, Equatable {
    let health: ConnectionState.ConnectionHealth
    let latencyMs: Int
}

// ── Push plan declarations (inside BridgePaneController) ──────

/// Diff state push plan: 2 slices (hot status + cold manifest).
private func makeDiffPushPlan() -> PushPlan<DiffState> {
    PushPlan(
        state: paneState.diff,
        transport: self,
        revisions: revisionClock,
        epoch: { [paneState] in paneState.diff.epoch }
    ) {
        Slice("diffStatus", store: .diff, level: .hot) { state in
            DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
        }
        Slice("diffManifest", store: .diff, level: .cold, op: .replace) { state in
            state.manifest
        }
    }
}

/// Review state push plan: 2 slices (entity threads + scalar viewedFiles).
private func makeReviewPushPlan() -> PushPlan<ReviewState> {
    PushPlan(
        state: paneState.review,
        transport: self,
        revisions: revisionClock,
        epoch: { [paneState] in paneState.diff.epoch }
    ) {
        EntitySlice(
            "reviewThreads", store: .review, level: .warm,
            capture: { state in state.threads },
            version: { thread in thread.version },
            keyToString: { $0.uuidString }
        )
        Slice("viewedFiles", store: .review, level: .warm) { state in
            state.viewedFiles
        }
    }
}

/// Connection state push plan: 1 hot slice.
private func makeConnectionPushPlan() -> PushPlan<SharedBridgeState> {
    PushPlan(
        state: domainState,
        transport: self,
        revisions: revisionClock,
        epoch: { 0 }  // connection has no epoch concept
    ) {
        Slice("connectionHealth", store: .connection, level: .hot) { state in
            ConnectionSlice(health: state.connection.health,
                            latencyMs: state.connection.latencyMs)
        }
    }
}
```

Lifecycle integration (in `BridgePaneController`):

```swift
private var diffPushPlan: PushPlan<DiffState>?
private var reviewPushPlan: PushPlan<ReviewState>?
private var connectionPushPlan: PushPlan<SharedBridgeState>?

/// Called when bridge.ready is received from React (§4.5 step 6).
func handleBridgeReady() {
    diffPushPlan = makeDiffPushPlan()
    reviewPushPlan = makeReviewPushPlan()
    connectionPushPlan = makeConnectionPushPlan()

    diffPushPlan?.start()       // creates 2 observation tasks
    reviewPushPlan?.start()     // creates 2 observation tasks
    connectionPushPlan?.start() // creates 1 observation task
}

func teardown() {
    diffPushPlan?.stop()
    reviewPushPlan?.stop()
    connectionPushPlan?.stop()
}
```

### 6.9 How Observation Scoping Works

`Observations` (SE-0475) tracks which properties are **read** inside its closure. Each `Slice` capture closure defines its own tracking scope:

```swift
// This capture reads ONLY .status, .error, .epoch on DiffState.
// Observations tracks these three properties.
// Changes to .manifest do NOT fire this loop.
{ state in DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch) }

// This capture reads ONLY .manifest on DiffState.
// Changes to .status do NOT fire this loop.
{ state in state.manifest }
```

Two closures reading different properties of the same `@Observable` object fire independently. The PushPlan creates one `Task` per slice, so each slice has its own independent observation loop with its own debounce and push level.

**Change detection**: `Observations` tells you "something you tracked changed" but NOT which property changed. The `Equatable` comparison (`snapshot != prev`) inside each loop filters no-op mutations (e.g., setting `.status = .idle` when it was already `.idle`).

### 6.10 Push Cost Considerations

The push pipeline involves three CPU-bound steps per push: (1) Swift `JSONEncoder.encode()`, (2) JS `JSON.parse()`, (3) JS store update (replace or merge). For large state (100+ file manifest), this can spike CPU and drive rerender fanout.

**Mitigations**:

| Strategy | When | Effect |
|---|---|---|
| **Metadata-only pushes** (§10.1) | Diff loaded | Push `DiffManifest` (file list + metadata), NOT file contents |
| **Content pull on demand** (§10.2) | File enters viewport | React fetches via `agentstudio://resource/file/{id}` — no state stream overhead |
| **Debounced observation** (§6.2) | Rapid mutations | Coalesce multiple changes into one push (per-level cadence) |
| **Off-main encoding** (§6.5) | `.cold` payloads | `Task.detached(priority: .utility)` keeps main actor responsive |
| **Equatable skip** (§6.9) | No-op mutations | Snapshot comparison prevents push when value unchanged |
| **Per-entity diff** (§6.6) | Keyed collections | Only changed entities in delta payload, not full collection |
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

// Capture push nonce from handshake (bridge world dispatches at bootstrap).
// If we missed the initial event, request a replay.
let _pushNonce: string | null = null;
document.addEventListener('__bridge_handshake', ((e: CustomEvent) => {
    if (_pushNonce === null) {  // Accept only the first handshake
        _pushNonce = e.detail.pushNonce;
    }
}) as EventListener);

// Request replay in case bridge world fired before we registered
if (_pushNonce === null) {
    document.dispatchEvent(new CustomEvent('__bridge_handshake_request'));
}

// Per-store tracking for revision ordering and epoch staleness (§5.7)
const lastRevision: Record<string, number> = {};
const lastEpoch: Record<string, number> = {};

// Listen for state pushes relayed from bridge world via CustomEvent
document.addEventListener('__bridge_push', ((e: CustomEvent) => {
    // Reject forged push events from page-world scripts
    if (e.detail?.__pushNonce !== _pushNonce) return;

    const { type, store: storeName, data, __revision, __epoch } = e.detail;
    const store = stores[storeName];
    if (!store) {
        console.warn(`[bridge] Unknown store: ${storeName}`);
        return;
    }

    // Epoch check: if epoch is older than current, drop entirely (stale load generation)
    if (__epoch !== undefined && lastEpoch[storeName] !== undefined && __epoch < lastEpoch[storeName]) {
        return;
    }
    // Epoch advance: clear store state for new load generation
    if (__epoch !== undefined && __epoch > (lastEpoch[storeName] ?? 0)) {
        lastEpoch[storeName] = __epoch;
        lastRevision[storeName] = 0;  // reset revision tracking for new epoch
    }

    // Revision check: drop out-of-order pushes within same epoch
    if (__revision !== undefined && __revision <= (lastRevision[storeName] ?? 0)) {
        return;
    }
    if (__revision !== undefined) {
        lastRevision[storeName] = __revision;
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
    const commandId = `cmd_${crypto.randomUUID()}`;
    document.dispatchEvent(new CustomEvent('__bridge_command', {
        detail: { jsonrpc: "2.0", method, params, __nonce: nonce, __commandId: commandId }
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
    // Shared state that is truly application-wide (not per-pane).
    // Connection health was moved to PaneDomainState — see §8.7.
}
```

**Ownership**: `BridgePaneController` owns one `PaneDomainState` (which includes `ConnectionState` — see §8.7). It holds a reference to the singleton `SharedBridgeState` for any truly application-wide state. Each pane's observation loops push per-pane state into their respective Zustand stores.

### 8.2 Diff Source and Manifest

The diff viewer supports four data sources, all producing the same review UI:

```swift
enum DiffSource: Codable {
    case none
    case agentSnapshot(taskId: UUID, timestamp: Date)  // agent produced this
    case commit(sha: String)                            // single commit review
    case branchDiff(head: String, base: String)         // branch comparison
    case workspace(rootPath: String, baseline: WorkspaceBaseline) // live workspace review
}

enum WorkspaceBaseline: Codable {
    case workingTreeVsHEAD
    case workingTreeVsBranch(name: String)
    case indexVsHEAD
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
    case editComment(commentId: UUID, body: String)
    case deleteComment(commentId: UUID)
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

Connection health is **per-pane**, not shared. Each `BridgePaneController` owns its own `ConnectionState` because WebKit process crashes are per-WebPage — one pane crashing must not mark other panes as disconnected.

```swift
@Observable
class ConnectionState: Codable {
    var health: ConnectionHealth = .connected
    var latencyMs: Int = 0
    enum ConnectionHealth: String, Codable { case connected, disconnected, error }
}
```

> **Design decision**: Earlier drafts placed `ConnectionState` in `SharedBridgeState` as a singleton. This was incorrect — WebKit isolates each `WebPage` in its own web content process, so crashes are per-pane. `ConnectionState` is now owned by `PaneDomainState` alongside other per-pane state.

### 8.8 Codable Conformance

All domain types conform to `Codable` for JSON serialization across the bridge. `@Observable` classes use the macro's auto-generated `Codable` conformance. `AnyCodableValue` (existing in `PaneContent.swift`) is reused for flexible metadata fields.

---

## 9. Swift Bridge Coordinator

### 9.1 Bridge Coordinator

> **Naming**: The bridge coordinator is called `BridgePaneController` in the implementation (see §15.2). This follows the existing naming convention set by `WebviewPaneController` — each pane kind gets a `*PaneController`. The term "BridgeCoordinator" in this section refers to the same type; the implementation name takes precedence.

> **Relationship to `WebviewPaneController`**: The existing `WebviewPaneController` (`Services/WebviewPaneController.swift`) is a general-purpose browser controller that uses a shared static `WebPage.Configuration`. `BridgePaneController` is a separate type that creates a **per-pane** configuration with content world isolation, message handlers, URL scheme handlers, and bootstrap scripts. They share the same `WebPage` + `WebView` rendering path but have different configuration, lifecycle, and navigation policies. See §15.4 for the configuration strategy.

One controller per WebPage (per pane). Owns its `PaneDomainState`, holds a reference to shared state. Uses `PushPlan` (§6.7) for all observation loops — no hand-written observation code.

```swift
@Observable
@MainActor
class BridgePaneController {
    let paneId: UUID
    let page: WebPage
    let paneState: PaneDomainState
    let sharedState: SharedBridgeState
    private let router: RPCRouter
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")

    // Push infrastructure (§6)
    let revisionClock = RevisionClock()       // shared across all plans for this pane
    private var diffPushPlan: PushPlan<DiffState>?
    private var reviewPushPlan: PushPlan<ReviewState>?
    private var connectionPushPlan: PushPlan<SharedBridgeState>?

    init(paneId: UUID, state: BridgePaneState, sharedState: SharedBridgeState) {
        self.paneId = paneId
        self.paneState = PaneDomainState()
        self.sharedState = sharedState

        // Per-pane configuration — NOT shared (unlike WebviewPaneController.sharedConfiguration).
        // Each bridge pane needs its own userContentController, urlSchemeHandlers, and bootstrap scripts.
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()  // No cookies/history needed for internal app panels

        // Register message handler in bridge world only
        config.userContentController.add(RPCMessageHandler(coordinator: self),
                                         contentWorld: bridgeWorld,
                                         name: "rpc")

        // Bootstrap script — installs __bridgeInternal in bridge content world
        let bootstrap = WKUserScript(
            source: Self.bridgeBootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        config.userContentController.addUserScript(bootstrap)

        // Register binary scheme handler for agentstudio:// URLs
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(paneId: paneId)
        }

        self.page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),    // strict: agentstudio + about only
            dialogPresenter: WebviewDialogHandler()           // reuse existing handler
        )
        self.router = RPCRouter()

        Task { await registerHandlers() }
    }

    func loadApp() {
        let url = URL(string: "agentstudio://app/index.html")!
        page.load(URLRequest(url: url))
        // Push plans start when bridge.ready is received (see handleBridgeReady).
        // Do NOT start here — page.isLoading == false does not guarantee
        // React has mounted and listeners are attached (§4.5).
    }

    /// Called by RPCMessageHandler when it receives { type: "bridge.ready" } from bridge world.
    /// This is the ONLY trigger for starting push plans (§4.5 step 6).
    func handleBridgeReady() {
        guard diffPushPlan == nil else { return }  // idempotent

        // Create and start push plans (see §6.8 for plan declarations)
        diffPushPlan = makeDiffPushPlan()
        reviewPushPlan = makeReviewPushPlan()
        connectionPushPlan = makeConnectionPushPlan()

        diffPushPlan?.start()       // 2 observation tasks (status + manifest)
        reviewPushPlan?.start()     // 2 observation tasks (threads + viewedFiles)
        connectionPushPlan?.start() // 1 observation task (health)
    }

    func handleCommand(json: String) async {
        await router.dispatch(json: json, coordinator: self)
    }

    /// Send a JSON-RPC success response to JS (rare direct-response path).
    /// Uses a typed Encodable struct to avoid string surgery.
    func sendResponse(id: RPCId, result: Data) async {
        struct ResponseEnvelope: Encodable {
            let jsonrpc: String; let id: RPCId; let result: AnyCodableValue
        }
        guard let resultValue = try? JSONDecoder().decode(AnyCodableValue.self, from: result) else { return }
        let response = ResponseEnvelope(jsonrpc: "2.0", id: id, result: resultValue)
        guard let json = try? String(data: JSONEncoder().encode(response), encoding: .utf8) else { return }
        try? await page.callJavaScript(
            "window.__bridgeInternal.response(JSON.parse(json))",
            arguments: ["json": json],
            contentWorld: bridgeWorld
        )
    }

    /// Send a JSON-RPC error response to JS.
    /// Uses typed Encodable structs to avoid string interpolation injection.
    func sendError(id: RPCId, code: Int, message: String) async {
        struct ErrorBody: Encodable { let code: Int; let message: String }
        struct ErrorResponse: Encodable { let jsonrpc: String; let id: RPCId; let error: ErrorBody }
        let response = ErrorResponse(jsonrpc: "2.0", id: id, error: ErrorBody(code: code, message: message))
        guard let json = try? String(data: JSONEncoder().encode(response), encoding: .utf8) else { return }
        try? await page.callJavaScript(
            "window.__bridgeInternal.response(JSON.parse(json))",
            arguments: ["json": json],
            contentWorld: bridgeWorld
        )
    }

    func teardown() {
        diffPushPlan?.stop()
        reviewPushPlan?.stop()
        connectionPushPlan?.stop()
        diffPushPlan = nil
        reviewPushPlan = nil
        connectionPushPlan = nil
    }

    // MARK: - Page Lifecycle

    /// Handle WebPage termination events (page close, web process crash, navigation failure).
    /// WebPage can terminate due to: pageClosed, provisional navigation failure, or
    /// web-content process termination. The bridge must detect these, update health state,
    /// and cleanly tear down push plans.
    func handlePageTermination(reason: PageTerminationReason) {
        domainState.connection.health = .disconnected
        teardown()

        switch reason {
        case .webProcessCrash:
            logger.error("[Bridge] Web content process crashed — bridge disconnected")
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

    /// Resume push plans after page reload (e.g., after web process crash recovery).
    /// Re-pushes full state to ensure React is synchronized.
    func resumeAfterReload() {
        guard diffPushPlan == nil else { return }
        domainState.connection.health = .connected

        Task {
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
            // Full state re-push on reload to sync React
            await pushFullState()
            handleBridgeReady()
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

    func dispatch(json: String, coordinator: BridgePaneController) async {
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
    /// Handles both String and Int ids per JSON-RPC 2.0 spec.
    /// Returns nil if the JSON doesn't contain a parseable "id" field.
    private func extractId(from json: String) -> RPCId? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] else { return nil }
        if let stringId = id as? String { return .string(stringId) }
        if let intId = id as? Int { return .number(intId) }
        return nil
    }
}

/// JSON-RPC 2.0 envelope. The `id` field accepts both string and integer
/// per the spec ("An identifier established by the Client that MUST contain
/// a String, Number, or NULL value"). Decoded to String for internal use.
struct RPCEnvelope: Codable {
    let jsonrpc: String
    let id: RPCId?
    let method: String
    let params: AnyCodableValue?  // Reuses existing AnyCodableValue from PaneContent.swift
}

/// JSON-RPC id: accepts both String and Int, normalizes to String.
enum RPCId: Codable, Equatable {
    case string(String)
    case number(Int)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let n = try? container.decode(Int.self) { self = .number(n) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "id must be string or number") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        }
    }
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
    private weak var coordinator: BridgePaneController?

    init(coordinator: BridgePaneController) {
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
// React: triggered by Pierre's virtualizer when a file becomes visible.
// Includes current epoch in URL so server can reject stale requests.
async function loadFileContent(fileId: string, epoch: number): Promise<FileContents> {
    const response = await fetch(`agentstudio://resource/file/${fileId}?epoch=${epoch}`);
    if (!response.ok) throw new Error(`Failed to load file ${fileId}`);
    const data = await response.json(); // { oldContent, newContent }
    return data;
}
```

```swift
// Swift: BridgeSchemeHandler serves file contents
// Path: agentstudio://resource/file/{fileId}?epoch={epoch}
// The client includes its current epoch in the query string so the server can
// reject requests from a previous diff generation even if file IDs overlap.
func resolveResource(for request: URLRequest) async throws -> (Data, String) {
    guard let url = request.url,
          let fileId = extractFileId(from: url),
          let clientEpoch = extractEpoch(from: url) else {
        throw BridgeError.invalidRequest("Invalid resource URL — must include fileId and epoch")
    }

    // Epoch check: reject requests from a stale diff generation
    guard clientEpoch == paneState.diff.epoch else {
        throw BridgeError.staleRequest("Client epoch \(clientEpoch) != current \(paneState.diff.epoch)")
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

        const epoch = useDiffStore.getState().epoch;
        fetch(`agentstudio://resource/file/${fileId}?epoch=${epoch}`, { signal: controller.signal })
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

### 10.5 Workspace Refresh Strategy (Event-First, Poll-Safe)

For live workspace sources, refresh is event-driven first with periodic safety revalidation:

| Trigger | Cadence | Action |
|---|---|---|
| File-system/git change event | Debounced 250-500ms | Incremental recompute for changed paths only |
| Manual refresh command | On demand | Force manifest recompute for current source |
| Safety revalidation timer | Every 10-15s | Verify event stream health and reconcile drift |

**Algorithm**:
1. Collect changed paths during debounce window.
2. Recompute metadata only for affected files.
3. Patch manifest in-place (insert/update/remove file entries).
4. Bump per-store `revision` (same `epoch` for incremental update).
5. If base source changes (new branch/commit/snapshot/workspace target), bump `epoch`, clear content cache, cancel in-flight loads, push fresh manifest.

**Why**: This avoids full-manifest rebuild every few seconds, keeps bridge traffic small, and preserves scroll/context in large diffs.

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

// Expose pushNonce to page world via a handshake stored in a closure,
// NOT via a DOM attribute (unlike bridgeNonce, this must not be readable by
// arbitrary page-world scripts).
//
// The receiver captures it at initialization via a '__bridge_handshake' event.
// To avoid a startup race (listener registers after event fires), the bridge
// world stores the nonce and replays it on demand when it sees a
// '__bridge_handshake_request' event from the page world.
document.addEventListener('__bridge_handshake_request', () => {
    // Page world missed the initial handshake — replay it
    document.dispatchEvent(new CustomEvent('__bridge_handshake', {
        detail: { pushNonce }
    }));
});

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

**Page world (React) listens** — validates push nonce to reject forged events. Uses replay request to handle startup race (see §7.2):
```typescript
// bridge/receiver.ts — installed in page world
// Capture push nonce from handshake (bridge world dispatches at bootstrap).
// If missed, request a replay via '__bridge_handshake_request'.
let _pushNonce: string | null = null;
document.addEventListener('__bridge_handshake', ((e: CustomEvent) => {
    if (_pushNonce === null) {
        _pushNonce = e.detail.pushNonce;
    }
}) as EventListener);
if (_pushNonce === null) {
    document.dispatchEvent(new CustomEvent('__bridge_handshake_request'));
}

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

The codebase has two navigation deciders for different pane kinds:

| Decider | File | Pane Kind | Allowed Schemes | Behavior for Other Schemes |
|---|---|---|---|---|
| `WebviewNavigationDecider` | `Services/WebviewNavigationDecider.swift` | Browser panes | `https`, `http`, `about`, `file`, `agentstudio` | Block silently |
| `BridgeNavigationDecider` | `Bridge/BridgeNavigationDecider.swift` (new) | Bridge panes | `agentstudio`, `about` | Block; `http`/`https` open in default browser |

The bridge decider is **strictly locked down** — bridge panels load only our bundled React app via `agentstudio://` and never navigate to external URLs:

```swift
/// Navigation policy for bridge-backed panels. Allows only internal schemes.
/// External URLs (http/https) are opened in the default browser, not rendered in the panel.
///
/// Contrast with `WebviewNavigationDecider` which allows http/https for browser panes.
final class BridgeNavigationDecider: WebPage.NavigationDeciding {
    static let allowedSchemes: Set<String> = ["agentstudio", "about"]
    private static let externalSchemes: Set<String> = ["http", "https"]

    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url,
              let scheme = url.scheme?.lowercased() else { return .cancel }

        if Self.allowedSchemes.contains(scheme) {
            return .allow
        }

        // External URLs — open in default browser, don't render in panel
        if Self.externalSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        // All other schemes (javascript:, data:, blob:, vbscript:, etc.) — block silently
        return .cancel
    }
}
```

---

## 12. Diff Viewer Integration (Pierre)

### 12.1 Pierre Packages

The diff viewer uses two Pierre packages:

| Package | Purpose | Verified Exports (contracted) |
|---|---|---|
| **`@pierre/diffs`** | Diff rendering with syntax highlighting | `@pierre/diffs/react` for React components (`MultiFileDiff`, `PatchDiff`, `FileDiff`), `@pierre/diffs/worker` for worker APIs (`WorkerPoolManager`) |
| **`@pierre/file-tree`** | File tree sidebar with search | `@pierre/file-tree/react` React entry point and core package APIs from `@pierre/file-tree` |

> **Verification rule**: Use only symbols exported by the installed package version. Do not rely on internal symbols or undocumented paths. If a symbol is not in package exports, treat it as unavailable.

### 12.2 Virtualized Diff Rendering

Pierre provides performant diff rendering with worker-backed highlighting. For large manifests, keep viewport-driven content loading in our bridge regardless of Pierre component shape.

```typescript
import { MultiFileDiff } from '@pierre/diffs/react';
import { WorkerPoolManager } from '@pierre/diffs/worker';

// Shared worker pool for syntax highlighting
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
- Diff components should render from manifest metadata first, then hydrate with content from the data stream
- Visibility/viewport signals trigger content loading via our priority queue
- `WorkerPoolManager` offloads syntax highlighting to web workers — critical for 500-file diffs
- `cacheKey` on `FileContents` enables worker-side AST caching; scrolling back to a file is instant

### 12.3 File Tree (Pierre)

Pierre's file tree APIs vary by version. The currently documented integration model is plugin-oriented (`createFileTree` + React plugin). Use that as the default shape and keep the adapter isolated:

```typescript
import { createFileTree } from '@pierre/file-tree';
import { fileTreeReactPlugin, FileTreeComponent } from '@pierre/file-tree/react';

function DiffSidebar() {
    const manifest = useDiffManifest();
    const tree = useMemo(() => createFileTree({
        plugins: [fileTreeReactPlugin()],
        files: manifest.files.map((f) => f.path),
    }), [manifest]);

    return <FileTreeComponent tree={tree} />;
}
```

**Custom badges**: Pierre's file tree renders `Icon` + `itemName` per node. To show status badges (change type, comment count, viewed), extend the tree item rendering or overlay badges via CSS selectors on `data-file-tree-item` attributes.

**Search/filter**: Built-in via `fileTreeSearchFeature`. Supports `expand-matches` and `collapse-non-matches` modes. Bound to the search input with `data-file-tree-search-input`. Filtering 500 files is pure JS — <16ms, no bridge traffic.

### 12.4 Content Loading Lifecycle

```
1. Swift pushes DiffManifest via state stream (file paths, sizes, hunk summaries)
2. React passes manifest to Pierre FileTree + creates diff components per file
3. Viewport visibility signals determine which files are active
4. Active file signal fires → content loader triggers
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
    guard !params.threadIds.isEmpty else {
        throw RPCError.invalidParams("threadIds must not be empty")
    }
    let task = AgentTask(
        id: UUID(),
        source: .threads(threadIds: params.threadIds),
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

### 13.0 Cross-Session Continuity Artifacts

Agent memory loss is expected; continuity is preserved through repository artifacts:

| Artifact | Location | Required Content |
|---|---|---|
| Architecture Decision Records (ADRs) | `docs/architecture/adr/` | Decision, alternatives, tradeoffs, reversal conditions |
| Bridge contract fixtures | `Tests/BridgeContractFixtures/` and `WebApp/test/fixtures/bridge/` | Valid/invalid/stale/duplicate/reordered payload examples |
| Stage handoff notes | `docs/architecture/swift_react_bridge_design.md` (phase checklist) | What is done, what is pending, which tests must pass next |
| Failure mode matrix | `docs/architecture/swift_react_bridge_failures.md` | Timeout, duplication, reorder, stale epoch, cancellation behavior |

No phase is considered complete unless these artifacts are updated.

### 13.1 Test Pyramid and Contract Parity

Testing prioritizes correctness under protocol failure modes, not snapshot volume:

| Layer | Focus | Required |
|---|---|---|
| Unit (majority) | Reducers, reconciler, envelope parsing, dedupe, epoch/revision rules | Fast and exhaustive |
| Integration | Swift bridge <-> page world transport, shared fixtures, cancellation, ordering | Deterministic harness |
| E2E (small set) | User-critical flows: instant comment UX, large diff loading, recovery/resync | Budgeted performance assertions |

**Contract parity rule**:
- Every bridge payload shape must have fixture-driven tests in BOTH Swift and TypeScript.
- Additions to contract types are blocked until both suites are updated.
- Invalid fixtures must fail decoding/validation deterministically in both runtimes.
- Test failures must print `commandId`, `epoch`, `revision`, and method/store names to make CI logs "see-through" without a custom inspector UI.

### Phase 1: Transport Foundation

**Goal**: `callJavaScript` and `postMessage` work bidirectionally.

**Deliverables**:
- `BridgePaneController` creates `WebPage` with per-pane configuration
- `BridgeSchemeHandler` serves bundled React app from `agentstudio://app/*`
- React app loads and renders in `WebView`
- Bootstrap script installs `window.__bridgeInternal` in bridge content world
- Message handler receives `postMessage` from bridge world
- Round-trip test: Swift calls JS → JS posts message → Swift receives

**Tests**:
- Unit: `BridgeSchemeHandler` returns correct MIME types and data for app resources
- Unit: `RPCMessageHandler` parses valid/invalid JSON correctly
- Integration: WebPage loads `agentstudio://app/index.html` and renders React
- Integration: Round-trip `callJavaScript` → `postMessage` → Swift handler fires

### Phase 2: State Push Pipeline

**Goal**: Swift `@Observable` changes arrive in Zustand stores via declarative `PushPlan` infrastructure (§6) and agent event stream.

**Deliverables**:
- Push infrastructure: `PushPlan`, `Slice`, `EntitySlice`, `PushTransport`, `RevisionClock` (§6.4–6.7)
- Push plan declarations for `DiffState`, `ReviewState`, `SharedBridgeState` (§6.8)
- `BridgePaneController` conforms to `PushTransport`, owns `RevisionClock` shared across all plans
- Zustand stores for `diff`, `review`, `agent`, and `connection` domains
- Bridge receiver listens for `__bridge_push` and `__bridge_agent` CustomEvents relayed from `__bridgeInternal`, routes to correct Zustand store
- Push envelope carries `__revision` (per store, monotonic via shared `RevisionClock`) and `__epoch` (from `EpochProvider`) — React drops stale pushes
- `.hot` slices push immediately; `.warm`/`.cold` use debounce from `PushLevel.debounce` (§6.2)
- `.cold` payloads encode off-main-actor via `Task.detached(priority: .utility)` (§6.5)
- Error handling: push failures log `store/level/revision/epoch/pushId` per §13.1
- Content world ↔ page world relay via CustomEvents

**Tests**:
- Unit: `PushPlan` creates correct number of observation tasks per slice
- Unit: `Slice` snapshot comparison filters no-op mutations (same value → no push)
- Unit: `EntitySlice` per-entity diff — only changed entities appear in delta
- Unit: `EntityDelta` normalizes keys to String in wire format
- Unit: `RevisionClock` produces monotonic values per store across concurrent callers
- Unit: `deepMerge` correctly merges partial state (if used; `replace`-only stores skip this)
- Unit: Zustand store updates on `merge` and `replace` calls
- Unit: Bridge receiver routes `__bridge_push` to correct store by `store` field
- Unit: Stale push rejection — push with `revision <= lastSeen` dropped
- Unit: Epoch mismatch — push with wrong `epoch` triggers cache clear
- Integration: Mutate `@Observable` property in Swift → verify Zustand store updated via PushPlan
- Integration: Rapid mutations coalesce into single push (verify with push counter per slice)
- Integration: `.hot` slice pushes immediately; `.cold` slice debounces (verify with timing)
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
- `DiffSource` enum: `.agentSnapshot`, `.commit`, `.branchDiff`, `.workspace`
- State stream: Swift pushes `DiffManifest` (file metadata only) into diff Zustand store
- Data stream: `BridgeSchemeHandler` extended for `agentstudio://resource/file/{id}` — React pulls file contents on demand
- Priority queue on React side: viewport files (high), hovered files (medium), neighbor files (low), cancel when leaving viewport
- LRU content cache (~20 files) in React, cleared on epoch change
- Pierre diff renderer integration (`@pierre/diffs/react`) with viewport-driven content hydration
- Pierre file tree adapter (`@pierre/file-tree`) for navigation and search
- Pierre `WorkerPoolManager` offloads syntax highlighting to web workers
- Path validation and security hardening for resource URLs
- Workspace refresh pipeline: event-driven incremental manifest updates + 10-15s safety revalidation

**Tests**:
- Unit: `DiffManifest` / `FileManifest` Codable round-trip
- Unit: `BridgeSchemeHandler` validates allowed resource types and rejects forbidden paths
- Unit: Priority queue ordering logic (viewport > hover > neighbor)
- Unit: LRU cache evicts oldest entries beyond capacity, clears on epoch bump
- Unit: Pierre diff component renders with mock file contents
- Integration: Swift pushes `DiffManifest` → FileTree renders file list within 100ms
- Integration: React `fetch('agentstudio://resource/file/xyz')` returns correct file content
- Integration: Scroll file into viewport → content pull fires → diff renders within 200ms
- Integration: Epoch guard: start new diff during active load → stale results discarded
- Integration: Workspace file change burst (N updates in debounce window) triggers incremental manifest patch, not full reload
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
| **G11** | Contract parity is enforced across Swift and TS | Every contract change updates shared fixtures + both test suites |
| **G12** | Optimistic overlay never becomes authoritative | Pending UI entities expire or reconcile; only Swift-pushed state is durable truth |

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
- [ ] `PushPlan` + `Slice` + `EntitySlice` infrastructure compiles and creates correct observation tasks
- [ ] `RevisionClock` produces monotonic revisions per store across all plans in a pane
- [ ] `EpochProvider` reads real epoch from domain state (not hardcoded 0)
- [ ] `.hot` slice: mutate `@Observable` property → Zustand store updated within 1 frame (< 16ms)
- [ ] `.cold` slice: payload encodes off-main-actor via `Task.detached` (verify main actor not blocked)
- [ ] 10 rapid synchronous mutations coalesce into ≤ 2 pushes per slice (verify with push counter)
- [ ] `EntitySlice`: single entity change → delta contains only that entity (not full collection)
- [ ] `EntityDelta` wire format uses String keys (UUID normalized, not raw)
- [ ] Push failures log `store/level/revision/epoch/pushId` (verify log output format)
- [ ] Push 100-file `DiffManifest` (metadata only): end-to-end < 32ms on target hardware
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
- [ ] Pierre diff renderer path renders with syntax highlighting (WorkerPoolManager active)
- [ ] Pierre `FileTree` search/filter works on 500+ file manifest
- [ ] Workspace refresh: bursty file changes produce incremental manifest patch (same epoch), not full reset

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
│   ├── BridgePaneController.swift        # Per-pane controller: WebPage setup, PushPlan lifecycle, PushTransport conformance
│   ├── BridgePaneState.swift             # BridgePaneState, BridgePanelKind, BridgePaneSource
│   ├── BridgePaneView.swift              # AppKit PaneView hosting BridgePaneContentView
│   ├── BridgePaneContentView.swift       # SwiftUI view: WebView(controller.page), no nav bar
│   ├── RPCRouter.swift                   # Method registry + dispatch
│   ├── RPCMethod.swift                   # Protocol + type-erased handler
│   ├── RPCMessageHandler.swift           # WKScriptMessageHandler for postMessage
│   ├── BridgeSchemeHandler.swift         # agentstudio:// URL scheme (app + resource)
│   ├── BridgeNavigationDecider.swift     # Strict navigation: agentstudio + about only
│   ├── BridgeBootstrap.swift             # JS bootstrap script for bridge world
│   ├── Push/                             # Declarative push infrastructure (§6)
│   │   ├── PushPlan.swift                # PushPlan, PushPlanBuilder (result builder)
│   │   ├── Slice.swift                   # Slice (value-level observation)
│   │   ├── EntitySlice.swift             # EntitySlice (keyed collection, per-entity diff)
│   │   ├── PushTransport.swift           # PushTransport protocol, PushLevel, PushOp, StoreKey
│   │   ├── RevisionClock.swift           # Monotonic per-store revision counter
│   │   └── PushSnapshots.swift           # DiffStatusSlice, ConnectionSlice, EntityDelta (wire types)
│   └── Methods/                          # One file per namespace
│       ├── DiffMethods.swift             # diff.requestFileContents, diff.loadDiff
│       ├── ReviewMethods.swift           # review.addComment, review.resolveThread
│       ├── AgentMethods.swift            # agent.sendReview, agent.cancelTask
│       └── SystemMethods.swift           # system.ping, system.getCapabilities
├── Domain/                               # Bridge-specific domain models (separate from Models/)
│   ├── BridgeDomainState.swift           # @Observable root: PaneDomainState, SharedBridgeState
│   ├── DiffManifest.swift                # DiffManifest, FileManifest, HunkSummary, DiffSource
│   ├── ReviewState.swift                 # ReviewThread, ReviewComment, ReviewAction, CommentAnchor
│   ├── AgentTask.swift                   # AgentTask, AgentTaskStatus
│   ├── TimelineEvent.swift               # TimelineEvent, TimelineEventKind (in-memory v1)
│   └── ConnectionState.swift             # Connection health
│   # Note: BridgePaneState and BridgePanelKind live in Bridge/ (co-located with controller)
├── Services/                             # Existing services (unchanged)
│   ├── WebviewPaneController.swift       # Browser pane controller (shared config, browser navigation)
│   ├── WebviewNavigationDecider.swift    # Browser navigation policy (http/https/file/about/agentstudio)
│   ├── WebviewDialogHandler.swift        # JS dialog handler (reused by bridge panes)
│   └── ...
└── (rest of existing Sources structure unchanged)

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
│   │   ├── DiffPanel.tsx                 # Layout: FileTree sidebar + diff renderer main
│   │   ├── FileTreeSidebar.tsx           # Pierre FileTree adapter (plugin/component API)
│   │   ├── FileDiffView.tsx              # Pierre diff component wrapper per file
│   │   ├── ReviewThreadOverlay.tsx       # Comment thread UI (add, resolve, delete)
│   │   ├── DiffHeader.tsx                # Status bar: source, file count, agent progress
│   │   └── SendToAgentButton.tsx         # Creates AgentTask with review context
│   ├── utils/
│   │   └── deep-merge.ts
│   └── App.tsx
├── vite.config.ts
└── package.json

Contracts/
├── bridge/
│   ├── command.schema.json               # JSON-RPC command envelope extensions
│   ├── push.schema.json                  # state/agent push envelope schema
│   └── ack.schema.json                   # commandAck schema

Tests/
├── BridgeContractFixtures/               # Shared fixture corpus consumed by Swift + TS tests
│   ├── valid/
│   ├── invalid/
│   └── edge/
```

---

## 15. Integration with Existing Pane System

### 15.1 Current State (Post Window System 7)

The pane system is fully operational. Webview panes already work as general-purpose browser panes:

| Component | File | Role |
|---|---|---|
| `PaneContent.webview(WebviewState)` | `Models/PaneContent.swift` | Discriminated union case for webview panes |
| `WebviewState` | `Models/PaneContent.swift` | Serializable state: `url`, `title`, `showNavigation` |
| `WebviewPaneController` | `Services/WebviewPaneController.swift` | Per-pane `@Observable` controller owning a `WebPage` |
| `WebviewPaneView` | `Views/WebviewPaneView.swift` | AppKit `PaneView` subclass hosting SwiftUI via `NSHostingView` |
| `WebviewPaneContentView` | `Views/Webview/WebviewPaneContentView.swift` | SwiftUI view: nav bar + `WebView(controller.page)` |
| `WebviewNavigationDecider` | `Services/WebviewNavigationDecider.swift` | Browser-oriented allowlist: `https`, `http`, `about`, `file`, `agentstudio` |
| `WebviewDialogHandler` | `Services/WebviewDialogHandler.swift` | JS dialog handler (default implementations) |
| `TerminalViewCoordinator.createViewForContent` | `App/TerminalViewCoordinator.swift` | Routes `PaneContent` → view creation; webview case at line 101 |
| `ActionExecutor.openWebview(url:)` | `App/ActionExecutor.swift` | Creates browser pane with `WebviewState` + tab |

All webview panes currently share a single static `WebPage.Configuration` (`WebviewPaneController.sharedConfiguration`) with default `websiteDataStore`. The `ViewRegistry` tracks all webview views and supports lookup by pane ID.

### 15.2 Pane Kind Split: Browser vs Bridge

Bridge panes (diff viewer, code review) have fundamentally different requirements from browser panes:

| Concern | Browser Pane | Bridge Pane |
|---|---|---|
| **Navigation** | Open web (`http`, `https`, `file`) | Locked to `agentstudio://` + `about:` only |
| **Configuration** | Shared static config, default data store | Per-pane config with `userContentController`, `urlSchemeHandlers`, bridge scripts |
| **Content worlds** | Not used (page world only) | Bridge content world isolates `__bridgeInternal` from page scripts |
| **Message handlers** | None | `rpc` handler scoped to bridge world |
| **URL scheme** | Standard schemes | `agentstudio://app/*` serves bundled React app; `agentstudio://resource/*` serves file contents |
| **Lifecycle** | Stateless (no observation loops) | `BridgePaneController` runs observation loops, pushes state, handles teardown |
| **State model** | `WebviewState` (url, title, showNavigation) | `BridgePaneState` (source, panel type — no URL bar, no browser navigation) |

**Implementation approach**: A new `PaneContent` case for bridge panes, with a dedicated controller type:

```swift
// PaneContent gains a new case:
enum PaneContent: Hashable {
    case terminal(TerminalState)
    case webview(WebviewState)          // Browser panes (existing)
    case bridgePanel(BridgePaneState)   // Bridge-backed app panels (new)
    case codeViewer(CodeViewerState)
    case unsupported(UnsupportedContent)
}

/// State for a bridge-backed panel (diff viewer, code review, etc.).
/// Unlike WebviewState, this has no user-visible URL or navigation controls.
struct BridgePaneState: Codable, Hashable {
    let panelKind: BridgePanelKind
    var source: BridgePaneSource?       // what this panel is displaying (set after creation)
}

enum BridgePanelKind: String, Codable, Hashable {
    case diffViewer                     // Diff review panel (Pierre-based)
    // Future: .agentDashboard, .prStatus, etc.
}

/// What the bridge panel is displaying. Serializable for persistence/restore.
enum BridgePaneSource: Codable, Hashable {
    case commit(sha: String)
    case branchDiff(head: String, base: String)
    case workspace(rootPath: String, baseline: WorkspaceBaseline)
    case agentSnapshot(taskId: UUID, timestamp: Date)
}
```

### 15.3 Routing and View Creation

`TerminalViewCoordinator.createViewForContent` gains a new case:

```swift
case .bridgePanel(let state):
    let controller = BridgePaneController(paneId: pane.id, state: state, sharedState: sharedBridgeState)
    let view = BridgePaneView(paneId: pane.id, controller: controller)
    viewRegistry.register(view, for: pane.id)
    return view
```

`ActionExecutor` gains a new method:

```swift
func openDiffViewer(source: BridgePaneSource? = nil) -> Pane? {
    let state = BridgePaneState(panelKind: .diffViewer, source: source)
    let pane = store.createPane(
        content: .bridgePanel(state),
        metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Diff Viewer"), title: "Diff Viewer")
    )
    // ... create view, tab, same pattern as openWebview
}
```

### 15.4 Configuration Strategy

| Pane Kind | Configuration | Rationale |
|---|---|---|
| **Browser** | `WebviewPaneController.sharedConfiguration` (static, shared) | All browser panes share cookies/localStorage; no custom handlers needed |
| **Bridge** | Per-pane `WebPage.Configuration` (created in `BridgePaneController.init`) | Each bridge pane needs its own `userContentController` (message handler + bootstrap script), `urlSchemeHandlers` (app + resource serving), and content world setup |

```swift
// BridgePaneController creates a dedicated config per instance:
init(paneId: UUID, state: BridgePaneState, sharedState: SharedBridgeState) {
    var config = WebPage.Configuration()
    // Bridge-specific: non-persistent data store (no cookies/history needed)
    config.websiteDataStore = .nonPersistent()

    // Per-pane message handler in bridge world
    config.userContentController.add(
        RPCMessageHandler(coordinator: self),
        contentWorld: bridgeWorld,
        name: "rpc"
    )

    // Per-pane bootstrap script in bridge world
    let bootstrap = WKUserScript(
        source: bridgeBootstrapJS,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true,
        in: bridgeWorld
    )
    config.userContentController.addUserScript(bootstrap)

    // Per-pane URL scheme handler
    if let scheme = URLScheme("agentstudio") {
        config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(paneId: paneId)
    }

    self.page = WebPage(
        configuration: config,
        navigationDecider: BridgeNavigationDecider(),   // strict: agentstudio + about only
        dialogPresenter: WebviewDialogHandler()          // reuse existing handler
    )
    // ...
}
```

### 15.5 Pane Lifecycle

- **Creation**: `ActionExecutor.openDiffViewer()` → `TerminalViewCoordinator.createViewForContent(.bridgePanel)` → `BridgePaneController` + `BridgePaneView` → `ViewRegistry.register`
- **Active**: `BridgePaneController` owns observation loops (started on `bridge.ready`), pushes state to Zustand
- **Teardown**: `BridgePaneController.teardown()` cancels observation tasks, releases `WebPage`. Triggered by pane removal via `WorkspaceStore.removePane` → `ViewRegistry.deregister`
- **Persistence**: `BridgePaneState` is `Codable` — round-trips through workspace save/restore. On restore, the panel reloads from source (re-computes manifest from git)

### 15.6 Shared State

- **`SharedBridgeState` is singleton** — held by `TerminalViewCoordinator` (or `AppDelegate`), injected into each `BridgePaneController`
- Holds truly application-wide state (not per-pane). Connection health is **per-pane** (see §8.7)
- Browser panes do NOT interact with `SharedBridgeState`

The existing `ViewRegistry`, `Layout`, drag/drop, and split system work unchanged — the bridge pane is just another leaf in the layout tree.

---

## 16. Open Questions

### Resolved (in this document)

- ~~**Domain state scope**~~ → **Per-pane** `PaneDomainState` (diff, review, agent tasks, timeline, connection health). `SharedBridgeState` exists for truly application-wide state. See §8.1, §8.7.
- ~~**CustomEvent command forgery**~~ → **Nonce token** generated at bootstrap, validated by bridge world. See §11.3.
- ~~**Push error handling**~~ → **do-catch** with logging and connection health state update. No force-unwraps. See §6.4.
- ~~**File loading race conditions**~~ → **Metadata push + content pull with priority queue, LRU cache, and epoch guard**. See §10.
- ~~**Large diff delivery**~~ → **Three-stream architecture**: metadata via state stream, file contents via data stream (pull-based), agent events via batched agent stream. See §1, §4.4, §10.
- ~~**Comment anchoring across line shifts**~~ → **Content hash + line number** with `isOutdated` flag. See §8, §12.5.
- ~~**Navigation policy edge cases**~~ → **Explicit blocklist** for `javascript:`, `data:`, `blob:`, `vbscript:`. Two deciders: `WebviewNavigationDecider` for browser panes, `BridgeNavigationDecider` for bridge panes. See §11.4.
- ~~**"Swift is too slow for interaction UX" concern**~~ → **Authority matrix**: interaction state is local in React; Swift owns durable domain truth. See §3.3.
- ~~**Periodic workspace updates vs efficiency**~~ → **Event-first refresh with safety poll and incremental invalidation**. See §10.5.

### Resolved by Existing Codebase (Post Window System 7 Merge)

These were previously open questions or verification spike items, now proven by working production code:

- ~~**`WebPage` initialization with `Configuration`**~~ → `WebviewPaneController` creates `WebPage(configuration:navigationDecider:dialogPresenter:)` successfully. See `Services/WebviewPaneController.swift:52`.
- ~~**`WebPage.NavigationDeciding` protocol**~~ → `WebviewNavigationDecider` implements the protocol with `decidePolicy(for:preferences:)`. Proven pattern. See `Services/WebviewNavigationDecider.swift:10`.
- ~~**`WebPage.DialogPresenting` protocol**~~ → `WebviewDialogHandler` conforms with default implementations. See `Services/WebviewDialogHandler.swift:9`.
- ~~**SwiftUI `WebView` rendering**~~ → `WebView(controller.page)` renders in `WebviewPaneContentView`. See `Views/Webview/WebviewPaneContentView.swift:25`.
- ~~**Pane system integration**~~ → Full create/teardown/persist/restore lifecycle working. `PaneContent.webview`, `WebviewState`, `TerminalViewCoordinator.createViewForContent`, `ActionExecutor.openWebview`, `ViewRegistry` — all operational.
- ~~**`AnyCodableValue` availability**~~ → Exists in `Models/PaneContent.swift:112`. Reusable for RPC envelope params.
- ~~**Pane kind split (browser vs bridge)**~~ → Architecture decided: new `PaneContent.bridgePanel(BridgePaneState)` case with dedicated `BridgePaneController`. See §15.2.

### Resolved by Verification Spike (Stage 0)

All bridge-specific WebKit APIs verified. Spike tests in `Tests/AgentStudioTests/Bridge/`. Results:

1. **`WKContentWorld.world(name:)`** — ✅ PASS. Same name returns identical object (`===`). Different names produce different worlds. See `BridgeWebKitSpikeTests.swift`.

2. **`callJavaScript(_:arguments:contentWorld:)`** — ✅ PASS. Arguments become JS local variables. Content world targeting works. **API finding:** `callJavaScript` returns nil in headless test context (no window host), but side effects (postMessage) execute correctly. Production use is unaffected since WebPages are always hosted in a WebView inside a window. Tests use message handlers as verification probes instead of return values.

3. **`WKUserScript(source:injectionTime:forMainFrameOnly:in:)`** — ✅ PASS. The `in:` parameter correctly targets a content world. A script injected into bridge world sets `window.__testFlag = true`; bridge world reads `"true"`, page world reads `"undefined"`. See `BridgeWebKitSpikeTests.swift`.

4. **`userContentController.add(handler, contentWorld:, name:)`** — ✅ PASS. Message handler scoped to bridge world receives messages from bridge world. Page world cannot access bridge-world-scoped handlers (`window.webkit?.messageHandlers?.rpc` is undefined in page world). JSON string payloads (JSON-RPC pattern) delivered correctly. See `BridgeWebKitSpikeTests.swift`.

5. **`URLSchemeHandler` protocol with `AsyncSequence`** — ✅ PASS. **API finding:** Protocol requires `Failure == any Error`, so `AsyncThrowingStream<URLSchemeTaskResult, any Error>` is needed (not `AsyncStream`). **API finding:** `URLScheme("agentstudio")` is a failable initializer — returns nil for built-in schemes, needs force-unwrap or guard for custom schemes. See `BridgeSchemeHandlerSpikeTests.swift`.

6. **`Observations` creation and `for await` iteration** — ✅ PASS. `Observations { state.property }` yields initial value immediately, then re-evaluates on tracked property change. Uses did-set semantics. See `ObservationSpikeTests.swift`.

7. **`.debounce(for:)` on `Observations`** — ✅ PASS. Works directly on `Observations` sequence via `AsyncAlgorithms`. Uses Swift `Duration` (not `TimeInterval`). Coalesces rapid synchronous mutations. See `ObservationSpikeTests.swift`.

8. **Property-group isolation** — ✅ PASS (CRITICAL). `Observations { state.propertyA }` does **NOT** fire when only `state.propertyB` changes. **This confirms the `Slice` capture closure design from §6.5 is viable.** See `ObservationSpikeTests.swift`.

9. **`@resultBuilder` with generic type parameter** — ✅ PASS. `SpikeBuilder<T>` with `buildBlock` accepting variadic `SpikeContainer<T>` compiles and infers correctly. **Confirms `PushPlanBuilder<State>` pattern is viable.** See `ObservationSpikeTests.swift`.

**API differences from spec requiring design updates:** None — all APIs work as documented. The `AsyncThrowingStream` requirement and `URLScheme` failable initializer are implementation details, not design changes.

### Phase 4 Gate (before diff viewer, not Phase 1)

2. **Workspace change feed implementation** — Verify the concrete watcher strategy:
   - FSEvents or DispatchSource-based file watching for workspace roots
   - Git-aware filtering (ignore build/cache artifacts and dot directories)
   - CPU profile under bursty file writes (save-all, branch switch)

### Still Open

3. **React app bundling** — Vite build output bundled as app resources? Or served from disk via the scheme handler? Need to decide the build pipeline and how `BridgeSchemeHandler` locates the built assets.
4. **WebPage lifecycle when hidden** — How does the WebPage behave when the pane is hidden (backgrounded via view switch)? Does it keep running JS? Do observation loops need to pause to avoid wasted work?
5. **Pierre license and bundle size** — Verify `@pierre/diffs` license compatibility and evaluate bundle size impact.
6. **Terminal injection mechanism** — What is the exact API for injecting text into a Ghostty terminal session? Need to trace through `SurfaceManager` → Ghostty C API. Candidate approaches: (a) Ghostty C API `ghostty_surface_write()` for direct terminal input injection, (b) accessibility-based paste simulation, (c) PTY stdin write via file descriptor. Need to spike each approach and determine which works within the Ghostty embedding model.
7. **Full-diff search API** — The "metadata push, content pull" model with ~20-file LRU cache (§10.4) means React only holds partial file contents. A "Find in Diff" (Cmd+F) searching across all changed files will fail for files not yet loaded. Solution: add a `diff.search(query)` RPC method that scans full content on the Swift side and returns matches with file IDs and line ranges. React can then display results and trigger content pulls for matched files. This is a Phase 4 UX requirement, not Phase 1-2.
8. **Optimistic mutation cascading rollback** — The current optimistic model (§5.1.1) handles single-command rollback: React shows optimistic state, Swift confirms or rejects, React rolls back on rejection. But dependent optimistic updates (e.g., create Thread A → add Comment B to A → Swift rejects A) need cascading rollback. Options: (a) batch dependent mutations into a single command, (b) track dependency chains in React's pending state, (c) accept that dependent optimistic mutations are rare enough to handle with a simple "refresh all" on rejection. Decide before Phase 4 review features.
