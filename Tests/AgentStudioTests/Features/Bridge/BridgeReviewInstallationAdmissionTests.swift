import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Canonical Review across installation replacement", .serialized)
struct BridgeReviewInstallationAdmissionTests {
    @Test("B reads and installs pane publication while closed A and foreign pane are refused")
    func canonicalPublicationSurvivesInstallationReplacement() async throws {
        let paneGate = BridgeProductAdmissionGate()
        let pane = try #require(paneGate.acquire())
        let coordinator = BridgeReviewPublicationCoordinator()
        let prepared = try await makeReviewPreparedPublication(suffix: "e1-canonical", reviewGeneration: 1)
        let committed = try commitObserved(prepared, in: coordinator, productAdmission: pane)
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: BridgePaneProductSessionProviderGate(), productAdmissionGate: paneGate)
        let first = try await installFirstCandidate(in: owner)
        let firstAdmission = try #require(first.productAdapter.acquireAdmission())
        #expect(
            coordinator.committedPublicationForReplay(productAdmission: firstAdmission)?.publicationId
                == committed.publicationId)
        let successor = try await installFirstCandidate(in: owner)
        let nextAdmission = try #require(successor.productAdapter.acquireAdmission())
        let foreign = try #require(BridgeProductAdmissionGate().acquire())
        #expect(!firstAdmission.matches(nextAdmission))
        #expect(firstAdmission.hasSamePaneAuthority(as: nextAdmission))
        #expect(
            coordinator.isCurrentCanonicalPublication(
                publicationId: committed.publicationId, productAdmission: nextAdmission))
        #expect(
            !coordinator.isCurrentCanonicalPublication(
                publicationId: committed.publicationId, productAdmission: firstAdmission))
        #expect(coordinator.committedPublicationForReplay(productAdmission: firstAdmission) == nil)
        #expect(coordinator.committedPublicationForReplay(productAdmission: foreign) == nil)
        #expect(
            coordinator.committedPublicationForReplay(productAdmission: nextAdmission)?.publicationId
                == committed.publicationId)
        #expect(
            coordinator.activeContentHandle(
                handleId: prepared.contentHandles[0].handleId,
                requestedGeneration: prepared.package.reviewGeneration, productAdmission: nextAdmission)
                == prepared.contentHandles[0])
        #expect(
            coordinator.activeContentHandle(
                handleId: prepared.contentHandles[0].handleId,
                requestedGeneration: prepared.package.reviewGeneration, productAdmission: firstAdmission) == nil)
        #expect(
            coordinator.activeContentHandle(
                handleId: "wrong-handle",
                requestedGeneration: prepared.package.reviewGeneration, productAdmission: nextAdmission) == nil)
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committed.publicationId, workerInstanceId: successor.bootstrap.workerInstanceId,
                productAdmission: nextAdmission) == .admitted)
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committed.publicationId,
                workerInstanceId: first.bootstrap.workerInstanceId, productAdmission: firstAdmission) == .rejected)
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committed.publicationId,
                workerInstanceId: successor.bootstrap.workerInstanceId, productAdmission: nextAdmission) == .advanced)
        #expect(
            coordinator.acknowledgedDisplayedPublication(productAdmission: nextAdmission)?.publicationId
                == committed.publicationId)
        #expect(await owner.retire(reason: .paneDisposal) == .retired)
        _ = coordinator.close()
        await coordinator.takeArtifactPinReleaseTask()?.value
    }
}
