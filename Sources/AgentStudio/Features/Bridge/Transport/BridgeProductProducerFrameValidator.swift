import Foundation

enum BridgeProductProducerFrameValidationError: Error, Equatable {
    case rejected(BridgeProductProducerEnqueueRejection)

    var rejection: BridgeProductProducerEnqueueRejection {
        switch self {
        case .rejected(let rejection): rejection
        }
    }
}

enum BridgeProductProducerFrameValidator {
    static func encode(
        for producerKey: BridgeProductProducerKey,
        sequence: Int,
        intent: BridgeProductProducerEnqueueIntent,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> Data {
        let frame = try build(sequence)
        guard frame.sequence == sequence else {
            throw BridgeProductProducerFrameValidationError.rejected(.frameIdentityMismatch)
        }
        if let rejection = rejection(for: frame, producerKey: producerKey) {
            throw BridgeProductProducerFrameValidationError.rejected(rejection)
        }
        guard frameMatchesIntent(frame, intent: intent) else {
            throw BridgeProductProducerFrameValidationError.rejected(.frameLifecycleMismatch)
        }
        return try frame.encode()
    }

    private static func rejection(
        for frame: BridgeProductProducerFrame,
        producerKey: BridgeProductProducerKey
    ) -> BridgeProductProducerEnqueueRejection? {
        switch (frame, producerKey) {
        case (.metadata(let metadataFrame), .metadata(let metadataKey)):
            let identity = metadataFrame.producerFrameIdentity
            let correlation = metadataKey.request.correlation
            let matches =
                identity.metadataStreamId == correlation.metadataStreamId
                && identity.paneSessionId == correlation.paneSessionId
                && identity.wireVersion == correlation.wireVersion
                && identity.workerInstanceId == correlation.workerInstanceId
            guard matches else { return .frameIdentityMismatch }
            if case .metadataStreamAccepted(let acceptedFrame) = metadataFrame,
                acceptedFrame.resumeDisposition != metadataKey.expectedResumeDisposition
            {
                return .frameIdentityMismatch
            }
            return nil
        case (.content(let contentFrame), .content(let request)):
            guard case .accepted(let header) = contentFrame.header else { return nil }
            return header == BridgeProductContentAcceptedHeader(admission: request.admission)
                ? nil : .frameIdentityMismatch
        default:
            return .frameKindMismatch
        }
    }

    private static func frameMatchesIntent(
        _ frame: BridgeProductProducerFrame,
        intent: BridgeProductProducerEnqueueIntent
    ) -> Bool {
        switch intent {
        case .requiredOpening: frame.isRequiredOpening && !frame.isTerminal
        case .nonterminal: !frame.isRequiredOpening && !frame.isTerminal
        case .terminal: !frame.isRequiredOpening && frame.isTerminal
        }
    }
}
