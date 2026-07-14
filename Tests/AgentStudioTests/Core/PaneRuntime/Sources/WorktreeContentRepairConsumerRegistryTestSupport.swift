import Foundation

@testable import AgentStudio

struct BoundRegistryFixture {
    let registry: WorktreeContentRepairConsumerRegistry
    let registration: FSEventRegistrationToken
    let consumer: ContentRepairConsumerRegistration
    let capture: ContentRepairPreparedCapture
    let activated: ContentRepairActivatedGeneration

    var bound: ContentRepairBoundGeneration {
        activated.boundGeneration
    }
}

enum ContentRepairRegistryTestError: Error {
    case registration
    case capture
    case binding
    case request
    case lookup
    case replacement
    case acknowledgement
    case withdrawal
}

func makeBoundFixture() async throws -> BoundRegistryFixture {
    let registry = WorktreeContentRepairConsumerRegistry()
    let registration = makeRegistration()
    let consumer = try await requireRegistration(
        registry.register(registration: registration, eligibility: .eligible)
    )
    let capture = try await requirePrepared(prepareCapture(registry, registration: registration))
    let activated = try await bindActive(capture, registry: registry)
    return BoundRegistryFixture(
        registry: registry,
        registration: registration,
        consumer: consumer,
        capture: capture,
        activated: activated
    )
}

func bindActive(
    _ capture: ContentRepairPreparedCapture,
    registry: WorktreeContentRepairConsumerRegistry
) async throws -> ContentRepairActivatedGeneration {
    let result = await registry.bind(capture, to: makeRepair(capture: capture))
    guard case .boundActive(let activated) = result else {
        throw ContentRepairRegistryTestError.binding
    }
    return activated
}

func prepareCapture(
    _ registry: WorktreeContentRepairConsumerRegistry,
    registration: FSEventRegistrationToken,
    identity: ContentRepairCaptureIdentity = .generate()
) async -> ContentRepairCapturePreparationResult {
    await registry.prepareCapture(identity: identity, registration: registration)
}

func makeRegistration() -> FSEventRegistrationToken {
    FSEventRegistrationToken(
        sourceID: FilesystemSourceID(
            kind: .registeredWorktreeContent,
            rootID: UUIDv7.generate()
        ),
        registrationGeneration: 3,
        rootGeneration: 5
    )
}

func makeRepair(capture: ContentRepairPreparedCapture) -> RepairGeneration {
    RepairGeneration(
        id: RepairGenerationID(
            registration: capture.registration,
            sequence: capture.invalidationGeneration.value
        ),
        watermark: .recoveryRevision(capture.invalidationGeneration.value),
        trigger: .continuityLoss,
        participants: capture.sourceGateParticipants
    )
}

func requireRegistration(
    _ result: ContentRepairConsumerRegistrationResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw ContentRepairRegistryTestError.registration
    }
    return registration
}

func requirePrepared(
    _ result: ContentRepairCapturePreparationResult
) throws -> ContentRepairPreparedCapture {
    guard case .prepared(let capture) = result else {
        throw ContentRepairRegistryTestError.capture
    }
    return capture
}

func requireRequest(
    for consumer: ContentRepairConsumerToken,
    in bound: ContentRepairBoundGeneration
) throws -> ContentRepairDeliveryRequest {
    guard let request = bound.deliveryRequests.first(where: { $0.consumer == consumer }) else {
        throw ContentRepairRegistryTestError.request
    }
    return request
}

func requireLookup(
    _ result: ContentRepairConsumerLookupResult
) throws -> ContentRepairConsumerRegistration {
    guard case .registered(let registration) = result else {
        throw ContentRepairRegistryTestError.lookup
    }
    return registration
}

func requireReplacement(
    _ result: ContentRepairConsumerReplacementResult
) throws -> ContentRepairConsumerReplacement {
    guard case .replaced(let replacement) = result else {
        throw ContentRepairRegistryTestError.replacement
    }
    return replacement
}

func requireAccepted(
    _ result: ContentRepairAcknowledgementResult
) throws -> ContentRepairAcceptedAcknowledgement {
    guard case .accepted(let accepted) = result else {
        throw ContentRepairRegistryTestError.acknowledgement
    }
    return accepted
}

func requireWithdrawalAccepted(
    _ result: ContentRepairWithdrawalResult
) throws -> ContentRepairAcceptedAcknowledgement {
    guard case .withdrawnAndAcknowledged(let accepted) = result else {
        throw ContentRepairRegistryTestError.withdrawal
    }
    return accepted
}

func emptyShutdownDebt() -> WorktreeContentRepairConsumerRegistryShutdownDebt {
    WorktreeContentRepairConsumerRegistryShutdownDebt(
        preparedCaptures: [],
        activeRepairGenerations: [],
        pendingRepairGenerations: [],
        retainedRetries: [],
        outboundAcknowledgements: []
    )
}
