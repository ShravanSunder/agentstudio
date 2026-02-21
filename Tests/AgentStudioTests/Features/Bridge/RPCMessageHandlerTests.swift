import Testing
import Foundation

@testable import AgentStudio

/// Tests for RPCMessageHandler JSON extraction and validation.
///
/// RPCMessageHandler receives postMessage bodies from WKScriptMessage in the bridge
/// content world. The body can be any JS value (string, number, object, array, null).
/// The bridge relay sends JSON.stringify'd strings, so we expect String bodies only.
///
/// These tests verify the static `extractJSON(from:)` method which validates:
/// 1. Body is a String (not number, object, etc.)
/// 2. String is non-empty
/// 3. String is valid JSON (parseable by JSONSerialization)
@Suite(.serialized)
final class RPCMessageHandlerTests {

    // MARK: - Valid JSON parsing

    @Test
    func test_parses_valid_json_string_body() {
        // Arrange
        let json = #"{"jsonrpc":"2.0","method":"system.ping","params":{}}"#

        // Act
        let result = RPCMessageHandler.extractJSON(from: json)

        // Assert
        #expect(result != nil)
    }

    @Test
    func test_extracts_method_from_valid_json() {
        // Arrange
        let json = #"{"jsonrpc":"2.0","method":"diff.requestFileContents","params":{"fileId":"abc"}}"#

        // Act
        let result = RPCMessageHandler.extractJSON(from: json)

        // Assert
        #expect(result == json)
    }

    // MARK: - Rejection cases

    @Test
    func test_rejects_non_string_body() {
        // Arrange — postMessage can send non-string values; handler should reject
        let nonStringBody: Any = 42

        // Act
        let result = RPCMessageHandler.extractJSON(from: nonStringBody)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_rejects_empty_string() {
        // Arrange
        let emptyString = ""

        // Act
        let result = RPCMessageHandler.extractJSON(from: emptyString)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_rejects_invalid_json() {
        // Arrange
        let invalidJSON = "not json {{{"

        // Act
        let result = RPCMessageHandler.extractJSON(from: invalidJSON)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_rejects_dictionary_body() {
        // Arrange — JS object arrives as NSDictionary, not string
        let dictBody: Any = ["method": "test"]

        // Act
        let result = RPCMessageHandler.extractJSON(from: dictBody)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_rejects_array_body() {
        // Arrange — JS array arrives as NSArray, not string
        let arrayBody: Any = [1, 2, 3]

        // Act
        let result = RPCMessageHandler.extractJSON(from: arrayBody)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_rejects_bool_body() {
        // Arrange
        let boolBody: Any = true

        // Act
        let result = RPCMessageHandler.extractJSON(from: boolBody)

        // Assert
        #expect(result == nil)
    }
}
