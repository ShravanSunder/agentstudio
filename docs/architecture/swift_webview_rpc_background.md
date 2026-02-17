# AgentStudio: Swift ↔ JS Bridge Architecture Spec

> **Target**: macOS 26 (Tahoe) · Swift 6.2 · WebKit for SwiftUI  
> **No WKWebView anywhere** — only the new `WebView` + `WebPage` APIs  
> **Status**: Implementation spec for Claude Code

---

## 1. Platform Foundation

### 1.1 Core Types

AgentStudio uses exclusively the WWDC 2025 WebKit for SwiftUI APIs:

| Type | Role | Notes |
|------|------|-------|
| `WebView` | SwiftUI view that renders web content | Declarative, supports modifiers like `.webViewBackForwardNavigationGestures()` |
| `WebPage` | `@Observable` model class — the state/control hub | Replaces `WKWebView` entirely. Has observable properties (`title`, `url`, `isLoading`, `estimatedProgress`, `themeColor`, `currentNavigationEvent`). Designed from the ground up for Swift and SwiftUI. |
| `WebPage.Configuration` | Setup object passed to `WebPage(configuration:)` | Contains `userContentController`, `urlSchemeHandlers`, navigation preferences, etc. |
| `URLSchemeHandler` | Protocol for custom URL schemes | New Swift Concurrency-native version — returns `AsyncSequence<URLSchemeTaskResult>`. Replaces the old `WKURLSchemeHandler` with `didReceive`/`didFinish` callbacks. |

### 1.2 Key APIs for the Bridge

**Swift → JS (push):**
```swift
// Async, returns optional Any, accepts typed arguments
let result = try await page.callJavaScript(
    "functionBody",
    arguments: ["key": value],
    in: frame,           // optional, defaults to main frame
    contentWorld: world   // isolation boundary
)
// Return type is Any? — cast to appropriate Swift type
```

**JS → Swift (pull):**
```swift
// Via userContentController on WebPage.Configuration
var config = WebPage.Configuration()
config.userContentController.add(handler, name: "rpc")
// JS calls: window.webkit.messageHandlers.rpc.postMessage(payload)
```

**Binary channel (large payloads):**
```swift
// Custom URL scheme handler — new AsyncSequence-based API
struct BinarySchemeHandler: URLSchemeHandler {
    static let scheme = "agentstudio"
    
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        // yield .response(URLResponse) then .data(Data), then .finish()
    }
}

guard let scheme = URLScheme(BinarySchemeHandler.scheme) else { fatalError() }
config.urlSchemeHandlers[scheme] = BinarySchemeHandler()
let page = WebPage(configuration: config)
```

### 1.3 Content Worlds (Security Isolation)

Content worlds provide JavaScript namespace isolation. The bridge MUST use a dedicated content world so that:
- Web page scripts cannot access bridge internals
- Bridge scripts cannot be tampered with by loaded web content
- Multiple content worlds can coexist for different security levels

```swift
// Create an isolated world for all bridge communication
let bridgeWorld = WebPage.ContentWorld.world(name: "agentStudioBridge")
```

All `callJavaScript` calls and script message handlers MUST specify this world.

---

## 2. Architecture: State Ownership Model

### 2.1 The Boundary

```
┌──────────────────────────────────────────┐
│  Swift (@Observable)                      │
│  "Source of Truth"                         │
│                                            │
│  • Domain state: agents, sessions, git     │
│    repos, workspace config, DuckDB results │
│  • Codable models                          │
│  • ALL business/domain data lives here     │
│  • @Observable tracks per-property changes │
└──────────────┬───────────────────────────┘
               │
               │  PUSH: callJavaScript (Swift→JS, ~1-5ms)
               │  PULL: postMessage JSON-RPC (JS→Swift)
               │  BINARY: agentstudio:// scheme handler
               │
┌──────────────▼───────────────────────────┐
│  React (UI state only)                    │
│                                            │
│  • Panel open/closed, scroll position      │
│  • Selection, hover, drag state            │
│  • Ephemeral form state                    │
│  • Animation / transition state            │
│  • Layout / responsive breakpoints         │
└────────────────────────────────────────────┘
```

