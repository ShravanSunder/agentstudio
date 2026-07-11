import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session control dispatch")
struct BridgeProductSessionControlDispatchTests {
    @Test("revocation may abandon an admission before provider dispatch is claimed")
    func revocationWinsBeforeProviderDispatchClaim() async throws {
        // Arrange
        let fixture = try makePendingControlFixture()
        let admission = await fixture.session.beginControl(
            exactRequestBytes: fixture.requestBytes,
            presentedCapability: fixture.capabilityHeader
        )
        let token = try #require(controlDispatchToken(admission))

        // Act
        let revocation = await fixture.session.revoke(acknowledgeLifecycle: { _ in true })
        let claimedAfterRevocation = await fixture.session.claimControlProviderDispatch(token: token)

        // Assert
        #expect(!claimedAfterRevocation)
        #expect(await revocation.wait())
        let snapshot = await fixture.session.snapshot
        #expect(snapshot.pendingRequestKind == nil)
        #expect(snapshot.controlReplay.inFlightRequestSequence == nil)
    }

    @Test("revocation waits for a claimed provider dispatch and preserves exact replay bytes")
    func providerDispatchClaimWinsBeforeRevocation() async throws {
        // Arrange
        let fixture = try makePendingControlFixture()
        let admission = await fixture.session.beginControl(
            exactRequestBytes: fixture.requestBytes,
            presentedCapability: fixture.capabilityHeader
        )
        let token = try #require(controlDispatchToken(admission))
        let request = try #require(controlDispatchRequest(admission))
        #expect(await fixture.session.claimControlProviderDispatch(token: token))
        let exactResponseBytes = try JSONEncoder().encode(
            BridgeProductControlResponse.workerSessionAccepted(correlating: request)
        )

        // Act
        let revocation = await fixture.session.revoke(acknowledgeLifecycle: { _ in true })
        let whileRevoking = await fixture.session.snapshot
        _ = try await fixture.session.completeControl(
            token: token,
            exactResponseBytes: exactResponseBytes
        )
        let revoked = await revocation.wait()

        // Assert
        #expect(whileRevoking.pendingRequestKind == "workerSession.open")
        #expect(whileRevoking.pendingControlProviderDispatched)
        #expect(revoked)
        let finalSnapshot = await fixture.session.snapshot
        #expect(finalSnapshot.lifecycle == .revoked)
        #expect(finalSnapshot.pendingRequestKind == nil)
        #expect(finalSnapshot.controlReplay.replayableRequestSequence == 1)
    }
}

private struct PendingControlFixture {
    let capabilityHeader: String
    let requestBytes: Data
    let session: BridgeProductSession
}

private func makePendingControlFixture() throws -> PendingControlFixture {
    let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
    return try .init(
        capabilityHeader: BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes),
        requestBytes: bridgeProductSchemeWorkerOpenBody(),
        session: BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
    )
}

private func controlDispatchToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private func controlDispatchRequest(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlRequest? {
    guard case .execute(_, let request) = admission else { return nil }
    return request
}
