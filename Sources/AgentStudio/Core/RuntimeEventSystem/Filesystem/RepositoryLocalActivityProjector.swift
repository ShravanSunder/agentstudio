import Foundation

package struct RepositoryLocalActivityParticipantIdentity: Hashable, Sendable {
    package let scopeKey: String
    package let generation: UInt64

    package init(scopeKey: String, generation: UInt64) {
        self.scopeKey = scopeKey
        self.generation = generation
    }
}

package struct RepositoryLocalActivityParticipant: Equatable, Sendable {
    package let scopeKey: String
    package let generation: UInt64
    package let volumeIdentifier: String
    package let repositoryStableKeys: Set<String>

    package var identity: RepositoryLocalActivityParticipantIdentity {
        RepositoryLocalActivityParticipantIdentity(scopeKey: scopeKey, generation: generation)
    }

    package init(
        scopeKey: String,
        generation: UInt64,
        volumeIdentifier: String,
        repositoryStableKeys: Set<String>
    ) {
        self.scopeKey = scopeKey
        self.generation = generation
        self.volumeIdentifier = volumeIdentifier
        self.repositoryStableKeys = repositoryStableKeys
    }
}

package enum RepositoryLocalActivityObservationDisposition: Equatable, Sendable {
    case progressOnly
    case qualifying
    case coverageLost
}

package struct RepositoryLocalActivityObservedEvent: Equatable, Sendable {
    package let scopeKey: String
    package let generation: UInt64
    package let eventID: UInt64
    package let disposition: RepositoryLocalActivityObservationDisposition
    package let observedAt: Date

    package init(
        scopeKey: String,
        generation: UInt64,
        eventID: UInt64,
        disposition: RepositoryLocalActivityObservationDisposition,
        observedAt: Date
    ) {
        self.scopeKey = scopeKey
        self.generation = generation
        self.eventID = eventID
        self.disposition = disposition
        self.observedAt = observedAt
    }
}

package struct RepositoryLocalActivityBarrier: Equatable, Sendable {
    package let deliveredEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64]
    package let completedAt: Date

    package init(
        deliveredEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64],
        completedAt: Date
    ) {
        self.deliveredEventIDByParticipant = deliveredEventIDByParticipant
        self.completedAt = completedAt
    }
}

