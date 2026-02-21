# Swift ↔ React Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the push-dominant bridge connecting Swift `@Observable` state to React/Zustand webview panels, proving the architecture with a diff viewer powered by Pierre.

**Architecture:** Swift pushes state into Zustand stores via `callJavaScript` through an isolated WebKit content world. React sends commands back via JSON-RPC 2.0 notifications relayed through `CustomEvent` → bridge world → `postMessage`. A binary URL scheme (`agentstudio://`) serves large payloads and the bundled React app. See `docs/architecture/swift_react_bridge_design.md` for the full spec.

**Tech Stack:** Swift 6.2, macOS 26 WebKit (`WebPage`, `WebView`), `@Observable` + `Observations`, Zustand, Vite, TypeScript, Pierre (`@pierre/diffs`), `swift-async-algorithms`.

---

## Invariants & Exit Criteria Matrix

### Global Invariants (all phases)

1. **Swift = source of truth** — Swift owns domain state; React mirrors it and owns only ephemeral UI state.
2. **Structured, versioned, validated messages** — Every cross-boundary message is structured (JSON-RPC or typed push), versioned (`__v` field on push envelopes), and validated before use.
3. **Explicit async lifecycle** — Every async loop has explicit lifecycle ownership and cancellation on pane teardown.
4. **Observable with correlation IDs** — Every state mutation path is observable with structured `os.log` and correlation IDs (`pushId` / `commandId`) for cross-boundary tracing.
5. **No crash on bridge errors** — No force-unwrap or crash path on bridge errors; failures degrade to `health: .error` state.
6. **Page lifecycle is first-class** — Page events (navigate, terminate, close) are first-class test scenarios, not afterthoughts.
7. **Measured performance** — Performance claims are enforced by measured budgets, not assumptions.
8. **Security by configuration** — Security boundaries are enforced by API configuration and negative tests.
9. **Explicit unsupported behavior** — Protocol behavior for unsupported features (batch, unknown methods) is explicit and deterministic.
10. **Independent phase shipping** — Any phase can ship independently without breaking previous phase guarantees.

### Phase 1: Transport Foundation

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 1.1 | Exactly one `WebPage` per pane and one RPC handler registration per page lifecycle. |
| Invariant | 1.2 | Bridge world identity is explicit (`WKContentWorld.world(name:)`) and used consistently. |
| Invariant | 1.3 | User script world scoping is correct (`WKUserScript(... in:)` + `addUserScript(_)`). |
| Test | 1.4 | Swift→JS `callJavaScript` success/failure on loaded, loading, and closed page states. |
| Test | 1.5 | JS→Swift message delivery only through configured handler name/world. |
| Test | 1.6 | Navigation during in-flight bridge call yields deterministic error handling. |
| Perf | 1.7 | p95 bridge call latency baseline recorded for 1KB / 10KB / 50KB payloads. |
| Perf | 1.8 | No unbounded retry loop when page unavailable. |
| Exit | 1.9 | Transport roundtrip tests pass, lifecycle race tests pass, baseline metrics published. |

### Phase 2: State Push Pipeline

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 2.1 | Observation loops are owned by coordinator and fully cancel on teardown. |
| Invariant | 2.2 | Pushes are epoch-safe; stale epoch updates never mutate current pane state. |
| Invariant | 2.3 | Hot scalar states bypass debounce; bulk states may debounce with explicit policy. |
| Test | 2.4 | Transactional coalescing verified for grouped synchronous mutations. |
| Test | 2.5 | Out-paced consumer behavior verified (latest consistency, intermediate skip tolerance). |
| Test | 2.6 | `merge`/`replace` semantics produce deterministic store snapshots. |
| Test | 2.7 | Selector fanout measured (only subscribed components rerender). |
| Perf | 2.8 | Push pipeline p95 CPU and rerender counts stay within budget for 100-file simulation. |
| Exit | 2.9 | Correctness tests pass, cancellation tests pass, rerender and latency budgets met. |

### Phase 3: JSON-RPC Command Channel

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 3.1 | Notification (`id` absent) produces no response object. |
| Invariant | 3.2 | Request (`id` present) produces exactly one terminal response (`result` or `error`). |
| Invariant | 3.3 | Error codes map correctly: -32700 parse, -32600 invalid request, -32601 method not found, -32602 invalid params, -32603 internal. |
| Invariant | 3.4 | Unsupported batch behavior is explicit (rejected with -32600). |
| Test | 3.5 | Malformed JSON, wrong envelope shape, unknown method, bad params type, handler throw. |
| Test | 3.6 | Mixed request/notification flow does not leak responses for notifications. |
| Test | 3.7 | Timeout and orphaned pending request handling for rare direct-response path. |
| Perf | 3.8 | Router dispatch throughput under burst load with no unbounded memory growth. |
| Exit | 3.9 | JSON-RPC compliance suite passes for declared feature set and burst tests pass. |

### Phase 4: Diff Viewer (Pierre Integration)

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 4.1 | Per-file state machine is valid (`pending → loading → loaded\|error`) with no illegal regressions. |
| Invariant | 4.2 | `loadEpoch` prevents stale writes after source switch. |
| Invariant | 4.3 | Duplicate file-content requests are deduped by lock/state guard. |
| Invariant | 4.4 | File list render never blocks on file-content fetch. |
| Test | 4.5 | 100+ file diff simulation with progressive content arrival correctness. |
| Test | 4.6 | On-demand priority requests during scroll do not duplicate or corrupt file state. |
| Test | 4.7 | Comment add/resolve/delete roundtrip and send-to-agent payload integrity. |
| Perf | 4.8 | First meaningful file list render and incremental content update latency measured and budgeted. |
| Exit | 4.9 | Large-diff functional suite passes, race-condition suite passes, UI performance budgets met. |

### Phase 5: Binary Channel

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 5.1 | Threshold routing is deterministic (`≤ threshold` → JSON push, `> threshold` → scheme fetch). |
| Invariant | 5.2 | URL scheme handler always emits `.response` before `.data` chunks. |
| Invariant | 5.3 | Request cancellation is honored promptly (task cancellation stops I/O work). |
| Invariant | 5.4 | MIME type and encoding are correct for all served resource classes. |
| Invariant | 5.5 | Path validation blocks traversal and disallowed resource types. |
| Test | 5.6 | Payload equivalence between JSON path and binary path for same file. |
| Test | 5.7 | Cancellation during large stream, navigation away mid-stream, and concurrent fetch bursts. |
| Perf | 5.8 | 100KB / 500KB / 1MB comparisons capture latency, throughput, memory, and CPU. |
| Exit | 5.9 | Security validation passes, streaming correctness passes, binary path beats or matches JSON above threshold. |

