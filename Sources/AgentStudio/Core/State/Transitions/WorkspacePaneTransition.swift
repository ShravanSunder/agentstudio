import Foundation

struct WorkspacePaneTitleUpdateRequest: Equatable, Sendable {
    let paneID: UUID
    let title: String
}

enum WorkspacePaneTitleTransitionRejection: Equatable, Sendable {
    case paneMissing(UUID)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
}

struct WorkspacePaneStateTransitionReplacement: Equatable, Sendable {
    let paneID: UUID
    let expectedCurrentState: PaneGraphState
    let replacementState: PaneGraphState
}

struct WorkspacePaneGraphTransition: Equatable, Sendable {
    let replacements: [WorkspacePaneStateTransitionReplacement]

    fileprivate init(replacements: [WorkspacePaneStateTransitionReplacement]) {
        precondition(!replacements.isEmpty, "pane graph transition requires at least one replacement")
        self.replacements = replacements
    }
}

enum WorkspacePaneTitleTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneGraphTransition)
    case unchanged
    case rejected(WorkspacePaneTitleTransitionRejection)
}

enum WorkspacePaneTitleTransitionPlanner {
    static func plan(
        _ request: WorkspacePaneTitleUpdateRequest,
        currentPaneState: PaneGraphState?
    ) -> WorkspacePaneTitleTransitionDecision {
        guard let currentPaneState else {
            return .rejected(.paneMissing(request.paneID))
        }
        guard currentPaneState.id == request.paneID else {
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: request.paneID,
                    currentPaneID: currentPaneState.id
                )
            )
        }
        guard currentPaneState.metadata.title != request.title else {
            return .unchanged
        }

        var replacementState = currentPaneState
        replacementState.metadata.title = request.title
        return .changed(
            WorkspacePaneGraphTransition(
                replacements: [
                    WorkspacePaneStateTransitionReplacement(
                        paneID: request.paneID,
                        expectedCurrentState: currentPaneState,
                        replacementState: replacementState
                    )
                ]
            )
        )
    }
}

struct WorkspacePaneZmxAnchorRepairRequest: Equatable, Sendable {
    let paneID: UUID
    let sessionID: String
}

enum WorkspacePaneZmxAnchorRepairRejectionReason: Equatable, Sendable {
    case contentIsNotTerminal
    case duplicateRequest
    case paneIdentityMismatch(currentPaneID: UUID)
    case paneMissing
    case providerMismatch(received: SessionProvider)
    case sessionIDDoesNotMatchPaneKind
}

struct WorkspacePaneZmxAnchorRepairRejection: Equatable, Sendable {
    let paneID: UUID
    let reason: WorkspacePaneZmxAnchorRepairRejectionReason
}

struct WorkspacePaneZmxAnchorRepairReport: Equatable, Sendable {
    let acceptedPaneIDs: [UUID]
    let unchangedPaneIDs: [UUID]
    let rejections: [WorkspacePaneZmxAnchorRepairRejection]
}

enum WorkspacePaneZmxAnchorRepairDecision: Equatable, Sendable {
    case changed(
        transition: WorkspacePaneGraphTransition,
        report: WorkspacePaneZmxAnchorRepairReport
    )
    case unchanged(WorkspacePaneZmxAnchorRepairReport)
}

/// Pure classifier for startup zmx-anchor repair.
///
/// Invalid or stale candidates are reported and skipped. Every accepted
/// replacement is returned in one pane-graph transition so the caller can
/// apply the valid subset atomically without making startup destructive.
enum WorkspacePaneZmxAnchorRepairPlanner {
    private enum EntryDecision {
        case changed(WorkspacePaneStateTransitionReplacement)
        case rejected(WorkspacePaneZmxAnchorRepairRejection)
        case unchanged(UUID)
    }

