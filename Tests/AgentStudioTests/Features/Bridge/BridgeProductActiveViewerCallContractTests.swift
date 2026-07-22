import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductActiveViewerCallContractTests {
    @Test("active viewer calls derive surface and reject repeated surface fields")
    func activeViewerCallsDeriveSurfaceAndRejectRepeatedFields() throws {
        let reviewObject: [String: Any] = [
            "call": [
                "method": "review.activeViewerMode.update",
                "request": [
                    "activeSource": ["generation": 3, "streamId": "review-stream-1"],
                    "nativeSelectionRequestId": NSNull(),
                    "sequence": 7,
                    "sessionId": "viewer-session-1",
                ],
            ],
            "kind": "product.call",
            "paneSessionId": "pane-session-1",
            "requestId": "active-mode-call-1",
            "requestSequence": 2,
            "wireVersion": 2,
            "workerDerivationEpoch": 4,
            "workerInstanceId": "worker-instance-1",
        ]
        let fileObject: [String: Any] = [
            "call": [
                "method": "file.activeViewerMode.update",
                "request": [
                    "activeSource": ["generation": 5, "streamId": "file-stream-1"],
                    "nativeSelectionRequestId": NSNull(),
                    "sequence": 8,
                    "sessionId": "viewer-session-1",
                ],
            ],
            "kind": "product.call",
            "paneSessionId": "pane-session-1",
            "requestId": "active-mode-call-2",
            "requestSequence": 3,
            "wireVersion": 2,
            "workerDerivationEpoch": 4,
            "workerInstanceId": "worker-instance-1",
        ]

        let reviewData = try JSONSerialization.data(withJSONObject: reviewObject, options: [.sortedKeys])
        let decodedReview = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: reviewData
        )
        guard case .productCall(let reviewCall) = decodedReview,
            case .reviewActiveViewerModeUpdate = reviewCall.call
        else {
            Issue.record("Expected a Review-derived active viewer call")
            return
        }
        let fileData = try JSONSerialization.data(withJSONObject: fileObject, options: [.sortedKeys])
        let decodedFile = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: fileData
        )
        guard case .productCall(let fileCall) = decodedFile,
            case .fileActiveViewerModeUpdate = fileCall.call
        else {
            Issue.record("Expected a File-derived active viewer call")
            return
        }
        for repeatedField in ["mode", "protocol", "surface"] {
            var invalidObject = reviewObject
            var call = try #require(invalidObject["call"] as? [String: Any])
            var request = try #require(call["request"] as? [String: Any])
            request[repeatedField] = "review"
            call["request"] = request
            invalidObject["call"] = call
            #expect(decodedValue(BridgeProductControlRequest.self, object: invalidObject) == nil)
        }
    }

    private func decodedValue<CodableValue: Codable>(
        _ type: CodableValue.Type,
        object: [String: Any]
    ) -> CodableValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return try? BridgeProductStrictJSON.decode(type, from: data)
    }
}
