import Foundation

enum FilesystemConfigurationIntentAdmissionPlanner {
    struct OrderedIntent: Sendable {
        let sourceID: FilesystemSourceID
        let intent: FilesystemSourceConfigurationIntent
    }

    struct Plan: Sendable {
        let batch: FilesystemSourceConfigurationIntentBatch
        let orderedIntents: [OrderedIntent]
    }

    enum PreparationResult: Sendable {
        case planned(Plan)
        case rejected(FilesystemConfigurationIntentBatchRejection)
    }

    static func prepare(
        _ batch: FilesystemSourceConfigurationIntentBatch
    ) -> PreparationResult {
        let sourceMismatches: Set<FilesystemConfigurationIntentSourceMismatch> = Set(
            batch.intentsBySourceID.compactMap { keyedSourceID, intent in
                let representedSourceIDs = representedSourceIDs(for: intent)
                guard representedSourceIDs != [keyedSourceID] else {
                    return nil
                }
                return FilesystemConfigurationIntentSourceMismatch(
                    keyedSourceID: keyedSourceID,
                    representedSourceIDs: representedSourceIDs
                )
            }
        )
        guard sourceMismatches.isEmpty else {
            return .rejected(.sourceMismatches(sourceMismatches))
        }

        let orderedIntents = batch.intentsBySourceID
            .map { sourceID, intent in
                (
                    orderedIntent: OrderedIntent(sourceID: sourceID, intent: intent),
                    phase: admissionPhase(intent),
                    sourceKindOrdinal: sourceKindOrdinal(sourceID.kind),
                    rootIdentityText: sourceID.rootID.uuidString
                )
            }
            .sorted { left, right in
                if left.phase != right.phase {
                    return left.phase < right.phase
                }
                if left.sourceKindOrdinal != right.sourceKindOrdinal {
                    return left.sourceKindOrdinal < right.sourceKindOrdinal
                }
                return left.rootIdentityText < right.rootIdentityText
            }
            .map(\.orderedIntent)

        return .planned(Plan(batch: batch, orderedIntents: orderedIntents))
    }

    private static func representedSourceIDs(
        for intent: FilesystemSourceConfigurationIntent
    ) -> Set<FilesystemSourceID> {
        switch intent {
        case .install(let installationIntent):
            [installationIntent.desiredConfiguration.sourceID]
        case .replace(let replacementIntent):
            [
                replacementIntent.exactPriorBinding.registration.sourceID,
                replacementIntent.desiredConfiguration.sourceID,
            ]
        case .remove(let removalIntent):
            [removalIntent.exactPriorBinding.registration.sourceID]
        }
    }

    private static func admissionPhase(
        _ intent: FilesystemSourceConfigurationIntent
    ) -> Int {
        switch intent {
        case .remove:
            0
        case .replace:
            1
        case .install:
            2
        }
    }

    private static func sourceKindOrdinal(
        _ sourceKind: FilesystemSourceKind
    ) -> Int {
        switch sourceKind {
        case .watchedParentMembership:
            0
        case .registeredWorktreeContent:
            1
        }
    }
}
