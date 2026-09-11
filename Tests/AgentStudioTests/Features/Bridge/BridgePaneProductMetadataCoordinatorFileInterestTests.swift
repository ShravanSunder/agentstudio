import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge File metadata interest admission")
struct BridgeFileInterestAdmissionTests {
    @Test(
        "committed File interest starts after source acceptance while bootstrap continues",
        .timeLimit(.minutes(1))
    )
    func committedFileInterestStartsAfterSourceAcceptance() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorGatedFileMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openRequest = try bridgeProductLifecycleControlRequest(
            bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        let openToken = try #require(controlExecutionToken(try await harness.begin(openRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: openToken))
        let emptyInterestSha256 = try BridgeProductSubscriptionInterestState.fileMetadata(
            interests: [],
            pathScope: []
        ).sha256Hex()
        let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
            correlating: openRequest,
            interestSha256: emptyInterestSha256
        )
        let openEffect = try await harness.session.completeControl(
            token: openToken,
            exactResponseBytes: try JSONEncoder().encode(openResponse)
        )
        _ = try await pullMetadataFrame(from: pump)
        await coordinator.apply(
            openEffect,
            productAdmission: harness.productAdmission.context
        )
        await source.waitUntilOpenStarted()
        await harness.session.settleControlProviderDispatch(token: openToken)
        let lifecycle = try coordinatorFileSubscriptionLifecycle()
        let updateId = "file-update-before-source-acceptance"
        let updateRequest = try coordinatorFileUpdateRequest(
            emptyInterestSha256: emptyInterestSha256,
            targetInterestSha256: lifecycle.updated.interestSha256,
            updateId: updateId
        )

        // Act
        let updateToken = try #require(controlExecutionToken(try await harness.begin(updateRequest)))
        #expect(await harness.session.claimControlProviderDispatch(token: updateToken))
        let updateResponse = try BridgeProductControlResponse.subscriptionUpdateBatchAccepted(
            correlating: updateRequest,
            disposition: .committed
        )
        let updateEffect = try await harness.session.completeControl(
            token: updateToken,
            exactResponseBytes: try JSONEncoder().encode(updateResponse)
        )
        let committedFrame = try await pullMetadataFrame(from: pump)
        await coordinator.apply(
            updateEffect,
            productAdmission: harness.productAdmission.context
        )
        await source.releaseSourceAcceptance()
        _ = try await pullMetadataFrame(from: pump)
        await source.waitUntilSourceAccepted()
        await source.waitUntilUpdateStarted()
        await source.releaseOpen()
        await source.waitUntilOpenFinished()

        // Assert
        #expect(!(await source.openObservedCancellation))
        #expect(!(await source.updateObservedOpenFinished))
        #expect(await source.updateObservedSourceAccepted)
        guard case .subscriptionInterestsCommitted(let committed) = committedFrame else {
            Issue.record("Expected the File interest commit before source acceptance")
            return
        }
        #expect(committed.updateId == updateId)
        await harness.session.settleControlProviderDispatch(token: updateToken)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }
}
