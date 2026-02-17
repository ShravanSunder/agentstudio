# Swift ↔ React Bridge Architecture

> **Target**: macOS 26 (Tahoe) · Swift 6.2 · WebKit for SwiftUI
> **Pattern**: Push-dominant state sync with JSON-RPC command channel
> **First use case**: Diff viewer with Pierre (@pierre/diffs)
> **Status**: Design spec

---

## 1. Overview

Agent Studio embeds React-based UI panels inside webview panes alongside native terminal panes. The bridge connects Swift (domain truth) to React (view layer) through a push-dominant architecture:

- **Swift → React**: State push via `callJavaScript` into Zustand stores
- **React → Swift**: JSON-RPC commands via `postMessage`
- **No optimistic updates**: XPC latency is sub-frame (~1-5ms), so React always renders real state

The diff viewer (powered by Pierre) is the first panel that proves this architecture. Future panels (agent management, DB dashboards, log viewers) reuse the same bridge.

---

## 2. Architecture Principles

1. **Swift owns domain truth** — All business data (diffs, comments, agents, sessions) lives in `@Observable` Swift models. React never holds authoritative state.
2. **React owns UI truth** — Panel open/closed, scroll position, selection, hover, drag, animation. Swift never tracks ephemeral UI state.
3. **Push over pull** — Swift decides when to send data. React receives. The rare "pull" (lazy-load a file) is a command that triggers a push.
4. **Commands, not requests** — React sends fire-and-forget commands to Swift. Responses arrive as state updates through the push pipeline. No pending promise maps.
5. **One pipe per direction** — `callJavaScript` for push, `postMessage` for commands. No WebSockets, no HTTP, no polling.
6. **Testable at every layer** — Transport, protocol, push pipeline, stores — each layer has a clear contract and can be tested in isolation.

---

## 3. State Ownership Model

```
┌──────────────────────────────────────────┐
│  Swift (@Observable)                      │
│  "Source of Truth"                         │
│                                            │
│  • Diff state: files, contents, comments   │
│  • Agent state: sessions, status, logs     │
│  • Workspace state: repos, config          │
│  • Codable models                          │
│  • Observations AsyncSequence drives push  │
└──────────────┬───────────────────────────┘
               │
               │  PUSH: callJavaScript → Zustand stores
               │  COMMAND: postMessage JSON-RPC (JS→Swift)
               │  BINARY: agentstudio:// scheme (large files)
               │
┌──────────────▼───────────────────────────┐
│  React + Zustand (UI state + mirrors)     │
│                                            │
│  • Zustand stores mirror Swift state       │
│  • Panel open/closed, scroll position      │
│  • Selection, hover, drag state            │
│  • Ephemeral form state (comment drafts)   │
│  • Pierre diff rendering state             │
└────────────────────────────────────────────┘
```

**Rule**: Domain state mutations always flow through Swift. React sends commands, Swift mutates, push pipeline delivers the update.

### Why no optimistic updates

`callJavaScript` uses XPC (Mach message passing, same machine):

| Payload Size | Latency | Context |
|---|---|---|
| < 5 KB JSON | Sub-millisecond to ~1ms | File list, status updates, comments |
| 5–50 KB | 1–5ms | Individual file contents |
| 50–500 KB | 5–20ms | Large files (serialization-dominated) |

A 60fps frame is 16.7ms. Even medium payloads arrive within a single frame.

> **Caveat**: These latency figures are estimates based on typical XPC/Mach message passing characteristics. Actual values must be validated on target hardware during Phase 1 verification. JSON serialization overhead, WebKit thread scheduling, and system load can shift these numbers. The Phase 1 transport test should include a round-trip latency benchmark across payload sizes.

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

> **Note on full-buffer load**: The current design loads the entire file into memory before yielding. For files > 1MB, consider streaming via chunked yields (e.g., 64KB chunks with `Task.checkCancellation()` between each). This is a Phase 5 optimization — the initial implementation uses full-buffer load with the 50KB threshold keeping payloads manageable.

