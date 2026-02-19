import XCTest
@testable import AgentStudio

final class PaneContentTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Round-Trip: Terminal

    func test_roundTrip_terminal() throws {
        // Arrange
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))

        // Act
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
        XCTAssertEqual(decoded, content)
    }

    func test_roundTrip_terminal_ghostty() throws {
        let content = PaneContent.terminal(TerminalState(provider: .ghostty, lifetime: .temporary))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        XCTAssertEqual(decoded, content)
    }

    // MARK: - Round-Trip: Webview

    func test_roundTrip_webview() throws {
        let content = PaneContent.webview(WebviewState(
            url: URL(string: "https://example.com")!,
            showNavigation: true
        ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        XCTAssertEqual(decoded, content)
    }

    func test_roundTrip_webview_withTitle() throws {
        // Arrange
        let content = PaneContent.webview(WebviewState(
            url: URL(string: "https://github.com")!,
            title: "GitHub",
            showNavigation: false
        ))

        // Act
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
        XCTAssertEqual(decoded, content)
        if case .webview(let state) = decoded {
            XCTAssertEqual(state.url.absoluteString, "https://github.com")
            XCTAssertEqual(state.title, "GitHub")
            XCTAssertFalse(state.showNavigation)
        } else {
            XCTFail("Expected .webview")
        }
    }

    // MARK: - Round-Trip: CodeViewer

    func test_roundTrip_codeViewer() throws {
        let content = PaneContent.codeViewer(CodeViewerState(
            filePath: URL(fileURLWithPath: "/tmp/test.swift"),
            scrollToLine: 42
        ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        XCTAssertEqual(decoded, content)
    }

    func test_roundTrip_codeViewer_noScrollLine() throws {
        let content = PaneContent.codeViewer(CodeViewerState(
            filePath: URL(fileURLWithPath: "/tmp/test.swift"),
            scrollToLine: nil
        ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        XCTAssertEqual(decoded, content)
    }

    // MARK: - Encoded Format

    func test_encode_containsTypeAndVersion() throws {
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "terminal")
        XCTAssertEqual(json["version"] as? Int, PaneContent.currentVersion)
        XCTAssertNotNil(json["state"])
    }

    func test_encode_webview_typeField() throws {
        let content = PaneContent.webview(WebviewState(
            url: URL(string: "https://example.com")!,
            showNavigation: false
        ))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "webview")
    }

    func test_encode_webview_encodesURLAndTitle() throws {
        // Arrange
        let content = PaneContent.webview(WebviewState(
            url: URL(string: "https://example.com")!,
            title: "Example",
            showNavigation: true
        ))

        // Act
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let stateJson = json["state"] as? [String: Any]

        // Assert — encodes flat url/title/showNavigation (not tabs array)
        XCTAssertEqual(stateJson?["url"] as? String, "https://example.com")
        XCTAssertEqual(stateJson?["title"] as? String, "Example")
        XCTAssertEqual(stateJson?["showNavigation"] as? Bool, true)
        XCTAssertNil(stateJson?["tabs"], "Should not encode legacy tabs array")
    }

    func test_encode_codeViewer_typeField() throws {
        let content = PaneContent.codeViewer(CodeViewerState(
            filePath: URL(fileURLWithPath: "/tmp/test.swift"),
            scrollToLine: nil
        ))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "codeViewer")
    }

    // MARK: - Unknown Type → .unsupported

    func test_decode_unknownType_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "type": "aiAssistant",
            "version": 2,
            "state": ["model": "claude-4", "temperature": 0.7]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            XCTAssertEqual(content.type, "aiAssistant")
            XCTAssertEqual(content.version, 2)
            XCTAssertNotNil(content.rawState)
        } else {
            XCTFail("Expected .unsupported, got \(decoded)")
        }
    }

    func test_decode_unknownType_noState_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "type": "futureType",
            "version": 5
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            XCTAssertEqual(content.type, "futureType")
            XCTAssertEqual(content.version, 5)
            XCTAssertNil(content.rawState)
        } else {
            XCTFail("Expected .unsupported, got \(decoded)")
        }
    }

    func test_decode_missingType_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "version": 1,
            "state": ["foo": "bar"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            XCTAssertEqual(content.type, "unknown")
        } else {
            XCTFail("Expected .unsupported, got \(decoded)")
        }
    }

    // MARK: - Unsupported Round-Trip Preservation

    func test_unsupported_roundTrip_preservesState() throws {
        let json: [String: Any] = [
            "type": "aiAssistant",
            "version": 3,
            "state": [
                "model": "claude-4",
                "config": ["temperature": 0.7, "maxTokens": 1000]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        let reencoded = try encoder.encode(decoded)
        let redecodedJson = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]

        XCTAssertEqual(redecodedJson["type"] as? String, "aiAssistant")
        XCTAssertEqual(redecodedJson["version"] as? Int, 3)
        let state = redecodedJson["state"] as? [String: Any]
        XCTAssertEqual(state?["model"] as? String, "claude-4")
    }

    // MARK: - Version Default

    func test_decode_missingVersion_defaultsTo1() throws {
        let json: [String: Any] = [
            "type": "terminal",
            "state": ["provider": "zmx", "lifetime": "persistent"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .terminal(let state) = decoded {
            XCTAssertEqual(state.provider, .zmx)
            XCTAssertEqual(state.lifetime, .persistent)
        } else {
            XCTFail("Expected .terminal, got \(decoded)")
        }
    }

    // MARK: - AnyCodableValue Round-Trip

    func test_anyCodableValue_roundTrip_allTypes() throws {
        let value = AnyCodableValue.object([
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .string("two"), .null]),
            "nested": .object(["key": .string("value")])
        ])

        let data = try encoder.encode(value)
        let decoded = try decoder.decode(AnyCodableValue.self, from: data)

        XCTAssertEqual(decoded, value)
    }

    // MARK: - Pane with PaneContent Round-Trip

    func test_pane_roundTrip_terminalContent() throws {
        let pane = makePane(provider: .zmx, lifetime: .persistent)

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.id, pane.id)
        XCTAssertEqual(decoded.content, pane.content)
        XCTAssertEqual(decoded.provider, .zmx)
        XCTAssertEqual(decoded.lifetime, .persistent)
    }

    // MARK: - WebviewState

    func test_webviewState_init_defaults() {
        // Arrange & Act
        let state = WebviewState(url: URL(string: "https://example.com")!)

        // Assert
        XCTAssertEqual(state.url.absoluteString, "https://example.com")
        XCTAssertEqual(state.title, "")
        XCTAssertTrue(state.showNavigation)
    }

    func test_webviewState_init_noNavigation() {
        let state = WebviewState(url: URL(string: "https://example.com")!, showNavigation: false)
        XCTAssertFalse(state.showNavigation)
    }

    func test_webviewState_hashable_sameContent_sameHash() {
        let url = URL(string: "https://example.com")!
        let s1 = WebviewState(url: url, title: "Test", showNavigation: true)
        let s2 = WebviewState(url: url, title: "Test", showNavigation: true)
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1.hashValue, s2.hashValue)
    }

    func test_webviewState_differentTitle_notEqual() {
        let url = URL(string: "https://example.com")!
        let s1 = WebviewState(url: url, title: "A")
        let s2 = WebviewState(url: url, title: "B")
        XCTAssertNotEqual(s1, s2)
    }

    // MARK: - Backward-Compatible Decoding

    func test_decode_legacyV1_singleURL() throws {
        // Arrange — v1 shape: {url, showNavigation} (no title)
        let json: [String: Any] = [
            "url": "https://example.com",
            "showNavigation": true
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert
        XCTAssertEqual(state.url.absoluteString, "https://example.com")
        XCTAssertEqual(state.title, "")
        XCTAssertTrue(state.showNavigation)
    }

    func test_decode_legacyV1_noNavigation() throws {
        let json: [String: Any] = [
            "url": "https://example.com",
            "showNavigation": false
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let state = try decoder.decode(WebviewState.self, from: data)

        XCTAssertFalse(state.showNavigation)
    }

    func test_decode_legacyV2_tabsArray_extractsActiveTab() throws {
        // Arrange — v2 multi-tab shape: {tabs: [{url, title}], activeTabIndex}
        let json: [String: Any] = [
            "tabs": [
                ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString],
                ["url": "https://docs.swift.org", "title": "Docs", "id": UUID().uuidString],
            ],
            "activeTabIndex": 1,
            "showNavigation": true
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert — extracts the active tab (index 1 = docs.swift.org)
        XCTAssertEqual(state.url.absoluteString, "https://docs.swift.org")
        XCTAssertTrue(state.showNavigation)
    }

    func test_decode_legacyV2_tabsArray_fallsBackToFirstTab() throws {
        // Arrange — tabs shape with out-of-range activeTabIndex
        let json: [String: Any] = [
            "tabs": [
                ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString],
            ],
            "activeTabIndex": 99,
            "showNavigation": false
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert — falls back to first tab
        XCTAssertEqual(state.url.absoluteString, "https://github.com")
    }

    func test_decode_legacyV2_viaFullPaneContent() throws {
        // Arrange — PaneContent envelope with v2 tabs shape
        let json: [String: Any] = [
            "type": "webview",
            "version": 2,
            "state": [
                "tabs": [
                    ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString],
                ],
                "activeTabIndex": 0,
                "showNavigation": true
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let content = try decoder.decode(PaneContent.self, from: data)

        // Assert
        if case .webview(let state) = content {
            XCTAssertEqual(state.url.absoluteString, "https://github.com")
        } else {
            XCTFail("Expected .webview, got \(content)")
        }
    }

    func test_decode_legacyV1_viaFullPaneContent() throws {
        // Arrange — PaneContent envelope with v1 single-URL shape
        let json: [String: Any] = [
            "type": "webview",
            "version": 1,
            "state": [
                "url": "https://github.com",
                "showNavigation": true
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let content = try decoder.decode(PaneContent.self, from: data)

        // Assert
        if case .webview(let state) = content {
            XCTAssertEqual(state.url.absoluteString, "https://github.com")
        } else {
            XCTFail("Expected .webview, got \(content)")
        }
    }

    func test_decode_currentShape_roundTrips() throws {
        // Arrange
        let state = WebviewState(
            url: URL(string: "https://example.com")!,
            title: "Example",
            showNavigation: false
        )

        // Act
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(WebviewState.self, from: data)

        // Assert
        XCTAssertEqual(decoded, state)
    }
}
