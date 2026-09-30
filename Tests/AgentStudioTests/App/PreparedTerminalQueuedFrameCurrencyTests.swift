import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal

@MainActor
@Suite("Prepared terminal queued frame currency")
struct PreparedTerminalQueuedFrameCurrencyTests {
    private let queuedFrame = NSRect(x: 0, y: 0, width: 800, height: 400)
    private let currentFrame = NSRect(x: 515, y: 90, width: 469, height: 454)

    private struct PortFixture {
        let generation: WorkspaceContentMountGeneration
        let paneID: PaneId
        let registry: ViewRegistry
        let handler: RecordingPreparedTerminalMountHandler
        let port: PreparedTerminalMountAdmissionPort
    }

    private func makeFixture(results: [TerminalActivationAttemptResult], initialFrame: NSRect?) throws -> PortFixture {
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDrawerDescriptor(pane: makePreparedTerminalTestPane())
        let paneID = descriptor.paneID
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: results)
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            viewRegistry: registry,
            mountHandler: handler,
            descriptorsByPaneID: [paneID: descriptor]
        )
        _ = port.installTrustedInitialFrames(initialFrame.map { [paneID: $0] } ?? [:])
        return PortFixture(generation: generation, paneID: paneID, registry: registry, handler: handler, port: port)
    }

    private func claimTerminal(_ fixture: PortFixture, attempt: Int = 1) -> ClaimedTerminalAdmission? {
        let outcome = fixture.port.claimPreparedTerminal(
            TerminalAdmissionProposal(
                generation: fixture.generation,
                paneID: fixture.paneID,
                attempt: attempt,
                appliedVisibilityRevision: TerminalVisibilityRevision(generation: fixture.generation, ordinal: 0)
            )
        )
        guard case .claimed(let claim) = outcome else { return nil }
        return claim
    }

    @Test("a pending member mounts with the frame refreshed after it was queued")
    func pendingMemberMountsWithRefreshedFrame() async throws {
        let fixture = try makeFixture(results: [.ready(surfaceID: UUIDv7.generate())], initialFrame: queuedFrame)

        let refreshed = fixture.port.refreshQueuedTrustedFrames([fixture.paneID: currentFrame])
        let claim = try #require(claimTerminal(fixture))
        _ = await fixture.port.activateClaimedTerminal(claim)

        #expect(refreshed == [fixture.paneID])
        #expect(fixture.handler.initialFrames == [currentFrame])
    }

    @Test("a claimed but not yet activated member mounts with the refreshed frame")
    func claimedMemberMountsWithRefreshedFrame() async throws {
        let fixture = try makeFixture(results: [.ready(surfaceID: UUIDv7.generate())], initialFrame: queuedFrame)
        let claim = try #require(claimTerminal(fixture))

        let refreshed = fixture.port.refreshQueuedTrustedFrames([fixture.paneID: currentFrame])
        _ = await fixture.port.activateClaimedTerminal(claim)

        #expect(refreshed == [fixture.paneID])
        #expect(fixture.handler.initialFrames == [currentFrame])
    }

    @Test("a member that already started mounting keeps its frame for the retry")
    func startedMountingMemberIsUntouched() async throws {
        let fixture = try makeFixture(
            results: [
                .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry),
                .ready(surfaceID: UUIDv7.generate()),
            ],
            initialFrame: queuedFrame
        )
        let firstClaim = try #require(claimTerminal(fixture))
        _ = await fixture.port.activateClaimedTerminal(firstClaim)

        let refreshed = fixture.port.refreshQueuedTrustedFrames([fixture.paneID: currentFrame])
        let secondClaim = try #require(claimTerminal(fixture, attempt: 2))
        _ = await fixture.port.activateClaimedTerminal(secondClaim)

        #expect(refreshed.isEmpty)
        #expect(fixture.handler.initialFrames == [queuedFrame, queuedFrame])
    }

    @Test("a retry claim keeps its first activation's frame even when refreshed before activation")
    func retryClaimKeepsFirstActivationFrame() async throws {
        let fixture = try makeFixture(
            results: [
                .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry),
                .ready(surfaceID: UUIDv7.generate()),
            ],
            initialFrame: queuedFrame
        )
        let firstClaim = try #require(claimTerminal(fixture))
        _ = await fixture.port.activateClaimedTerminal(firstClaim)
        let retryClaim = try #require(claimTerminal(fixture, attempt: 2))

        let refreshed = fixture.port.refreshQueuedTrustedFrames([fixture.paneID: currentFrame])
        _ = await fixture.port.activateClaimedTerminal(retryClaim)

        #expect(refreshed.isEmpty)
        #expect(fixture.handler.initialFrames == [queuedFrame, queuedFrame])
    }

    @Test("ready and deferred members are not refreshed; deferred keeps its own readmission path")
    func readyAndDeferredMembersAreUntouched() async throws {
        let ready = try makeFixture(results: [.ready(surfaceID: UUIDv7.generate())], initialFrame: queuedFrame)
        let readyClaim = try #require(claimTerminal(ready))
        _ = await ready.port.activateClaimedTerminal(readyClaim)
        #expect(ready.port.refreshQueuedTrustedFrames([ready.paneID: currentFrame]).isEmpty)

        let deferred = try makeFixture(results: [], initialFrame: nil)
        #expect(deferred.port.refreshQueuedTrustedFrames([deferred.paneID: currentFrame]).isEmpty)
        #expect(
            deferred.registry.preparedContentMountState(for: deferred.paneID, generation: deferred.generation)
                == .deferredGeometry(owner: .terminal)
        )
        #expect(deferred.port.acceptLaterTrustedFrames([deferred.paneID: currentFrame]) == [deferred.paneID])
    }

    @Test("a non-finite or empty refresh frame is ignored")
    func invalidRefreshFrameIsIgnored() async throws {
        let fixture = try makeFixture(results: [.ready(surfaceID: UUIDv7.generate())], initialFrame: queuedFrame)

        let refreshed = fixture.port.refreshQueuedTrustedFrames([
            fixture.paneID: NSRect(x: 0, y: 0, width: CGFloat.nan, height: 10)
        ])
        let claim = try #require(claimTerminal(fixture))
        _ = await fixture.port.activateClaimedTerminal(claim)

        #expect(refreshed.isEmpty)
        #expect(fixture.handler.initialFrames == [queuedFrame])
    }
}
