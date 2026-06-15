import AgentStudioIPCTransport
import Foundation
import Testing

@Suite("JSON-RPC codec")
struct JSONRPCCodecTests {
    @Test("decodes a strict JSON-RPC 2 request with object params")
    func decodesStrictRequestWithObjectParams() throws {
        let payload = #"{"jsonrpc":"2.0","id":"1","method":"system.identify","params":{}}"#

        let request = try JSONRPCCodec.decodeRequest(payload)

        #expect(request.id == .string("1"))
        #expect(request.method == "system.identify")
        #expect(request.params == .object([:]))
    }

    @Test("rejects batch arrays")
    func rejectsBatchArrays() throws {
        let payload = #"[{"jsonrpc":"2.0","id":"1","method":"system.identify","params":{}}]"#

        #expect(throws: JSONRPCError.self) {
            try JSONRPCCodec.decodeRequest(payload)
        }
    }

    @Test("rejects params that are not objects")
    func rejectsNonObjectParams() throws {
        let payload = #"{"jsonrpc":"2.0","id":"1","method":"system.identify","params":[]}"#

        #expect(throws: JSONRPCError.self) {
            try JSONRPCCodec.decodeRequest(payload)
        }
    }

    @Test("rejects out-of-range numeric ids without trapping")
    func rejectsOutOfRangeNumericIdsWithoutTrapping() throws {
        let payload = #"{"jsonrpc":"2.0","id":1e100,"method":"system.identify","params":{}}"#

        #expect(throws: JSONRPCError.self) {
            try JSONRPCCodec.decodeRequest(payload)
        }
    }

    @Test("rejects requests over the configured byte limit")
    func rejectsRequestsOverByteLimit() throws {
        let payload = #"{"jsonrpc":"2.0","id":"1","method":"system.identify","params":{}}"#

        #expect(throws: JSONRPCError.self) {
            try JSONRPCCodec.decodeRequest(payload, maxBytes: 8)
        }
    }

    @Test("encodes success responses with result and no error")
    func encodesSuccessResponseWithResultOnly() throws {
        let response = JSONRPCResponse.success(
            id: .string("1"),
            result: .object(["runtimeId": .string("runtime-1")])
        )

        let encoded = try JSONRPCCodec.encodeResponse(response)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])

        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["id"] as? String == "1")
        #expect(object["error"] == nil)
        #expect((object["result"] as? [String: Any])?["runtimeId"] as? String == "runtime-1")
    }

    @Test("rejects responses that include both result and error")
    func rejectsResponseWithResultAndError() throws {
        #expect(throws: JSONRPCError.self) {
            try JSONRPCResponse(
                id: .string("1"),
                result: .object([:]),
                error: JSONRPCErrorPayload(code: -32_000, message: "failed")
            )
        }
    }

    @Test("supports the JSON-RPC application error-code range")
    func supportsApplicationErrorCodeRange() throws {
        let payload = try JSONRPCErrorPayload.application(code: -32_042, message: "permission denied")
        let response = JSONRPCResponse.failure(id: .string("1"), error: payload)

        let encoded = try JSONRPCCodec.encodeResponse(response)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])

        #expect(error["code"] as? Int == -32_042)
        #expect(error["message"] as? String == "permission denied")
    }

    @Test("encodes server notifications without an id")
    func encodesServerNotificationsWithoutAnId() throws {
        let notification = try JSONRPCNotification(
            method: "events.notification",
            params: .object(["name": .string("terminal.commandFinished")])
        )

        let encoded = try JSONRPCCodec.encodeNotification(notification)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])

        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["method"] as? String == "events.notification")
        #expect(object["id"] == nil)
        #expect((object["params"] as? [String: Any])?["name"] as? String == "terminal.commandFinished")
    }

    @Test("rejects error codes outside the application range")
    func rejectsApplicationErrorCodeOutsideRange() throws {
        #expect(throws: JSONRPCError.self) {
            try JSONRPCErrorPayload.application(code: -32_100, message: "too low")
        }
    }
}