React consumes via standard `fetch()`:
```typescript
const content = await fetch(`agentstudio://resource/file/${fileId}`);
const text = await content.text();
```

### 4.4 When to use each channel

| Channel | Direction | When | Example |
|---|---|---|---|
| `callJavaScript` | Swift → JS | State pushes, all domain data | File list, comments, status |
| `postMessage` | JS → Swift | Commands, user actions | Request file contents, add comment |
| `agentstudio://` | JS → Swift (request) → JS (response) | Large binary payloads | Full file contents > 50KB, images |

---

## 5. Protocol Layer

### 5.1 Commands (JS → Swift): JSON-RPC 2.0

Commands use JSON-RPC 2.0 **notifications** (no `id` field). Responses arrive through state push, not as JSON-RPC responses.

```json
{
    "jsonrpc": "2.0",
    "method": "diff.requestFileContents",
    "params": { "fileId": "abc123" }
}
```

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
| `comment.*` | `comment.add`, `comment.resolve`, `comment.delete` | Comment lifecycle |
| `agent.*` | `agent.start`, `agent.stop`, `agent.injectPrompt` | Agent lifecycle |
| `git.*` | `git.status`, `git.fileTree` | Git operations |
| `system.*` | `system.health`, `system.capabilities` | System info |

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

**Push envelope metadata**: Each push includes a version and correlation ID for debugging:
- `__v: 1` — Push envelope version (bump on shape changes)
- `__pushId: "<uuid>"` — Correlation ID for tracing a push from Swift observation through JS merge to React rerender

These are passed as additional arguments to `__bridgeInternal.merge/replace` and forwarded in the `CustomEvent` detail. The receiver logs them but does not use them for business logic.

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

Even with `Observations` transactional coalescing, rapid async updates (file contents loading in parallel) can produce many yields. Use frame-aligned debouncing:

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
| **Granular per-file pushes** (§10.4) | File contents | Push only changed files, not entire `files` map |
| **Debounced observation** (§6.2) | Rapid mutations | Coalesce multiple changes into one push |
| **Status-only push channel** | Loading indicators | Separate lightweight push for status scalars |
| **Binary channel for large files** (§4.3) | Files > 50KB | Skip JSON encode/parse entirely |

**Measurement requirement**: Phase 2 testing must include a benchmark: push a 100-file diff state object (file list + 10 loaded file contents ~50KB each), measure end-to-end time from Swift mutation to React rerender. If > 32ms (2 frames), increase granularity or move large payloads to binary channel.

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

interface DiffComment {
    id: string;
    fileId: string;
    lineNumber: number | null;
    side: 'old' | 'new';
    text: string;
    createdAt: string;
    author: { type: 'user' | 'agent'; name: string };
}

interface DiffStore {
    source: DiffSource | null;
    files: Record<string, DiffFile>;
    fileOrder: string[];
    comments: Record<string, DiffComment[]>;
    status: 'idle' | 'loadingFileList' | 'loadingContents' | 'ready' | 'error';
    error: string | null;
}

