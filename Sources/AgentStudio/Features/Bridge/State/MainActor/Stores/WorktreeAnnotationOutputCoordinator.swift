import Foundation

protocol WorktreeAnnotationOutputStoreAccess: Sendable {
    func prepareOutput(
        _ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func inspectOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func repeatOutputAttempt(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID,
        repeatedAttemptID: WorktreeAnnotationOutputAttemptID,
        destinationPath: String?,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        effectError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func markOutputAttemptFinalizationFailed(
        attemptID: WorktreeAnnotationOutputAttemptID,
        cleanupError: String,
        now: Date
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int
}

struct WorktreeAnnotationOutputRequest: Sendable {
    let outputKind: WorktreeAnnotationOutputKind
    let sessionDetail: WorktreeAnnotationSessionDetail
    let selectedMessages: [WorktreeAnnotationSQLiteRepository.OutputMessageSelection]
    let placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
    let sessionLabel: String
    let worktreeLabel: String
    let comparisonLabel: String?
}

struct WorktreeAnnotationOutputLabels: Equatable, Sendable {
    let sessionLabel: String
    let worktreeLabel: String
    let comparisonLabel: String?
}

struct WorktreeAnnotationOutputResultSummary: Equatable, Sendable {
    let attemptID: WorktreeAnnotationOutputAttemptID
    let sessionID: WorktreeAnnotationSessionID
    let outputKind: WorktreeAnnotationOutputKind
    let messageCount: Int
    let destinationFilename: String?

    init(_ output: WorktreeAnnotationSQLiteRepository.PreparedOutput) {
        attemptID = output.attempt.id
        sessionID = output.attempt.sessionID
        outputKind = output.attempt.outputKind
        messageCount = output.memberships.count
        destinationFilename = output.attempt.destinationPath.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
    }
}

enum WorktreeAnnotationOutputCommandOutcome: Equatable, Sendable {
    case destinationCancelled
    case destinationSelectionFailed(String)
    case succeeded(WorktreeAnnotationOutputResultSummary)
    case effectFailed(summary: WorktreeAnnotationOutputResultSummary, effectError: String)
    case effectAndCleanupFailed(
        summary: WorktreeAnnotationOutputResultSummary,
        effectError: String,
        cleanupError: String
    )
    case partialSuccess(summary: WorktreeAnnotationOutputResultSummary, finalizationError: String)

    var summary: WorktreeAnnotationOutputResultSummary? {
        switch self {
        case .destinationCancelled, .destinationSelectionFailed:
            nil
        case .succeeded(let summary):
            summary
        case .effectFailed(let summary, _),
            .effectAndCleanupFailed(let summary, _, _),
            .partialSuccess(let summary, _):
            summary
        }
    }
}

package enum WorktreeAnnotationOutputEffectKind: Equatable, Sendable {
    case clipboardMarkdown
    case jsonFile
}

package struct WorktreeAnnotationOutputEffectRequest: Equatable, Sendable {
    package let attemptID: UUID
    package let outputKind: WorktreeAnnotationOutputEffectKind
    package let contentType: String
    package let exactBytes: Data
    package let destinationPath: String?

    package init(
        attemptID: UUID,
        outputKind: WorktreeAnnotationOutputEffectKind,
        contentType: String,
        exactBytes: Data,
        destinationPath: String?
    ) {
        self.attemptID = attemptID
        self.outputKind = outputKind
        self.contentType = contentType
        self.exactBytes = exactBytes
        self.destinationPath = destinationPath
    }
}

package enum WorktreeAnnotationOutputEffectOutcome: Equatable, Sendable {
    case succeeded
    case failed(String)
}

package enum WorktreeAnnotationOutputDestinationOutcome: Equatable, Sendable {
    case selected(path: String)
    case cancelled
    case failed(String)
}

package protocol WorktreeAnnotationOutputEffect: Sendable {
    func chooseJSONDestination(
        suggestedFilename: String
    ) async -> WorktreeAnnotationOutputDestinationOutcome

    func perform(
        _ request: WorktreeAnnotationOutputEffectRequest
    ) async -> WorktreeAnnotationOutputEffectOutcome
}

enum WorktreeAnnotationOutputExecutionResult: Equatable, Sendable {
    case destinationCancelled
    case destinationSelectionFailed(String)
    case succeeded(WorktreeAnnotationSQLiteRepository.PreparedOutput)
    case effectFailed(
        effectError: String,
        output: WorktreeAnnotationSQLiteRepository.PreparedOutput
    )
    case effectAndCleanupFailed(
        output: WorktreeAnnotationSQLiteRepository.PreparedOutput,
        effectError: String,
        cleanupError: String
    )
    case partialSuccess(
        output: WorktreeAnnotationSQLiteRepository.PreparedOutput,
        finalizationError: String
    )

    var commandOutcome: WorktreeAnnotationOutputCommandOutcome {
        switch self {
        case .destinationCancelled:
            .destinationCancelled
        case .destinationSelectionFailed(let error):
            .destinationSelectionFailed(error)
        case .succeeded(let output):
            .succeeded(.init(output))
        case .effectFailed(let effectError, let output):
            .effectFailed(summary: .init(output), effectError: effectError)
        case .effectAndCleanupFailed(let output, let effectError, let cleanupError):
            .effectAndCleanupFailed(
                summary: .init(output),
                effectError: effectError,
                cleanupError: cleanupError
            )
        case .partialSuccess(let output, let finalizationError):
            .partialSuccess(summary: .init(output), finalizationError: finalizationError)
        }
    }
}

enum WorktreeAnnotationOutputCoordinatorError: Error, Equatable, Sendable {
    case cleanupProofUnavailable
    case invalidDestination
}

package actor WorktreeAnnotationOutputCoordinator {
    typealias NowProvider = @Sendable () -> Date
    typealias AttemptIDProvider = @Sendable () async -> WorktreeAnnotationOutputAttemptID

    private struct CancellationProof: Sendable {
        let effectError: String
    }

    private struct MaterializedOutput: Sendable {
        let snapshot: WorktreeAnnotationBatchSnapshot
        let exactBytes: Data
        let contentType: String
        let markdownPresentation: WorktreeAnnotationMarkdownPresentationContext?
    }

    private let store: any WorktreeAnnotationOutputStoreAccess
    private let effect: any WorktreeAnnotationOutputEffect
    private let now: NowProvider
    private let generateAttemptID: AttemptIDProvider
    private var cancellationProofByAttemptID: [WorktreeAnnotationOutputAttemptID: CancellationProof] = [:]

    init(
        store: any WorktreeAnnotationOutputStoreAccess,
        effect: any WorktreeAnnotationOutputEffect,
        now: @escaping NowProvider = Date.init,
        generateAttemptID: @escaping AttemptIDProvider = {
            WorktreeAnnotationOutputAttemptID.generate()
        }
    ) {
        self.store = store
        self.effect = effect
        self.now = now
        self.generateAttemptID = generateAttemptID
    }

    package init(
        store: WorktreeAnnotationStore,
        effect: any WorktreeAnnotationOutputEffect
    ) {
        self.store = store
        self.effect = effect
        now = Date.init
        generateAttemptID = {
            WorktreeAnnotationOutputAttemptID.generate()
        }
    }

    func executeNew(
        _ request: WorktreeAnnotationOutputRequest
    ) async throws -> WorktreeAnnotationOutputExecutionResult {
        let destinationResolution = await resolveDestination(outputKind: request.outputKind)
        let destinationPath: String?
        switch destinationResolution {
        case .resolved(let path):
            destinationPath = path
        case .cancelled:
            return .destinationCancelled
        case .failed(let error):
            return .destinationSelectionFailed(error)
        }
        let createdAt = now()
        let attemptID = await generateAttemptID()
        let materialization = try await Self.materialize(
            request: request,
            attemptID: attemptID,
            createdAt: createdAt
        )
        let orderedSelection = materialization.snapshot.entries.map {
            WorktreeAnnotationSQLiteRepository.OutputMessageSelection(
                messageID: $0.messageID,
                expectedSavedRevision: $0.savedRevision
            )
        }
        let prepared = try await store.prepareOutput(
            .init(
                attemptID: attemptID,
                sessionID: request.sessionDetail.session.id,
                outputKind: request.outputKind,
                formatVersion: materialization.snapshot.formatVersion,
                contentType: materialization.contentType,
                canonicalSnapshot: materialization.snapshot,
                exactBytes: materialization.exactBytes,
                markdownPresentation: materialization.markdownPresentation,
                destinationPath: destinationPath,
                repeatedFromAttemptID: nil,
                selectedMessages: orderedSelection,
                now: createdAt
            )
        )
        return await performEffect(for: prepared)
    }

    func executeRepeat(
        sourceAttemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationOutputExecutionResult {
        let source = try await store.inspectOutputAttempt(attemptID: sourceAttemptID)
        let destinationResolution = await resolveDestination(outputKind: source.attempt.outputKind)
        let destinationPath: String?
        switch destinationResolution {
        case .resolved(let path):
            destinationPath = path
        case .cancelled:
            return .destinationCancelled
        case .failed(let error):
            return .destinationSelectionFailed(error)
        }
        let repeated = try await store.repeatOutputAttempt(
            sourceAttemptID: sourceAttemptID,
            repeatedAttemptID: await generateAttemptID(),
            destinationPath: destinationPath,
            now: now()
        )
        return await performEffect(for: repeated)
    }

    func retryCancellationCleanup(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationSQLiteRepository.PreparedOutput {
        guard let proof = cancellationProofByAttemptID[attemptID] else {
            throw WorktreeAnnotationOutputCoordinatorError.cleanupProofUnavailable
        }
        let cancelled = try await store.cancelOutputAttempt(
            attemptID: attemptID,
            effectError: proof.effectError,
            now: now()
        )
        cancellationProofByAttemptID.removeValue(forKey: attemptID)
        return cancelled
    }

    package func recoverPreparedAttemptsAsUnknown() async throws -> Int {
        cancellationProofByAttemptID.removeAll()
        return try await store.markPreparedOutputAttemptsUnknown(now: now())
    }

    private func performEffect(
        for prepared: WorktreeAnnotationSQLiteRepository.PreparedOutput
    ) async -> WorktreeAnnotationOutputExecutionResult {
        let outcome = await effect.perform(
            .init(
                attemptID: prepared.attempt.id.rawValue,
                outputKind: prepared.attempt.outputKind == .clipboardMarkdown
                    ? .clipboardMarkdown
                    : .jsonFile,
                contentType: prepared.attempt.contentType,
                exactBytes: prepared.attempt.exactBytes,
                destinationPath: prepared.attempt.destinationPath
            )
        )
        switch outcome {
        case .succeeded:
            return await finalizeKnownSuccess(prepared)
        case .failed(let effectError):
            return await cancelKnownFailure(prepared, effectError: effectError)
        }
    }

    private func finalizeKnownSuccess(
        _ prepared: WorktreeAnnotationSQLiteRepository.PreparedOutput
    ) async -> WorktreeAnnotationOutputExecutionResult {
        do {
            let finalized = try await store.finalizeOutputAttempt(
                attemptID: prepared.attempt.id,
                eventKind: prepared.attempt.outputKind == .clipboardMarkdown ? .copied : .exported,
                now: now()
            )
            return .succeeded(finalized)
        } catch {
            let finalizationError = String(describing: error)
            let recordedOutput: WorktreeAnnotationSQLiteRepository.PreparedOutput
            do {
                recordedOutput = try await store.markOutputAttemptFinalizationFailed(
                    attemptID: prepared.attempt.id,
                    cleanupError: finalizationError,
                    now: now()
                )
            } catch {
                recordedOutput = prepared
            }
            return .partialSuccess(
                output: recordedOutput,
                finalizationError: finalizationError
            )
        }
    }

    private func cancelKnownFailure(
        _ prepared: WorktreeAnnotationSQLiteRepository.PreparedOutput,
        effectError: String
    ) async -> WorktreeAnnotationOutputExecutionResult {
        do {
            let cancelled = try await store.cancelOutputAttempt(
                attemptID: prepared.attempt.id,
                effectError: effectError,
                now: now()
            )
            return .effectFailed(effectError: effectError, output: cancelled)
        } catch {
            cancellationProofByAttemptID[prepared.attempt.id] = .init(effectError: effectError)
            return .effectAndCleanupFailed(
                output: prepared,
                effectError: effectError,
                cleanupError: String(describing: error)
            )
        }
    }

    @concurrent nonisolated private static func materialize(
        request: WorktreeAnnotationOutputRequest,
        attemptID: WorktreeAnnotationOutputAttemptID,
        createdAt: Date
    ) async throws -> MaterializedOutput {
        let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            .init(
                batchID: attemptID,
                createdAt: createdAt,
                sessionDetail: request.sessionDetail,
                selectedMessages: request.selectedMessages,
                placementsByThreadID: request.placementsByThreadID,
                sessionLabel: request.sessionLabel,
                worktreeLabel: request.worktreeLabel,
                comparisonLabel: request.comparisonLabel
            )
        )
        switch request.outputKind {
        case .clipboardMarkdown:
            let presentation = WorktreeAnnotationMarkdownPresentationContext(
                worktreeLabel: request.worktreeLabel,
                comparisonLabel: request.comparisonLabel
            )
            return MaterializedOutput(
                snapshot: snapshot,
                exactBytes: WorktreeAnnotationBatchProjector.markdownData(
                    for: snapshot,
                    presentation: presentation
                ),
                contentType: "text/markdown; charset=utf-8",
                markdownPresentation: presentation
            )
        case .jsonFile:
            return try MaterializedOutput(
                snapshot: snapshot,
                exactBytes: WorktreeAnnotationBatchProjector.jsonData(for: snapshot),
                contentType: "application/json; charset=utf-8",
                markdownPresentation: nil
            )
        }
    }

    private enum DestinationResolution {
        case resolved(String?)
        case cancelled
        case failed(String)
    }

    private func resolveDestination(
        outputKind: WorktreeAnnotationOutputKind
    ) async -> DestinationResolution {
        switch outputKind {
        case .clipboardMarkdown:
            return .resolved(nil)
        case .jsonFile:
            switch await effect.chooseJSONDestination(
                suggestedFilename: "AgentStudio Review Comments.json"
            ) {
            case .selected(let path):
                guard !path.isEmpty else {
                    return .failed("The selected export destination was empty.")
                }
                return .resolved(path)
            case .cancelled:
                return .cancelled
            case .failed(let error):
                return .failed(error)
            }
        }
    }
}
