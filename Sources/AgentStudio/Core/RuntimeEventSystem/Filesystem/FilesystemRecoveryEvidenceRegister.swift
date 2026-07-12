import Foundation
import os

/// A closed, fixed-width set of reasons that make callback detail non-authoritative.
///
/// The private representation prevents callers from constructing unsupported bits. The
/// register retains this value only; it never retains paths or callback payloads.
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

struct FilesystemRecoveryEvidenceRevision: Equatable, Hashable, Sendable {
    let registration: FSEventRegistrationToken
    let stamp: GatherRecoveryStamp
}

/// Exact evidence custody captured by a mailbox drain lease.
///
/// Acknowledgement compares the entire snapshot, not only its revision. This remains
/// safe after revision authority is exhausted, when newly joined evidence cannot advance
/// the stamp but must still survive acknowledgement of an older snapshot.
struct FilesystemRecoveryEvidenceSnapshot: Equatable, Sendable {
    let revision: FilesystemRecoveryEvidenceRevision
    let evidence: FilesystemRecoveryEvidence
    fileprivate let custodyIdentity: AdmissionOpaqueIdentity
}

struct FilesystemRecoveryEvidenceAuthoritySeed: Sendable {
    let stampsByRegistration: [FSEventRegistrationToken: GatherRecoveryStamp]

    init(
        stampsByRegistration: [FSEventRegistrationToken: GatherRecoveryStamp] = [:]
    ) {
        self.stampsByRegistration = stampsByRegistration
    }
}

enum FilesystemRecoveryRegisterConfigurationError: Error, Equatable {
    case nonPositiveMaximumDeclaredRegistrations(Int)
    case declaredRegistrationCapacityExceeded(maximum: Int, actual: Int)
    case duplicateDeclaredRegistration(FSEventRegistrationToken)
    case authoritySeedContainsUndeclaredRegistration(FSEventRegistrationToken)
}

enum FilesystemRecoveryEvidenceRecordResult: Equatable, Sendable {
    case recorded(FilesystemRecoveryEvidenceSnapshot)
    case unknownRegistration
}

enum FilesystemRecoveryEvidenceSnapshotResult: Equatable, Sendable {
    case evidence(FilesystemRecoveryEvidenceSnapshot)
    case noEvidence(GatherRecoveryStamp)
    case unknownRegistration
}

enum FilesystemRecoveryEvidenceAcknowledgementResult: Equatable, Sendable {
    case cleared(FilesystemRecoveryEvidenceRevision)
    case newerEvidenceRetained(FilesystemRecoveryEvidenceSnapshot)
    case alreadyCleared(GatherRecoveryStamp)
    case unknownRegistration
}

/// Fixed-cardinality, monotonic recovery evidence custody for declared registrations.
///
/// All operations are synchronous and constant in the number of declared registrations.
/// The owner declares every key up front, so callback admission can never grow the table.
final class FilesystemRecoveryEvidenceRegister: @unchecked Sendable {
    private enum EvidenceCustody: Sendable {
        case clear
        case retained(
            evidence: FilesystemRecoveryEvidence,
            custodyIdentity: AdmissionOpaqueIdentity
        )
    }

    private struct RegistrationSlot: Sendable {
        var stamp: GatherRecoveryStamp
        var custody: EvidenceCustody
    }

    private struct State: Sendable {
        var slotsByRegistration: [FSEventRegistrationToken: RegistrationSlot]
    }

    private let lock: OSAllocatedUnfairLock<State>

    init(
        maximumDeclaredRegistrations: Int,
        declaredRegistrations: [FSEventRegistrationToken],
        authoritySeed: FilesystemRecoveryEvidenceAuthoritySeed = .init()
    ) throws {
        guard maximumDeclaredRegistrations > 0 else {
            throw
                FilesystemRecoveryRegisterConfigurationError
                .nonPositiveMaximumDeclaredRegistrations(maximumDeclaredRegistrations)
        }
        guard declaredRegistrations.count <= maximumDeclaredRegistrations else {
            throw
                FilesystemRecoveryRegisterConfigurationError
                .declaredRegistrationCapacityExceeded(
                    maximum: maximumDeclaredRegistrations,
                    actual: declaredRegistrations.count
                )
        }

        let declaredRegistrationSet = Set(declaredRegistrations)
        guard declaredRegistrationSet.count == declaredRegistrations.count else {
            var encountered: Set<FSEventRegistrationToken> = []
            guard
                let duplicate = declaredRegistrations.first(where: {
                    !encountered.insert($0).inserted
                })
            else {
                preconditionFailure("unequal registration cardinality requires a duplicate")
            }
            throw
                FilesystemRecoveryRegisterConfigurationError
                .duplicateDeclaredRegistration(duplicate)
        }
        if let undeclaredSeed = authoritySeed.stampsByRegistration.keys.first(where: {
            !declaredRegistrationSet.contains($0)
        }) {
            throw
                FilesystemRecoveryRegisterConfigurationError
                .authoritySeedContainsUndeclaredRegistration(undeclaredSeed)
        }

        var slotsByRegistration: [FSEventRegistrationToken: RegistrationSlot] = [:]
        slotsByRegistration.reserveCapacity(maximumDeclaredRegistrations)
        for registration in declaredRegistrations {
            slotsByRegistration[registration] = RegistrationSlot(
                stamp: authoritySeed.stampsByRegistration[registration] ?? .sequenced(0),
                custody: .clear
            )
        }
        lock = OSAllocatedUnfairLock(
            initialState: State(slotsByRegistration: slotsByRegistration)
        )
    }

