import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("File refresh failure values")
struct BridgePaneProductFileRefreshFailureTests {
    private struct ExpectedRootFailure {
        let rootAccessError: BridgeWorktreeFileRootAccessError
        let failureKind: BridgePaneProductFileRefreshFailureKind
        let retryable: Bool
        let safeMessage: String
    }

    @Test("root access failures encode closed copy and retryability")
    func rootAccessFailuresEncodeClosedCopyAndRetryability() throws {
        let cases: [ExpectedRootFailure] = [
            .init(
                rootAccessError: .missingRoot,
                failureKind: .missingRoot,
                retryable: true,
                safeMessage: "The File root is unavailable. Restore it, then retry."
            ),
            .init(
                rootAccessError: .unreadable,
                failureKind: .unreadable,
                retryable: true,
                safeMessage: "The File root or range cannot be read. Check access, then retry."
            ),
            .init(
                rootAccessError: .refused,
                failureKind: .refused,
                retryable: false,
                safeMessage: "Choose an accessible directory as the File root."
            ),
        ]

        for expected in cases {
            let failure = BridgePaneProductFileRefreshFailure(rootAccessFailure: expected.rootAccessError)
            #expect(failure.failureKind == expected.failureKind)
            #expect(failure.retryable == expected.retryable)
            #expect(failure.safeMessage == expected.safeMessage)

            let encoded = try JSONEncoder().encode(failure)
            let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(object["safeMessage"] as? String == expected.safeMessage)
            #expect(try JSONDecoder().decode(BridgePaneProductFileRefreshFailure.self, from: encoded) == failure)
        }
    }

    @Test("generic file failures retain their existing wire shape")
    func genericFileFailuresRetainTheirExistingWireShape() throws {
        for failureKind in BridgePaneProductFileRefreshFailureKind.allCases.prefix(3) {
            let failure = BridgePaneProductFileRefreshFailure(failureKind: failureKind)
            #expect(failure.safeMessage == nil)

            let encoded = try JSONEncoder().encode(failure)
            let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(Set(object.keys) == Set(["failureKind", "retryable"]))
            #expect(try JSONDecoder().decode(BridgePaneProductFileRefreshFailure.self, from: encoded) == failure)
        }
    }

    @Test("decoder rejects a root copy that does not match the closed failure kind")
    func decoderRejectsUnmatchedRootSafeCopy() {
        let encoded = Data(
            #"{"failureKind":"missingRoot","retryable":true,"safeMessage":"provider path leaked"}"#.utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BridgePaneProductFileRefreshFailure.self, from: encoded)
        }
    }
}
