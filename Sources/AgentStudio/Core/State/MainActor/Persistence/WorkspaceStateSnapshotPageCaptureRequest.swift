import Synchronization

enum SnapshotPageCaptureClaimResult: Sendable {
    case claimed(MainActorWorkTicket)
    case alreadyClaimed
}

final class WorkspaceStateSnapshotPageCaptureRequestCustody: Sendable {
    private enum State: Sendable {
        case pending(MainActorWorkTicket)
        case claimed
    }

    let workLedger: MainActorWorkLedger
    private let state: Mutex<State>

    init(workLedger: MainActorWorkLedger, workTicket: MainActorWorkTicket) {
        self.workLedger = workLedger
        self.state = Mutex(.pending(workTicket))
    }

    deinit {
        guard case .claimed(let ticket) = claim() else { return }
        _ = workLedger.discard(ticket: ticket)
    }

    func claim() -> SnapshotPageCaptureClaimResult {
        state.withLock { state in
            switch state {
            case .pending(let ticket):
                state = .claimed
                return .claimed(ticket)
            case .claimed:
                return .alreadyClaimed
            }
        }
    }

    func discard() -> MainActorWorkDiscardResult {
        switch claim() {
        case .claimed(let ticket):
            return workLedger.discard(ticket: ticket)
        case .alreadyClaimed:
            return .rejected(.duplicateSettlement)
        }
    }
}

struct WorkspaceStateSnapshotPageCaptureRequest: Sendable {
    let pagerIdentity: WorkspaceStateSnapshotPagerIdentity
    let lease: WorkspaceStateSnapshotLease
    let limits: WorkspaceStateSnapshotPageLimits
    let custody: WorkspaceStateSnapshotPageCaptureRequestCustody

    func discardBeforeExecution() -> MainActorWorkDiscardResult {
        custody.discard()
    }
}