    static func plan(
        _ requests: [WorkspacePaneZmxAnchorRepairRequest],
        currentPaneStateByID: [UUID: PaneGraphState]
    ) -> WorkspacePaneZmxAnchorRepairDecision {
        let requestCountByPaneID = requestCountsByPaneID(requests)
        var duplicateRejections = Set<UUID>()
        var replacements: [WorkspacePaneStateTransitionReplacement] = []
        var acceptedPaneIDs: [UUID] = []
        var unchangedPaneIDs: [UUID] = []
        var rejections: [WorkspacePaneZmxAnchorRepairRejection] = []
        replacements.reserveCapacity(requests.count)
        acceptedPaneIDs.reserveCapacity(requests.count)
        unchangedPaneIDs.reserveCapacity(requests.count)
        rejections.reserveCapacity(requests.count)

        for request in requests {
            if requestCountByPaneID[request.paneID, default: 0] > 1 {
                if duplicateRejections.insert(request.paneID).inserted {
                    rejections.append(
                        WorkspacePaneZmxAnchorRepairRejection(
                            paneID: request.paneID,
                            reason: .duplicateRequest
                        )
                    )
                }
                continue
            }
            switch classify(
                request,
                currentPaneState: currentPaneStateByID[request.paneID]
            ) {
            case .changed(let replacement):
                replacements.append(replacement)
                acceptedPaneIDs.append(request.paneID)
            case .unchanged(let paneID):
                unchangedPaneIDs.append(paneID)
            case .rejected(let rejection):
                rejections.append(rejection)
            }
        }

        let report = WorkspacePaneZmxAnchorRepairReport(
            acceptedPaneIDs: acceptedPaneIDs,
            unchangedPaneIDs: unchangedPaneIDs,
            rejections: rejections
        )
        guard !replacements.isEmpty else {
            return .unchanged(report)
        }
        return .changed(
            transition: WorkspacePaneGraphTransition(replacements: replacements),
            report: report
        )
    }

    private static func requestCountsByPaneID(
        _ requests: [WorkspacePaneZmxAnchorRepairRequest]
    ) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(requests.count)
        for request in requests {
            counts[request.paneID, default: 0] += 1
        }
        return counts
    }

    private static func classify(
        _ request: WorkspacePaneZmxAnchorRepairRequest,
        currentPaneState: PaneGraphState?
    ) -> EntryDecision {
        guard let currentPaneState else {
            return .rejected(.init(paneID: request.paneID, reason: .paneMissing))
        }
        guard currentPaneState.id == request.paneID else {
            return .rejected(
                .init(
                    paneID: request.paneID,
                    reason: .paneIdentityMismatch(currentPaneID: currentPaneState.id)
                )
            )
        }
        guard case .terminal(var terminalState) = currentPaneState.content else {
            return .rejected(.init(paneID: request.paneID, reason: .contentIsNotTerminal))
        }
        guard terminalState.provider == .zmx else {
            return .rejected(
                .init(
                    paneID: request.paneID,
                    reason: .providerMismatch(received: terminalState.provider)
                )
            )
        }
        guard sessionIDMatchesPaneKind(request.sessionID, paneState: currentPaneState) else {
            return .rejected(
                .init(paneID: request.paneID, reason: .sessionIDDoesNotMatchPaneKind)
            )
        }
        guard terminalState.zmxSessionId != request.sessionID else {
            return .unchanged(request.paneID)
        }

        terminalState.zmxSessionId = request.sessionID
        var replacementState = currentPaneState
        replacementState.content = .terminal(terminalState)
        return .changed(
            WorkspacePaneStateTransitionReplacement(
                paneID: request.paneID,
                expectedCurrentState: currentPaneState,
                replacementState: replacementState
            )
        )
    }

    private static func sessionIDMatchesPaneKind(
        _ sessionID: String,
        paneState: PaneGraphState
    ) -> Bool {
        switch paneState.kind {
        case .layout:
            ZmxBackend.isValidStoredLayoutPaneSessionId(sessionID, paneId: paneState.id)
        case .drawerChild(let parentPaneID):
            ZmxBackend.isValidStoredDrawerSessionId(
                sessionID,
                parentPaneId: parentPaneID,
                drawerPaneId: paneState.id
            )
        }
    }
}
