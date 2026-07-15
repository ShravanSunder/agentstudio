import Foundation

@MainActor
final class SnapshotParticipantPreparationCustody {
    struct Reservation: Equatable {
        struct Identity: Equatable {
            let rawValue: UUID

            static func make() -> Self {
                let rawValue = UUIDv7.generate()
                precondition(UUIDv7.isV7(rawValue), "snapshot preparation reservation must be UUIDv7")
                return Self(rawValue: rawValue)
            }
        }

        let identity: Identity
        let transaction: WorkspacePersistenceTransaction

        static func make(transaction: WorkspacePersistenceTransaction) -> Self {
            Self(identity: .make(), transaction: transaction)
        }
    }

    private enum State {
        case available
        case reserved(Reservation)
        case applying(Reservation)
    }

    private var state: State = .available
    private var appliedReservationCount: UInt64 = 0
    private var cancelledReservationCount: UInt64 = 0

    var isAvailable: Bool {
        guard case .available = state else { return false }
        return true
    }

    var permitsParticipantMutation: Bool {
        switch state {
        case .available, .applying: true
        case .reserved: false
        }
    }

    func reserve(_ reservation: Reservation) {
        guard case .available = state else {
            preconditionFailure("snapshot participant reservation requires available custody")
        }
        state = .reserved(reservation)
    }

    func beginApplying(_ reservation: Reservation) {
        guard case .reserved(let activeReservation) = state,
            activeReservation == reservation
        else {
            preconditionFailure("prepared participant reservation apply custody mismatch")
        }
        state = .applying(reservation)
    }

    func completeApplying(_ reservation: Reservation) {
        guard case .applying(let activeReservation) = state,
            activeReservation == reservation
        else {
            preconditionFailure("prepared participant reservation completion custody mismatch")
        }
        appliedReservationCount = incrementedDiagnosticCount(appliedReservationCount)
        state = .available
    }

    func cancel(_ reservation: Reservation) {
        guard case .reserved(let activeReservation) = state,
            activeReservation == reservation
        else {
            preconditionFailure("prepared participant reservation cancel custody mismatch")
        }
        cancelledReservationCount = incrementedDiagnosticCount(cancelledReservationCount)
        state = .available
    }

    var diagnostics: WorkspaceSnapshotPreparationDiagnostics {
        WorkspaceSnapshotPreparationDiagnostics(
            status: status,
            appliedReservationCount: appliedReservationCount,
            cancelledReservationCount: cancelledReservationCount
        )
    }

    private var status: WorkspaceSnapshotReservationStatus {
        switch state {
        case .available: .available
        case .reserved: .reserved
        case .applying: .applying
        }
    }

    private func incrementedDiagnosticCount(_ count: UInt64) -> UInt64 {
        let increment = count.addingReportingOverflow(1)
        precondition(!increment.overflow, "snapshot preparation diagnostic count exhausted")
        return increment.partialValue
    }
}
