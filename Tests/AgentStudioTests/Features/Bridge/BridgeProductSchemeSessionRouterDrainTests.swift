import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

/// The stream-drain wait must never strand its caller.
///
/// Before this, `waitForStreamClaimDrain` parked a `CheckedContinuation` with one
/// resume site — the last stream claim finishing — so cancelling a parked
/// bootstrap hung it forever and the `Task.checkCancellation()` after it was
/// unreachable; router teardown did not resume it either.
@Suite("Bridge product scheme session router stream drain")
struct BridgeProductSchemeSessionRouterDrainTests {
    private func makeRouterWithLiveStreamClaim() throws -> (
        router: BridgeProductSchemeSessionRouter,
        capability: String
    ) {
        let productAdmissionGate = BridgeProductAdmissionGate()
        let installation = try BridgeProductSessionInstallation.make(
            paneSessionId: UUIDv7.generate().uuidString,
            provider: BridgeProductSchemeProviderSpy(
                holdFirstControlResponse: false,
                contentReturnsWithoutTerminal: false
            ),
            productAdmissionGate: productAdmissionGate
        )
        let router = BridgeProductSchemeSessionRouter(
            activeInstallation: installation,
            productAdmissionGate: productAdmissionGate
        )
        let capability = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        return (router, capability)
    }

    @Test("a cancelled bootstrap stops waiting for the stream drain")
    func cancelledBootstrapStopsWaitingForTheStreamDrain() async throws {
        // Arrange — one live stream claim, so the drain wait parks.
        let (router, capability) = try makeRouterWithLiveStreamClaim()
        let admission = await router.claimActiveAdapter(
            presentedCapability: capability,
            schemeTaskId: UUIDv7.generate(),
            route: .metadataStream
        )
        guard case .admitted = admission else {
            Issue.record("expected the stream claim to be admitted")
            return
        }
        let parked = DrainWaitProbe()

        // Act — park, then cancel. The probe resumes this test from the waiter's
        // own effects, so there is no clock anywhere.
        let waiting = Task {
            await parked.markParked()
            await router.waitForStreamClaimDrain()
            await parked.markReturned()
        }
        await parked.awaitParked()
        waiting.cancel()

        // Assert — it returns rather than stranding. Awaiting the task IS the
        // assertion: if cancellation did not resume the continuation this never
        // completes and the lane's inactivity bound reports it.
        await waiting.value
        #expect(await parked.didReturn)
        // The claim is still live, so this proves the return came from
        // cancellation and not from the drain completing.
        #expect(await router.snapshot.activeSchemeTaskCount == 1)
    }

    @Test("clearing the router resumes a parked stream-drain waiter")
    func clearingTheRouterResumesAParkedStreamDrainWaiter() async throws {
        // Arrange
        let (router, capability) = try makeRouterWithLiveStreamClaim()
        let admission = await router.claimActiveAdapter(
            presentedCapability: capability,
            schemeTaskId: UUIDv7.generate(),
            route: .metadataStream
        )
        guard case .admitted = admission else {
            Issue.record("expected the stream claim to be admitted")
            return
        }
        let parked = DrainWaitProbe()

        // Act
        let waiting = Task {
            await parked.markParked()
            await router.waitForStreamClaimDrain()
            await parked.markReturned()
        }
        await parked.awaitParked()
        await router.clear()

        // Assert — a waiter must not outlive the router that would have woken it.
        await waiting.value
        #expect(await parked.didReturn)
    }

    @Test("a router with no stream claim does not park at all")
    func routerWithNoStreamClaimDoesNotParkAtAll() async throws {
        let (router, _) = try makeRouterWithLiveStreamClaim()

        // No claim was taken, so this returns without parking; completing is the
        // assertion.
        await router.waitForStreamClaimDrain()
        #expect(await router.snapshot.activeSchemeTaskCount == 0)
    }
}

/// Reports when the waiter parked and when it returned, so the test can sequence
/// on the waiter's own progress instead of a delay.
private actor DrainWaitProbe {
    private(set) var didReturn = false
    private var isParked = false
    private var parkedWaiters: [CheckedContinuation<Void, Never>] = []

    func markParked() {
        isParked = true
        let resumed = parkedWaiters
        parkedWaiters.removeAll()
        for waiter in resumed { waiter.resume() }
    }

    func awaitParked() async {
        guard !isParked else { return }
        await withCheckedContinuation { continuation in
            parkedWaiters.append(continuation)
        }
    }

    func markReturned() {
        didReturn = true
    }
}
