import Foundation

enum BridgeProductStreamWebKitFeasibilityContentFrames {
    struct Fixture {
        let request: BridgeProductContentRequest
        let completedFrames: [Data]
        let acceptedFrame: Data
    }

    static let payloadSHA256 = "15601535eca4a38b7e31ad6494861121cb9f84ccf55d4beb6a707d4f7a87813d"

    static func makeFixture() throws -> Fixture {
        let request = try makeRequest()
        let payload = Data(
            repeating: 0x78,
            count: BridgeProductWireContract.maximumContentDataPayloadBytes
        )
        let encoder = BridgeProductContentFrameEncoder(expectedRequest: request)
        let acceptedFrame = try encoder.encode(
            .init(
                header: .accepted(for: request.admission),
                payload: Data()
            ))
        let dataFrame = try encoder.encode(
            .init(
                header: try .data(contentSequence: 1, offsetBytes: 0),
                payload: payload
            ))
        let endFrame = try encoder.encode(
            .init(
                header: try .end(
                    contentSequence: 2,
                    observedByteLength: payload.count,
                    observedSha256: payloadSHA256
                ),
                payload: Data()
            ))
        try encoder.finish()
        return Fixture(
            request: request,
            completedFrames: [acceptedFrame, dataFrame, endFrame],
            acceptedFrame: acceptedFrame
        )
    }

    private static func makeRequest() throws -> BridgeProductContentRequest {
        let requestData = Data(
            #"""
            {
              "kind":"content.open",
              "wireVersion":2,
              "paneSessionId":"s2a-pane-session",
              "workerDerivationEpoch":1,
              "workerInstanceId":"s2a-worker-instance",
              "contentRequestId":"s2a-content-request",
              "leaseId":"s2a-content-lease",
              "contentKind":"file.content",
              "descriptor":{
                "contentKind":"file.content",
                "declaredByteLength":131072,
                "descriptorId":"s2a-file-descriptor",
                "encoding":"utf-8",
                "expectedSha256":"15601535eca4a38b7e31ad6494861121cb9f84ccf55d4beb6a707d4f7a87813d",
                "fileId":"s2a-file",
                "maximumBytes":131072,
                "source":{
                  "repoId":"00000000-0000-4000-8000-000000000001",
                  "rootRevisionToken":null,
                  "sourceCursor":"s2a-source-cursor",
                  "sourceId":"s2a-source",
                  "subscriptionGeneration":1,
                  "worktreeId":"00000000-0000-4000-8000-000000000002"
                },
                "window":{
                  "kind":"prefix",
                  "maximumBytes":131072,
                  "maximumLines":10000,
                  "startByte":0
                }
              }
            }
            """#.utf8)
        try BridgeProductStrictJSON.validate(requestData)
        return try JSONDecoder().decode(BridgeProductContentRequest.self, from: requestData)
    }
}
