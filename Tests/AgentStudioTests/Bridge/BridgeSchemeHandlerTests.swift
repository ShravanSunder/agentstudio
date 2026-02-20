import XCTest

@testable import AgentStudio

/// Tests for BridgeSchemeHandler static helpers: MIME type resolution and path classification.
///
/// The scheme handler serves bundled React app assets via `agentstudio://app/*` and
/// file contents via `agentstudio://resource/file/<fileId>`. These tests verify the
/// pure logic layer without requiring a live WebKit instance.
final class BridgeSchemeHandlerTests: XCTestCase {

    // MARK: - MIME type resolution

    func test_mimeType_html() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "index.html"), "text/html")
    }

    func test_mimeType_htm() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "page.htm"), "text/html")
    }

    func test_mimeType_js() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "app.js"), "application/javascript")
    }

    func test_mimeType_mjs() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "module.mjs"), "application/javascript")
    }

    func test_mimeType_css() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "styles.css"), "text/css")
    }

    func test_mimeType_json() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "manifest.json"), "application/json")
    }

    func test_mimeType_svg() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "icon.svg"), "image/svg+xml")
    }

    func test_mimeType_png() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "logo.png"), "image/png")
    }

    func test_mimeType_woff2() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "font.woff2"), "font/woff2")
    }

    func test_mimeType_wasm() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "app.wasm"), "application/wasm")
    }

    func test_mimeType_unknown_defaults_to_octetStream() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "data.bin"), "application/octet-stream")
    }

    func test_mimeType_noExtension_defaults_to_octetStream() {
        XCTAssertEqual(BridgeSchemeHandler.mimeType(for: "LICENSE"), "application/octet-stream")
    }

    // MARK: - Path classification — app routes

    func test_pathType_appRoute_indexHtml() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/index.html")
        XCTAssertEqual(result, .app("index.html"))
    }

    func test_pathType_appRoute_nestedAsset() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/main.js")
        XCTAssertEqual(result, .app("assets/main.js"))
    }

    // MARK: - Path classification — resource routes

    func test_pathType_resourceRoute() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/file/abc123")
        XCTAssertEqual(result, .resource(fileId: "abc123"))
    }

    func test_pathType_resourceRoute_uuidFileId() {
        let result = BridgeSchemeHandler.classifyPath(
            "agentstudio://resource/file/550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(result, .resource(fileId: "550e8400-e29b-41d4-a716-446655440000"))
    }

    // MARK: - Path classification — invalid routes

    func test_pathType_unknownHost_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://unknown/path")
        XCTAssertEqual(result, .invalid)
    }

    func test_pathType_wrongScheme_invalid() {
        let result = BridgeSchemeHandler.classifyPath("https://app/index.html")
        XCTAssertEqual(result, .invalid)
    }

    func test_pathType_emptyAppPath_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/")
        XCTAssertEqual(result, .invalid)
    }

    func test_pathType_resourceMissingFileId_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/file/")
        XCTAssertEqual(result, .invalid)
    }

    func test_pathType_resourceWrongSegment_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/blob/abc123")
        XCTAssertEqual(result, .invalid)
    }

    // MARK: - Path traversal rejection (security)

    func test_rejects_path_traversal_dotdot() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/../../../etc/passwd")
        XCTAssertEqual(result, .invalid)
    }

    func test_rejects_path_traversal_midPath() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/../secret.key")
        XCTAssertEqual(result, .invalid)
    }

    func test_rejects_percent_encoded_path_traversal() {
        // %2e%2e is URL-encoded ".."
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/%2e%2e/etc/passwd")
        XCTAssertEqual(result, .invalid)
    }
}
