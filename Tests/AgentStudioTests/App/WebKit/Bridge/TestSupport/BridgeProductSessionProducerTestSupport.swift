import Foundation
import Testing

@testable import AgentStudioBridge

func bridgeProductMetadataAcceptedFrame(
    request: BridgeProductMetadataStreamRequest,
    streamSequence: Int,
    resumeDisposition: BridgeProductMetadataStreamResumeDisposition
) throws -> BridgeProductProducerFrame {
    .metadata(
        .metadataStreamAccepted(
            try BridgeProductMetadataStreamAcceptedFrame(
                stream: request.correlation,
                streamSequence: streamSequence,
                resumeDisposition: resumeDisposition
            )
        )
    )
}

func consumeNextBridgeProductProducerFrame(
    for lease: BridgeProductProducerLease,
    from session: BridgeProductSession,
    productAdmission: BridgeProductAdmissionContext
) async -> BridgeProductQueuedProducerFrame? {
    guard
        case .frame(let delivery) = await session.pullProducerFrame(
            for: lease,
            productAdmission: productAdmission
        )
    else {
        Issue.record("Expected a queued producer frame")
        return nil
    }
    guard
        await session.acknowledgeProducerFrameConsumed(
            delivery.receipt,
            productAdmission: productAdmission
        )
    else {
        Issue.record("Expected the exact producer frame receipt to be accepted")
        return nil
    }
    return delivery.frame
}

func closeBridgeProductSessionProducer(
    _ lease: BridgeProductProducerLease,
    in session: BridgeProductSession
) async throws {
    guard await session.stopProducer(lease) else {
        throw BridgeProductSessionProducerTestSupportError.stopRejected
    }
    let acknowledgement = try bridgeProductLifecycleAcknowledgement(
        await session.unregisterProducer(lease)
    )
    guard await session.acknowledgeProducerLifecycle(acknowledgement) else {
        throw BridgeProductSessionProducerTestSupportError.acknowledgementRejected
    }
}

func bridgeProductAcceptedLease(
    _ registration: BridgeProductProducerRegistration
) throws -> BridgeProductProducerLease {
    guard case .accepted(let lease) = registration else {
        throw BridgeProductSessionProducerTestSupportError.expectedAcceptedRegistration
    }
    return lease
}

private enum BridgeProductSessionProducerTestSupportError: Error {
    case acknowledgementRejected
    case expectedAcceptedRegistration
    case expectedExecutionAdmission
    case expectedLifecycleAcknowledgement
    case stopRejected
}

private func bridgeProductLifecycleAcknowledgement(
    _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement?
) throws -> BridgeProductProducerLifecycleAcknowledgement {
    guard let acknowledgement else {
        throw BridgeProductSessionProducerTestSupportError.expectedLifecycleAcknowledgement
    }
    return acknowledgement
}

func producerRegistryContentOpeningFrame(
    for request: BridgeProductContentRequest
) -> BridgeProductProducerFrame {
    .content(
        BridgeProductContentFrame(
            header: .accepted(for: request.admission),
            payload: Data()
        )
    )
}
