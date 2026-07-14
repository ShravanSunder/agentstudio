import Foundation

struct FilesystemContinuityRepairHandoffAuthority: Hashable, Sendable {
    let acceptingBinding: FilesystemObservationSlotBinding
    let handoffIdentity: FilesystemContinuityRepairHandoffIdentity
    let desiredIdentity: FilesystemObservationDesiredIdentity
    let acceptedTopologyRevision: UInt64
}

struct FilesystemSourceGateContinuityRepairAcceptance: Equatable, Sendable {
    let authority: FilesystemContinuityRepairHandoffAuthority
    let repairGeneration: RepairGeneration

    func matches(_ expectedAuthority: FilesystemContinuityRepairHandoffAuthority) -> Bool {
        authority == expectedAuthority
    }
}

enum FilesystemContinuityRepairHandoffRequestMismatch: Hashable, Sendable {
    case authority
    case trigger
    case watermark
    case participants
}

struct FilesystemContinuityRepairHandoffRequestConflict: Equatable, Sendable {
    let mismatches: Set<FilesystemContinuityRepairHandoffRequestMismatch>

    fileprivate init(mismatches: Set<FilesystemContinuityRepairHandoffRequestMismatch>) {
        precondition(!mismatches.isEmpty, "a retained continuity-repair handoff conflict must differ")
        self.mismatches = mismatches
    }
}

enum FilesystemSourceGateHandoffAdmissionResult: Equatable, Sendable {
    case admitted(FilesystemSourceGateContinuityRepairAcceptance)
    case bindingMismatch
    case retainedRequestConflict(FilesystemContinuityRepairHandoffRequestConflict)
    case rejected(FilesystemRepairAdmissionRejection)
    case generationExhausted
    case shuttingDown
}

struct FilesystemSourceGateContinuityRepairReplay: Sendable {
    enum Comparison: Equatable, Sendable {
        case vacant
        case identical(FilesystemSourceGateContinuityRepairAcceptance)
        case conflict(FilesystemContinuityRepairHandoffRequestConflict)
    }

    private struct Request: Equatable, Sendable {
        let authority: FilesystemContinuityRepairHandoffAuthority
        let trigger: FilesystemRepairTriggerClass
        let watermark: FilesystemRepairWatermark
        let participants: Set<FilesystemRepairParticipantToken>
    }

    private struct RetainedHandoff: Equatable, Sendable {
        let request: Request
        let acceptance: FilesystemSourceGateContinuityRepairAcceptance
    }

    private enum State: Equatable, Sendable {
        case vacant
        case retained(RetainedHandoff)
    }

    private var state = State.vacant

    func compare(
        authority: FilesystemContinuityRepairHandoffAuthority,
        trigger: FilesystemRepairTriggerClass,
        watermark: FilesystemRepairWatermark,
        participants: Set<FilesystemRepairParticipantToken>
    ) -> Comparison {
        guard case .retained(let retained) = state else { return .vacant }
        let request = Request(
            authority: authority,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        )
        var mismatches: Set<FilesystemContinuityRepairHandoffRequestMismatch> = []
        if request.authority != retained.request.authority { mismatches.insert(.authority) }
        if request.trigger != retained.request.trigger { mismatches.insert(.trigger) }
        if request.watermark != retained.request.watermark { mismatches.insert(.watermark) }
        if request.participants != retained.request.participants { mismatches.insert(.participants) }
        guard !mismatches.isEmpty else { return .identical(retained.acceptance) }
        return .conflict(
            FilesystemContinuityRepairHandoffRequestConflict(mismatches: mismatches)
        )
    }

    mutating func retain(
        authority: FilesystemContinuityRepairHandoffAuthority,
        trigger: FilesystemRepairTriggerClass,
        watermark: FilesystemRepairWatermark,
        participants: Set<FilesystemRepairParticipantToken>,
        acceptance: FilesystemSourceGateContinuityRepairAcceptance
    ) {
        precondition(state == .vacant, "continuity-repair handoff replay retains one request")
        state = .retained(
            RetainedHandoff(
                request: Request(
                    authority: authority,
                    trigger: trigger,
                    watermark: watermark,
                    participants: participants
                ),
                acceptance: acceptance
            )
        )
    }
}
