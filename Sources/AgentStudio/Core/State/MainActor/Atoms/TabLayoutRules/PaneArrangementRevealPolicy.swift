import Foundation

package enum PaneArrangementRevealTarget: Equatable, Sendable {
    case mainPane(UUID)
    case drawerChild(paneID: UUID, parentPaneID: UUID, drawerID: UUID)

    package var paneID: UUID {
        switch self {
        case .mainPane(let paneID), .drawerChild(let paneID, _, _):
            paneID
        }
    }
}

package struct PaneArrangementRevealSelection: Equatable, Sendable {
    package let tabID: UUID
    package let arrangementID: UUID
    package let target: PaneArrangementRevealTarget
    package let requiresDrawerChildExpansion: Bool
    let capturedGraphRevision: Int
    let capturedActiveArrangementID: UUID
}

package struct PaneArrangementRevealSnapshot: Sendable {
    package let tabID: UUID
    let graphRevision: Int
    package let activeArrangementID: UUID
    let allPaneIDs: [UUID]
    let arrangements: [PaneArrangementGraphState]

    init(
        graphState: TabGraphState,
        graphRevision: Int,
        activeArrangementID: UUID
    ) {
        tabID = graphState.tabId
        self.graphRevision = graphRevision
        self.activeArrangementID = activeArrangementID
        allPaneIDs = graphState.allPaneIds
        arrangements = graphState.arrangements
    }
}

package enum PaneArrangementRevealPolicy {
    @concurrent nonisolated package static func resolve(
        target: PaneArrangementRevealTarget,
        from snapshot: PaneArrangementRevealSnapshot
    ) async -> PaneArrangementRevealSelection? {
        let allPaneIDs = Set(snapshot.allPaneIDs)
        guard containsCanonicalTargetIdentity(target, in: allPaneIDs),
            let currentArrangement = snapshot.arrangements.first(where: {
                $0.id == snapshot.activeArrangementID
            }),
            let defaultArrangement = snapshot.arrangements.first(where: \.isDefault)
        else { return nil }

        if qualifiesAsVisible(target, in: currentArrangement) {
            return selection(
                target: target,
                arrangement: currentArrangement,
                tabID: snapshot.tabID,
                snapshot: snapshot,
                requiresDrawerChildExpansion: false
            )
        }

        if let customArrangement = snapshot.arrangements.first(where: {
            !$0.isDefault
                && $0.id != currentArrangement.id
                && qualifiesAsVisible(target, in: $0)
        }) {
            return selection(
                target: target,
                arrangement: customArrangement,
                tabID: snapshot.tabID,
                snapshot: snapshot,
                requiresDrawerChildExpansion: false
            )
        }

        guard containsCanonicalTarget(target, in: defaultArrangement) else { return nil }
        return selection(
            target: target,
            arrangement: defaultArrangement,
            tabID: snapshot.tabID,
            snapshot: snapshot,
            requiresDrawerChildExpansion: defaultRequiresDrawerChildExpansion(
                target,
                in: defaultArrangement
            )
        )
    }

    private nonisolated static func containsCanonicalTargetIdentity(
        _ target: PaneArrangementRevealTarget,
        in allPaneIDs: Set<UUID>
    ) -> Bool {
        switch target {
        case .mainPane(let paneID):
            allPaneIDs.contains(paneID)
        case .drawerChild(let paneID, let parentPaneID, _):
            allPaneIDs.contains(paneID) && allPaneIDs.contains(parentPaneID)
        }
    }

    nonisolated static func containsCanonicalTarget(
        _ target: PaneArrangementRevealTarget,
        in arrangement: PaneArrangementGraphState
    ) -> Bool {
        switch target {
        case .mainPane(let paneID):
            arrangement.layout.contains(paneID)
        case .drawerChild(let paneID, let parentPaneID, let drawerID):
            arrangement.layout.contains(parentPaneID)
                && arrangement.drawerViews[drawerID]?.layout.contains(paneID) == true
        }
    }

    private nonisolated static func qualifiesAsVisible(
        _ target: PaneArrangementRevealTarget,
        in arrangement: PaneArrangementGraphState
    ) -> Bool {
        switch target {
        case .mainPane(let paneID):
            return arrangement.layout.contains(paneID)
                && !arrangement.minimizedPaneIds.contains(paneID)
        case .drawerChild(let paneID, let parentPaneID, let drawerID):
            guard arrangement.layout.contains(parentPaneID),
                !arrangement.minimizedPaneIds.contains(parentPaneID),
                let drawerView = arrangement.drawerViews[drawerID]
            else { return false }
            return drawerView.layout.contains(paneID)
                && !drawerView.minimizedPaneIds.contains(paneID)
        }
    }

    private nonisolated static func defaultRequiresDrawerChildExpansion(
        _ target: PaneArrangementRevealTarget,
        in arrangement: PaneArrangementGraphState
    ) -> Bool {
        guard case .drawerChild(let paneID, _, let drawerID) = target else { return false }
        return arrangement.drawerViews[drawerID]?.minimizedPaneIds.contains(paneID) == true
    }

    private nonisolated static func selection(
        target: PaneArrangementRevealTarget,
        arrangement: PaneArrangementGraphState,
        tabID: UUID,
        snapshot: PaneArrangementRevealSnapshot,
        requiresDrawerChildExpansion: Bool
    ) -> PaneArrangementRevealSelection {
        PaneArrangementRevealSelection(
            tabID: tabID,
            arrangementID: arrangement.id,
            target: target,
            requiresDrawerChildExpansion: requiresDrawerChildExpansion,
            capturedGraphRevision: snapshot.graphRevision,
            capturedActiveArrangementID: snapshot.activeArrangementID
        )
    }
}
