import Foundation
import os

/// A closed, fixed-width set of reasons that make callback detail non-authoritative.
///
/// The private representation prevents callers from constructing unsupported bits. The
/// fixed register retains this value only; it never retains paths or callback payloads.
struct FilesystemRecoveryEvidence: Equatable, Hashable, Sendable {
    private let bits: UInt8

    static let continuityLoss = Self(bits: 1 << 0)
    static let rootIdentityRevalidation = Self(bits: 1 << 1)
    static let callbackCaptureTruncation = Self(bits: 1 << 2)
    static let callbackAdmissionOverflow = Self(bits: 1 << 3)
    static let unsupportedNativeFlags = Self(bits: 1 << 4)

    func contains(_ evidence: Self) -> Bool {
        bits & evidence.bits == evidence.bits
    }

    func unioning(_ evidence: Self) -> Self {
        Self(bits: bits | evidence.bits)
    }
}

struct FixedFilesystemRecoveryCustodyIdentity: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FixedFilesystemRecoveryEvidenceRevision: Equatable, Hashable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let genericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>
    let recoveryCustodyIdentity: FixedFilesystemRecoveryCustodyIdentity

    fileprivate init(
        binding: FilesystemObservationSlotBinding,
        genericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>,
        recoveryCustodyIdentity: FixedFilesystemRecoveryCustodyIdentity
    ) {
        self.binding = binding
        self.genericRecoveryRevision = genericRecoveryRevision
        self.recoveryCustodyIdentity = recoveryCustodyIdentity
    }
}

struct FixedFilesystemRecoveryEvidenceSnapshot: Equatable, Sendable {
    let revision: FixedFilesystemRecoveryEvidenceRevision
    let evidence: FilesystemRecoveryEvidence

    fileprivate init(
        revision: FixedFilesystemRecoveryEvidenceRevision,
        evidence: FilesystemRecoveryEvidence
    ) {
        self.revision = revision
        self.evidence = evidence
    }
}

enum FixedFilesystemRecoverySlotState: Equatable, Sendable {
    case undeclaredPhysicalSlot
    case vacant
    case boundClear(FilesystemObservationSlotBinding)
    case boundRetained(FixedFilesystemRecoveryEvidenceSnapshot)
}

enum FixedFilesystemRecoveryEvidenceBindResult: Equatable, Sendable {
    case boundClear(FilesystemObservationSlotBinding)
    case alreadyBoundClear(FilesystemObservationSlotBinding)
    case alreadyBoundRetained(FixedFilesystemRecoveryEvidenceSnapshot)
    case foreignFleet
    case undeclaredPhysicalSlot
    case currentBindingMismatch(FilesystemObservationSlotBinding)
}

enum FixedFilesystemRecoveryEvidenceRecordResult: Equatable, Sendable {
    case recorded(FixedFilesystemRecoveryEvidenceSnapshot)
    case foreignFleet
    case undeclaredPhysicalSlot
    case unboundPhysicalSlot
    case currentBindingMismatch(FilesystemObservationSlotBinding)
}

enum FixedFilesystemRecoveryEvidenceSnapshotResult: Equatable, Sendable {
    case clear(FilesystemObservationSlotBinding)
    case retained(FixedFilesystemRecoveryEvidenceSnapshot)
    case foreignFleet
    case undeclaredPhysicalSlot
    case unboundPhysicalSlot
    case currentBindingMismatch(FilesystemObservationSlotBinding)
}

enum FixedFilesystemRecoveryAcknowledgeResult: Equatable, Sendable {
    case cleared(FixedFilesystemRecoveryEvidenceRevision)
    case newerEvidenceRetained(FixedFilesystemRecoveryEvidenceSnapshot)
    case alreadyClear(FilesystemObservationSlotBinding)
    case foreignFleet
    case undeclaredPhysicalSlot
    case unboundPhysicalSlot
    case currentBindingMismatch(FilesystemObservationSlotBinding)
}

