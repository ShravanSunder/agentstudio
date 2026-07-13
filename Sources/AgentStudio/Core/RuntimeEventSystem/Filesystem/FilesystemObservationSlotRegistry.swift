import Foundation

enum FilesystemObservationSlotConfigurationError: Error, Equatable {
    case nonPositiveMaximumSimultaneousSourceCount(Int)
    case negativeReplacementReserveSlotCount(Int)
    case physicalSlotCountOverflow
}

struct FilesystemObservationFleetMailboxIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationPhysicalSlotID: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotBindingIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationControlBlockIdentity: Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSlotBinding: Hashable, Sendable {
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotID: FilesystemObservationPhysicalSlotID
    let identity: FilesystemObservationSlotBindingIdentity
    let registration: FSEventRegistrationToken
    let controlBlockIdentity: FilesystemObservationControlBlockIdentity

    fileprivate init(
        fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity,
        physicalSlotID: FilesystemObservationPhysicalSlotID,
        identity: FilesystemObservationSlotBindingIdentity,
        registration: FSEventRegistrationToken,
        controlBlockIdentity: FilesystemObservationControlBlockIdentity
    ) {
        self.fleetMailboxIdentity = fleetMailboxIdentity
        self.physicalSlotID = physicalSlotID
        self.identity = identity
        self.registration = registration
        self.controlBlockIdentity = controlBlockIdentity
    }
}

enum FilesystemObservationSlotBindingIssueResult: Equatable, Sendable {
    case issued(FilesystemObservationSlotBinding)
    case occupied(FilesystemObservationSlotBinding)
    case undeclaredPhysicalSlot
}

enum FilesystemObservationPhysicalSlotState: Equatable, Sendable {
    case undeclaredPhysicalSlot
    case unbound
    case current(FilesystemObservationSlotBinding)
}

enum FilesystemObservationSlotBindingCurrentness: Equatable, Sendable {
    case foreignFleet
    case undeclaredPhysicalSlot
    case unbound
    case current
    case superseded
}

/// Fixed-cardinality owner of physical slots and their current bindings.
///
/// This owner is intentionally non-locking. Its eventual mailbox caller must hold the
/// wrapper coordination lock. UUIDv7 values provide opaque identity only: exact stored
/// equality determines currentness, and UUID order never determines lifecycle or FIFO.
final class FilesystemObservationSlotRegistry {
    private enum SlotState: Equatable {
        case unbound
        case current(FilesystemObservationSlotBinding)
    }

    let maximumSimultaneousSourceCount: Int
    let replacementReserveSlotCount: Int
    let physicalSlotCount: Int
    let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    let physicalSlotIDs: [FilesystemObservationPhysicalSlotID]

    private var statesByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: SlotState]

    init(
        maximumSimultaneousSourceCount: Int,
        replacementReserveSlotCount: Int
    ) throws {
        guard maximumSimultaneousSourceCount > 0 else {
            throw
                FilesystemObservationSlotConfigurationError
                .nonPositiveMaximumSimultaneousSourceCount(maximumSimultaneousSourceCount)
        }
        guard replacementReserveSlotCount >= 0 else {
            throw
                FilesystemObservationSlotConfigurationError
                .negativeReplacementReserveSlotCount(replacementReserveSlotCount)
        }
        let (physicalSlotCount, physicalSlotCountOverflow) =
            maximumSimultaneousSourceCount.addingReportingOverflow(
                replacementReserveSlotCount
            )
        guard !physicalSlotCountOverflow else {
            throw FilesystemObservationSlotConfigurationError.physicalSlotCountOverflow
        }

        self.maximumSimultaneousSourceCount = maximumSimultaneousSourceCount
        self.replacementReserveSlotCount = replacementReserveSlotCount
        self.physicalSlotCount = physicalSlotCount
        fleetMailboxIdentity = FilesystemObservationFleetMailboxIdentity(
            value: UUIDv7.generate()
        )
        physicalSlotIDs = (0..<physicalSlotCount).map { _ in
            FilesystemObservationPhysicalSlotID(value: UUIDv7.generate())
        }
        statesByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: physicalSlotIDs.map { ($0, .unbound) }
        )
    }

    func issueInitialBinding(
        physicalSlotID: FilesystemObservationPhysicalSlotID,
        registration: FSEventRegistrationToken
    ) -> FilesystemObservationSlotBindingIssueResult {
        guard let slotState = statesByPhysicalSlotID[physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .unbound:
            let binding = FilesystemObservationSlotBinding(
                fleetMailboxIdentity: fleetMailboxIdentity,
                physicalSlotID: physicalSlotID,
                identity: FilesystemObservationSlotBindingIdentity(
                    value: UUIDv7.generate()
                ),
                registration: registration,
                controlBlockIdentity: FilesystemObservationControlBlockIdentity(
                    value: UUIDv7.generate()
                )
            )
            statesByPhysicalSlotID[physicalSlotID] = .current(binding)
            return .issued(binding)
        case .current(let binding):
            return .occupied(binding)
        }
    }

    func state(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FilesystemObservationPhysicalSlotState {
        guard let slotState = statesByPhysicalSlotID[physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .unbound:
            return .unbound
        case .current(let binding):
            return .current(binding)
        }
    }

    func currentness(
        of binding: FilesystemObservationSlotBinding
    ) -> FilesystemObservationSlotBindingCurrentness {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        guard let slotState = statesByPhysicalSlotID[binding.physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        switch slotState {
        case .unbound:
            return .unbound
        case .current(let currentBinding):
            return currentBinding == binding ? .current : .superseded
        }
    }
}