**Rule**: Swift owns domain truth. React owns UI truth. No domain state in React. No UI state in Swift.

### 2.2 Why No Optimistic Updates

Since Swift owns domain truth, React cannot do optimistic local mutations. This is fine because `callJavaScript` uses XPC (Mach message passing on the same machine, not network):

| Payload Size | Latency | Context |
|---|---|---|
| < 5 KB JSON | Sub-millisecond to ~1ms | Most domain state updates |
| 5–50 KB | 1–5ms | Medium collections |
| 50–500 KB | 5–20ms | Large data (serialization-dominated) |

A 60fps frame is 16.7ms. Even medium payloads arrive within a single frame. The user cannot perceive the gap between "request action" and "receive real state."

---

## 3. JSON-RPC 2.0 Protocol

All structured communication uses JSON-RPC 2.0 over the native IPC bridge. No WebSockets, no HTTP — pure `callJavaScript` + `postMessage`.

### 3.1 Message Types

**Request** (JS → Swift):
```json
{
    "jsonrpc": "2.0",
    "id": "req_001",
    "method": "git.fileTree",
    "params": { "path": "/workspace/src" }
}
```

**Response** (Swift → JS):
```json
{
    "jsonrpc": "2.0",
    "id": "req_001",
    "result": { "files": [...] }
}
```

**Error Response**:
```json
{
    "jsonrpc": "2.0",
    "id": "req_001",
    "error": { "code": -32601, "message": "Method not found", "data": null }
}
```

**Notification** (Swift → JS, no `id` field):
```json
{
    "jsonrpc": "2.0",
    "method": "agent.statusChanged",
    "params": { "sessionId": "abc", "status": "idle" }
}
```

### 3.2 Standard Error Codes

| Code | Meaning |
|------|---------|
| -32700 | Parse error (invalid JSON) |
| -32600 | Invalid request (missing required fields) |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |
| -32000 to -32099 | Application-defined errors |

### 3.3 Method Namespace Convention

Methods use dot-notation namespaces:

| Namespace | Examples | Description |
|-----------|----------|-------------|
| `agent.*` | `agent.start`, `agent.stop`, `agent.queryLogs` | Agent lifecycle and queries |
| `git.*` | `git.fileTree`, `git.diff`, `git.status` | Git operations |
| `workspace.*` | `workspace.config`, `workspace.openFile` | Workspace management |
| `session.*` | `session.list`, `session.create`, `session.switch` | Session management |
| `db.*` | `db.query`, `db.schema` | DuckDB queries |
| `system.*` | `system.health`, `system.capabilities` | System-level info |

---

## 4. Type-Safe Bridge Implementation

### 4.1 Swift Side: Protocol-Driven Method Routing

```swift
// MARK: - Type-safe method definitions

/// Every RPC method is a concrete type conforming to this protocol
protocol RPCMethod {
    associatedtype Params: Codable
    associatedtype Result: Codable
    static var method: String { get }
}

// Example method definitions
enum Methods {
    struct GitFileTree: RPCMethod {
        struct Params: Codable { let path: String }
        struct Result: Codable { let files: [FileNode] }
        static let method = "git.fileTree"
    }
    
    struct AgentStart: RPCMethod {
        struct Params: Codable { let model: String; let sessionId: String? }
        struct Result: Codable { let sessionId: String }
        static let method = "agent.start"
    }
    
    struct AgentStop: RPCMethod {
        typealias Params = SessionIdParam
        struct Result: Codable { let stopped: Bool }
        static let method = "agent.stop"
    }
    
    struct DbQuery: RPCMethod {
        struct Params: Codable { let sql: String; let params: [String]? }
        struct Result: Codable { let columns: [String]; let rows: [[AnyCodable]] }
        static let method = "db.query"
    }
}

// Shared param types
struct SessionIdParam: Codable { let sessionId: String }
```

