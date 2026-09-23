import Foundation
import Testing

@testable import AgentStudioBridge

/// Characterization of audit finding S13 (2026-09-23 Bridge stuck-state audit).
///
/// These tests pin CURRENT behavior, not the desired contract. A native provider
/// call that never answers (for example an export waiting on an open Save panel)
/// holds the product session's single pending-control slot. While it is held,
/// native refuses every other control on the pane, and revocation, which both a
/// page reload and a worker replacement route through, cannot finish. When the
/// owner decides the S13 fix, these tests must be rewritten to assert the new
/// contract instead of being deleted.
@Suite("Bridge product session held-provider stall characterization (S13, pins current behavior)")
struct BridgeProductHeldProviderStallTests {
    @Test("current behavior: a held provider call refuses later controls and holds revocation until it returns")
    func heldProviderCallRefusesLaterControlsAndHoldsRevocation() async throws {
        // Arrange
        let harness = try HeldProviderSessionHarness.make()
        let log = S13OrderedEventLog()
        #expect(try await harness.send(bridgeProductSchemeWorkerOpenBody()).response?.statusCode == 200)
        await harness.provider.holdNextProductCall()
        let heldCall = Task {
            try await harness.send(bridgeProductSchemeReviewCallBody(requestSequence: 2))
        }
        await harness.provider.waitUntilProductCallStarted(count: 1)

        // Act: a second control while the first provider call is held.
        let secondControl = try await harness.send(bridgeProductSchemeReviewCallBody(requestSequence: 3))
        let secondControlResponse = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: secondControl.body
        )

        // Assert: native refuses it without dispatching it to the provider.
        guard case .requestError(let secondControlError) = secondControlResponse else {
            Issue.record("Expected the second control to be refused while the first is held")
            return
        }
        #expect(secondControlError.code == .sequenceConflict)
        #expect(secondControlError.retryable)
        #expect(secondControlError.nextExpectedRequestSequence == 2)
        #expect(await harness.provider.productCallStartCount == 1)

        // Act: revoke the session (the step a page reload or a worker replacement awaits).
        let revocation = await harness.session.revoke(acknowledgeLifecycle: { _ in true })
        let whileRevoking = await harness.session.snapshot
        let revocationWatcher = Task {
            let didRevoke = await revocation.wait()
            await log.record(.revocationCompleted)
            return didRevoke
        }

        // Assert: revocation is committed, but the held dispatch still owns the slot, and
        // the revocation barrier awaits that dispatch's completion.
        #expect(whileRevoking.lifecycle == .revoked)
        #expect(whileRevoking.pendingRequestKind == "product.call")
        #expect(whileRevoking.pendingControlProviderDispatched)

        // Act: the provider finally answers.
        await log.record(.providerReleased)
        await harness.provider.releaseHeldProductCall()
        let didRevoke = await revocationWatcher.value
        _ = try? await heldCall.value

        // Assert: revocation completes only after the provider answered, and the slot is free.
        #expect(didRevoke)
        #expect(await log.events == [.providerReleased, .revocationCompleted])
        let afterRelease = await harness.session.snapshot
        #expect(afterRelease.pendingRequestKind == nil)
        #expect(!afterRelease.pendingControlProviderDispatched)
    }

    @Test("current behavior: page-reload retirement does not complete while a provider call is held")
    func pageReloadRetirementWaitsForHeldProviderCall() async throws {
        // Arrange
        let log = S13OrderedEventLog()
        let provider = S13HeldProductCallProvider(log: log)
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider,
            productAdmissionGate: BridgeProductAdmissionGate(),
            didRetireWorkerInstance: { _ in
                await log.record(.workerRetired)
            }
        )
        let productAdmission = try #require(owner.productAdmissionGate.acquire())
        let installation = try await owner.prepareCandidate(productAdmission: productAdmission)
        #expect(
            await owner.activatePreparedCandidate(installation, productAdmission: productAdmission)
                == .activated
        )
        try await openBridgePaneProductSession(installation)
        await provider.holdNextProductCall()
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        let heldCall = Task {
            try await collectBridgeProductSchemeReply(
                adapter: installation.productAdapter,
                request: bridgeProductSchemeRequest(
                    route: BridgeProductWireContract.commandRoute,
                    capability: capabilityHeader,
                    body: s13ProductCallBody(installation: installation, requestSequence: 2)
                )
            )
        }
        await provider.waitUntilProductCallStarted(count: 1)

        // Act
        let retirement = Task { await owner.retire(reason: .pageReload) }
        await log.waitUntilRecorded(.comparisonTargetReservationInvalidated, count: 1)
        let activeDuringRetirement = await owner.activeInstallation

        // Assert: retirement began and fenced the installation.
        #expect(activeDuringRetirement == nil)

        // Act: the provider finally answers.
        await log.record(.providerReleased)
        await provider.releaseHeldProductCall()
        let result = await retirement.value
        _ = try? await heldCall.value

        // Assert: the worker is retired only after the held provider call returned.
        #expect(result == .retired)
        let events = await log.events
        let releaseIndex = try #require(events.firstIndex(of: .providerReleased))
        let retiredIndex = try #require(events.firstIndex(of: .workerRetired))
        #expect(releaseIndex < retiredIndex)
        #expect((await installation.session.snapshot).lifecycle == .revoked)
    }
}

