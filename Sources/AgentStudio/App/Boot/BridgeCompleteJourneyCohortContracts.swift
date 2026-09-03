import AgentStudioBridge
import Foundation

#if DEBUG
    func bridgeCompleteJourneyUsablePaintTimeoutFailureReason(
        observedForegroundActivity: Bool,
        latestActivity: BridgePaneActivity?
    ) -> String {
        guard !observedForegroundActivity else { return "usable_paint_timeout" }
        guard let latestActivity else { return "native_activity_missing" }
        return "native_activity_never_foreground_\(latestActivity.rawValue)"
    }

    enum BridgeCompleteJourneyConfigurationError: Error {
        case disabled
        case invalidAttemptCount
        case invalidLaunchId
        case invalidMode
    }

    struct BridgeCompleteJourneyConfiguration: Decodable, Equatable {
        let attemptCount: Int
        let launchId: String

        private struct WireValue: Decodable {
            let attemptCount: Int
            let enabled: Bool
            let launchId: String
            let mode: String
        }

        static func decode(_ data: Data) throws -> Self {
            let wireValue = try JSONDecoder().decode(WireValue.self, from: data)
            guard wireValue.enabled else { throw BridgeCompleteJourneyConfigurationError.disabled }
            guard wireValue.mode == "native" else {
                throw BridgeCompleteJourneyConfigurationError.invalidMode
            }
            guard wireValue.attemptCount > 0, wireValue.attemptCount <= 10_000 else {
                throw BridgeCompleteJourneyConfigurationError.invalidAttemptCount
            }
            let allowedLaunchIdCharacters = CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-._")
            )
            guard !wireValue.launchId.isEmpty, wireValue.launchId.count <= 128,
                wireValue.launchId.unicodeScalars.allSatisfy(allowedLaunchIdCharacters.contains)
            else {
                throw BridgeCompleteJourneyConfigurationError.invalidLaunchId
            }
            return Self(
                attemptCount: wireValue.attemptCount,
                launchId: wireValue.launchId
            )
        }

        static func configURL(dataDirectory: URL) -> URL {
            cohortDirectoryURL(dataDirectory: dataDirectory).appending(path: "config.json")
        }

        static func receiptURL(dataDirectory: URL) -> URL {
            cohortDirectoryURL(dataDirectory: dataDirectory).appending(path: "native-launch.json")
        }

        private static func cohortDirectoryURL(dataDirectory: URL) -> URL {
            dataDirectory.appending(path: "bridge-complete-journey", directoryHint: .isDirectory)
        }
    }

    struct BridgeCompleteJourneyPhaseCompletion: Codable, Equatable {
        let pageApplication: Double?
        let handshakeWorker: Double?
        let sourceMetadata: Double?
        let selectionContent: Double?
        let commitPaint: Double?

        init(
            pageApplication: Double? = nil,
            handshakeWorker: Double? = nil,
            sourceMetadata: Double? = nil,
            selectionContent: Double? = nil,
            commitPaint: Double? = nil
        ) {
            self.pageApplication = pageApplication
            self.handshakeWorker = handshakeWorker
            self.sourceMetadata = sourceMetadata
            self.selectionContent = selectionContent
            self.commitPaint = commitPaint
        }

        private enum CodingKeys: String, CodingKey {
            case pageApplication
            case handshakeWorker
            case sourceMetadata
            case selectionContent
            case commitPaint
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(pageApplication, forKey: .pageApplication)
            try container.encodeIfPresent(handshakeWorker, forKey: .handshakeWorker)
            try container.encodeIfPresent(sourceMetadata, forKey: .sourceMetadata)
            try container.encodeIfPresent(selectionContent, forKey: .selectionContent)
            try container.encodeIfPresent(commitPaint, forKey: .commitPaint)
        }
    }

    struct BridgeCompleteJourneyAttempt: Encodable, Equatable {
        enum Outcome: String, Encodable {
            case succeeded
            case failed
        }

        let attemptId: String
        let durationMilliseconds: Double
        let outcome: Outcome
        let phaseCompletionElapsedMilliseconds: BridgeCompleteJourneyPhaseCompletion
        let failureReason: String?

        private enum CodingKeys: String, CodingKey {
            case attemptId
            case durationMilliseconds
            case outcome
            case phaseCompletionElapsedMilliseconds
            case failureReason
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attemptId, forKey: .attemptId)
            try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
            try container.encode(outcome, forKey: .outcome)
            try container.encode(
                phaseCompletionElapsedMilliseconds,
                forKey: .phaseCompletionElapsedMilliseconds
            )
            if outcome == .failed {
                try container.encode(failureReason ?? "unknown_failure", forKey: .failureReason)
            }
        }

        func failing(reason: String) -> Self {
            Self(
                attemptId: attemptId,
                durationMilliseconds: durationMilliseconds,
                outcome: .failed,
                phaseCompletionElapsedMilliseconds: phaseCompletionElapsedMilliseconds,
                failureReason: reason
            )
        }
    }

    struct BridgeCompleteJourneyTelemetryProofObservation: Equatable {
        let drainFailed: Bool
        let lossy: Bool
        let missingReport: Bool
        let nativeBatchSequenceGapCount: Int
        let optionalLossCount: Int
        let proofEligible: Bool
        let requiredLossCount: Int
        let workerSequenceGapCount: Int

        static func missing(drainFailed: Bool) -> Self {
            Self(
                drainFailed: drainFailed,
                lossy: false,
                missingReport: true,
                nativeBatchSequenceGapCount: 0,
                optionalLossCount: 0,
                proofEligible: false,
                requiredLossCount: 0,
                workerSequenceGapCount: 0
            )
        }

        var attemptFailureReason: String? {
            if missingReport { return "telemetry_report_missing" }
            if drainFailed { return "telemetry_not_drained" }
            return nil
        }
    }

    struct BridgeCompleteJourneyTelemetryProof: Encodable, Equatable {
        let expectedAttemptCount: Int
        private(set) var observedPaneReportCount = 0
        private(set) var missingPaneReportCount = 0
        private(set) var proofEligiblePaneReportCount = 0
        private(set) var lossyPaneReportCount = 0
        private(set) var requiredLossCount = 0
        private(set) var optionalLossCount = 0
        private(set) var workerSequenceGapCount = 0
        private(set) var nativeBatchSequenceGapCount = 0
        private(set) var drainFailureCount = 0

        mutating func merge(_ observation: BridgeCompleteJourneyTelemetryProofObservation) {
            if observation.missingReport {
                missingPaneReportCount += 1
            } else {
                observedPaneReportCount += 1
                if observation.proofEligible { proofEligiblePaneReportCount += 1 }
                if observation.lossy { lossyPaneReportCount += 1 }
                requiredLossCount += observation.requiredLossCount
                optionalLossCount += observation.optionalLossCount
                workerSequenceGapCount += observation.workerSequenceGapCount
                nativeBatchSequenceGapCount += observation.nativeBatchSequenceGapCount
            }
            if observation.drainFailed { drainFailureCount += 1 }
        }
    }

    struct BridgeCompleteJourneyAttemptsByJourney: Encodable, Equatable {
        var firstFile: [BridgeCompleteJourneyAttempt]
        var firstReview: [BridgeCompleteJourneyAttempt]
        var fileToReview: [BridgeCompleteJourneyAttempt]
        var reviewToFile: [BridgeCompleteJourneyAttempt]
    }

    struct BridgeCompleteJourneyNativeLaunchReceipt: Encodable, Equatable {
        let launchId: String
        let attemptsByJourney: BridgeCompleteJourneyAttemptsByJourney
        let telemetryProof: BridgeCompleteJourneyTelemetryProof
    }
#endif
