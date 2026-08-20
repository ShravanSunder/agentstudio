import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product File refresh failure classification")
struct BridgeFileRefreshFailureClassificationTests {
    @Test("every closed failure kind round-trips with derived retryability")
    func everyFailureKindRoundTrips() throws {
        for failureKind in BridgePaneProductFileRefreshFailureKind.allCases {
            let failure = BridgePaneProductFileRefreshFailure(failureKind: failureKind)
            let encoded = try JSONEncoder().encode(failure)

            #expect(try JSONDecoder().decode(BridgePaneProductFileRefreshFailure.self, from: encoded) == failure)
            #expect(failure.retryable == failureKind.retryable)
        }
    }

    @Test("invalid retryability and unknown members fail closed")
    func invalidWireFailuresFailClosed() {
        for json in [
            #"{"failureKind":"fileSourceUnavailable","retryable":false}"#,
            #"{"failureKind":"fileRefreshFailed","retryable":false,"unknown":1}"#,
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(
                    BridgePaneProductFileRefreshFailure.self,
                    from: Data(json.utf8)
                )
            }
        }
    }

    @Test("producer queue reset requires stream replacement without spending File retry")
    func producerQueueResetRequiresStreamReplacement() {
        #expect(
            BridgePaneProductMetadataCoordinator.fileRefreshDisposition(
                for: BridgePaneProductMetadataCoordinatorError.producerQueueReset
            ) == .streamResetRequired
        )
    }

    @Test("foreground invalidation is stale instead of failed")
    func foregroundInvalidationIsStale() {
        #expect(
            BridgePaneProductMetadataCoordinator.fileRefreshDisposition(
                for: BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
            ) == .stale
        )
    }

    @Test("temporary File source failure is retryable")
    func temporaryFileSourceFailureIsRetryable() {
        #expect(
            BridgePaneProductMetadataCoordinator.fileRefreshDisposition(
                for: BridgePaneProductFileMetadataSourceError.unavailableAuthority
            )
                == .failed(
                    .init(failureKind: .fileSourceUnavailable)
                )
        )
    }
}