export const useDiffStore = create<DiffStore>()(
    devtools(
        () => ({
            source: null,
            files: {},
            fileOrder: [],
            comments: {},
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
            sendCommand("diff.load", { source }),
        requestFileContents: (fileId: string) =>
            sendCommand("diff.requestFileContents", { fileId }),
    },
    comment: {
        add: (fileId: string, lineNumber: number | null, side: 'old' | 'new', text: string) =>
            sendCommand("comment.add", { fileId, lineNumber, side, text }),
        resolve: (commentId: string) =>
            sendCommand("comment.resolve", { commentId }),
        delete: (commentId: string) =>
            sendCommand("comment.delete", { commentId }),
        sendToAgent: (commentIds: string[]) =>
            sendCommand("comment.sendToAgent", { commentIds }),
    },
    agent: {
        injectPrompt: (text: string) =>
            sendCommand("agent.injectPrompt", { text }),
    },
    system: {
        health: () =>
            sendCommand("system.health"),
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
    // Future: var agentChat: AgentChatState = .init()
    // Future: var logViewer: LogViewerState = .init()
}
```

**Shared state** — Singleton, shared across all panes. Connection health, system capabilities:

```swift
@Observable
@MainActor
class SharedBridgeState {
    var connection: ConnectionState = .init()
    // Future: var system: SystemState = .init()
}
```

**Ownership**: `BridgeCoordinator` owns one `PaneDomainState` and holds a reference to the singleton `SharedBridgeState`. Each pane's observation loops push both per-pane and shared state into their respective Zustand stores.

### 8.2 Diff State

```swift
@Observable
class DiffState {
    var source: DiffSource = .none
    var files: [String: DiffFile] = [:]
    var fileOrder: [String] = []
    var comments: [String: [DiffComment]] = [:]
    var status: DiffStatus = .idle
    var error: String? = nil
}

enum DiffSource: Codable {
    case none
    case workingTree(worktreeId: UUID)
    case commitRange(from: String, to: String)
    case branch(name: String, base: String)
}

enum DiffStatus: String, Codable {
    case idle
    case loadingFileList
    case loadingContents
    case ready
    case error
}

struct DiffFile: Codable, Identifiable {
    let id: String
    let path: String
    let oldPath: String?
    let changeType: FileChangeType
    var status: FileLoadStatus
    var oldContent: String?
    var newContent: String?
    let size: Int
}

enum FileChangeType: String, Codable {
    case added, modified, deleted, renamed
}

enum FileLoadStatus: String, Codable {
    case pending, loading, loaded, error
}

struct DiffComment: Codable, Identifiable {
    let id: UUID
    let fileId: String
    let lineNumber: Int?
    let side: DiffSide
    var text: String
    let createdAt: Date
    let author: CommentAuthor
}

enum DiffSide: String, Codable { case old, new }

struct CommentAuthor: Codable {
    let type: AuthorType
    let name: String
    enum AuthorType: String, Codable { case user, agent }
}

@Observable
class ConnectionState: Codable {
    var health: ConnectionHealth = .connected
    var latencyMs: Int = 0
    enum ConnectionHealth: String, Codable { case connected, disconnected, error }
}
```

### 8.3 Codable Conformance

All domain types conform to `Codable` for JSON serialization across the bridge. `@Observable` classes use the macro's auto-generated `Codable` conformance.

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

## 10. Chunked Progressive Loading

For large PRs (100+ files), loading happens in three phases:

### 10.1 Phase 1 — File List (immediate)

Swift pushes the file list with metadata (paths, change types, sizes) but NO file contents:

```swift
func loadDiff(source: DiffSource) async {
    domainState.diff.source = source
    domainState.diff.status = .loadingFileList

    let changedFiles = try await gitService.listChangedFiles(source: source)

    // Push file list without contents
    for file in changedFiles {
        domainState.diff.files[file.id] = DiffFile(
            id: file.id, path: file.path, oldPath: file.oldPath,
            changeType: file.changeType, status: .pending,
            oldContent: nil, newContent: nil, size: file.size
        )
    }
    domainState.diff.fileOrder = changedFiles.map(\.id)
    domainState.diff.status = .loadingContents
    // Observations triggers push → React renders file tree immediately
}
```

### 10.2 Phase 2 — Background Batches (progressive)

Swift loads file contents in batches of 10, prioritized by size (smaller first):

```swift
func loadFileContents() async {
    let sortedFiles = domainState.diff.fileOrder
        .compactMap { domainState.diff.files[$0] }
        .filter { $0.status == .pending }
        .sorted { $0.size < $1.size }

    for batch in sortedFiles.chunked(into: 10) {
        await withTaskGroup(of: Void.self) { group in
            for file in batch {
                group.addTask {
                    await self.loadSingleFile(fileId: file.id)
                }
            }
        }
        // Each file status change triggers Observations → push
    }

    domainState.diff.status = .ready
}

private func loadSingleFile(fileId: String) async {
    domainState.diff.files[fileId]?.status = .loading

    do {
        let contents = try await gitService.readFileContents(fileId: fileId)
        domainState.diff.files[fileId]?.oldContent = contents.old
        domainState.diff.files[fileId]?.newContent = contents.new
        domainState.diff.files[fileId]?.status = .loaded
    } catch {
        domainState.diff.files[fileId]?.status = .error
    }
}
```

### 10.3 Phase 3 — On-Demand Priority (user scroll)

When the user scrolls to a file that hasn't loaded yet, React sends a command to prioritize it:

```typescript
// React: user scrolls to unloaded file
const status = file?.status;
useEffect(() => {
    if (status === 'pending') {
        commands.diff.requestFileContents(file.id);
    }
}, [file.id, status]);
```

```swift
// Swift: handler reprioritizes the file
await router.register(Methods.DiffRequestFileContents.self) { params in
    await self.loadSingleFile(fileId: params.fileId)
}
```

### 10.4 Race Condition Guards

The same file can be requested concurrently by Phase 2 (batch) and Phase 3 (on-demand). Three guards prevent races:

**1. Per-file load lock**: `loadSingleFile` checks and sets `.loading` atomically. If already `.loading`, skip:

```swift
private func loadSingleFile(fileId: String) async {
    // Guard: skip if already loading or loaded
    guard let file = paneState.diff.files[fileId],
          file.status == .pending else { return }

    paneState.diff.files[fileId]?.status = .loading
    // ... load contents
}
```

**2. Load epoch**: Each `loadDiff()` call increments an epoch counter. File loads check the epoch before writing results — stale loads from a previous diff source are discarded:

```swift
@Observable
class DiffState {
    var loadEpoch: Int = 0
    // ...
}

private func loadSingleFile(fileId: String, epoch: Int) async {
    do {
        let contents = try await gitService.readFileContents(fileId: fileId)

        // Transactional epoch check: verify BEFORE EACH property write after await.
        // The await above is a suspension point — epoch could have changed while we waited.
        guard paneState.diff.loadEpoch == epoch else { return }
        paneState.diff.files[fileId]?.oldContent = contents.old

        guard paneState.diff.loadEpoch == epoch else { return }
        paneState.diff.files[fileId]?.newContent = contents.new

        guard paneState.diff.loadEpoch == epoch else { return }
        paneState.diff.files[fileId]?.status = .loaded
    } catch {
        guard paneState.diff.loadEpoch == epoch else { return }
        paneState.diff.files[fileId]?.status = .error
    }
}
```

**3. Debounced on-demand requests**: React debounces `requestFileContents` calls (e.g., 100ms) to avoid flooding Swift when the user scrolls rapidly through the file list.

### 10.4 Push Granularity for File Contents

Individual file content updates push only the changed file, not the entire files map. This is achieved through granular observation:

```swift
func watchFileContents() async {
    // Observe individual file status changes
    // Push only the changed file to avoid sending all 100 files on each update
    for await _ in Observations({ self.domainState.diff.files }).debounce(for: .milliseconds(16)) {
        // Diff the current files against last-pushed state
        // Push only changed entries
        let changed = diffAgainstLastPush(self.domainState.diff.files)
        for (fileId, file) in changed {
            await pushToJS(store: "diff", path: "files.\(fileId)", value: file)
        }
    }
}
```

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

### 12.1 Pierre Component Usage

Pierre (`@pierre/diffs`, v1.0.11+) provides React components for rendering diffs from full file contents. Key exports: `MultiFileDiff`, `PatchDiff`. Note: Pierre's virtualized rendering is an internal implementation detail — consumers use the high-level components, not the internal `VirtualizedFileDiff`.

```typescript
import { MultiFileDiff } from '@pierre/diffs/react';

function DiffFileView({ fileId }: { fileId: string }) {
    const file = useFileContent(fileId);

    if (!file || file.status === 'pending') return <FileListItem skeleton />;
    if (file.status === 'loading') return <FileListItem loading />;
    if (file.status === 'error') return <FileListItem error />;

    return (
        <MultiFileDiff
            oldFile={{ name: file.oldPath ?? file.path, contents: file.oldContent ?? '' }}
            newFile={{ name: file.path, contents: file.newContent ?? '' }}
            options={{
                theme: { dark: 'pierre-dark', light: 'pierre-light' },
                diffStyle: 'split',
            }}
        />
    );
}
```

### 12.2 File List with Progressive Loading

```typescript
function DiffPanel() {
    const { fileOrder, files, status } = useDiffFiles();

    return (
        <div className="diff-panel">
            <DiffHeader status={status} fileCount={fileOrder.length} />
            <div className="file-list">
                {fileOrder.map((fileId) => (
                    <DiffFileView key={fileId} fileId={fileId} />
                ))}
            </div>
        </div>
    );
}
```

### 12.3 Comment Integration

Pierre supports annotations via the `lineAnnotations` prop and `renderAnnotation` render prop. Comments from the Zustand store map to Pierre's annotation API:

```typescript
function DiffFileWithComments({ fileId }: { fileId: string }) {
    const file = useFileContent(fileId);
    const comments = useFileComments(fileId);

    const annotations = useMemo(() =>
        comments.map((c) => ({
            line: c.lineNumber,
            side: c.side,
            content: c.text,
            author: c.author.name,
        })),
        [comments]
    );

    // ... render MultiFileDiff with annotations
}
```

### 12.4 Sending Comments to Agent

```typescript
function SendToAgentButton({ fileId }: { fileId: string }) {
    const comments = useFileComments(fileId);

    const handleSend = () => {
        const commentIds = comments.map((c) => c.id);
        commands.comment.sendToAgent(commentIds);
    };

    return <button onClick={handleSend}>Send to Agent</button>;
}
```

Swift handler formats comments as a structured prompt and injects into the terminal:

```swift
await router.register(Methods.CommentSendToAgent.self) { params in
    let comments = params.commentIds.compactMap { id in
        self.domainState.diff.allComments.first { $0.id.uuidString == id }
    }
    let prompt = CommentFormatter.formatForAgent(comments: comments)
    try await self.terminalService.injectText(prompt, sessionId: activeSessionId)
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

**Goal**: Swift `@Observable` changes arrive in Zustand stores.

**Deliverables**:
- Zustand stores for `diff` and `connection` domains
- Bridge receiver listens for `__bridge_push` CustomEvents relayed from `__bridgeInternal`, updates Zustand
- `Observations` AsyncSequence watches `BridgeDomainState`
- Push coalescing with debounce
- Content world ↔ page world relay via CustomEvents

**Tests**:
- Unit: `deepMerge` correctly merges partial state
- Unit: Zustand store updates on `merge` and `replace` calls
- Unit: Bridge receiver routes to correct store
- Integration: Mutate `@Observable` property in Swift → verify Zustand store updated
- Integration: Rapid mutations coalesce into single push (verify with mock)
- Integration: Content world isolation — page world script cannot call `window.webkit.messageHandlers.rpc`

### Phase 3: JSON-RPC Command Channel

**Goal**: React can send typed commands to Swift.

**Deliverables**:
- `RPCRouter` with typed method registration
- Method definitions for `diff.*` and `comment.*` namespaces
- Command sender on JS side (`commands.diff.requestFileContents(...)`)
- Error handling (method not found, invalid params, internal error)
- Direct-response path for rare request/response needs

**Tests**:
- Unit: `RPCRouter` dispatches to correct handler
- Unit: Unknown methods return `-32601`
- Unit: Invalid params return `-32602`
- Unit: `RPCMethod` protocol correctly decodes typed params
- Integration: JS sends command → Swift handler fires → state updates → push arrives in Zustand

### Phase 4: Diff Viewer (Pierre Integration)

**Goal**: Full diff viewer renders in a webview pane.

**Deliverables**:
- `DiffState` domain model with file list, contents, comments
- `DiffLoader` with chunked progressive loading (3 phases)
- Pierre `MultiFileDiff` component renders diffs
- File list with loading indicators per file
- Comment UI (add, resolve, delete)
- "Send to Agent" flows comments to terminal

**Tests**:
- Unit: `DiffLoader` chunking logic (batch size, prioritization)
- Unit: `DiffState` mutations produce correct Codable JSON
- Unit: Pierre renders with mock file contents
- Unit: Comment formatting for agent injection
- Integration: Load a real git diff → file list renders → contents stream in progressively
- Integration: Add comment → appears in Zustand → send to agent → verify terminal input
- E2E: Open diff pane in Agent Studio → see real diff → add comment → inject into terminal

### Phase 5: Binary Channel

**Goal**: Large file contents served efficiently via URL scheme.

**Deliverables**:
- Extend `BinarySchemeHandler` for `agentstudio://resource/file/{id}` paths
- React fetches large files via `fetch()` instead of JSON push
- Threshold logic: files > 50KB use binary channel, smaller use JSON push
- Path validation and security hardening

**Tests**:
- Unit: `BinarySchemeHandler` validates allowed resource types
- Unit: `BinarySchemeHandler` rejects forbidden paths
- Integration: React `fetch('agentstudio://resource/file/xyz')` returns correct file content
- Performance: Compare JSON push vs binary channel for 100KB, 500KB, 1MB files

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
- [ ] File list renders within 100ms of `loadDiff` call (100 files)
- [ ] Progressive loading: first 10 files visible within 500ms, remaining stream in
- [ ] On-demand priority: scroll to unloaded file → content appears within 200ms
- [ ] Race condition: simultaneous batch + on-demand for same file → no duplicate loads, no data corruption
- [ ] Epoch guard: start new diff during active load → stale results discarded
- [ ] Comment add/resolve/delete round-trips correctly
- [ ] "Send to Agent" injects formatted text into terminal

#### Phase 5 Exit Criteria
- [ ] Binary channel returns correct content for `agentstudio://resource/file/{id}`
- [ ] **Performance benchmarks** (measured on M-series Mac):
  - 100KB file: binary channel < 5ms, JSON push < 10ms
  - 500KB file: binary channel < 15ms, JSON push < 50ms
  - 1MB file: binary channel < 30ms
- [ ] Cancellation: navigate away during active scheme request → task cancelled, no resource leak
- [ ] Path traversal: `../../etc/passwd` → rejected with error

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
│   ├── BridgeCoordinator.swift           # WebPage setup, observation loops, push
│   ├── RPCRouter.swift                   # Method registry + dispatch
│   ├── RPCMethod.swift                   # Protocol + type-erased handler
│   ├── RPCMessageHandler.swift           # WKScriptMessageHandler for postMessage
│   ├── BinarySchemeHandler.swift         # agentstudio:// URL scheme
│   ├── NavigationDecider.swift           # WebPage.NavigationDeciding
│   ├── BridgeBootstrap.swift             # JS bootstrap script for bridge world
│   └── Methods/                          # One file per namespace
│       ├── DiffMethods.swift
│       ├── CommentMethods.swift
│       ├── AgentMethods.swift
│       └── SystemMethods.swift
├── Domain/
│   ├── BridgeDomainState.swift           # @Observable root state
│   ├── DiffState.swift                   # Diff domain model
│   ├── ConnectionState.swift             # Connection health
│   └── DiffLoader.swift                  # Chunked progressive loading logic
└── (existing Sources structure unchanged)

WebApp/                                    # React app (Vite + TypeScript)
├── src/
│   ├── bridge/
│   │   ├── receiver.ts                   # __bridge_push CustomEvent → Zustand
│   │   ├── commands.ts                   # Typed command senders
│   │   ├── rpc-client.ts                 # Direct-response RPC (rare)
│   │   └── types.ts                      # Shared protocol types
│   ├── stores/
│   │   ├── diff-store.ts                 # Zustand diff state
│   │   └── connection-store.ts           # Zustand connection state
│   ├── hooks/
│   │   ├── use-diff-files.ts
│   │   ├── use-file-content.ts
│   │   └── use-file-comments.ts
│   ├── components/
│   │   ├── DiffPanel.tsx                 # Main diff viewer
│   │   ├── DiffFileView.tsx              # Per-file diff (Pierre)
│   │   ├── DiffHeader.tsx                # Status bar
│   │   ├── CommentOverlay.tsx            # Comment UI
│   │   └── SendToAgentButton.tsx
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

- ~~**DiffState scope**~~ → **Per-pane** `PaneDomainState`. Shared state (`ConnectionState`) is singleton. See §8.1.
- ~~**CustomEvent command forgery**~~ → **Nonce token** generated at bootstrap, validated by bridge world. See §11.3.
- ~~**Push error handling**~~ → **do-catch** with logging and connection health state update. No force-unwraps. See §6.4.
- ~~**File loading race conditions**~~ → **Per-file load lock + load epoch + debounced requests**. See §10.4.
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