### Phase 6: Security Hardening

| Type | # | Requirement |
|------|---|-------------|
| Invariant | 6.1 | Only allowlisted RPC methods are dispatchable. |
| Invariant | 6.2 | Page-world script cannot directly access bridge-only handler surface. |
| Invariant | 6.3 | Navigation policy allows only explicitly approved schemes/routes. |
| Invariant | 6.4 | Dangerous schemes and malformed URLs are rejected safely. |
| Invariant | 6.5 | RPC flooding is rate-limited or backpressured without process instability. |
| Test | 6.6 | Forged command event, unknown method flood, malformed payload flood, traversal attempts. |
| Test | 6.7 | External URL navigation attempt triggers intended handoff/block behavior. |
| Test | 6.8 | Web-content process termination and restart path preserves security guarantees. |
| Exit | 6.9 | Full negative security suite passes and no high-severity finding remains open. |

---

## Prerequisites

Before starting, verify you have:
- Xcode 26 beta (Swift 6.2, macOS 26 SDK)
- Node.js 20+ and pnpm
- The project builds: `swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL"`

## Codebase Context

**Key files you'll touch or reference:**

| Purpose | Path |
|---------|------|
| Package manifest | `Package.swift` |
| Pane content enum | `Sources/AgentStudio/Models/PaneContent.swift` |
| Webview state model | `Sources/AgentStudio/Models/PaneContent.swift:168-173` |
| Webview view (stub) | `Sources/AgentStudio/Views/WebviewPaneView.swift` |
| Base pane view | `Sources/AgentStudio/Views/PaneView.swift` |
| View coordinator | `Sources/AgentStudio/App/TerminalViewCoordinator.swift:75-79` |
| View registry | `Sources/AgentStudio/Services/ViewRegistry.swift` |
| Workspace store | `Sources/AgentStudio/Services/WorkspaceStore.swift` |
| Command bar (Observable example) | `Sources/AgentStudio/CommandBar/CommandBarState.swift` |
| Existing tests | `Tests/AgentStudioTests/` |
| Design spec | `docs/architecture/swift_react_bridge_design.md` |

**Patterns to follow:**
- `@MainActor` on all state classes and services
- `@Observable` for new state (not `ObservableObject` — see `CommandBarState.swift:12`)
- `XCTestCase` with Arrange/Act/Assert
- Forward-compatible `Codable` with version discriminator (see `PaneContent.swift`)
- `PaneView` base class for all pane types

---

## Phase 1: Transport Foundation

> **Goal**: `callJavaScript` and `postMessage` work bidirectionally. React app loads from `agentstudio://` scheme.

### Task 1.1: Add swift-async-algorithms Dependency

**Files:**
- Modify: `Package.swift`

**Step 1: Add the dependency**

Add `swift-async-algorithms` to `Package.swift`. This provides `.debounce(for:)` on `AsyncSequence`, which the push pipeline needs (§6.2 of design spec).

```swift
// Package.swift — add to dependencies array (line 12)
dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
],

// Add to the AgentStudio executable target's dependencies (line 16)
dependencies: ["GhosttyKit", .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")],
```

Also bump the platform to macOS 26:
```swift
platforms: [
    .macOS("26.0")
],
```

And bump swift-tools-version to 6.0:
```swift
// swift-tools-version:6.0
```

**Step 2: Verify build**

Run: `swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL"`
Expected: BUILD OK (package resolves and project compiles)

**Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "feat: add swift-async-algorithms dependency and bump to macOS 26"
```

---

### Task 1.2: Scaffold React App with Vite

**Files:**
- Create: `WebApp/` directory with Vite + TypeScript + React project
- Create: `WebApp/package.json`
- Create: `WebApp/vite.config.ts`
- Create: `WebApp/tsconfig.json`
- Create: `WebApp/src/App.tsx`
- Create: `WebApp/src/main.tsx`
- Create: `WebApp/index.html`

**Step 1: Initialize the React project**

```bash
cd WebApp
pnpm create vite . --template react-ts
pnpm install
pnpm add zustand @pierre/diffs
pnpm add -D @types/react @types/react-dom
```

**Step 2: Configure Vite for bridge context**

```typescript
// WebApp/vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
    plugins: [react()],
    base: './',  // Relative paths for agentstudio:// scheme
    build: {
        outDir: 'dist',
        assetsDir: 'assets',
        // Single chunk for simplicity — no code splitting for embedded app
        rollupOptions: {
            output: {
                manualChunks: undefined,
            },
        },
    },
});
```

**Step 3: Create minimal App component**

```tsx
// WebApp/src/App.tsx
import { ReactElement } from 'react';

export function App(): ReactElement {
    return (
        <div id="bridge-app">
            <h1>Agent Studio Bridge</h1>
            <p>Transport: waiting for connection...</p>
        </div>
    );
}
```

```tsx
// WebApp/src/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';

createRoot(document.getElementById('root')!).render(
    <StrictMode>
        <App />
    </StrictMode>,
);
```

**Step 4: Build and verify**

```bash
cd WebApp && pnpm build
ls dist/  # Should contain index.html + assets/
```

**Step 5: Commit**

```bash
git add WebApp/
git commit -m "feat: scaffold React app with Vite, Zustand, Pierre"
```

---

### Task 1.3: BinarySchemeHandler — Serve React App

**Files:**
- Create: `Sources/AgentStudio/Bridge/BinarySchemeHandler.swift`
- Test: `Tests/AgentStudioTests/Bridge/BinarySchemeHandlerTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/AgentStudioTests/Bridge/BinarySchemeHandlerTests.swift
import XCTest
@testable import AgentStudio

final class BinarySchemeHandlerTests: XCTestCase {
    func test_mimeType_html() {
        XCTAssertEqual(BinarySchemeHandler.mimeType(for: "index.html"), "text/html")
    }

    func test_mimeType_js() {
        XCTAssertEqual(BinarySchemeHandler.mimeType(for: "app.js"), "application/javascript")
    }

    func test_mimeType_css() {
        XCTAssertEqual(BinarySchemeHandler.mimeType(for: "style.css"), "text/css")
    }

    func test_mimeType_unknown_defaults_to_octet_stream() {
        XCTAssertEqual(BinarySchemeHandler.mimeType(for: "data.bin"), "application/octet-stream")
    }

