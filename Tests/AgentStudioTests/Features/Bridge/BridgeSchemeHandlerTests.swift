import Testing
import Foundation

@testable import AgentStudio

/// Tests for BridgeSchemeHandler static helpers: MIME type resolution and path classification.
///
/// The scheme handler serves bundled React app assets via `agentstudio://app/*` and
/// file contents via `agentstudio://resource/file/<fileId>`. These tests verify the
/// pure logic layer without requiring a live WebKit instance.
@Suite(.serialized)
final class BridgeSchemeHandlerTests {

    // MARK: - MIME type resolution

    @Test
    func test_mimeType_html() {
        #expect(BridgeSchemeHandler.mimeType(for: "index.html") == "text/html")
    }

    @Test
    func test_mimeType_htm() {
        #expect(BridgeSchemeHandler.mimeType(for: "page.htm") == "text/html")
    }

    @Test
    func test_mimeType_js() {
        #expect(BridgeSchemeHandler.mimeType(for: "app.js") == "application/javascript")
    }

    @Test
    func test_mimeType_mjs() {
        #expect(BridgeSchemeHandler.mimeType(for: "module.mjs") == "application/javascript")
    }

    @Test
    func test_mimeType_css() {
        #expect(BridgeSchemeHandler.mimeType(for: "styles.css") == "text/css")
    }

    @Test
    func test_mimeType_json() {
        #expect(BridgeSchemeHandler.mimeType(for: "manifest.json") == "application/json")
    }

    @Test
    func test_mimeType_svg() {
        #expect(BridgeSchemeHandler.mimeType(for: "icon.svg") == "image/svg+xml")
    }

    @Test
    func test_mimeType_png() {
        #expect(BridgeSchemeHandler.mimeType(for: "logo.png") == "image/png")
    }

    @Test
    func test_mimeType_woff2() {
        #expect(BridgeSchemeHandler.mimeType(for: "font.woff2") == "font/woff2")
    }

    @Test
    func test_mimeType_wasm() {
        #expect(BridgeSchemeHandler.mimeType(for: "app.wasm") == "application/wasm")
    }

    @Test
    func test_mimeType_unknown_defaults_to_octetStream() {
        #expect(BridgeSchemeHandler.mimeType(for: "data.bin") == "application/octet-stream")
    }

    @Test
    func test_mimeType_noExtension_defaults_to_octetStream() {
        #expect(BridgeSchemeHandler.mimeType(for: "LICENSE") == "application/octet-stream")
    }

    // MARK: - Path classification — app routes

    @Test
    func test_pathType_appRoute_indexHtml() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/index.html")
        #expect(result == .app("index.html"))
    }

    @Test
    func test_pathType_appRoute_nestedAsset() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/main.js")
        #expect(result == .app("assets/main.js"))
    }

    // MARK: - Path classification — resource routes

    @Test
    func test_pathType_resourceRoute() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/file/abc123")
        #expect(result == .resource(fileId: "abc123"))
    }

    @Test
    func test_pathType_resourceRoute_uuidFileId() {
        let result = BridgeSchemeHandler.classifyPath(
            "agentstudio://resource/file/550e8400-e29b-41d4-a716-446655440000")
        #expect(result == .resource(fileId: "550e8400-e29b-41d4-a716-446655440000"))
    }

    // MARK: - Path classification — invalid routes

    @Test
    func test_pathType_unknownHost_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://unknown/path")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_wrongScheme_invalid() {
        let result = BridgeSchemeHandler.classifyPath("https://app/index.html")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_emptyAppPath_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceMissingFileId_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/file/")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceWrongSegment_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/blob/abc123")
        #expect(result == .invalid)
    }

    // MARK: - Path traversal rejection (security)

    @Test
    func test_rejects_path_traversal_dotdot() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/../../../etc/passwd")
        #expect(result == .invalid)
    }

    @Test
    func test_rejects_path_traversal_midPath() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/../secret.key")
        #expect(result == .invalid)
    }

    @Test
    func test_rejects_percent_encoded_path_traversal() {
        // %2e%2e is URL-encoded ".." — url.path() decodes it before segment check
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/%2e%2e/etc/passwd")
        #expect(result == .invalid)
    }

    @Test
    func test_allows_benign_encoded_paths() {
        // %2e is a single encoded dot — not traversal, should NOT be rejected
        // e.g. "my%2efile.txt" decodes to "my.file.txt" which is a valid filename
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/my%2efile.txt")
        #expect(result == .app("my.file.txt"))
    }

    @Test
    func test_allows_filenames_containing_double_dots() {
        // "my..config.js" is a valid filename — not a traversal segment
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/my..config.js")
        #expect(result == .app("my..config.js"))
    }

    @Test
    func test_rejects_double_encoded_path_traversal() {
        // %252e%252e → first decode → %2e%2e → second decode → ".."
        // Stable-decode loop catches this.
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/%252e%252e/etc/passwd")
        #expect(result == .invalid)
    }
}
