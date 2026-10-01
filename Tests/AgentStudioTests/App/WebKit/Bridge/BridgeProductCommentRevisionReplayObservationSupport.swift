import Foundation
import Synchronization

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
            recordCommentProducerObservation(event, stage: "opened")
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
            recordCommentProducerObservation(event, stage: "sealed")
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
            recordCommentProducerObservation(event, stage: "handoff")
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

private func recordCommentProducerObservation(
    _ event: BridgePaneAnnotationProducerObservation,
    stage: String
) {
    let detail: String
    switch event {
    case .opened(let handle, let producerID):
        detail = "opened handle=\(handle) producer=\(producerID)"
    case .waitingForRetirement(let handle, let producerID, let predecessorID):
        detail = "waiting handle=\(handle) producer=\(producerID) predecessor=\(predecessorID)"
    case .publisherInstalled(let handle, let producerID):
        detail = "installed handle=\(handle) producer=\(producerID)"
    case .sealed(let handle, let producerID, let batch):
        detail =
            "sealed handle=\(handle) producer=\(producerID) base=\(batch.baseRevision) target=\(batch.targetRevision) scope=\(batch.scopeRevision) puts=\(batch.puts.count) deletes=\(batch.deletes.count)"
    case .finished(let handle, let producerID, let reason):
        detail = "finished handle=\(handle) producer=\(producerID) reason=\(reason)"
    }
    recordCommentFixtureDiagnostic("C11_PRODUCER[\(stage)] \(detail)")
}

private let commentDiagnosticWriteLock = Mutex(())

func recordCommentFixtureDiagnostic(_ line: String) {
    guard let ledgerPath = ProcessInfo.processInfo.environment["AGENTSTUDIO_HELD_STEP_LOG"] else { return }
    let logURL = URL(fileURLWithPath: ledgerPath).deletingPathExtension()
        .appendingPathExtension("producer-observations.log")
    commentDiagnosticWriteLock.withLock { _ in
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data("\(line)\n".utf8))
    }
}

@MainActor
func withCommentProducerDiagnostics<TValue>(
    source: BridgePaneAnnotationNotificationSource,
    operation: @MainActor () async throws -> TValue
) async throws -> TValue {
    let observation = await source.observeProducerEvents()
    recordCommentFixtureDiagnostic("C11_TAP_STARTED sourceWorktree=\(await source.admittedWorktreeID() ?? "nil")")
    let diagnosticTask = Task { @MainActor in
        for await event in observation.events {
            recordCommentProducerObservation(event, stage: "live")
        }
    }
    do {
        let result = try await operation()
        await source.stopObservingProducerEvents(id: observation.id)
        diagnosticTask.cancel()
        await diagnosticTask.value
        return result
    } catch {
        await source.stopObservingProducerEvents(id: observation.id)
        diagnosticTask.cancel()
        await diagnosticTask.value
        throw error
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