```swift
// MARK: - Method handler registry

/// Type-erased handler wrapper
struct AnyMethodHandler {
    let handle: (Data) async throws -> Data
}

/// Build a type-safe handler from an RPCMethod + closure
func makeHandler<M: RPCMethod>(
    _: M.Type,
    handler: @escaping (M.Params) async throws -> M.Result
) -> AnyMethodHandler {
    AnyMethodHandler { paramsData in
        let params = try JSONDecoder().decode(M.Params.self, from: paramsData)
        let result = try await handler(params)
        return try JSONEncoder().encode(result)
    }
}

/// The router that dispatches JSON-RPC requests
actor RPCRouter {
    private var handlers: [String: AnyMethodHandler] = [:]
    
    func register<M: RPCMethod>(_ type: M.Type, handler: @escaping (M.Params) async throws -> M.Result) {
        handlers[M.method] = makeHandler(type, handler: handler)
    }
    
    func dispatch(method: String, paramsJSON: Data) async throws -> Data {
        guard let handler = handlers[method] else {
            throw RPCError.methodNotFound(method)
        }
        return try await handler.handle(paramsJSON)
    }
}
```

```swift
// MARK: - Bridge coordinator (ties WebPage to RPCRouter)

@Observable
class BridgeCoordinator {
    let page: WebPage
    private let router = RPCRouter()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        var config = WebPage.Configuration()
        
        // Register JS → Swift message handler
        config.userContentController.add(self, name: "rpc")
        
        // Register binary scheme handler
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BinarySchemeHandler()
        }
        
        self.page = WebPage(configuration: config)
        
        // Register all method handlers
        Task { await registerHandlers() }
    }
    
    private func registerHandlers() async {
        await router.register(Methods.GitFileTree.self) { params in
            // actual implementation calls git service
            try await GitService.shared.fileTree(at: params.path)
        }
        await router.register(Methods.AgentStart.self) { params in
            try await AgentService.shared.start(model: params.model, sessionId: params.sessionId)
        }
        // ... register all methods
    }
}
```

### 4.2 JS Side: Typed RPC Client

```typescript
// bridge/rpc-client.ts

interface JSONRPCRequest {
    jsonrpc: "2.0";
    id: string;
    method: string;
    params?: unknown;
}

interface JSONRPCResponse<T = unknown> {
    jsonrpc: "2.0";
    id: string;
    result?: T;
    error?: { code: number; message: string; data?: unknown };
}

interface JSONRPCNotification {
    jsonrpc: "2.0";
    method: string;
    params?: unknown;
}

type NotificationHandler = (params: unknown) => void;

class RPCClient {
    private pending = new Map<string, {
        resolve: (value: unknown) => void;
        reject: (error: Error) => void;
    }>();
    private counter = 0;
    private notificationHandlers = new Map<string, Set<NotificationHandler>>();

    /** Called by Swift via callJavaScript for responses */
    handleResponse(raw: JSONRPCResponse): void {
        const entry = this.pending.get(raw.id);
        if (!entry) return;
        this.pending.delete(raw.id);
        
        if (raw.error) {
            entry.reject(new RPCError(raw.error.code, raw.error.message, raw.error.data));
        } else {
            entry.resolve(raw.result);
        }
    }

    /** Called by Swift via callJavaScript for notifications */
    handleNotification(raw: JSONRPCNotification): void {
        const handlers = this.notificationHandlers.get(raw.method);
        if (handlers) {
            for (const handler of handlers) {
                handler(raw.params);
            }
        }
    }

    /** Send an RPC request to Swift */
    request<TResult>(method: string, params?: unknown): Promise<TResult> {
        const id = `req_${++this.counter}`;
        const message: JSONRPCRequest = { jsonrpc: "2.0", id, method, params };

        return new Promise<TResult>((resolve, reject) => {
            this.pending.set(id, {
                resolve: resolve as (value: unknown) => void,
                reject,
            });
            // Send to Swift via webkit message handler
            window.webkit.messageHandlers.rpc.postMessage(JSON.stringify(message));
        });
    }

    /** Subscribe to notifications from Swift */
    onNotification(method: string, handler: NotificationHandler): () => void {
        if (!this.notificationHandlers.has(method)) {
            this.notificationHandlers.set(method, new Set());
        }
        this.notificationHandlers.get(method)!.add(handler);
        return () => this.notificationHandlers.get(method)?.delete(handler);
    }
}

export const rpc = new RPCClient();

// Install on window for Swift to call
(window as any).__bridge = {
    handleResponse: (raw: JSONRPCResponse) => rpc.handleResponse(raw),
    handleNotification: (raw: JSONRPCNotification) => rpc.handleNotification(raw),
    setQueryData: (key: unknown, data: unknown) => {
        // Direct push into TanStack Query cache (see Section 5)
        queryClient.setQueryData(key as any, data);
    },
    merge: (storeName: string, patch: unknown) => {
        // Merge into domain stores (see Section 6)
        bridgeStores.merge(storeName, patch);
    },
};
```

