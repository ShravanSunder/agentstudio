import Foundation

struct BridgeProductMetadataProducerKey: Equatable {
    let expectedResumeDisposition: BridgeProductMetadataStreamResumeDisposition
    let request: BridgeProductMetadataStreamRequest
}

enum BridgeProductProducerKey: Equatable {
    case metadata(BridgeProductMetadataProducerKey)
    case content(BridgeProductContentRequest)

    var isContent: Bool {
        guard case .content = self else { return false }
        return true
    }

    var maximumAdmittedSequence: Int {
        switch self {
        case .metadata:
            BridgeProductWireContract.maximumSafeInteger
        case .content:
            Int(UInt32.max)
        }
    }
}

enum BridgeProductProducerWorkLifecycle: Equatable {
    case running
    case stopped
    case stopping
}

enum BridgeProductProducerEnqueueIntent {
    case nonterminal
    case requiredOpening
    case terminal
}

struct BridgeProductProducerState {
    let key: BridgeProductProducerKey
    let metadataStreamSequenceRewindFloor: Int?
    var nextMetadataStreamSequence: Int?
    var task: Task<Void, Never>?
    var lifecycle = BridgeProductProducerWorkLifecycle.running
    var openingFrameState = BridgeProductProducerOpeningFrameState.required
    var queuedFrames: [BridgeProductQueuedProducerFrame] = []
    var queuedByteCount = 0
    var nextContentSequence = 0
    var terminalFrameAdmitted = false
}
