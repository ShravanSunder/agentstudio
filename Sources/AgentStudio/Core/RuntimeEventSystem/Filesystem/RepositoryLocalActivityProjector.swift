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

package struct RepositoryLocalActivityObservedEvent: Equatable, Sendable {
    package let scopeKey: String
    package let generation: UInt64
    package let eventID: UInt64
    package let qualifyingRepositoryStableKeys: Set<String>
    package let coverageLostRepositoryStableKeys: Set<String>
    package let observedAt: Date

    package init(
        scopeKey: String,
        generation: UInt64,
        eventID: UInt64,
        qualifyingRepositoryStableKeys: Set<String> = [],
        coverageLostRepositoryStableKeys: Set<String> = [],
        observedAt: Date
    ) {
        self.scopeKey = scopeKey
        self.generation = generation
        self.eventID = eventID
        self.qualifyingRepositoryStableKeys = qualifyingRepositoryStableKeys
        self.coverageLostRepositoryStableKeys = coverageLostRepositoryStableKeys
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
    package typealias AuthorityRevocationSink = @Sendable (Set<String>) async -> Void

    private struct BufferedObservation {
        var processedEventID: UInt64
        var qualifyingActivityByRepositoryStableKey: [String: Date]
        var coverageRestartByRepositoryStableKey: [String: Date]
    }

    private struct DeferredParticipantReplacement {
        let participants: [RepositoryLocalActivityParticipant]
        let coverageRestartedAt: Date
    }

    private let commitSink: CommitSink
    private let authorityRevocationSink: AuthorityRevocationSink
    private var participantByScopeKey: [String: RepositoryLocalActivityParticipant] = [:]
    private var bufferedObservationByParticipant: [RepositoryLocalActivityParticipantIdentity: BufferedObservation] =
        [:]
    private var processedEventIDByParticipant: [RepositoryLocalActivityParticipantIdentity: UInt64] = [:]
    private var pendingQualifyingActivityByRepositoryStableKey: [String: Date] = [:]
    private var pendingCoverageRestartByRepositoryStableKey: [String: Date] = [:]
    private var isCommitInFlight = false
    private var deferredParticipantReplacement: DeferredParticipantReplacement?

    package init(
        authorityRevocationSink: @escaping AuthorityRevocationSink = { _ in },
        commitSink: @escaping CommitSink
    ) {
        self.authorityRevocationSink = authorityRevocationSink
        self.commitSink = commitSink
    }

    package func revokeAuthority(for repositoryStableKeys: Set<String>) async {
        guard !repositoryStableKeys.isEmpty else { return }
        await authorityRevocationSink(repositoryStableKeys)
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
        let identity = RepositoryLocalActivityParticipantIdentity(
            scopeKey: observation.scopeKey,
            generation: observation.generation
        )
        guard let participant = participantByScopeKey[observation.scopeKey],
            participant.identity == identity
        else {
            bufferUnverifiedObservation(observation, identity: identity)
            return
        }
        applyObservation(observation, participant: participant)
    }

    private func applyObservation(
        _ observation: RepositoryLocalActivityObservedEvent,
        participant: RepositoryLocalActivityParticipant
    ) {
        let identity = participant.identity
        processedEventIDByParticipant[identity] = max(
            processedEventIDByParticipant[identity] ?? 0,
            observation.eventID
        )
        for repositoryStableKey in observation.qualifyingRepositoryStableKeys
        where participant.repositoryStableKeys.contains(repositoryStableKey) {
            pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey] = max(
                pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey]
                    ?? observation.observedAt,
                observation.observedAt
            )
        }
        restartCoverage(
            for: observation.coverageLostRepositoryStableKeys.intersection(
                participant.repositoryStableKeys
            ),
            at: observation.observedAt
        )
    }

    private func bufferUnverifiedObservation(
        _ observation: RepositoryLocalActivityObservedEvent,
        identity: RepositoryLocalActivityParticipantIdentity
    ) {
        var buffered =
            bufferedObservationByParticipant[identity]
            ?? BufferedObservation(
                processedEventID: 0,
                qualifyingActivityByRepositoryStableKey: [:],
                coverageRestartByRepositoryStableKey: [:]
            )
        buffered.processedEventID = max(buffered.processedEventID, observation.eventID)
        for repositoryStableKey in observation.qualifyingRepositoryStableKeys {
            buffered.qualifyingActivityByRepositoryStableKey[repositoryStableKey] = max(
                buffered.qualifyingActivityByRepositoryStableKey[repositoryStableKey]
                    ?? observation.observedAt,
                observation.observedAt
            )
        }
        for repositoryStableKey in observation.coverageLostRepositoryStableKeys {
            buffered.coverageRestartByRepositoryStableKey[repositoryStableKey] = max(
                buffered.coverageRestartByRepositoryStableKey[repositoryStableKey]
                    ?? observation.observedAt,
                observation.observedAt
            )
        }
        bufferedObservationByParticipant[identity] = buffered
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
        for identity in currentIdentities where processedEventIDByParticipant[identity] == nil {
            processedEventIDByParticipant[identity] = 0
        }
        for participant in replacement.values {
            guard let buffered = bufferedObservationByParticipant[participant.identity] else {
                continue
            }
            processedEventIDByParticipant[participant.identity] = max(
                processedEventIDByParticipant[participant.identity] ?? 0,
                buffered.processedEventID
            )
            for (repositoryStableKey, timestamp) in buffered.qualifyingActivityByRepositoryStableKey
            where participant.repositoryStableKeys.contains(repositoryStableKey) {
                pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey] = max(
                    pendingQualifyingActivityByRepositoryStableKey[repositoryStableKey]
                        ?? timestamp,
                    timestamp
                )
            }
            for (repositoryStableKey, timestamp) in buffered.coverageRestartByRepositoryStableKey
            where participant.repositoryStableKeys.contains(repositoryStableKey) {
                restartCoverage(for: [repositoryStableKey], at: timestamp)
            }
        }
        bufferedObservationByParticipant.removeAll(keepingCapacity: true)
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