### 4.3 Type-Safe Method Definitions (JS Side)

```typescript
// bridge/methods.ts — mirrors Swift RPCMethod definitions

import { rpc } from "./rpc-client";

// Each method is a typed function
export const bridge = {
    git: {
        fileTree: (path: string) =>
            rpc.request<{ files: FileNode[] }>("git.fileTree", { path }),
        diff: (commitSha: string) =>
            rpc.request<{ hunks: DiffHunk[] }>("git.diff", { commitSha }),
        status: () =>
            rpc.request<GitStatus>("git.status"),
    },
    agent: {
        start: (model: string, sessionId?: string) =>
            rpc.request<{ sessionId: string }>("agent.start", { model, sessionId }),
        stop: (sessionId: string) =>
            rpc.request<{ stopped: boolean }>("agent.stop", { sessionId }),
        queryLogs: (params: LogQueryParams) =>
            rpc.request<LogQueryResult>("agent.queryLogs", params),
    },
    session: {
        list: () => rpc.request<Session[]>("session.list"),
        create: (name: string) =>
            rpc.request<Session>("session.create", { name }),
    },
    db: {
        query: (sql: string, params?: string[]) =>
            rpc.request<QueryResult>("db.query", { sql, params }),
    },
    system: {
        health: () => rpc.request<HealthStatus>("system.health"),
    },
} as const;
```

---

## 5. React State Integration: TanStack Query + Stores

### 5.1 Pattern Distribution

| Pattern | Hops | When | Frequency |
|---------|------|------|-----------|
| **Push data → `setQueryData`** | 1 | Swift has data React needs | ~70% |
| **Push scalar → `useSyncExternalStore`** | 1 | Small hot state (status enum, phase, health) | ~20% |
| **Push invalidation → refetch** | 3 | React controls query shape (filters, pagination) | ~10% |

### 5.2 Push Data via TanStack Query (Dominant Pattern)

Swift pushes complete data directly into TanStack Query's cache. One `callJavaScript` call — React gets data immediately.

**Swift side:**
```swift
func pushFileTree(path: String, tree: [FileNode]) async {
    let data = try! encoder.encode(tree)
    let json = String(data: data, encoding: .utf8)!
    
    try? await page.callJavaScript(
        "window.__bridge.setQueryData(key, JSON.parse(data))",
        arguments: ["key": ["fileTree", path], "data": json],
        contentWorld: bridgeWorld
    )
}
```

**React side — useQuery as cache reader:**
```typescript
function useFileTree(path: string) {
    return useQuery({
        queryKey: ["fileTree", path],
        // queryFn is the FALLBACK — only called if cache is empty
        queryFn: () => bridge.git.fileTree(path),
        // Keep cache for 5 min, consider stale after 30s
        staleTime: 30_000,
        gcTime: 300_000,
    });
}
```

TanStack Query gives us: deduplication, cache lifecycle (gcTime, staleTime), automatic garbage collection, loading/error states, refetch on window focus (if desired). All for free — Swift just writes to the cache.

### 5.3 Push Scalar State via `useSyncExternalStore` (Hot State)

For small, frequently-changing scalar state that Swift fully owns — agent status, session phase, connection health. These are "the state IS the notification."

