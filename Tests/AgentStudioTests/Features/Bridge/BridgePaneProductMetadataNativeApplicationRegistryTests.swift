import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge metadata native application registry")
struct BridgeMetadataNativeApplicationRegistryTests {
    @Test("only File metadata admits interest after source acceptance")
    func onlyFileMetadataOverlapsBootstrap() throws {
        let registry = BridgePaneProductMetadataNativeApplicationRegistry.product

        #expect(
            try registry.application(for: .fileMetadata).adapter.interestBootstrapAdmission
                == .afterSourceAcceptance
        )
        #expect(
            try registry.application(for: .reviewMetadata).adapter.interestBootstrapAdmission
                == .afterBootstrap
        )
        #expect(
            try registry.application(for: .fileAnnotations).adapter.interestBootstrapAdmission
                == .afterBootstrap
        )
        #expect(
            try registry.application(for: .reviewAnnotations).adapter.interestBootstrapAdmission
                == .afterBootstrap
        )
    }

    @Test("one bound fixture registration owns schema open update cancel and active close lifecycle")
    func boundFixtureRegistrationOwnsNativeLifecycle() async throws {
        let registration = AnyBridgeProductMetadataApplicationProtocol(FixtureLifecycleApplication.self)
        let (events, continuation) = AsyncStream<String>.makeStream()
        var iterator = events.makeAsyncIterator()
        let adapter = BridgePaneProductMetadataNativeAdapter(
            open: { _, subscription, _, _, _, _, _ in
                continuation.yield("open:\(subscription.subscriptionId)")
            },
            update: { _, subscription, _, _, _, _, _ in
                continuation.yield("update:\(subscription.subscriptionId)")
            },
            cancel: { _, subscriptionId in
                continuation.yield("cancel:\(subscriptionId)")
            }
        )
        let nativeRegistry = try BridgePaneProductMetadataNativeApplicationRegistry(
            applications: [.init(registration: registration, adapter: adapter)]
        )
        #expect(
            try nativeRegistry.schemaRegistry.registration(for: registration.kind).kind
                == registration.kind
        )
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source,
            nativeApplicationRegistry: nativeRegistry
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let request = try BridgeProductSubscriptionRequest.registered(
            registration: registration,
            options: FixtureLifecycleApplication.SubscriptionOptions()
        )
        let applicationState = try registration.initialInterestState(
            from: registration.decodeSubscriptionOptions(from: Data("{}".utf8))
        )
        let interestState = BridgeProductSubscriptionInterestState(
            subscriptionKind: registration.kind,
            applicationState: applicationState
        )
        let explicitlyCancelledSnapshot = BridgeProductSubscriptionSnapshot(
            subscription: request,
            subscriptionId: "fixture-explicit-cancel",
            subscriptionKind: registration.kind,
            workerDerivationEpoch: 0,
            interestRevision: 0,
            interestSha256: String(repeating: "0", count: 64),
            interestState: interestState,
            hasStagedUpdate: false
        )
        await coordinator.apply(
            .subscriptionOpened(explicitlyCancelledSnapshot),
            productAdmission: harness.productAdmission.context
        )
        #expect(await iterator.next() == "open:fixture-explicit-cancel")
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: .init(
                    subscriptionId: explicitlyCancelledSnapshot.subscriptionId,
                    subscriptionKind: explicitlyCancelledSnapshot.subscriptionKind,
                    workerDerivationEpoch: explicitlyCancelledSnapshot.workerDerivationEpoch,
                    interestRevision: explicitlyCancelledSnapshot.interestRevision,
                    interestSha256: explicitlyCancelledSnapshot.interestSha256,
                    updateId: "fixture-update"
                ),
                subscription: explicitlyCancelledSnapshot
            ),
            productAdmission: harness.productAdmission.context
        )
        #expect(await iterator.next() == "update:fixture-explicit-cancel")
        await coordinator.apply(
            .subscriptionCancelled(explicitlyCancelledSnapshot),
            productAdmission: harness.productAdmission.context
        )
        #expect(await iterator.next() == "cancel:fixture-explicit-cancel")

        let closeDrainedSnapshot = replacingSubscriptionId(
            of: explicitlyCancelledSnapshot,
            with: "fixture-close-drain"
        )
        await coordinator.apply(
            .subscriptionOpened(closeDrainedSnapshot),
            productAdmission: harness.productAdmission.context
        )
        #expect(await iterator.next() == "open:fixture-close-drain")
        await coordinator.closeAndDrain()
        #expect(await iterator.next() == "cancel:fixture-close-drain")
        #expect(!(await coordinator.hasActiveStream))
        continuation.finish()
    }
}

private func replacingSubscriptionId(
    of snapshot: BridgeProductSubscriptionSnapshot,
    with subscriptionId: String
) -> BridgeProductSubscriptionSnapshot {
    BridgeProductSubscriptionSnapshot(
        subscription: snapshot.subscription,
        subscriptionId: subscriptionId,
        subscriptionKind: snapshot.subscriptionKind,
        workerDerivationEpoch: snapshot.workerDerivationEpoch,
        interestRevision: snapshot.interestRevision,
        interestSha256: snapshot.interestSha256,
        interestState: snapshot.interestState,
        hasStagedUpdate: snapshot.hasStagedUpdate
    )
}

private enum FixtureLifecycleApplication: BridgeProductMetadataApplicationProtocol {
    struct SubscriptionOptions: Codable, Equatable, Sendable {}
    struct InterestState: Codable, Equatable, Sendable {}
    struct InterestDelta: Codable, Equatable, Sendable {}
    struct Event: Codable, Equatable, Sendable { let generation: Int }

    static let kind = try! BridgeProductSubscriptionKind("fixture.lifecycle")
    static let surface = BridgeProductSurface.file
    static let canonicalInterestTag: UInt8 = 10
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "fixture-lifecycle"
    )
    static func initialInterestState(from _: SubscriptionOptions) -> InterestState { .init() }
    static func applying(_: [InterestDelta], to state: InterestState) -> InterestState { state }
    static func deltaItemCount(_: InterestDelta) -> Int { 0 }
    static func deltaMemberIdentities(_: InterestDelta) -> Set<Data> { [] }
    static func canonicalInterestBody(_: InterestState) -> Data { Data([0, 0, 0, 0]) }
    static func sourceGeneration(of event: Event) -> Int { event.generation }
}