    func record(
        _ evidence: FilesystemRecoveryEvidence,
        for registration: FSEventRegistrationToken
    ) -> FilesystemRecoveryEvidenceRecordResult {
        lock.withLock { state in
            guard var slot = state.slotsByRegistration[registration] else {
                return .unknownRegistration
            }

            switch slot.custody {
            case .clear:
                slot.stamp = Self.advanced(slot.stamp)
                slot.custody = .retained(
                    evidence: evidence,
                    custodyIdentity: AdmissionOpaqueIdentity()
                )
            case .retained(let retainedEvidence, let custodyIdentity):
                let joinedEvidence = retainedEvidence.unioning(evidence)
                guard joinedEvidence != retainedEvidence else {
                    return .recorded(
                        Self.snapshot(
                            registration: registration,
                            stamp: slot.stamp,
                            evidence: retainedEvidence,
                            custodyIdentity: custodyIdentity
                        )
                    )
                }
                slot.stamp = Self.advanced(slot.stamp)
                slot.custody = .retained(
                    evidence: joinedEvidence,
                    custodyIdentity: custodyIdentity
                )
            }

            state.slotsByRegistration[registration] = slot
            guard case .retained(let retainedEvidence, let custodyIdentity) = slot.custody else {
                preconditionFailure("recording evidence must retain evidence custody")
            }
            return .recorded(
                Self.snapshot(
                    registration: registration,
                    stamp: slot.stamp,
                    evidence: retainedEvidence,
                    custodyIdentity: custodyIdentity
                )
            )
        }
    }

    func snapshot(
        for registration: FSEventRegistrationToken
    ) -> FilesystemRecoveryEvidenceSnapshotResult {
        lock.withLock { state in
            guard let slot = state.slotsByRegistration[registration] else {
                return .unknownRegistration
            }
            switch slot.custody {
            case .clear:
                return .noEvidence(slot.stamp)
            case .retained(let evidence, let custodyIdentity):
                return .evidence(
                    Self.snapshot(
                        registration: registration,
                        stamp: slot.stamp,
                        evidence: evidence,
                        custodyIdentity: custodyIdentity
                    )
                )
            }
        }
    }

    func acknowledge(
        _ acceptedSnapshot: FilesystemRecoveryEvidenceSnapshot
    ) -> FilesystemRecoveryEvidenceAcknowledgementResult {
        let registration = acceptedSnapshot.revision.registration
        return lock.withLock { state in
            guard var slot = state.slotsByRegistration[registration] else {
                return .unknownRegistration
            }
            switch slot.custody {
            case .clear:
                return .alreadyCleared(slot.stamp)
            case .retained(let evidence, let custodyIdentity):
                let currentSnapshot = Self.snapshot(
                    registration: registration,
                    stamp: slot.stamp,
                    evidence: evidence,
                    custodyIdentity: custodyIdentity
                )
                guard currentSnapshot == acceptedSnapshot else {
                    return .newerEvidenceRetained(currentSnapshot)
                }
                slot.custody = .clear
                state.slotsByRegistration[registration] = slot
                return .cleared(currentSnapshot.revision)
            }
        }
    }

    private static func snapshot(
        registration: FSEventRegistrationToken,
        stamp: GatherRecoveryStamp,
        evidence: FilesystemRecoveryEvidence,
        custodyIdentity: AdmissionOpaqueIdentity
    ) -> FilesystemRecoveryEvidenceSnapshot {
        FilesystemRecoveryEvidenceSnapshot(
            revision: FilesystemRecoveryEvidenceRevision(
                registration: registration,
                stamp: stamp
            ),
            evidence: evidence,
            custodyIdentity: custodyIdentity
        )
    }

    private static func advanced(_ stamp: GatherRecoveryStamp) -> GatherRecoveryStamp {
        switch stamp {
        case .sequenced(let sequence):
            let next = sequence.addingReportingOverflow(1)
            return next.overflow ? .authorityExhausted : .sequenced(next.partialValue)
        case .authorityExhausted:
            return .authorityExhausted
        }
    }
}