```typescript
// stores/domain-stores.ts

type Listener = () => void;

interface BridgeStore<T> {
    getSnapshot: () => T;
    subscribe: (listener: Listener) => () => void;
    setState: (updater: (prev: T) => T) => void;
}

function createBridgeStore<T>(initial: T): BridgeStore<T> {
    let state = initial;
    const listeners = new Set<Listener>();

    return {
        getSnapshot: () => state,
        subscribe: (listener) => {
            listeners.add(listener);
            return () => listeners.delete(listener);
        },
        setState: (updater) => {
            state = updater(state);
            listeners.forEach((l) => l());
        },
    };
}

// Domain stores — one per bounded context
export const agentStore = createBridgeStore<AgentState>({
    sessions: {},
    activeSessionId: null,
});

export const workspaceStore = createBridgeStore<WorkspaceState>({
    activePath: null,
    config: null,
});

export const connectionStore = createBridgeStore<ConnectionState>({
    health: "connected",
    latencyMs: 0,
});
```

**React hook:**
```typescript
function useAgentState() {
    return useSyncExternalStore(
        agentStore.subscribe,
        agentStore.getSnapshot
    );
}
```

**Merge updates from Swift:**
```typescript
// Called by Swift via callJavaScript("window.__bridge.merge(store, patch)")
export const bridgeStores = {
    merge(storeName: string, patch: unknown) {
        const store = { agents: agentStore, workspace: workspaceStore, connection: connectionStore }[storeName];
        if (!store) return;
        store.setState((prev) => deepMerge(prev, patch));
    },
};
```

**Swift push (whole object — start with this, optimize later):**
```swift
// In the bridge coordinator, using withObservationTracking
func watchAgentState() {
    withObservationTracking {
        _ = domainState.agents  // register interest in agents
    } onChange: {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data = try! self.encoder.encode(self.domainState.agents)
            let json = String(data: data, encoding: .utf8)!
            try? await self.page.callJavaScript(
                "window.__bridge.merge('agents', JSON.parse(data))",
                arguments: ["data": json],
                contentWorld: self.bridgeWorld
            )
            self.watchAgentState()  // re-register (fires once per spec)
        }
    }
}
```

### 5.4 Push Invalidation → Refetch (Rare Pattern)

Only when React controls query shape (filters, pagination, SQL) and Swift can't know what to push:

```typescript
// React has a filtered view
useQuery({
    queryKey: ["agentLogs", sessionId, { level: "error", limit: 50 }],
    queryFn: () => bridge.agent.queryLogs({ sessionId, level: "error", limit: 50 }),
});

// Swift pushes invalidation when new logs arrive
// → JS handler invalidates matching queries → TanStack refetches automatically
rpc.onNotification("agent.logsChanged", ({ sessionId }) => {
    queryClient.invalidateQueries({ queryKey: ["agentLogs", sessionId] });
});
```

### 5.5 Unified Notification Dispatcher

All Swift notifications flow through one handler that routes to both stores and TanStack:

```typescript
// bridge/notification-dispatcher.ts

import { rpc } from "./rpc-client";
import { bridgeStores } from "../stores/domain-stores";
import { queryClient } from "./query-client";

// Scalar state pushes → useSyncExternalStore
rpc.onNotification("state.merge", ({ store, patch }) => {
    bridgeStores.merge(store as string, patch);
});

// Data pushes → TanStack cache
rpc.onNotification("data.push", ({ key, data }) => {
    queryClient.setQueryData(key as any, data);
});

// Invalidation pushes → TanStack refetch
rpc.onNotification("data.invalidate", ({ key }) => {
    queryClient.invalidateQueries({ queryKey: key as any });
});
```

---

## 6. `@Observable` Architecture in Swift

### 6.1 How @Observable Works

`@Observable` is a **class-level** macro. You cannot put it on individual properties. But it tracks changes at the **property level** automatically via the `@ObservationTracked` macro applied to each stored property at compile time.

```swift
@Observable
class AgentSession {
    var status: AgentStatus = .idle        // automatically tracked
    var currentModel: String = "claude"    // automatically tracked
    var tokenCount: Int = 0                // automatically tracked
    var logs: [LogEntry] = []              // automatically tracked
    
    @ObservationIgnored
    var internalCache: Data? = nil         // NOT tracked — opt-out
}
```

