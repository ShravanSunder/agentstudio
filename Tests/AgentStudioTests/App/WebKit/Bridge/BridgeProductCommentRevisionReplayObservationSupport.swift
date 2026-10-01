import Foundation

@testable import AgentStudio
@testable import AgentStudioBridge

enum CommentRevisionReplayProducerBatchOutcome: Sendable, CustomStringConvertible {
    case sealed(batch: BridgeProductCommentCatalogBatch)
    case finished(reason: BridgePaneAnnotationProducerFinishReason)
    case streamEnded

    var description: String {
        switch self {
        case .sealed(let batch):
            "sealed(base=\(batch.baseRevision), target=\(batch.targetRevision))"
        case .finished(let reason):
            "finished(reason: \(reason))"
        case .streamEnded:
            "streamEnded"
        }
    }
}

enum CommentRevisionReplayHandoffDecision: Sendable {
    case waitingForRetirement(predecessorID: UUID)
    case publisherInstalled
}

actor CommentRevisionReplayProducerObservationReader {
    private let events: AsyncStream<BridgePaneAnnotationProducerObservation>

    init(_ events: AsyncStream<BridgePaneAnnotationProducerObservation>) {
        self.events = events
    }

    func nextOpenedProducerID(handle: String) async -> UUID? {
        for await event in events {
            guard case .opened(let observedHandle, let producerID) = event,
                observedHandle == handle
            else { continue }
            return producerID
        }
        return nil
    }

    func nextSealedBatch(
        handle: String,
        producerID: UUID
    ) async -> CommentRevisionReplayProducerBatchOutcome {
        for await event in events {
            switch event {
            case .opened:
                continue
            case .sealed(let observedHandle, let observedProducerID, let batch)
            where observedHandle == handle && observedProducerID == producerID:
                return .sealed(batch: batch)
            case .finished(let observedHandle, let observedProducerID, let reason)
            where observedHandle == handle && observedProducerID == producerID:
                return .finished(reason: reason)
            default:
                continue
            }
        }
        return .streamEnded
    }

    func nextHandoffDecision(
        handle: String,
        producerID: UUID
    ) async -> CommentRevisionReplayHandoffDecision? {
        for await event in events {
            switch event {
            case .waitingForRetirement(let observedHandle, let observedProducerID, let predecessorID)
            where observedHandle == handle && observedProducerID == producerID:
                return .waitingForRetirement(predecessorID: predecessorID)
            case .publisherInstalled(let observedHandle, let observedProducerID)
            where observedHandle == handle && observedProducerID == producerID:
                return .publisherInstalled
            default:
                continue
            }
        }
        return nil
    }
}

func requireSealedBatch(
    _ outcome: CommentRevisionReplayProducerBatchOutcome,
    milestone: String
) throws -> BridgeProductCommentCatalogBatch {
    switch outcome {
    case .sealed(let batch):
        return batch
    case .finished(let reason):
        throw CommentRevisionReplaySealedBatchFailure(
            message: "Expected a sealed catalog batch for \(milestone), but producer finished: \(reason)"
        )
    case .streamEnded:
        throw CommentRevisionReplaySealedBatchFailure(
            message: "Expected a sealed catalog batch for \(milestone), but producer observation stream ended"
        )
    }
}

private struct CommentRevisionReplaySealedBatchFailure: Error, Sendable, CustomStringConvertible {
    let message: String

    var description: String { message }
}