private enum S13Event: Equatable, Sendable {
    case comparisonTargetReservationInvalidated
    case providerReleased
    case revocationCompleted
    case workerRetired
}

private actor S13OrderedEventLog {
    private(set) var events: [S13Event] = []
    private var waiters: [(S13Event, Int, CheckedContinuation<Void, Never>)] = []

    func record(_ event: S13Event) {
        events.append(event)
        let ready = waiters.filter { recordedCount(of: $0.0) >= $0.1 }
        waiters.removeAll { recordedCount(of: $0.0) >= $0.1 }
        for (_, _, continuation) in ready { continuation.resume() }
    }

    func waitUntilRecorded(_ event: S13Event, count: Int) async {
        guard recordedCount(of: event) < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((event, count, continuation))
        }
    }

    private func recordedCount(of event: S13Event) -> Int {
        events.filter { $0 == event }.count
    }
}

private actor S13HeldProductCallProvider: BridgeProductSchemeProvider {
    private let log: S13OrderedEventLog?
    private var heldCallContinuation: CheckedContinuation<Void, Never>?
    private var holdsNextProductCall = false
    private var productCallStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var productCallStartCount = 0

    init(log: S13OrderedEventLog? = nil) {
        self.log = log
    }

    func holdNextProductCall() {
        holdsNextProductCall = true
    }

    func waitUntilProductCallStarted(count: Int) async {
        guard productCallStartCount < count else { return }
        await withCheckedContinuation { continuation in
            productCallStartWaiters.append((count, continuation))
        }
    }

    func releaseHeldProductCall() {
        heldCallContinuation?.resume()
        heldCallContinuation = nil
    }

    func invalidatePendingComparisonTargetReservation() async {
        await log?.record(.comparisonTargetReservationInvalidated)
    }

    func response(
        for request: BridgeProductControlRequest,
        productAdmission _: BridgeProductAdmissionContext?
    ) async -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .productCall:
                productCallStartCount += 1
                let ready = productCallStartWaiters.filter { $0.0 <= productCallStartCount }
                productCallStartWaiters.removeAll { $0.0 <= productCallStartCount }
                for (_, continuation) in ready { continuation.resume() }
                if holdsNextProductCall {
                    holdsNextProductCall = false
                    await withCheckedContinuation { continuation in
                        heldCallContinuation = continuation
                    }
                }
                return try .callCompleted(correlating: request, result: .reviewMarkFileViewed)
            case .subscriptionOpen, .subscriptionUpdateBatch, .subscriptionCancel,
                .workerSessionResync:
                preconditionFailure("The S13 provider received an unconfigured control request")
            }
        } catch {
            preconditionFailure("The S13 provider could not build a correlated response")
        }
    }

    func runMetadataProducer(
        request _: BridgeProductMetadataStreamRequest,
        lease _: BridgeProductProducerLease,
        productAdmission _: BridgeProductAdmissionContext,
        session _: BridgeProductSession
    ) async {
        Issue.record("The S13 characterization does not open metadata streams")
    }

    func runContentProducer(
        request _: BridgeProductContentRequest,
        lease _: BridgeProductProducerLease,
        productAdmission _: BridgeProductAdmissionContext,
        session _: BridgeProductSession
    ) async {
        Issue.record("The S13 characterization does not open content")
    }

    func acknowledgeLifecycle(
        _: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        true
    }
}

private struct HeldProviderSessionHarness {
    let adapter: BridgeProductSchemeAdapter
    let capabilityHeader: String
    let provider: S13HeldProductCallProvider
    let session: BridgeProductSession

    static func make() throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let provider = S13HeldProductCallProvider()
        return try Self(
            adapter: BridgeProductSchemeAdapter(
                session: session,
                provider: provider,
                productAdmissionGate: BridgeProductAdmissionGate()
            ),
            capabilityHeader: BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes),
            provider: provider,
            session: session
        )
    }

    func send(_ body: Data) async throws -> BridgeProductSchemeReplyObservation {
        try await collectBridgeProductSchemeReply(
            adapter: adapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: capabilityHeader,
                body: body
            )
        )
    }
}

private func s13ProductCallBody(
    installation: BridgeProductSessionInstallation,
    requestSequence: Int
) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "call": [
                "method": "review.markFileViewed",
                "request": ["itemId": "item-s13-held"],
            ],
            "kind": "product.call",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "requestId": "product-call-s13-held",
            "requestSequence": requestSequence,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
}