Key behaviors:
- Each stored property becomes a computed property backed by hidden storage, with getter/setter that notifies an `ObservationRegistrar`
- SwiftUI tracks which properties a view body *actually reads*, then only re-renders when those specific properties change (unlike old `ObservableObject` where any `@Published` change re-rendered every observer)
- `withObservationTracking` tells you *when* something changed, but not *which* property. It fires **once** — you must re-register after each notification.

### 6.2 Domain State Structure

```swift
@Observable
class DomainState {
    var agents: AgentState = .init()
    var workspace: WorkspaceState = .init()
    var sessions: SessionState = .init()
    var connection: ConnectionState = .init()
}

@Observable
class AgentState: Codable {
    var sessions: [String: AgentSession] = [:]
    var activeSessionId: String? = nil
}

@Observable
class AgentSession: Codable {
    var id: String
    var status: AgentStatus
    var model: String
    var tokenCount: Int
    var createdAt: Date
}

enum AgentStatus: String, Codable {
    case idle, running, paused, error, completed
}
```

### 6.3 Push Strategy: Start with Whole Object

Start with pushing entire Codable objects (Option A). Payloads are tiny (1–10KB for most domain objects). Optimize to granular patches later only if profiling shows serialization is a bottleneck.

```swift
// Push whole AgentState when any agent property changes
func watchAndPushAgents() {
    withObservationTracking {
        _ = domainState.agents
    } onChange: {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.pushToJS(store: "agents", value: self.domainState.agents)
            self.watchAndPushAgents()
        }
    }
}

private func pushToJS<T: Codable>(store: String, value: T) async {
    let data = try! encoder.encode(value)
    let json = String(data: data, encoding: .utf8)!
    try? await page.callJavaScript(
        "window.__bridge.merge(store, JSON.parse(data))",
        arguments: ["store": store, "data": json],
        contentWorld: bridgeWorld
    )
}
```

---

## 7. Security Model

### 7.1 Six-Layer Protection

| Layer | Mechanism | What It Protects |
|-------|-----------|-----------------|
| **1. Content World Isolation** | `WebPage.ContentWorld.world(name: "agentStudioBridge")` | Bridge JS is invisible to page scripts. Page scripts cannot call `window.__bridge.*`. |
| **2. Message Handler Scoping** | `userContentController.add(handler, name: "rpc")` registered only in bridge world | Only bridge-world scripts can post to the `rpc` handler. |
| **3. Method Allowlisting** | `RPCRouter` only dispatches registered methods | Unknown methods return `-32601 Method not found`. No arbitrary code execution. |
| **4. Typed Params Validation** | `JSONDecoder` with concrete `Codable` types | Malformed or unexpected params fail at decode, never reach business logic. |
| **5. URL Scheme Sandboxing** | `agentstudio://` scheme with explicit path validation | Binary handler rejects paths outside allowed directories. No filesystem traversal. |
| **6. Navigation Policy** | `WebPage.NavigationDeciding` protocol | Only `agentstudio://` and `about:blank` allowed. All external URLs blocked or opened in default browser. |

### 7.2 Content World Setup

```swift
// All bridge communication goes through this isolated world
private let bridgeWorld = WebPage.ContentWorld.world(name: "agentStudioBridge")

// Script injection at document start — installs __bridge in the isolated world
let bootstrapScript = WKUserScript(
    source: bridgeBootstrapJS,
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(bootstrapScript, contentWorld: bridgeWorld)

// Message handler — only accessible from bridge world
config.userContentController.add(self, contentWorld: bridgeWorld, name: "rpc")
```

### 7.3 Navigation Policy

```swift
struct AgentStudioNavigationPolicy: WebPage.NavigationDeciding {
    func decidePolicy(for action: WebPage.NavigationAction) -> WebPage.NavigationAction.Policy {
        guard let url = action.request.url else { return .cancel }
        
        switch url.scheme {
        case "agentstudio":
            return .allow  // custom scheme — handled by URLSchemeHandler
        case "about":
            return .allow  // about:blank for initial load
        default:
            // Open external URLs in default browser
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}
```

---