enum FixedFilesystemRecoveryEvidenceRetirementResult: Equatable, Sendable {
    case retired(FilesystemObservationSlotBinding)
    case recoveryEvidenceRetained(FixedFilesystemRecoveryEvidenceSnapshot)
    case alreadyVacant
    case foreignFleet
    case undeclaredPhysicalSlot
    case currentBindingMismatch(FilesystemObservationSlotBinding)
}

/// Fixed-cardinality recovery custody keyed by physical observation slots.
///
/// Physical-slot and opaque generic-revision equality are metadata, not authority. Every mutating
/// operation validates the complete current binding, and acknowledgement additionally
/// validates the register-minted UUIDv7 custody identity captured in the exact snapshot.
final class FixedFilesystemRecoveryEvidenceRegister: @unchecked Sendable {
    private enum SlotState: Equatable, Sendable {
        case vacant
        case boundClear(FilesystemObservationSlotBinding)
        case boundRetained(FixedFilesystemRecoveryEvidenceSnapshot)
    }

    private struct State: Sendable {
        var slotsByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: SlotState]
    }

    let physicalSlotCount: Int

    private let fleetMailboxIdentity: FilesystemObservationFleetMailboxIdentity
    private let lock: OSAllocatedUnfairLock<State>

    init(slotRegistry: FilesystemObservationSlotRegistry) {
        fleetMailboxIdentity = slotRegistry.fleetMailboxIdentity
        physicalSlotCount = slotRegistry.physicalSlotCount
        lock = OSAllocatedUnfairLock(
            initialState: State(
                slotsByPhysicalSlotID: Dictionary(
                    uniqueKeysWithValues: slotRegistry.physicalSlotIDs.map { ($0, .vacant) }
                )
            )
        )
    }

    func state(
        of physicalSlotID: FilesystemObservationPhysicalSlotID
    ) -> FixedFilesystemRecoverySlotState {
        lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            switch slotState {
            case .vacant:
                return .vacant
            case .boundClear(let binding):
                return .boundClear(binding)
            case .boundRetained(let snapshot):
                return .boundRetained(snapshot)
            }
        }
    }

    func bind(
        _ binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceBindResult {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        return lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[binding.physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            switch slotState {
            case .vacant:
                state.slotsByPhysicalSlotID[binding.physicalSlotID] = .boundClear(binding)
                return .boundClear(binding)
            case .boundClear(let currentBinding):
                guard currentBinding == binding else {
                    return .currentBindingMismatch(currentBinding)
                }
                return .alreadyBoundClear(currentBinding)
            case .boundRetained(let snapshot):
                guard snapshot.revision.binding == binding else {
                    return .currentBindingMismatch(snapshot.revision.binding)
                }
                return .alreadyBoundRetained(snapshot)
            }
        }
    }

    func record(
        _ evidence: FilesystemRecoveryEvidence,
        genericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>,
        for binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceRecordResult {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        return lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[binding.physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            let snapshot: FixedFilesystemRecoveryEvidenceSnapshot
            switch slotState {
            case .vacant:
                return .unboundPhysicalSlot
            case .boundClear(let currentBinding):
                guard currentBinding == binding else {
                    return .currentBindingMismatch(currentBinding)
                }
                snapshot = Self.snapshot(
                    binding: binding,
                    genericRecoveryRevision: genericRecoveryRevision,
                    evidence: evidence,
                    recoveryCustodyIdentity: FixedFilesystemRecoveryCustodyIdentity(
                        value: UUIDv7.generate()
                    )
                )
            case .boundRetained(let currentSnapshot):
                guard currentSnapshot.revision.binding == binding else {
                    return .currentBindingMismatch(currentSnapshot.revision.binding)
                }
                let joinedEvidence = currentSnapshot.evidence.unioning(evidence)
                guard
                    joinedEvidence != currentSnapshot.evidence
                        || genericRecoveryRevision
                            != currentSnapshot.revision.genericRecoveryRevision
                else {
                    return .recorded(currentSnapshot)
                }
                snapshot = Self.snapshot(
                    binding: binding,
                    genericRecoveryRevision: genericRecoveryRevision,
                    evidence: joinedEvidence,
                    recoveryCustodyIdentity:
                        currentSnapshot.revision.recoveryCustodyIdentity
                )
            }
            state.slotsByPhysicalSlotID[binding.physicalSlotID] = .boundRetained(snapshot)
            return .recorded(snapshot)
        }
    }

    func snapshot(
        for binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceSnapshotResult {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        return lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[binding.physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            switch slotState {
            case .vacant:
                return .unboundPhysicalSlot
            case .boundClear(let currentBinding):
                guard currentBinding == binding else {
                    return .currentBindingMismatch(currentBinding)
                }
                return .clear(currentBinding)
            case .boundRetained(let retainedSnapshot):
                guard retainedSnapshot.revision.binding == binding else {
                    return .currentBindingMismatch(retainedSnapshot.revision.binding)
                }
                return .retained(retainedSnapshot)
            }
        }
    }

    func acknowledge(
        _ acceptedSnapshot: FixedFilesystemRecoveryEvidenceSnapshot
    ) -> FixedFilesystemRecoveryAcknowledgeResult {
        let binding = acceptedSnapshot.revision.binding
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        return lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[binding.physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            switch slotState {
            case .vacant:
                return .unboundPhysicalSlot
            case .boundClear(let currentBinding):
                guard currentBinding == binding else {
                    return .currentBindingMismatch(currentBinding)
                }
                return .alreadyClear(currentBinding)
            case .boundRetained(let currentSnapshot):
                guard currentSnapshot.revision.binding == binding else {
                    return .currentBindingMismatch(currentSnapshot.revision.binding)
                }
                guard currentSnapshot == acceptedSnapshot else {
                    return .newerEvidenceRetained(currentSnapshot)
                }
                state.slotsByPhysicalSlotID[binding.physicalSlotID] = .boundClear(binding)
                return .cleared(currentSnapshot.revision)
            }
        }
    }

    func retire(
        _ binding: FilesystemObservationSlotBinding
    ) -> FixedFilesystemRecoveryEvidenceRetirementResult {
        guard binding.fleetMailboxIdentity == fleetMailboxIdentity else {
            return .foreignFleet
        }
        return lock.withLock { state in
            guard let slotState = state.slotsByPhysicalSlotID[binding.physicalSlotID] else {
                return .undeclaredPhysicalSlot
            }
            switch slotState {
            case .vacant:
                return .alreadyVacant
            case .boundClear(let currentBinding):
                guard currentBinding == binding else {
                    return .currentBindingMismatch(currentBinding)
                }
                state.slotsByPhysicalSlotID[binding.physicalSlotID] = .vacant
                return .retired(binding)
            case .boundRetained(let currentSnapshot):
                guard currentSnapshot.revision.binding == binding else {
                    return .currentBindingMismatch(currentSnapshot.revision.binding)
                }
                return .recoveryEvidenceRetained(currentSnapshot)
            }
        }
    }

    private static func snapshot(
        binding: FilesystemObservationSlotBinding,
        genericRecoveryRevision: GatherRecoveryRevision<FilesystemObservationPhysicalSlotID>,
        evidence: FilesystemRecoveryEvidence,
        recoveryCustodyIdentity: FixedFilesystemRecoveryCustodyIdentity
    ) -> FixedFilesystemRecoveryEvidenceSnapshot {
        FixedFilesystemRecoveryEvidenceSnapshot(
            revision: FixedFilesystemRecoveryEvidenceRevision(
                binding: binding,
                genericRecoveryRevision: genericRecoveryRevision,
                recoveryCustodyIdentity: recoveryCustodyIdentity
            ),
            evidence: evidence
        )
    }
}