package actor RepositoryLocalActivityProjector {
    package typealias CommitSink = @Sendable (RepositoryLocalActivityCommit) async throws -> Void

    private struct DeferredParticipantReplacement {
        let participants: [RepositoryLocalActivityParticipant]
        let coverageRestartedAt: Date
    }

    private let commitSink: CommitSink
    private var participantByScopeKey: [String: RepositoryLocalActivityParticipant] = [:]
    private var processedEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64] = [:]
    private var pendingQualifyingActivityByRepositoryStableKey: [String: Date] = [:]
    private var pendingCoverageRestartByRepositoryStableKey: [String: Date] = [:]
    private var isCommitInFlight = false
    private var deferredParticipantReplacement: DeferredParticipantReplacement?

    package init(commitSink: @escaping CommitSink) {
        self.commitSink = commitSink
    }

    package func replaceParticipants(
        _ participants: [RepositoryLocalActivityParticipant],
        coverageRestartedAt: Date
    ) {
        if isCommitInFlight {
            deferredParticipantReplacement = DeferredParticipantReplacement(
                participants: participants,
                coverageRestartedAt: coverageRestartedAt
            )
            return
        }
        applyParticipantReplacement(
            participants,
            coverageRestartedAt: coverageRestartedAt
        )
    }

    package func ingest(_ observation: RepositoryLocalActivityObservedEvent) {
        guard
            let participant = participantByScopeKey[observation.scopeKey],
            participant.generation == observation.generation
        else { return }
        let identity = participant.identity
        processedEventIDByParticipant[identity] = max(
            processedEventIDByParticipant[identity] ?? 0,
            observation.eventID
        )
        switch observation.disposition {
        case .progressOnly:
            break
        case .qualifying:
            for repositoryStableKey in participant.repositoryStableKeys {
                pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey] = max(
                    pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey]
                        ?? observation.observedAt,
                    observation.observedAt
                )
            }
        case .coverageLost:
            restartCoverage(
                for: participant.repositoryStableKeys,
                at: observation.observedAt
            )
        }
    }

    @discardableResult
    package func commitBarrier(_ barrier: RepositoryLocalActivityBarrier) async throws -> Bool {
        guard !isCommitInFlight else { return false }
        let currentParticipants = participantByScopeKey.values.sorted {
            $0.scopeKey < $1.scopeKey
        }
        for participant in currentParticipants {
            guard
                let deliveredEventID = barrier.deliveredEventIDByParticipant[participant.identity],
                let processedEventID = processedEventIDByParticipant[participant.identity],
                processedEventID >= deliveredEventID
            else { return false }
        }

        let capturedQualifyingActivity = pendingQualifyingActivityByRepositoryStableKey
        let capturedCoverageRestarts = pendingCoverageRestartByRepositoryStableKey
        let repositoryStableKeys = Set(capturedQualifyingActivity.keys)
            .union(capturedCoverageRestarts.keys)
        let repositoryUpdates = repositoryStableKeys.sorted().map { repositoryStableKey in
            RepositoryLocalActivityUpdate(
                repositoryStableKey: repositoryStableKey,
                qualifyingActivityAt: capturedQualifyingActivity[repositoryStableKey],
                coverageChange: capturedCoverageRestarts[repositoryStableKey].map {
                    .restart(at: $0)
                } ?? .unchanged
            )
        }
        let cursorWatermarks = try Self.cursorWatermarks(
            participants: currentParticipants,
            deliveredEventIDByParticipant: barrier.deliveredEventIDByParticipant,
            completedAt: barrier.completedAt
        )
        let commit = try RepositoryLocalActivityCommit(
            repositoryUpdates: repositoryUpdates,
            cursorWatermarks: cursorWatermarks,
            updatedAt: barrier.completedAt
        )

        isCommitInFlight = true
        do {
            try await commitSink(commit)
            clearCapturedPendingValues(
                qualifyingActivity: capturedQualifyingActivity,
                coverageRestarts: capturedCoverageRestarts
            )
            finishCommitCustody()
            return true
        } catch {
            finishCommitCustody()
            throw error
        }
    }

    private func applyParticipantReplacement(
        _ participants: [RepositoryLocalActivityParticipant],
        coverageRestartedAt: Date
    ) {
        let replacement = Dictionary(
            participants.map { ($0.scopeKey, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let scopeKeys = Set(participantByScopeKey.keys).union(replacement.keys)
        for scopeKey in scopeKeys {
            let previous = participantByScopeKey[scopeKey]
            let next = replacement[scopeKey]
            guard previous != next else { continue }
            restartCoverage(
                for: (previous?.repositoryStableKeys ?? []).union(next?.repositoryStableKeys ?? []),
                at: coverageRestartedAt
            )
        }
        participantByScopeKey = replacement
        let currentIdentities = Set(replacement.values.map(\.identity))
        processedEventIDByParticipant = processedEventIDByParticipant.filter {
            currentIdentities.contains($0.key)
        }
    }

    private func restartCoverage(for repositoryStableKeys: Set<String>, at timestamp: Date) {
        for repositoryStableKey in repositoryStableKeys {
            pendingCoverageRestartByRepositoryStableKey[repositoryStableKey] = max(
                pendingCoverageRestartByRepositoryStableKey[repositoryStableKey] ?? timestamp,
                timestamp
            )
        }
    }

    private func clearCapturedPendingValues(
        qualifyingActivity: [String: Date],
        coverageRestarts: [String: Date]
    ) {
        for (repositoryStableKey, capturedTimestamp) in qualifyingActivity
        where pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey] == capturedTimestamp {
            pendingQualifyingActivityByRepositoryStableKey.removeValue(forKey: repositoryStableKey)
        }
        for (repositoryStableKey, capturedTimestamp) in coverageRestarts
        where pendingCoverageRestartByRepositoryStableKey[repositoryStableKey] == capturedTimestamp {
            pendingCoverageRestartByRepositoryStableKey.removeValue(forKey: repositoryStableKey)
        }
    }

    private func finishCommitCustody() {
        isCommitInFlight = false
        if let deferredParticipantReplacement {
            self.deferredParticipantReplacement = nil
            applyParticipantReplacement(
                deferredParticipantReplacement.participants,
                coverageRestartedAt: deferredParticipantReplacement.coverageRestartedAt
            )
        }
    }

    private static func cursorWatermarks(
        participants: [RepositoryLocalActivityParticipant],
        deliveredEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64],
        completedAt: Date
    ) throws -> [RepositoryLocalActivityCursor] {
        let participantsByVolume = Dictionary(grouping: participants, by: \.volumeIdentifier)
        return try participantsByVolume.keys.sorted().compactMap { volumeIdentifier in
            guard let volumeParticipants = participantsByVolume[volumeIdentifier] else { return nil }
            let deliveredEventIDs = volumeParticipants.compactMap {
                deliveredEventIDByParticipant[$0.identity]
            }
            guard deliveredEventIDs.count == volumeParticipants.count,
                let conservativeEventID = deliveredEventIDs.min()
            else { return nil }
            return try RepositoryLocalActivityCursor(
                volumeIdentifier: volumeIdentifier,
                lastEventID: conservativeEventID,
                updatedAt: completedAt
            )
        }
    }
}