## 8. Binary Channel: URLSchemeHandler

For large binary payloads (images, files, serialized data > 50KB) that would be expensive to base64-encode through `callJavaScript`.

### 8.1 Scheme Handler Implementation

```swift
struct BinarySchemeHandler: URLSchemeHandler {
    static let scheme = "agentstudio"
    
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncStream { continuation in
            Task {
                guard let url = request.url else {
                    continuation.finish(throwing: BridgeError.invalidURL)
                    return
                }
                
                // Route: agentstudio://resource/{type}/{id}
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                guard pathComponents.count >= 2 else {
                    continuation.finish(throwing: BridgeError.invalidPath)
                    return
                }
                
                let resourceType = pathComponents[0]
                let resourceId = pathComponents[1]
                
                // Security: validate resource type is allowed
                guard ["file", "image", "export"].contains(resourceType) else {
                    continuation.finish(throwing: BridgeError.forbiddenResource)
                    return
                }
                
                let (data, mimeType) = try await resolveResource(type: resourceType, id: resourceId)
                
                let response = URLResponse(
                    url: url,
                    mimeType: mimeType,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                
                continuation.yield(.response(response))
                continuation.yield(.data(data))
                continuation.finish()
            }
        }
    }
}
```

### 8.2 React Usage

```typescript
// Fetch binary data through the custom scheme
async function fetchResource(type: string, id: string): Promise<ArrayBuffer> {
    const response = await fetch(`agentstudio://resource/${type}/${id}`);
    return response.arrayBuffer();
}

// Example: load file content as text
async function loadFileContent(fileId: string): Promise<string> {
    const response = await fetch(`agentstudio://resource/file/${fileId}`);
    return response.text();
}

// Example: load image as blob URL for <img>
function useResourceImage(imageId: string) {
    return useQuery({
        queryKey: ["resource", "image", imageId],
        queryFn: async () => {
            const response = await fetch(`agentstudio://resource/image/${imageId}`);
            const blob = await response.blob();
            return URL.createObjectURL(blob);
        },
    });
}
```

---

## 9. SwiftUI Integration

### 9.1 Top-Level View

```swift
import SwiftUI
import WebKit

@main
struct AgentStudioApp: App {
    @State private var bridge = BridgeCoordinator()
    
    var body: some Scene {
        WindowGroup {
            WebView(bridge.page)
                .ignoresSafeArea()
                .webViewBackForwardNavigationGestures(.disabled)
                .webViewMagnificationGestures(.disabled)
                .webViewLinkPreviews(.disabled)
                .onAppear {
                    bridge.loadApp()
                }
        }
    }
}
```

### 9.2 Loading the React App

```swift
extension BridgeCoordinator {
    func loadApp() {
        // Load from custom scheme (bundled React build)
        let url = URL(string: "agentstudio://app/index.html")!
        page.load(URLRequest(url: url))
        
        // Start watching domain state after page loads
        Task {
            // Wait for page to finish loading
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            // Initialize state watches
            watchAndPushAgents()
            watchAndPushWorkspace()
            watchAndPushSessions()
        }
    }
}
```

---

## 10. File Structure

```
AgentStudio/
├── Sources/
│   ├── App/
│   │   └── AgentStudioApp.swift              # @main, WindowGroup with WebView
│   ├── Bridge/
│   │   ├── BridgeCoordinator.swift           # WebPage setup, state watching, push
│   │   ├── RPCRouter.swift                   # Method registry + dispatch
│   │   ├── RPCMethod.swift                   # Protocol + type-erased handler
│   │   ├── Methods/                          # One file per namespace
│   │   │   ├── AgentMethods.swift
│   │   │   ├── GitMethods.swift
│   │   │   ├── WorkspaceMethods.swift
│   │   │   ├── SessionMethods.swift
│   │   │   └── DbMethods.swift
│   │   ├── BinarySchemeHandler.swift         # agentstudio:// URL scheme
│   │   └── NavigationPolicy.swift            # WebPage.NavigationDeciding
│   ├── Domain/
│   │   ├── DomainState.swift                 # @Observable root state
│   │   ├── AgentState.swift                  # @Observable + Codable
│   │   ├── WorkspaceState.swift
│   │   ├── SessionState.swift
│   │   └── ConnectionState.swift
│   └── Services/
│       ├── AgentService.swift
│       ├── GitService.swift
│       └── DbService.swift
├── WebApp/                                    # React app (Vite + TypeScript)
│   ├── src/
│   │   ├── bridge/
│   │   │   ├── rpc-client.ts                 # JSON-RPC client
│   │   │   ├── methods.ts                    # Typed method wrappers
│   │   │   ├── query-client.ts               # TanStack QueryClient setup
│   │   │   └── notification-dispatcher.ts    # Routes notifications
│   │   ├── stores/
│   │   │   └── domain-stores.ts              # useSyncExternalStore stores
│   │   ├── hooks/
│   │   │   ├── useAgentState.ts              # useSyncExternalStore wrapper
│   │   │   ├── useFileTree.ts                # useQuery wrapper
│   │   │   └── useResourceImage.ts           # Binary fetch via scheme
│   │   └── App.tsx
│   └── vite.config.ts
└── Package.swift
```

---

## 11. Implementation Order

### Phase 1: Bootstrap (get React rendering in WebView)
1. Create `WebPage` with `WebPage.Configuration`
2. Implement `BinarySchemeHandler` for serving the React build (`agentstudio://app/*`)
3. Build React app with Vite, bundle into app resources
4. Load `agentstudio://app/index.html` in `WebView`
5. Verify React renders

