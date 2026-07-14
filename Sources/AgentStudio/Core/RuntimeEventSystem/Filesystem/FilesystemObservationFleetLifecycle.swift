import Foundation
import os

struct FilesystemObservationFleetShutdownIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init() {
        value = UUIDv7.generate()
    }
}

enum FilesystemObservationFleetIngressLifecycle: Equatable, Sendable {
    case accepting
    case shutdownFrozen(FilesystemObservationFleetShutdownIdentity)
}

struct FilesystemObservationFleetAdmissionExhaustionDebt: Equatable, Sendable {
    let triggeringBinding: FilesystemObservationSlotBinding
    let terminalGenericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>
}

enum FilesystemFleetOrdinaryAdmissionDisposition: Equatable, Sendable {
    case ordinary
    case fleetAdmissionExhausted(FilesystemObservationFleetAdmissionExhaustionDebt)
}

enum FilesystemObservationFleetIngressFreezeResult: Equatable, Sendable {
    case applied(FilesystemObservationFleetShutdownIdentity)
    case alreadyApplied(FilesystemObservationFleetShutdownIdentity)
    case shutdownIdentityMismatch(
        expected: FilesystemObservationFleetShutdownIdentity,
        presented: FilesystemObservationFleetShutdownIdentity
    )
    case terminationAlreadyAdvanced(FilesystemObservationLifecycleStateSnapshot)
}

final class FilesystemObservationFleetLifecycle: @unchecked Sendable {
    private enum State: Sendable {
        case open
        case freezing(FilesystemObservationFleetShutdownIdentity)
        case draining(FilesystemObservationFleetShutdownIdentity)
        case rejected(FilesystemObservationFleetShutdownIdentity)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.open)

    @discardableResult
    func beginShutdown(
        mailbox: FilesystemObservationMailbox
    ) -> FilesystemObservationFleetIngressFreezeResult {
        let shutdownIdentity = lock.withLock { state in
            switch state {
            case .open:
                let mintedIdentity = FilesystemObservationFleetShutdownIdentity()
                state = .freezing(mintedIdentity)
                return mintedIdentity
            case .freezing(let retainedIdentity), .draining(let retainedIdentity),
                .rejected(let retainedIdentity):
                return retainedIdentity
            }
        }

        let result = mailbox.freezeFleetIngress(for: shutdownIdentity)
        lock.withLock { state in
            guard
                case .freezing(let retainedIdentity) = state,
                retainedIdentity == shutdownIdentity
            else {
                return
            }
            switch result {
            case .applied, .alreadyApplied:
                state = .draining(shutdownIdentity)
            case .shutdownIdentityMismatch, .terminationAlreadyAdvanced:
                state = .rejected(shutdownIdentity)
            }
        }
        return result
    }
}
