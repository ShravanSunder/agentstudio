import AgentStudioGit
import CoreServices
import Foundation

package enum GitCleanContinuityFailureReason: String, Sendable, Equatable {
    case unsupportedObservation
    case registrationMissing
    case registrationReplaced
    case identityChanged
    case mutationObserved
    case eventStreamUncertain
    case streamStartFailed
    case shutdown
}

package struct GitCleanContinuityBarrier: Sendable, Equatable {
    package let registrationId: UUID
    package let observationIdentity: AgentStudioGit.GitStatusObservationIdentity
    package let registrationGeneration: UInt64
    package let mutationEpoch: UInt64
    package let uncertaintyEpoch: UInt64
}

package struct GitCleanContinuityAuthority: Sendable, Equatable {
    package let registrationId: UUID
    package let observationIdentity: AgentStudioGit.GitStatusObservationIdentity
    package let registrationGeneration: UInt64
    package let mutationEpoch: UInt64
    package let uncertaintyEpoch: UInt64
}

package enum GitCleanContinuityAuthorityValidation: Sendable, Equatable {
    case authoritative(GitCleanContinuityAuthority)
    case requiresExact(GitCleanContinuityFailureReason)
}

/// Lock-protected authority ledger updated directly from the raw FSEvents callback.
///
/// Ordinary filesystem delivery is intentionally lossy. This ledger therefore
/// records mutation and uncertainty before a batch enters that delivery path.
package final class GitCleanContinuityLedger: @unchecked Sendable {
    private struct RegistrationState {
        let identity: AgentStudioGit.GitStatusObservationIdentity
        let generation: UInt64
        var mutationEpoch: UInt64
        var uncertaintyEpoch: UInt64
        var latestEventId: FSEventStreamEventId?
    }

    private static let uncertaintyFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
    )

    private let lock = NSLock()
    private var nextRegistrationGeneration: UInt64 = 0
    private var registrationById: [UUID: RegistrationState] = [:]
    private var hasShutdown = false

    package init() {}

    package func register(
        registrationId: UUID,
        identity: AgentStudioGit.GitStatusObservationIdentity
    ) {
        lock.withLock {
            guard !hasShutdown else { return }
            nextRegistrationGeneration &+= 1
            registrationById[registrationId] = RegistrationState(
                identity: identity,
                generation: nextRegistrationGeneration,
                mutationEpoch: 0,
                uncertaintyEpoch: 0,
                latestEventId: nil
            )
        }
    }

    package func unregister(registrationId: UUID) {
        _ = lock.withLock {
            registrationById.removeValue(forKey: registrationId)
        }
    }

    package func beginBarrier(
        registrationId: UUID,
        identity: AgentStudioGit.GitStatusObservationIdentity
    ) -> GitCleanContinuityBarrier? {
        lock.withLock {
            guard !hasShutdown,
                let registration = registrationById[registrationId],
                registration.identity == identity
            else {
                return nil
            }
            return GitCleanContinuityBarrier(
                registrationId: registrationId,
                observationIdentity: identity,
                registrationGeneration: registration.generation,
                mutationEpoch: registration.mutationEpoch,
                uncertaintyEpoch: registration.uncertaintyEpoch
            )
        }
    }

    package func commitBarrier(
        _ barrier: GitCleanContinuityBarrier
    ) -> GitCleanContinuityAuthorityValidation {
        lock.withLock {
            guard !hasShutdown else { return .requiresExact(.shutdown) }
            guard let registration = registrationById[barrier.registrationId] else {
                return .requiresExact(.registrationMissing)
            }
            guard registration.identity == barrier.observationIdentity else {
                return .requiresExact(.identityChanged)
            }
            guard registration.generation == barrier.registrationGeneration else {
                return .requiresExact(.registrationReplaced)
            }
            guard registration.mutationEpoch == barrier.mutationEpoch else {
                return .requiresExact(.mutationObserved)
            }
            guard registration.uncertaintyEpoch == barrier.uncertaintyEpoch else {
                return .requiresExact(.eventStreamUncertain)
            }
            return .authoritative(
                GitCleanContinuityAuthority(
                    registrationId: barrier.registrationId,
                    observationIdentity: barrier.observationIdentity,
                    registrationGeneration: barrier.registrationGeneration,
                    mutationEpoch: barrier.mutationEpoch,
                    uncertaintyEpoch: barrier.uncertaintyEpoch
                )
            )
        }
    }

    package func renew(
        _ authority: GitCleanContinuityAuthority
    ) -> GitCleanContinuityAuthorityValidation {
        lock.withLock {
            guard !hasShutdown else { return .requiresExact(.shutdown) }
            guard let registration = registrationById[authority.registrationId] else {
                return .requiresExact(.registrationMissing)
            }
            guard registration.identity == authority.observationIdentity else {
                return .requiresExact(.identityChanged)
            }
            guard registration.generation == authority.registrationGeneration else {
                return .requiresExact(.registrationReplaced)
            }
            guard registration.mutationEpoch == authority.mutationEpoch else {
                return .requiresExact(.mutationObserved)
            }
            guard registration.uncertaintyEpoch == authority.uncertaintyEpoch else {
                return .requiresExact(.eventStreamUncertain)
            }
            return .authoritative(authority)
        }
    }

    package func recordMutation(
        registrationId: UUID,
        eventId: FSEventStreamEventId
    ) {
        recordRawEvent(
            registrationId: registrationId,
            eventId: eventId,
            flags: 0,
            hasRelevantMutation: true
        )
    }

    package func recordRawEvent(
        registrationId: UUID,
        eventId: FSEventStreamEventId,
        flags: FSEventStreamEventFlags,
        hasRelevantMutation: Bool
    ) {
        lock.withLock {
            guard !hasShutdown, var registration = registrationById[registrationId] else { return }

            let cursorRegressed = registration.latestEventId.map { eventId < $0 } ?? false
            if flags & Self.uncertaintyFlags != 0 || cursorRegressed {
                registration.uncertaintyEpoch &+= 1
            }
            if hasRelevantMutation {
                registration.mutationEpoch &+= 1
            }
            registration.latestEventId = eventId
            registrationById[registrationId] = registration
        }
    }

    package func markUncertain(registrationId: UUID) {
        lock.withLock {
            guard !hasShutdown, var registration = registrationById[registrationId] else { return }
            registration.uncertaintyEpoch &+= 1
            registrationById[registrationId] = registration
        }
    }

    package func shutdown() {
        lock.withLock {
            hasShutdown = true
            registrationById.removeAll(keepingCapacity: false)
        }
    }
}

package protocol GitCleanContinuityWitness: Sendable {
    func prepare(
        worktreeId: UUID,
        rootPath: URL,
        observationPlan: AgentStudioGit.GitStatusObservationPlan
    ) async -> GitCleanContinuityBarrier?
    func commit(_ barrier: GitCleanContinuityBarrier) async -> GitCleanContinuityAuthorityValidation
    func renew(_ authority: GitCleanContinuityAuthority) async -> GitCleanContinuityAuthorityValidation
    func retire(worktreeId: UUID, rootPath: URL)
}
