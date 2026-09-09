import Foundation

/// A complete pane graph that has passed the pane domain's normalization and
/// relational invariants. Its initializer is intentionally private so full
/// atom replacement cannot bypass validation.
struct WorkspacePaneGraphReplacement: Equatable, Sendable {
    let paneStates: [UUID: PaneGraphState]

    private init(paneStates: [UUID: PaneGraphState]) {
        self.paneStates = paneStates
    }

    static func prepare(
        _ proposedPaneStates: [UUID: PaneGraphState]
    ) -> Result<Self, WorkspacePaneGraphReplacementRejection> {
        for (paneID, paneState) in proposedPaneStates where paneID != paneState.id {
            return .failure(.paneKeyIdentityMismatch(key: paneID, paneID: paneState.id))
        }

        let validPaneIDs = Set(proposedPaneStates.keys)
        var normalizedPaneStates = proposedPaneStates
        for paneID in normalizedPaneStates.keys {
            normalizedPaneStates[paneID]?.withDrawer { drawer in
                drawer.paneIds.removeAll { !validPaneIDs.contains($0) }
            }
        }

        var parentPaneIDByDrawerID: [UUID: UUID] = [:]
        var parentPaneIDByChildPaneID: [UUID: UUID] = [:]
        for paneState in normalizedPaneStates.values {
            guard let drawer = paneState.drawer else { continue }
            guard drawer.parentPaneId == paneState.id else {
                return .failure(
                    .drawerParentMismatch(
                        drawerID: drawer.drawerId,
                        expectedParentPaneID: paneState.id,
                        actualParentPaneID: drawer.parentPaneId
                    )
                )
            }
            guard parentPaneIDByDrawerID.updateValue(paneState.id, forKey: drawer.drawerId) == nil else {
                return .failure(.duplicateDrawerIdentity(drawer.drawerId))
            }
            for childPaneID in drawer.paneIds {
                guard parentPaneIDByChildPaneID.updateValue(paneState.id, forKey: childPaneID) == nil else {
                    return .failure(.duplicateDrawerChildMembership(childPaneID))
                }
                guard let childPaneState = normalizedPaneStates[childPaneID],
                    let actualParentPaneID = childPaneState.parentPaneId
                else {
                    preconditionFailure("normalized drawer membership retained a missing pane")
                }
                guard actualParentPaneID == paneState.id else {
                    return .failure(
                        .drawerChildParentMismatch(
                            childPaneID: childPaneID,
                            expectedParentPaneID: paneState.id,
                            actualParentPaneID: actualParentPaneID
                        )
                    )
                }
            }
        }

        for paneState in normalizedPaneStates.values {
            guard let parentPaneID = paneState.parentPaneId else { continue }
            guard parentPaneIDByChildPaneID[paneState.id] == parentPaneID else {
                return .failure(
                    .orphanDrawerChild(
                        childPaneID: paneState.id,
                        parentPaneID: parentPaneID
                    )
                )
            }
        }

        return .success(Self(paneStates: normalizedPaneStates))
    }
}
