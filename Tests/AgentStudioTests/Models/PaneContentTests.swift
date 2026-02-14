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

    func test_roundTrip_webview_multipleTabs() throws {
        // Arrange
        let tabs = [
            WebviewTabState(url: URL(string: "https://github.com")!, title: "GitHub"),
            WebviewTabState(url: URL(string: "https://docs.swift.org")!, title: "Swift Docs"),
        ]
        let content = PaneContent.webview(WebviewState(tabs: tabs, activeTabIndex: 1))

        // Act
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
        XCTAssertEqual(decoded, content)
        if case .webview(let state) = decoded {
            XCTAssertEqual(state.tabs.count, 2)
            XCTAssertEqual(state.activeTabIndex, 1)
            XCTAssertEqual(state.activeTab?.url.absoluteString, "https://docs.swift.org")
            XCTAssertEqual(state.activeTab?.title, "Swift Docs")
        } else {
            XCTFail("Expected .webview")
        }
    }

    func test_webviewState_activeTab_invalidIndex_returnsNil() {
        // Arrange
        let state = WebviewState(url: URL(string: "https://example.com")!)

        // Act — manually construct with out-of-range index
        let badState = WebviewState(tabs: state.tabs, activeTabIndex: 5)

        // Assert
        XCTAssertNil(badState.activeTab)
    }

    func test_webviewTabState_identity() {
        // Arrange
        let tab = WebviewTabState(url: URL(string: "https://example.com")!, title: "Example")

        // Assert
        XCTAssertEqual(tab.id, tab.id)
        XCTAssertFalse(tab.id == UUID()) // Unique
        XCTAssertEqual(tab.title, "Example")
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
        // Arrange: JSON with a type this version doesn't know about
        let json: [String: Any] = [
            "type": "aiAssistant",
            "version": 2,
            "state": ["model": "claude-4", "temperature": 0.7]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
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
        // JSON with no type field at all
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
        // Arrange: decode an unknown type
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

        // Act: re-encode the unsupported content
        let reencoded = try encoder.encode(decoded)
        let redecodedJson = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]

        // Assert: type and version preserved
        XCTAssertEqual(redecodedJson["type"] as? String, "aiAssistant")
        XCTAssertEqual(redecodedJson["version"] as? Int, 3)

        // Assert: state structure preserved
        let state = redecodedJson["state"] as? [String: Any]
        XCTAssertEqual(state?["model"] as? String, "claude-4")
        let config = state?["config"] as? [String: Any]
        XCTAssertEqual(config?["temperature"] as? Double, 0.7)
        XCTAssertEqual(config?["maxTokens"] as? Int, 1000)
    }

    // MARK: - Version Default

    func test_decode_missingVersion_defaultsTo1() throws {
        // JSON without a version field — should default to 1
        let json: [String: Any] = [
            "type": "terminal",
            "state": ["provider": "zmx", "lifetime": "persistent"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Should decode successfully as terminal
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
        // Full Pane round-trip to verify PaneContent integrates correctly
        let pane = makePane(provider: .zmx, lifetime: .persistent)

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        XCTAssertEqual(decoded.id, pane.id)
        XCTAssertEqual(decoded.content, pane.content)
        XCTAssertEqual(decoded.provider, .zmx)
        XCTAssertEqual(decoded.lifetime, .persistent)
    }

    // MARK: - WebviewState Edge Cases

    func test_webviewState_convenienceInit_defaults() {
        // Arrange & Act
        let state = WebviewState(url: URL(string: "https://example.com")!)

        // Assert
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabIndex, 0)
        XCTAssertTrue(state.showNavigation)
        XCTAssertEqual(state.activeTab?.url.absoluteString, "https://example.com")
    }

    func test_webviewState_convenienceInit_noNavigation() {
        let state = WebviewState(url: URL(string: "https://example.com")!, showNavigation: false)
        XCTAssertFalse(state.showNavigation)
    }

    func test_webviewState_emptyTabs_activeTabIsNil() {
        let state = WebviewState(tabs: [], activeTabIndex: 0)
        XCTAssertNil(state.activeTab)
    }

    func test_webviewState_hashable_sameContent_sameHash() {
        let url = URL(string: "https://example.com")!
        let id = UUID()
        let tab = WebviewTabState(id: id, url: url, title: "Test")
        let s1 = WebviewState(tabs: [tab], activeTabIndex: 0, showNavigation: true)
        let s2 = WebviewState(tabs: [tab], activeTabIndex: 0, showNavigation: true)
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1.hashValue, s2.hashValue)
    }

    func test_webviewState_differentActiveTab_notEqual() {
        let url = URL(string: "https://example.com")!
        let tabs = [
            WebviewTabState(url: url, title: "A"),
            WebviewTabState(url: url, title: "B"),
        ]
        let s1 = WebviewState(tabs: tabs, activeTabIndex: 0)
        let s2 = WebviewState(tabs: tabs, activeTabIndex: 1)
        XCTAssertNotEqual(s1, s2)
    }

    func test_webviewTabState_defaultTitle_isEmpty() {
        let tab = WebviewTabState(url: URL(string: "https://example.com")!)
        XCTAssertEqual(tab.title, "")
    }
}