### Phase 2: JSON-RPC Foundation
1. Implement `RPCClient` (JS) and `RPCRouter` (Swift)
2. Wire up `postMessage` (JS→Swift) and `callJavaScript` (Swift→JS)
3. Register one test method (`system.health`) end-to-end
4. Add content world isolation
5. Verify round-trip with typed params/results

### Phase 3: State Push Pipeline
1. Implement `createBridgeStore` + `useSyncExternalStore` for agent status
2. Implement TanStack Query integration with `setQueryData`
3. Wire up `withObservationTracking` → `callJavaScript` push loop
4. Implement notification dispatcher
5. Verify: change `@Observable` property in Swift → React re-renders

### Phase 4: Domain Methods
1. Register git, workspace, session, agent methods
2. Build React hooks (`useFileTree`, `useAgentState`, etc.)
3. Wire up DuckDB query path

### Phase 5: Binary Channel
1. Extend `BinarySchemeHandler` for file/image resources
2. Build `useResourceImage` hook
3. Verify large payload performance

### Phase 6: Security Hardening
1. Navigation policy — block all external navigation
2. Path validation in scheme handler
3. Rate limiting on RPC methods (if needed)
4. Audit content world isolation

---

## 12. Constraints & Limitations

### Known
- `withObservationTracking` fires **once** — must re-register after each change
- `withObservationTracking` tells you something changed but **not which property**
- `callJavaScript` return type is `Any?` — requires casting
- `WebPage` is macOS 26+ / iOS 26+ only — no backward compatibility
- Some WWDC 2025 sample code had compilation issues in later betas (confirmed in beta 7); validate against latest release
- `callJavaScript` goes through XPC (inter-process) — very fast but not zero-cost for huge payloads
- Custom scheme handler `reply(for:)` must return an `AsyncSequence` — blocking operations must be wrapped in `Task`

### Design Decisions
- **Whole-object push first** (Option A) — optimize to granular patches only if profiling warrants it
- **No optimistic updates** — latency is sub-frame, so real data arrives before user perceives gap
- **Multiple stores** over monolith — each domain context gets its own `BridgeStore`
- **TanStack Query as cache** — even for pushed data, gives us cache lifecycle, dedup, GC for free
- **JSON-RPC 2.0 strict** — standard error codes, `id` for requests, no `id` for notifications

### Open Questions
- Should `BridgeCoordinator` be a singleton or injectable?
- DuckDB queries — should results go through JSON-RPC or binary channel?
- Token streaming (LLM output) — use notifications or a dedicated streaming primitive?
- How to handle WebPage content world isolation in debug/dev mode (need console access)?