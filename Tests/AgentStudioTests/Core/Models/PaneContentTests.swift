import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class PaneContentTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Round-Trip: Terminal

    @Test

    func test_roundTrip_terminal() throws {
        // Arrange
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))

        // Act
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
        #expect(decoded == content)
    }

    @Test

    func test_roundTrip_terminal_ghostty() throws {
        let content = PaneContent.terminal(TerminalState(provider: .ghostty, lifetime: .temporary))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        #expect(decoded == content)
    }

    // MARK: - Round-Trip: Webview

    @Test

    func test_roundTrip_webview() throws {
        let content = PaneContent.webview(
            WebviewState(
                url: URL(string: "https://example.com")!,
                showNavigation: true
            ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        #expect(decoded == content)
    }

    @Test

    func test_roundTrip_webview_withTitle() throws {
        // Arrange
        let content = PaneContent.webview(
            WebviewState(
                url: URL(string: "https://github.com")!,
                title: "GitHub",
                showNavigation: false
            ))

        // Act
        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        // Assert
        #expect(decoded == content)
        if case .webview(let state) = decoded {
            #expect(state.url.absoluteString == "https://github.com")
            #expect(state.title == "GitHub")
            #expect(!(state.showNavigation))
        } else {
            Issue.record("Expected .webview")
        }
    }

    // MARK: - Round-Trip: CodeViewer

    @Test

    func test_roundTrip_codeViewer() throws {
        let content = PaneContent.codeViewer(
            CodeViewerState(
                filePath: URL(fileURLWithPath: "/tmp/test.swift"),
                scrollToLine: 42
            ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        #expect(decoded == content)
    }

    @Test

    func test_roundTrip_codeViewer_noScrollLine() throws {
        let content = PaneContent.codeViewer(
            CodeViewerState(
                filePath: URL(fileURLWithPath: "/tmp/test.swift"),
                scrollToLine: nil
            ))

        let data = try encoder.encode(content)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        #expect(decoded == content)
    }

    // MARK: - Encoded Format

    @Test

    func test_encode_containsTypeAndVersion() throws {
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "terminal")
        #expect(json["version"] as? Int == PaneContent.currentVersion)
        #expect((json["state"]) != nil)
    }

    @Test

    func test_encode_webview_typeField() throws {
        let content = PaneContent.webview(
            WebviewState(
                url: URL(string: "https://example.com")!,
                showNavigation: false
            ))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "webview")
    }

    @Test

    func test_encode_webview_encodesURLAndTitle() throws {
        // Arrange
        let content = PaneContent.webview(
            WebviewState(
                url: URL(string: "https://example.com")!,
                title: "Example",
                showNavigation: true
            ))

        // Act
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let stateJson = json["state"] as? [String: Any]

        // Assert — encodes flat url/title/showNavigation (not tabs array)
        #expect(stateJson?["url"] as? String == "https://example.com")
        #expect(stateJson?["title"] as? String == "Example")
        #expect(stateJson?["showNavigation"] as? Bool == true)
        #expect((stateJson?["tabs"]) == nil)
    }

    @Test

    func test_encode_codeViewer_typeField() throws {
        let content = PaneContent.codeViewer(
            CodeViewerState(
                filePath: URL(fileURLWithPath: "/tmp/test.swift"),
                scrollToLine: nil
            ))

        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "codeViewer")
    }

    // MARK: - Unknown Type → .unsupported

    @Test

    func test_decode_unknownType_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "type": "aiAssistant",
            "version": 2,
            "state": ["model": "claude-4", "temperature": 0.7],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            #expect(content.type == "aiAssistant")
            #expect(content.version == 2)
            #expect((content.rawState) != nil)
        } else {
            Issue.record("Expected .unsupported, got \(decoded)")
        }
    }

    @Test

    func test_decode_unknownType_noState_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "type": "futureType",
            "version": 5,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            #expect(content.type == "futureType")
            #expect(content.version == 5)
            #expect((content.rawState) == nil)
        } else {
            Issue.record("Expected .unsupported, got \(decoded)")
        }
    }

    @Test

    func test_decode_missingType_decodesAsUnsupported() throws {
        let json: [String: Any] = [
            "version": 1,
            "state": ["foo": "bar"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .unsupported(let content) = decoded {
            #expect(content.type == "unknown")
        } else {
            Issue.record("Expected .unsupported, got \(decoded)")
        }
    }

    // MARK: - Unsupported Round-Trip Preservation

    @Test

    func test_unsupported_roundTrip_preservesState() throws {
        let json: [String: Any] = [
            "type": "aiAssistant",
            "version": 3,
            "state": [
                "model": "claude-4",
                "config": ["temperature": 0.7, "maxTokens": 1000],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(PaneContent.self, from: data)

        let reencoded = try encoder.encode(decoded)
        let redecodedJson = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]

        #expect(redecodedJson["type"] as? String == "aiAssistant")
        #expect(redecodedJson["version"] as? Int == 3)
        let state = redecodedJson["state"] as? [String: Any]
        #expect(state?["model"] as? String == "claude-4")
    }

    // MARK: - Version Default

    @Test

    func test_decode_missingVersion_defaultsTo1() throws {
        let json: [String: Any] = [
            "type": "terminal",
            "state": ["provider": "zmx", "lifetime": "persistent"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PaneContent.self, from: data)

        if case .terminal(let state) = decoded {
            #expect(state.provider == .zmx)
            #expect(state.lifetime == .persistent)
        } else {
            Issue.record("Expected .terminal, got \(decoded)")
        }
    }

    // MARK: - AnyCodableValue Round-Trip

    @Test

    func test_anyCodableValue_roundTrip_allTypes() throws {
        let value = AnyCodableValue.object([
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .string("two"), .null]),
            "nested": .object(["key": .string("value")]),
        ])

        let data = try encoder.encode(value)
        let decoded = try decoder.decode(AnyCodableValue.self, from: data)

        #expect(decoded == value)
    }

    // MARK: - Pane with PaneContent Round-Trip

    @Test

    func test_pane_roundTrip_terminalContent() throws {
        let pane = makePane(provider: .zmx, lifetime: .persistent)

        let data = try encoder.encode(pane)
        let decoded = try decoder.decode(Pane.self, from: data)

        #expect(decoded.id == pane.id)
        #expect(decoded.content == pane.content)
        #expect(decoded.provider == .zmx)
        #expect(decoded.lifetime == .persistent)
    }

    // MARK: - WebviewState

    @Test

    func test_webviewState_init_defaults() {
        // Arrange & Act
        let state = WebviewState(url: URL(string: "https://example.com")!)

        // Assert
        #expect(state.url.absoluteString == "https://example.com")
        #expect(state.title == "")
        #expect(state.showNavigation)
    }

    @Test

    func test_webviewState_init_noNavigation() {
        let state = WebviewState(url: URL(string: "https://example.com")!, showNavigation: false)
        #expect(!(state.showNavigation))
    }

    @Test

    func test_webviewState_hashable_sameContent_sameHash() {
        let url = URL(string: "https://example.com")!
        let s1 = WebviewState(url: url, title: "Test", showNavigation: true)
        let s2 = WebviewState(url: url, title: "Test", showNavigation: true)
        #expect(s1 == s2)
        #expect(s1.hashValue == s2.hashValue)
    }

    @Test

    func test_webviewState_differentTitle_notEqual() {
        let url = URL(string: "https://example.com")!
        let s1 = WebviewState(url: url, title: "A")
        let s2 = WebviewState(url: url, title: "B")
        #expect(s1 != s2)
    }

    // MARK: - Backward-Compatible Decoding

    @Test

    func test_decode_legacyV1_singleURL() throws {
        // Arrange — v1 shape: {url, showNavigation} (no title)
        let json: [String: Any] = [
            "url": "https://example.com",
            "showNavigation": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert
        #expect(state.url.absoluteString == "https://example.com")
        #expect(state.title == "")
        #expect(state.showNavigation)
    }

    @Test

    func test_decode_legacyV1_noNavigation() throws {
        let json: [String: Any] = [
            "url": "https://example.com",
            "showNavigation": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let state = try decoder.decode(WebviewState.self, from: data)

        #expect(!(state.showNavigation))
    }

    @Test

    func test_decode_legacyV2_tabsArray_extractsActiveTab() throws {
        // Arrange — v2 multi-tab shape: {tabs: [{url, title}], activeTabIndex}
        let json: [String: Any] = [
            "tabs": [
                ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString],
                ["url": "https://docs.swift.org", "title": "Docs", "id": UUID().uuidString],
            ],
            "activeTabIndex": 1,
            "showNavigation": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert — extracts the active tab (index 1 = docs.swift.org)
        #expect(state.url.absoluteString == "https://docs.swift.org")
        #expect(state.showNavigation)
    }

    @Test

    func test_decode_legacyV2_tabsArray_fallsBackToFirstTab() throws {
        // Arrange — tabs shape with out-of-range activeTabIndex
        let json: [String: Any] = [
            "tabs": [
                ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString]
            ],
            "activeTabIndex": 99,
            "showNavigation": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let state = try decoder.decode(WebviewState.self, from: data)

        // Assert — falls back to first tab
        #expect(state.url.absoluteString == "https://github.com")
    }

    @Test

    func test_decode_legacyV2_viaFullPaneContent() throws {
        // Arrange — PaneContent envelope with v2 tabs shape
        let json: [String: Any] = [
            "type": "webview",
            "version": 2,
            "state": [
                "tabs": [
                    ["url": "https://github.com", "title": "GitHub", "id": UUID().uuidString]
                ],
                "activeTabIndex": 0,
                "showNavigation": true,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let content = try decoder.decode(PaneContent.self, from: data)

        // Assert
        if case .webview(let state) = content {
            #expect(state.url.absoluteString == "https://github.com")
        } else {
            Issue.record("Expected .webview, got \(content)")
        }
    }

    @Test

    func test_decode_legacyV1_viaFullPaneContent() throws {
        // Arrange — PaneContent envelope with v1 single-URL shape
        let json: [String: Any] = [
            "type": "webview",
            "version": 1,
            "state": [
                "url": "https://github.com",
                "showNavigation": true,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // Act
        let content = try decoder.decode(PaneContent.self, from: data)

        // Assert
        if case .webview(let state) = content {
            #expect(state.url.absoluteString == "https://github.com")
        } else {
            Issue.record("Expected .webview, got \(content)")
        }
    }

    @Test

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
        #expect(decoded == state)
    }
}