    func test_resolveAppPath_rejects_traversal() {
        XCTAssertNil(BinarySchemeHandler.resolveAppPath("../../etc/passwd"))
    }

    func test_resolveAppPath_accepts_valid_path() {
        // This will return nil in test context (no bundle), but should not crash
        let result = BinarySchemeHandler.resolveAppPath("index.html")
        // Just verify it doesn't crash — path resolution depends on bundle
        _ = result
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter BinarySchemeHandlerTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: FAIL — `BinarySchemeHandler` type not found

**Step 3: Write the implementation**

```swift
// Sources/AgentStudio/Bridge/BinarySchemeHandler.swift
import Foundation
import WebKit
import os.log

private let schemeLogger = Logger(subsystem: "com.agentstudio", category: "BinarySchemeHandler")

/// Serves bundled React app assets and resource files via the `agentstudio://` URL scheme.
///
/// Two path prefixes:
/// - `agentstudio://app/*` — Bundled React app (index.html, JS, CSS)
/// - `agentstudio://resource/file/*` — Dynamic file contents (Phase 5)
@MainActor
struct BinarySchemeHandler {

    /// Resolve a MIME type from a file extension.
    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "html": return "text/html"
        case "js", "mjs": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }

    /// Resolve a relative path within the bundled app directory.
    /// Returns nil if the path attempts traversal or the file doesn't exist.
    static func resolveAppPath(_ relativePath: String) -> URL? {
        // Block path traversal
        guard !relativePath.contains("..") else {
            schemeLogger.warning("Path traversal blocked: \(relativePath)")
            return nil
        }

        // Look for the built React app in the app's Resources directory
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let webAppDir = resourceURL.appendingPathComponent("WebApp")
        let resolved = webAppDir.appendingPathComponent(relativePath)

        // Verify the resolved path is still within the webAppDir
        guard resolved.path.hasPrefix(webAppDir.path) else {
            schemeLogger.warning("Path escape blocked: \(relativePath)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }

        return resolved
    }
}
```

> **Note**: The full `URLSchemeHandler` protocol conformance (with `AsyncSequence` return) requires macOS 26 WebKit APIs. This task implements the pure-logic helpers. Task 1.5 wires it into `WebPage.Configuration`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter BinarySchemeHandlerTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Bridge/BinarySchemeHandler.swift Tests/AgentStudioTests/Bridge/BinarySchemeHandlerTests.swift
git commit -m "feat: add BinarySchemeHandler with MIME type resolution and path validation"
```

---

### Task 1.4: Bridge Bootstrap Script

**Files:**
- Create: `Sources/AgentStudio/Bridge/BridgeBootstrap.swift`
- Test: `Tests/AgentStudioTests/Bridge/BridgeBootstrapTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/AgentStudioTests/Bridge/BridgeBootstrapTests.swift
import XCTest
@testable import AgentStudio

final class BridgeBootstrapTests: XCTestCase {
    func test_bootstrapJS_contains_bridgeInternal() {
        let js = BridgeBootstrap.bridgeBootstrapJS
        XCTAssertTrue(js.contains("__bridgeInternal"), "Bootstrap must define __bridgeInternal")
    }

    func test_bootstrapJS_contains_nonce_setup() {
        let js = BridgeBootstrap.bridgeBootstrapJS
        XCTAssertTrue(js.contains("data-bridge-nonce"), "Bootstrap must set nonce on documentElement")
    }

    func test_bootstrapJS_contains_command_listener() {
        let js = BridgeBootstrap.bridgeBootstrapJS
        XCTAssertTrue(js.contains("__bridge_command"), "Bootstrap must listen for command events")
    }

    func test_bootstrapJS_contains_nonce_validation() {
        let js = BridgeBootstrap.bridgeBootstrapJS
        XCTAssertTrue(js.contains("__nonce"), "Bootstrap must validate nonce on commands")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter BridgeBootstrapTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: FAIL — `BridgeBootstrap` not found

**Step 3: Write the implementation**

```swift
// Sources/AgentStudio/Bridge/BridgeBootstrap.swift
import Foundation

/// Contains the JavaScript bootstrap code injected into the bridge content world.
///
/// This script runs at document start in the isolated `agentStudioBridge` content world.
/// It installs `__bridgeInternal` (invisible to page world), generates a nonce for
/// command authentication, and sets up the CustomEvent relay between bridge ↔ page worlds.
///
/// See design spec §11.2 and §11.3.
enum BridgeBootstrap {

    /// JavaScript source injected into the bridge content world at document start.
    static let bridgeBootstrapJS: String = """
    (function() {
        'use strict';

        // Generate nonce for command authentication
        const bridgeNonce = crypto.randomUUID();

        // Expose nonce to page world via DOM attribute (page world reads this)
        document.documentElement.setAttribute('data-bridge-nonce', bridgeNonce);

        // Bridge internal API — only visible in this content world
        window.__bridgeInternal = {
            merge(store, data) {
                document.dispatchEvent(new CustomEvent('__bridge_push', {
                    detail: { type: 'merge', store: store, data: data }
                }));
            },
            replace(store, data) {
                document.dispatchEvent(new CustomEvent('__bridge_push', {
                    detail: { type: 'replace', store: store, data: data }
                }));
            },
            response(payload) {
                document.dispatchEvent(new CustomEvent('__bridge_response', {
                    detail: payload
                }));
            }
        };

        // Relay commands from page world to Swift (with nonce validation)
        document.addEventListener('__bridge_command', function(e) {
            if (!e.detail || e.detail.__nonce !== bridgeNonce) return;
            var payload = Object.assign({}, e.detail);
            delete payload.__nonce;
            window.webkit.messageHandlers.rpc.postMessage(JSON.stringify(payload));
        });
    })();
    """
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter BridgeBootstrapTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Bridge/BridgeBootstrap.swift Tests/AgentStudioTests/Bridge/BridgeBootstrapTests.swift
git commit -m "feat: add bridge bootstrap script with nonce auth and CustomEvent relay"
```

---

### Task 1.5: RPCMessageHandler

**Files:**
- Create: `Sources/AgentStudio/Bridge/RPCMessageHandler.swift`
- Test: `Tests/AgentStudioTests/Bridge/RPCMessageHandlerTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/AgentStudioTests/Bridge/RPCMessageHandlerTests.swift
import XCTest
@testable import AgentStudio

final class RPCMessageHandlerTests: XCTestCase {
    func test_extractJSON_from_valid_string() {
        let result = RPCMessageHandler.extractJSON(from: #"{"jsonrpc":"2.0","method":"test"}"#)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, #"{"jsonrpc":"2.0","method":"test"}"#)
    }

    func test_extractJSON_from_non_string_returns_nil() {
        let result = RPCMessageHandler.extractJSON(from: 42)
        XCTAssertNil(result)
    }

    func test_extractJSON_from_empty_string_returns_nil() {
        let result = RPCMessageHandler.extractJSON(from: "")
        XCTAssertNil(result)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RPCMessageHandlerTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: FAIL

**Step 3: Write the implementation**

```swift
// Sources/AgentStudio/Bridge/RPCMessageHandler.swift
import Foundation
import WebKit
import os.log

private let handlerLogger = Logger(subsystem: "com.agentstudio", category: "RPCMessageHandler")

/// WKScriptMessageHandler that receives JSON-RPC commands from the bridge content world.
///
/// Registered on `WKUserContentController` scoped to the bridge content world, so only
/// the bootstrap script can call `window.webkit.messageHandlers.rpc.postMessage()`.
///
/// See design spec §9.3.
final class RPCMessageHandler: NSObject, WKScriptMessageHandler {
    /// Callback invoked with the raw JSON string when a command arrives.
    private let onCommand: @MainActor (String) -> Void

    init(onCommand: @escaping @MainActor (String) -> Void) {
        self.onCommand = onCommand
        super.init()
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let json = Self.extractJSON(from: message.body) else {
            handlerLogger.warning("Received non-string message body from bridge world")
            return
        }

        Task { @MainActor in
            onCommand(json)
        }
    }

    /// Extract a non-empty JSON string from a WKScriptMessage body.
    /// Returns nil if the body is not a String or is empty.
    static func extractJSON(from body: Any) -> String? {
        guard let json = body as? String, !json.isEmpty else { return nil }
        return json
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter RPCMessageHandlerTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Bridge/RPCMessageHandler.swift Tests/AgentStudioTests/Bridge/RPCMessageHandlerTests.swift
git commit -m "feat: add RPCMessageHandler for bridge world postMessage reception"
```

---

### Task 1.6: RPCRouter — Method Registry and Dispatch

**Files:**
- Create: `Sources/AgentStudio/Bridge/RPCRouter.swift`
- Create: `Sources/AgentStudio/Bridge/RPCMethod.swift`
- Test: `Tests/AgentStudioTests/Bridge/RPCRouterTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/AgentStudioTests/Bridge/RPCRouterTests.swift
import XCTest
@testable import AgentStudio

// Test method definitions
private enum TestPing: RPCMethod {
    static let method = "test.ping"
    struct Params: Codable { let message: String }
    typealias Result = Never  // Notification, no response
}

private enum TestHealth: RPCMethodWithResponse {
    static let method = "test.health"
    struct Params: Codable {}
    struct Result: Codable { let status: String }
}

final class RPCRouterTests: XCTestCase {
    func test_dispatch_known_method_invokes_handler() async throws {
        // Arrange
        let router = RPCRouter()
        var receivedMessage: String?
        await router.register(TestPing.self) { params in
            receivedMessage = params.message
        }

        // Act
        let json = #"{"jsonrpc":"2.0","method":"test.ping","params":{"message":"hello"}}"#
        let response = await router.dispatch(json: json)

        // Assert
        XCTAssertEqual(receivedMessage, "hello")
        XCTAssertNil(response, "Notification should produce no response")
    }

    func test_dispatch_unknown_method_returns_error() async {
        // Arrange
        let router = RPCRouter()

        // Act
        let json = #"{"jsonrpc":"2.0","id":"1","method":"unknown.method","params":{}}"#
        let response = await router.dispatch(json: json)

        // Assert
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains("-32601"), "Should return method-not-found error")
    }

    func test_dispatch_invalid_json_returns_parse_error() async {
        // Arrange
        let router = RPCRouter()

        // Act
        let response = await router.dispatch(json: "not valid json{{{")

        // Assert
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains("-32700"), "Should return parse error")
    }

    func test_dispatch_notification_no_id_returns_nil() async {
        // Arrange
        let router = RPCRouter()
        await router.register(TestPing.self) { _ in }

        // Act — notification has no id field
        let json = #"{"jsonrpc":"2.0","method":"test.ping","params":{"message":"hi"}}"#
        let response = await router.dispatch(json: json)

        // Assert
        XCTAssertNil(response, "Notification (no id) must not produce a response")
    }

    func test_dispatch_missing_params_uses_empty_object() async {
        // Arrange
        let router = RPCRouter()
        var handlerCalled = false
        await router.register(TestHealth.self) { _ in
            handlerCalled = true
            return TestHealth.Result(status: "ok")
        }

        // Act — no params field at all
        let json = #"{"jsonrpc":"2.0","id":"1","method":"test.health"}"#
        _ = await router.dispatch(json: json)

        // Assert
        XCTAssertTrue(handlerCalled)
    }

    func test_dispatch_batch_request_rejected() async {
        // Arrange
        let router = RPCRouter()

        // Act — batch request (array)
        let json = #"[{"jsonrpc":"2.0","method":"test.ping","params":{"message":"hi"}}]"#
        let response = await router.dispatch(json: json)

        // Assert
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains("-32600"), "Batch requests should return invalid request error")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RPCRouterTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: FAIL

**Step 3: Write RPCMethod protocol**

```swift
// Sources/AgentStudio/Bridge/RPCMethod.swift
import Foundation

/// Protocol for JSON-RPC notification methods (fire-and-forget, no response).
protocol RPCMethod {
    associatedtype Params: Codable
    static var method: String { get }
}

/// Protocol for JSON-RPC request methods that return a direct response (rare path).
protocol RPCMethodWithResponse: RPCMethod {
    associatedtype Result: Codable
}

/// Type-erased method handler stored in the router.
struct AnyMethodHandler: Sendable {
    /// Handle raw param bytes, return optional response bytes.
    /// Returns nil for notifications (no response needed).
    let handle: @Sendable (Data) async throws -> Data?
}

/// JSON-RPC envelope decoded from incoming messages.
struct RPCEnvelope: Codable {
    let jsonrpc: String
    let id: String?
    let method: String
    // params stored as raw JSON — decoded lazily by the handler
}

/// JSON-RPC error response.
struct RPCErrorResponse: Codable {
    let jsonrpc: String
    let id: String?
    let error: RPCError

    struct RPCError: Codable {
        let code: Int
        let message: String
    }

    init(id: String?, code: Int, message: String) {
        self.jsonrpc = "2.0"
        self.id = id
        self.error = RPCError(code: code, message: message)
    }
}

/// JSON-RPC success response.
struct RPCSuccessResponse: Codable {
    let jsonrpc: String
    let id: String
    let result: AnyCodableValue

    init(id: String, result: AnyCodableValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
    }
}
```

**Step 4: Write RPCRouter**

```swift
// Sources/AgentStudio/Bridge/RPCRouter.swift
import Foundation
import os.log

private let routerLogger = Logger(subsystem: "com.agentstudio", category: "RPCRouter")

/// Routes incoming JSON-RPC messages to registered method handlers.
///
/// Thread-safe via actor isolation. Handlers are registered at startup and
/// dispatched on incoming messages from the bridge world.
///
/// See design spec §9.2.
actor RPCRouter {
    private var handlers: [String: AnyMethodHandler] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Register a notification handler (fire-and-forget, no response).
    func register<M: RPCMethod>(
        _ type: M.Type,
        handler: @escaping @Sendable (M.Params) async throws -> Void
    ) {
        handlers[M.method] = AnyMethodHandler { paramsData in
            let params = try JSONDecoder().decode(M.Params.self, from: paramsData)
            try await handler(params)
            return nil
        }
    }

    /// Register a request handler that returns a direct response (rare path).
    func register<M: RPCMethodWithResponse>(
        _ type: M.Type,
        handler: @escaping @Sendable (M.Params) async throws -> M.Result
    ) {
        handlers[M.method] = AnyMethodHandler { paramsData in
            let params = try JSONDecoder().decode(M.Params.self, from: paramsData)
            let result = try await handler(params)
            return try JSONEncoder().encode(result)
        }
    }

    /// Dispatch an incoming JSON-RPC message.
    ///
    /// Returns a JSON response string if the message was a request (had `id`),
    /// or nil if it was a notification.
    func dispatch(json: String) async -> String? {
        guard let data = json.data(using: .utf8) else {
            return encodeError(id: nil, code: -32700, message: "Invalid encoding")
        }

        // Reject batch requests (JSON arrays)
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            return encodeError(id: nil, code: -32600, message: "Batch requests not supported")
        }

        // Parse envelope — extract method and id, keep raw params
        let envelope: RPCEnvelope
        let rawParamsData: Data
        do {
            envelope = try decoder.decode(RPCEnvelope.self, from: data)
            // Extract raw params from JSON
            rawParamsData = extractRawParams(from: data) ?? Data("{}".utf8)
        } catch {
            routerLogger.warning("JSON-RPC parse error: \(error)")
            return encodeError(id: nil, code: -32700, message: "Parse error")
        }

        // Look up handler
        guard let handler = handlers[envelope.method] else {
            routerLogger.info("Method not found: \(envelope.method)")
            if let id = envelope.id {
                return encodeError(id: id, code: -32601, message: "Method not found: \(envelope.method)")
            }
            return nil  // Notification with unknown method — silently ignore per spec
        }

        // Execute handler
        do {
            let responseData = try await handler.handle(rawParamsData)

            // If request has id AND handler returned data, send response
            if let id = envelope.id, let responseData {
                let resultValue = try decoder.decode(AnyCodableValue.self, from: responseData)
                let response = RPCSuccessResponse(id: id, result: resultValue)
                return String(data: try encoder.encode(response), encoding: .utf8)
            }

            return nil  // Notification — no response
        } catch {
            routerLogger.error("Handler error for \(envelope.method): \(error)")
            if let id = envelope.id {
                return encodeError(id: id, code: -32603, message: "Internal error: \(error.localizedDescription)")
            }
            return nil
        }
    }

    // MARK: - Private

    private func encodeError(id: String?, code: Int, message: String) -> String? {
        let response = RPCErrorResponse(id: id, code: code, message: message)
        guard let data = try? encoder.encode(response) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Extract the raw "params" value from a JSON-RPC message as Data.
    /// Returns nil if "params" key is missing.
    private func extractRawParams(from jsonData: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let params = json["params"] else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: params)
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter RPCRouterTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`
Expected: PASS (all 6 tests)

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Bridge/RPCRouter.swift Sources/AgentStudio/Bridge/RPCMethod.swift Tests/AgentStudioTests/Bridge/RPCRouterTests.swift
git commit -m "feat: add RPCRouter with typed method dispatch and JSON-RPC 2.0 compliance"
```

---

### Task 1.7: BridgeCoordinator — WebPage Setup and Wiring

**Files:**
- Create: `Sources/AgentStudio/Bridge/BridgeCoordinator.swift`
- Modify: `Sources/AgentStudio/Views/WebviewPaneView.swift` — replace stub with WebView
- Modify: `Sources/AgentStudio/App/TerminalViewCoordinator.swift:75-79` — wire BridgeCoordinator

> **Note**: This task uses macOS 26 WebKit APIs (`WebPage`, `WebView`, `WKContentWorld`). It cannot be unit tested without a running app. Write the code, verify it compiles, and test visually with Peekaboo in Task 1.8.

**Step 1: Write BridgeCoordinator**

```swift
// Sources/AgentStudio/Bridge/BridgeCoordinator.swift
import Foundation
import WebKit
import os.log

private let bridgeLogger = Logger(subsystem: "com.agentstudio", category: "BridgeCoordinator")

/// Owns one WebPage and bridges Swift domain state to a React webview panel.
///
/// One coordinator per webview pane. Manages:
/// - WebPage configuration (content world, message handler, scheme handler, bootstrap script)
/// - RPC command dispatch from JS to Swift
/// - State push from Swift to JS (Phase 2)
/// - Observation loops watching @Observable state (Phase 2)
///
/// See design spec §9.1.
@MainActor
@Observable
final class BridgeCoordinator {
    let page: WebPage
    let router: RPCRouter
    private let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
    private var observationTask: Task<Void, Never>?

    init() {
        self.router = RPCRouter()

        var config = WebPage.Configuration()

        // 1. Register bootstrap script in bridge content world
        let bootstrapScript = WKUserScript(
            source: BridgeBootstrap.bridgeBootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        config.userContentController.addUserScript(bootstrapScript)

        // 2. Register message handler in bridge world only
        let messageHandler = RPCMessageHandler { [weak self] json in
            guard let self else { return }
            Task {
                if let response = await self.router.dispatch(json: json) {
                    await self.sendResponseToJS(response)
                }
            }
        }
        config.userContentController.add(
            messageHandler,
            contentWorld: bridgeWorld,
            name: "rpc"
        )

        // 3. Register URL scheme handler for agentstudio://
        // TODO: Wire BinarySchemeHandler as URLSchemeHandler protocol conformance (Phase 5)

        // 4. Create WebPage
        self.page = WebPage(configuration: config)

        // 5. Set navigation policy
        // TODO: Wire AgentStudioNavigationDecider (Phase 6)
    }

    /// Load the React app from the bundled assets.
    func loadApp() {
        // For now, load a simple HTML page to verify transport works.
        // Phase 5 will serve from agentstudio:// scheme.
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Agent Studio Bridge</title></head>
        <body>
            <div id="root">
                <h1>Bridge Active</h1>
                <p id="status">Waiting for push...</p>
            </div>
            <script>
                document.addEventListener('__bridge_push', function(e) {
                    document.getElementById('status').textContent =
                        'Received push: ' + e.detail.store + ' (' + e.detail.type + ')';
                });
            </script>
        </body>
        </html>
        """
        page.loadHTMLString(html, baseURL: nil)

        bridgeLogger.info("Bridge coordinator loaded app")
    }

    /// Send a JSON-RPC response back to JS via callJavaScript.
    private func sendResponseToJS(_ json: String) async {
        do {
            try await page.callJavaScript(
                "window.__bridgeInternal.response(JSON.parse(data))",
                arguments: ["data": json],
                in: page.mainFrame,
                contentWorld: bridgeWorld
            )
        } catch {
            bridgeLogger.warning("Failed to send response to JS: \(error)")
        }
    }

    /// Push state to a named Zustand store via merge.
    func pushState<T: Codable>(store storeName: String, value: T) async {
        do {
            let data = try JSONEncoder().encode(value)
            guard let json = String(data: data, encoding: .utf8) else { return }

            try await page.callJavaScript(
                "window.__bridgeInternal.merge(store, JSON.parse(data))",
                arguments: ["store": storeName, "data": json],
                in: page.mainFrame,
                contentWorld: bridgeWorld
            )
        } catch {
            bridgeLogger.warning("Push to \(storeName) failed: \(error)")
        }
    }

    /// Clean up observation loops and cancel pending tasks.
    func teardown() {
        observationTask?.cancel()
        observationTask = nil
        bridgeLogger.info("Bridge coordinator torn down")
    }
}
```

**Step 2: Update WebviewPaneView to host WebView**

Replace the stub in `Sources/AgentStudio/Views/WebviewPaneView.swift`:

```swift
// Sources/AgentStudio/Views/WebviewPaneView.swift
import AppKit
import WebKit

/// Hosts a WebView connected to a BridgeCoordinator for React-powered panels.
final class WebviewPaneView: PaneView {
    private let state: WebviewState
    let coordinator: BridgeCoordinator

    init(paneId: UUID, state: WebviewState) {
        self.state = state
        self.coordinator = BridgeCoordinator()
        super.init(paneId: paneId)
        setupWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupWebView() {
        wantsLayer = true

        // Create WebView from the coordinator's WebPage
        let webView = WebView(page: coordinator.page)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        coordinator.loadApp()
    }
}
```

**Step 3: Verify build compiles**

Run: `swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -30 /tmp/build-output.txt)"`
Expected: BUILD OK

> **Important**: If macOS 26 WebKit APIs (`WebPage`, `WebView`, `WKContentWorld.world(name:)`) produce compile errors, this is the verification spike from the design doc §16. Consult the exact API docs and adjust signatures. Common issues:
> - `callJavaScript` parameter labels may differ
> - `WKUserScript(in:)` parameter name may differ
> - `WebView(page:)` initializer may differ
> Document any API mismatches and update the design doc.

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Bridge/BridgeCoordinator.swift Sources/AgentStudio/Views/WebviewPaneView.swift
git commit -m "feat: add BridgeCoordinator with WebPage setup and content world isolation"
```

---

### Task 1.8: Visual Verification — Round-Trip Transport Test

**Files:**
- No new files — visual test of existing code

**Step 1: Build the app**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -30 /tmp/build-output.txt)"
```

**Step 2: Launch and verify**

1. Launch the app: `.build/debug/AgentStudio &`
2. Open a webview pane (via command bar or action)
3. Use Peekaboo to capture screenshot: verify "Bridge Active" text renders in the webview pane
4. If the bridge is working, the `__bridge_push` listener will update "Waiting for push..." when state is pushed (Phase 2 will wire this)

**Step 3: Verify round-trip manually (optional)**

In the app's webview, open Safari Web Inspector → Console. From the bridge world:
```javascript
// This should trigger the page-world listener
window.__bridgeInternal.merge("test", { hello: "world" })
```

The page should update to show "Received push: test (merge)".

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve API mismatches discovered during transport verification"
```

---

## Phase 2: State Push Pipeline

> **Goal**: Swift `@Observable` changes arrive in Zustand stores. Content world relay works.

### Task 2.1: Domain State Models

**Files:**
- Create: `Sources/AgentStudio/Bridge/Domain/DiffState.swift`
- Create: `Sources/AgentStudio/Bridge/Domain/ConnectionState.swift`
- Create: `Sources/AgentStudio/Bridge/Domain/PaneDomainState.swift`
- Create: `Sources/AgentStudio/Bridge/Domain/SharedBridgeState.swift`
- Test: `Tests/AgentStudioTests/Bridge/DiffStateTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/AgentStudioTests/Bridge/DiffStateTests.swift
import XCTest
@testable import AgentStudio

final class DiffStateTests: XCTestCase {
    func test_diffFile_roundTrip() throws {
        // Arrange
        let file = DiffFile(
            id: "abc", path: "src/main.swift", oldPath: nil,
            changeType: .modified, status: .pending,
            oldContent: nil, newContent: nil, size: 1024
        )

        // Act
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(DiffFile.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.path, "src/main.swift")
        XCTAssertEqual(decoded.changeType, .modified)
        XCTAssertEqual(decoded.status, .pending)
    }

    func test_diffSource_commitRange_roundTrip() throws {
        // Arrange
        let source = DiffSource.commitRange(from: "abc123", to: "def456")

        // Act
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(DiffSource.self, from: data)

        // Assert
        XCTAssertEqual(decoded, source)
    }

    func test_diffComment_codable() throws {
        // Arrange
        let comment = DiffComment(
            id: UUID(),
            fileId: "file1",
            lineNumber: 42,
            side: .new,
            text: "Looks good",
            createdAt: Date(),
            author: CommentAuthor(type: .user, name: "Shravan")
        )

        // Act
        let data = try JSONEncoder().encode(comment)
        let decoded = try JSONDecoder().decode(DiffComment.self, from: data)

        // Assert
        XCTAssertEqual(decoded.fileId, "file1")
        XCTAssertEqual(decoded.lineNumber, 42)
        XCTAssertEqual(decoded.side, .new)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DiffStateTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"`

**Step 3: Write the domain models**

Create all four files matching the design spec §8. Each `@Observable` class with `Codable` conformance, all `@MainActor`. Reference design spec §8.1–§8.3 for exact type definitions.

**Step 4: Run test to verify it passes**

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Bridge/Domain/ Tests/AgentStudioTests/Bridge/DiffStateTests.swift
git commit -m "feat: add domain state models for bridge (DiffState, ConnectionState, PaneDomainState)"
```

---

### Task 2.2: Zustand Stores + Bridge Receiver (React)

**Files:**
- Create: `WebApp/src/stores/diff-store.ts`
- Create: `WebApp/src/stores/connection-store.ts`
- Create: `WebApp/src/bridge/receiver.ts`
- Create: `WebApp/src/bridge/types.ts`
- Create: `WebApp/src/types/bridge-events.d.ts`
- Create: `WebApp/src/utils/deep-merge.ts`
- Test: `WebApp/src/utils/deep-merge.test.ts`

**Step 1: Write failing test for deepMerge**

```typescript
// WebApp/src/utils/deep-merge.test.ts
import { describe, it, expect } from 'vitest';
import { deepMerge } from './deep-merge';

describe('deepMerge', () => {
    it('merges flat objects', () => {
        const target = { a: 1, b: 2 };
        const source = { b: 3, c: 4 };
        const result = deepMerge(target, source);
        expect(result).toEqual({ a: 1, b: 3, c: 4 });
    });

    it('merges nested objects', () => {
        const target = { a: { x: 1, y: 2 }, b: 3 };
        const source = { a: { y: 99 } };
        const result = deepMerge(target, source);
        expect(result).toEqual({ a: { x: 1, y: 99 }, b: 3 });
    });

    it('replaces arrays (does not merge)', () => {
        const target = { list: [1, 2, 3] };
        const source = { list: [4, 5] };
        const result = deepMerge(target, source);
        expect(result).toEqual({ list: [4, 5] });
    });

    it('returns new root reference', () => {
        const target = { a: 1 };
        const source = { b: 2 };
        const result = deepMerge(target, source);
        expect(result).not.toBe(target);
    });

    it('preserves reference for unchanged branches', () => {
        const nested = { x: 1 };
        const target = { a: nested, b: 2 };
        const source = { b: 3 };
        const result = deepMerge(target, source);
        expect(result.a).toBe(nested); // Structural sharing
    });

    it('deletes keys when source value is null', () => {
        const target = { a: 1, b: 2 } as Record<string, unknown>;
        const source = { a: null };
        const result = deepMerge(target, source);
        expect(result).toEqual({ b: 2 });
    });
});
```

**Step 2: Install vitest and run test**

```bash
cd WebApp && pnpm add -D vitest
pnpm vitest run src/utils/deep-merge.test.ts
```
Expected: FAIL

**Step 3: Implement deepMerge, stores, receiver, and types**

Write all files matching design spec §7.1–§7.7. Key contracts:
- `deepMerge` must produce new references for changed branches (structural sharing)
- Arrays are replaced, not merged
- null values delete the key
- Stores use `create()` with `devtools` middleware
- Receiver listens for `__bridge_push` CustomEvents
- Types file extends `DocumentEventMap`

**Step 4: Run test to verify it passes**

```bash
cd WebApp && pnpm vitest run src/utils/deep-merge.test.ts
```
Expected: PASS

**Step 5: Commit**

```bash
git add WebApp/src/
git commit -m "feat: add Zustand stores, bridge receiver, and deepMerge utility"
```

---

### Task 2.3: Observation Loops in BridgeCoordinator

**Files:**
- Modify: `Sources/AgentStudio/Bridge/BridgeCoordinator.swift`
- Create: `Sources/AgentStudio/Bridge/Domain/SharedBridgeState.swift` (if not already created)

**Step 1: Add observation loops to BridgeCoordinator**

Wire `Observations` + `.debounce(for:)` from `AsyncAlgorithms` to watch `PaneDomainState` and push changes to JS via `callJavaScript`. Follow design spec §6.1–§6.3:

- `watchDiffState()` — debounced at 16ms
- `watchConnectionState()` — immediate (no debounce)
- `startObservationLoops()` — `withTaskGroup` running all watchers

**Step 2: Add lifecycle handling**

Implement `handlePageTermination()` and `resumeAfterReload()` per design spec §9.1.

**Step 3: Verify build compiles**

Run: `swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL"`

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Bridge/BridgeCoordinator.swift
git commit -m "feat: add observation loops for state push pipeline"
```

---

### Task 2.4: Integration Test — State Push End-to-End

**Files:**
- No new files — visual + manual verification

**Step 1: Build and launch**

**Step 2: Verify state push**

Mutate a domain state property from Swift (e.g., set `connection.health = .connected`) and verify the Zustand store updates in the webview via Web Inspector.

**Step 3: Verify push coalescing**

Rapidly mutate multiple properties and verify that pushes are coalesced (≤ 2 pushes for 10 mutations).

**Step 4: Commit any fixes**

---

## Phase 3: JSON-RPC Command Channel

> **Goal**: React can send typed commands to Swift. Full bidirectional communication.

### Task 3.1: Command Sender (React)

**Files:**
- Create: `WebApp/src/bridge/commands.ts`
- Create: `WebApp/src/bridge/rpc-client.ts`

Write the command sender and RPC client per design spec §7.3–§7.4. Key points:
- `sendCommand()` dispatches CustomEvent with nonce
- `rpcClient` manages pending requests with timeout
- All typed command functions under `commands.*` namespace

**Commit:**
```bash
git add WebApp/src/bridge/
git commit -m "feat: add command sender and RPC client for JS→Swift commands"
```

---

### Task 3.2: Diff Method Definitions (Swift)

**Files:**
- Create: `Sources/AgentStudio/Bridge/Methods/DiffMethods.swift`
- Create: `Sources/AgentStudio/Bridge/Methods/SystemMethods.swift`
- Test: `Tests/AgentStudioTests/Bridge/DiffMethodsTests.swift`

Define `RPCMethod` conformances for `diff.load`, `diff.requestFileContents`, `system.health`. Register handlers in `BridgeCoordinator.registerHandlers()`.

TDD: Write failing test that verifies method registration and dispatch, then implement.

**Commit:**
```bash
git add Sources/AgentStudio/Bridge/Methods/ Tests/AgentStudioTests/Bridge/DiffMethodsTests.swift
git commit -m "feat: add diff and system JSON-RPC method definitions"
```

---

### Task 3.3: Integration Test — Full Round-Trip

**Files:** None new

Verify: React sends `commands.system.health()` → Swift handler fires → state push arrives back in Zustand. Visual verification with Peekaboo.

---

## Phase 4: Diff Viewer (Pierre Integration)

> **Goal**: Full diff viewer renders in a webview pane with progressive loading.

### Task 4.1: React Hooks for Diff Data

**Files:**
- Create: `WebApp/src/hooks/use-diff-files.ts`
- Create: `WebApp/src/hooks/use-file-content.ts`
- Create: `WebApp/src/hooks/use-file-comments.ts`

Write hooks per design spec §7.5. Use `useShallow` for object selectors (§7.6).

---

### Task 4.2: DiffPanel and DiffFileView Components

**Files:**
- Create: `WebApp/src/components/DiffPanel.tsx`
- Create: `WebApp/src/components/DiffFileView.tsx`
- Create: `WebApp/src/components/DiffHeader.tsx`

Wire Pierre `MultiFileDiff` component with progressive loading states per design spec §12.1–§12.2.

---

### Task 4.3: DiffLoader — Chunked Progressive Loading (Swift)

**Files:**
- Create: `Sources/AgentStudio/Bridge/Domain/DiffLoader.swift`
- Test: `Tests/AgentStudioTests/Bridge/DiffLoaderTests.swift`

Implement the 3-phase loading strategy (§10.1–§10.4): file list immediate, background batches, on-demand priority. Include epoch guards and per-file load locks.

TDD: Test batch chunking, prioritization by size, epoch invalidation, concurrent load deduplication.

---

### Task 4.4: Comment Methods and UI

**Files:**
- Create: `Sources/AgentStudio/Bridge/Methods/CommentMethods.swift`
- Create: `WebApp/src/components/CommentOverlay.tsx`
- Create: `WebApp/src/components/SendToAgentButton.tsx`

Wire comment add/resolve/delete/sendToAgent per design spec §12.3–§12.4.

---

### Task 4.5: Visual Verification — Full Diff Viewer

Build, launch, load a real git diff, verify progressive loading and comment UI with Peekaboo.

---

## Phase 5: Binary Channel

> **Goal**: Large files served via `agentstudio://` URL scheme.

### Task 5.1: URLSchemeHandler Protocol Conformance

**Files:**
- Modify: `Sources/AgentStudio/Bridge/BinarySchemeHandler.swift`
- Test: `Tests/AgentStudioTests/Bridge/BinarySchemeHandlerTests.swift`

Add full `URLSchemeHandler` conformance with `AsyncSequence<URLSchemeTaskResult>` return, cancellation handling per design spec §4.3.

---

### Task 5.2: Wire Scheme Handler into BridgeCoordinator

**Files:**
- Modify: `Sources/AgentStudio/Bridge/BridgeCoordinator.swift`

Register `agentstudio://` scheme on `WebPage.Configuration`. Serve both `agentstudio://app/*` (React app) and `agentstudio://resource/file/*` (dynamic content).

---

### Task 5.3: Serve React App from Bundle

**Files:**
- Modify: `Sources/AgentStudio/Bridge/BridgeCoordinator.swift` — load from `agentstudio://app/index.html` instead of inline HTML
- Modify: build process — copy Vite output to app resources

---

### Task 5.4: Performance Benchmark

Measure JSON push vs binary channel for 100KB, 500KB, 1MB files. Document results.

---

## Phase 6: Security Hardening

> **Goal**: All six security layers verified and hardened.

### Task 6.1: Navigation Policy

**Files:**
- Create: `Sources/AgentStudio/Bridge/NavigationDecider.swift`
- Test: `Tests/AgentStudioTests/Bridge/NavigationDeciderTests.swift`

Implement `WebPage.NavigationDeciding` per design spec §11.4. Block `javascript:`, `data:`, `blob:`, `vbscript:`. External URLs open in default browser.

TDD: Test each scheme type.

---

### Task 6.2: Content World Isolation Audit

Manual security tests:
- Verify page world cannot access `window.__bridgeInternal`
- Verify page world cannot call `window.webkit.messageHandlers.rpc`
- Verify forged `__bridge_command` without nonce is rejected
- Verify bootstrap script runs only in bridge world

---

### Task 6.3: Path Traversal Hardening

**Files:**
- Modify: `Sources/AgentStudio/Bridge/BinarySchemeHandler.swift`
- Test: expand `BinarySchemeHandlerTests` with traversal attack vectors

Test: `../../etc/passwd`, URL-encoded traversal, symlink resolution.

---

### Task 6.4: Final Verification and Peekaboo

Full visual verification of the complete bridge with diff viewer, comments, and security hardening.

---

## Implementation Notes

### Build Commands
```bash
# Build
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL"

# Test all
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"

# Test specific
swift test --filter RPCRouterTests > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"

# React build
cd WebApp && pnpm build

# React test
cd WebApp && pnpm vitest run

# Lint React
cd WebApp && pnpm biome check src/
```

### Key Design Spec References
- Transport: §4 (callJavaScript, postMessage, URL scheme)
- Protocol: §5 (JSON-RPC 2.0, method namespaces, error codes)
- Push pipeline: §6 (Observations, debounce, granular observation)
- React layer: §7 (Zustand, deepMerge, hooks, rendering caveats)
- Domain model: §8 (DiffState, ConnectionState, per-pane vs shared)
- Coordinator: §9 (BridgeCoordinator, RPCRouter, message handler)
- Progressive loading: §10 (chunked, race condition guards, epoch)
- Security: §11 (content world, nonce, navigation policy)
- Pierre: §12 (MultiFileDiff, annotations, comments)
- Phases: §13 (exit criteria per phase)

### Potential API Verification Needed
The design spec notes that some macOS 26 WebKit APIs need verification (§16). If any of these fail to compile:
1. `callJavaScript(_:arguments:in:contentWorld:)` — check exact parameter labels
2. `WKUserScript(source:injectionTime:forMainFrameOnly:in:)` — check content world param
3. `WebView(page:)` — check initializer
4. `page.mainFrame` — check if this property exists
5. `URLSchemeHandler` protocol — check `AsyncSequence` return type

Document any mismatches and update `docs/architecture/swift_react_bridge_design.md`.
