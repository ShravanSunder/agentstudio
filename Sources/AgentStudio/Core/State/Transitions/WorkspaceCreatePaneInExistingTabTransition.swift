import Foundation

enum WorkspaceNewPaneIdentity: Equatable, Sendable {
    case pane
    case drawer
}

enum WorkspaceNewPaneIDRejection: Equatable, Sendable {
    case nonUUIDv7(identity: WorkspaceNewPaneIdentity, value: UUID)
    case duplicateIdentity(UUID)
}

enum WorkspaceNewPaneIDsPreparation: Equatable, Sendable {
    case validated(WorkspaceNewPaneIDs)
    case rejected(WorkspaceNewPaneIDRejection)
}

struct WorkspaceNewPaneIDs: Equatable, Sendable {
    let paneID: PaneId
    let drawerID: UUID

    private init(paneID: PaneId, drawerID: UUID) {
        self.paneID = paneID
        self.drawerID = drawerID
    }

    static func prepare(paneID: UUID, drawerID: UUID) -> WorkspaceNewPaneIDsPreparation {
        guard UUIDv7.isV7(paneID) else {
            return .rejected(.nonUUIDv7(identity: .pane, value: paneID))
        }
        guard UUIDv7.isV7(drawerID) else {
            return .rejected(.nonUUIDv7(identity: .drawer, value: drawerID))
        }
        guard paneID != drawerID else { return .rejected(.duplicateIdentity(paneID)) }
        return .validated(Self(paneID: .init(existingUUID: paneID), drawerID: drawerID))
    }
}

struct WorkspaceCreatePaneInExistingTabRequest: Equatable, Sendable {
    let identities: WorkspaceNewPaneIDs
    let content: WorkspaceResolvedPaneContent
    let metadata: PaneMetadata
    let residency: SessionResidency
    let targetTabID: UUID
    let targetPaneID: UUID
    let direction: Layout.SplitDirection
    let position: Layout.Position
    let sizingMode: DropSizingMode
}

enum WorkspaceProposedPaneIdentityWitness: Equatable, Sendable {
    case vacant
    case paneGraphOccupied
    case tabOwned(tabID: UUID)
    case paneGraphOccupiedAndTabOwned(tabID: UUID)
}

enum WorkspaceProposedDrawerIdentityWitness: Equatable, Sendable {
    case vacant
    case owned(parentPaneID: UUID)
}

enum WorkspaceCreatePaneTargetTabWitness: Equatable, Sendable {
    case missing
    case present(TabGraphState)
}

struct WorkspaceCreatePaneArrangementCursorWitness: Equatable, Sendable {
    let arrangementID: UUID
    let cursor: WorkspaceActivePaneCursorWitness
}

struct WorkspaceCreatePaneInExistingTabPlanningContext: Equatable, Sendable {
    let proposedPane: WorkspaceProposedPaneIdentityWitness
    let proposedDrawer: WorkspaceProposedDrawerIdentityWitness
    let targetTab: WorkspaceCreatePaneTargetTabWitness
    let activeArrangement: WorkspaceActiveArrangementSelection
    let activePaneCursors: [WorkspaceCreatePaneArrangementCursorWitness]
    let zoom: WorkspaceZoomSelection
}

enum WorkspaceCreatePaneActivePaneMutation: Equatable, Sendable {
    case witness(arrangementID: UUID, expected: WorkspaceActivePaneCursorWitness)
    case replace(
        arrangementID: UUID,
        previous: WorkspaceActivePaneCursorWitness,
        replacement: WorkspacePaneSelection
    )
}

enum WorkspaceCreatePaneZoomMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previousPaneID: UUID)
}

struct WorkspaceCreatePaneInExistingTabTransition: Equatable, Sendable {
    let paneInsertion: PaneGraphState
    let previousTab: TabGraphState
    let replacementTab: TabGraphState
    let activeArrangement: WorkspaceActiveArrangementSelection
    let activePaneMutations: [WorkspaceCreatePaneActivePaneMutation]
    let zoom: WorkspaceCreatePaneZoomMutation

    var presentationPane: Pane {
        paneInsertion.pane(isDrawerExpanded: false)
    }
}

enum WorkspaceCreatePaneInExistingTabDecision: Equatable, Sendable {
    case changed(WorkspaceCreatePaneInExistingTabTransition)
    case rejected(WorkspaceCreatePaneInExistingTabRejection)
}

enum WorkspaceCreatePaneInExistingTabRejection: Error, Equatable, Sendable {
    case activeArrangementMissing(UUID)
    case activeArrangementNotInTab(tabID: UUID, arrangementID: UUID)
    case arrangementLayoutEmpty(UUID)
    case duplicateArrangementIdentity(UUID)
    case cursorArrangementDuplicate(UUID)
    case cursorArrangementUnknown(UUID)
    case cursorInvalid(arrangementID: UUID, cursor: WorkspaceActivePaneCursorWitness)
    case cursorMissing(UUID)
    case drawerIdentityAlreadyOwned(drawerID: UUID, parentPaneID: UUID)
    case duplicateExistingPaneID(UUID)
    case layoutInsertionRejected(tabID: UUID, targetPaneID: UUID)
    case paneIdentityAlreadyExists(UUID)
    case paneIdentityAlreadyOwned(paneID: UUID, tabID: UUID)
    case paneIdentityAlreadyExistsAndOwned(paneID: UUID, tabID: UUID)
    case tabIdentityMismatch(expected: UUID, actual: UUID)
    case targetPaneMissing(tabID: UUID, paneID: UUID)
    case targetTabMissing(UUID)
}

enum WorkspaceCreatePaneInExistingTabTransitionPlanner {
    static func plan(
        _ request: WorkspaceCreatePaneInExistingTabRequest,
        context: WorkspaceCreatePaneInExistingTabPlanningContext
    ) -> WorkspaceCreatePaneInExistingTabDecision {
        if let rejection = validateIdentityVacancy(request, context: context) {
            return .rejected(rejection)
        }
        let tab: TabGraphState
        switch resolveTargetTab(request.targetTabID, witness: context.targetTab) {
        case .success(let witnessedTab):
            tab = witnessedTab
        case .failure(let rejection):
            return .rejected(rejection)
        }
        if let duplicatePaneID = firstDuplicate(tab.allPaneIds) {
            return .rejected(.duplicateExistingPaneID(duplicatePaneID))
        }

        let activeArrangementID: UUID
        switch context.activeArrangement {
        case .missing:
            return .rejected(.activeArrangementMissing(tab.tabId))
        case .selected(let arrangementID):
            activeArrangementID = arrangementID
        }
        guard let activeArrangementIndex = tab.arrangements.firstIndex(where: { $0.id == activeArrangementID }) else {
            return .rejected(.activeArrangementNotInTab(tabID: tab.tabId, arrangementID: activeArrangementID))
        }
        guard tab.arrangements[activeArrangementIndex].layout.contains(request.targetPaneID) else {
            return .rejected(.targetPaneMissing(tabID: tab.tabId, paneID: request.targetPaneID))
        }

        let cursors: [UUID: WorkspaceActivePaneCursorWitness]
        switch validateCursors(context.activePaneCursors, arrangements: tab.arrangements) {
        case .success(let validated): cursors = validated
        case .failure(let rejection): return .rejected(rejection)
        }

        guard
            let insertedActiveLayout = tab.arrangements[activeArrangementIndex].layout.inserting(
                paneId: request.identities.paneID.uuid,
                at: request.targetPaneID,
                direction: request.direction,
                position: request.position,
                sizingMode: request.sizingMode
            )
        else {
            return .rejected(.layoutInsertionRejected(tabID: tab.tabId, targetPaneID: request.targetPaneID))
        }

        var replacement = tab
        replacement.allPaneIds.append(request.identities.paneID.uuid)
        var cursorMutations: [WorkspaceCreatePaneActivePaneMutation] = []
        cursorMutations.reserveCapacity(tab.arrangements.count)
        for index in replacement.arrangements.indices {
            let arrangementID = replacement.arrangements[index].id
            guard let cursor = cursors[arrangementID] else {
                return .rejected(.cursorMissing(arrangementID))
            }
            if index == activeArrangementIndex {
                replacement.arrangements[index].layout = insertedActiveLayout
                cursorMutations.append(
                    .replace(
                        arrangementID: arrangementID,
                        previous: cursor,
                        replacement: .selected(request.identities.paneID.uuid)
                    )
                )
            } else {
                let previousLayout = replacement.arrangements[index].layout
                guard let anchor = previousLayout.paneIds.last else {
                    return .rejected(.arrangementLayoutEmpty(arrangementID))
                }
                guard
                    let appended = previousLayout.inserting(
                        paneId: request.identities.paneID.uuid,
                        at: anchor,
                        direction: .horizontal,
                        position: .after,
                        sizingMode: .proportional
                    )
                else {
                    return .rejected(.layoutInsertionRejected(tabID: tab.tabId, targetPaneID: anchor))
                }
                replacement.arrangements[index].layout = appended
                cursorMutations.append(.witness(arrangementID: arrangementID, expected: cursor))
            }
            replacement.arrangements[index].minimizedPaneIds.remove(request.identities.paneID.uuid)
        }

        return .changed(
            .init(
                paneInsertion: .init(pane: makePane(request)),
                previousTab: tab,
                replacementTab: replacement,
                activeArrangement: context.activeArrangement,
                activePaneMutations: cursorMutations,
                zoom: makeZoomMutation(tabID: tab.tabId, witness: context.zoom)
            )
        )
    }

    private static func resolveTargetTab(
        _ targetTabID: UUID,
        witness: WorkspaceCreatePaneTargetTabWitness
    ) -> Result<TabGraphState, WorkspaceCreatePaneInExistingTabRejection> {
        switch witness {
        case .missing:
            return .failure(.targetTabMissing(targetTabID))
        case .present(let tab) where tab.tabId != targetTabID:
            return .failure(.tabIdentityMismatch(expected: targetTabID, actual: tab.tabId))
        case .present(let tab):
            return .success(tab)
        }
    }

    private static func makePane(_ request: WorkspaceCreatePaneInExistingTabRequest) -> Pane {
        Pane(
            id: request.identities.paneID.uuid,
            content: request.content.paneContent(for: request.identities.paneID),
            metadata: request.metadata,
            residency: request.residency,
            kind: .layout(
                drawer: Drawer(
                    drawerId: request.identities.drawerID,
                    parentPaneId: request.identities.paneID.uuid
                )
            )
        )
    }

    private static func makeZoomMutation(
        tabID: UUID,
        witness: WorkspaceZoomSelection
    ) -> WorkspaceCreatePaneZoomMutation {
        switch witness {
        case .notZoomed: .witness(tabID: tabID, expected: .notZoomed)
        case .zoomed(let paneID): .clear(tabID: tabID, previousPaneID: paneID)
        }
    }

    private static func validateIdentityVacancy(
        _ request: WorkspaceCreatePaneInExistingTabRequest,
        context: WorkspaceCreatePaneInExistingTabPlanningContext
    ) -> WorkspaceCreatePaneInExistingTabRejection? {
        switch context.proposedPane {
        case .vacant: break
        case .paneGraphOccupied: return .paneIdentityAlreadyExists(request.identities.paneID.uuid)
        case .tabOwned(let tabID):
            return .paneIdentityAlreadyOwned(paneID: request.identities.paneID.uuid, tabID: tabID)
        case .paneGraphOccupiedAndTabOwned(let tabID):
            return .paneIdentityAlreadyExistsAndOwned(paneID: request.identities.paneID.uuid, tabID: tabID)
        }
        switch context.proposedDrawer {
        case .vacant: return nil
        case .owned(let parentPaneID):
            return .drawerIdentityAlreadyOwned(
                drawerID: request.identities.drawerID,
                parentPaneID: parentPaneID
            )
        }
    }

    private static func validateCursors(
        _ witnesses: [WorkspaceCreatePaneArrangementCursorWitness],
        arrangements: [PaneArrangementGraphState]
    ) -> Result<[UUID: WorkspaceActivePaneCursorWitness], WorkspaceCreatePaneInExistingTabRejection> {
        var arrangementByID: [UUID: PaneArrangementGraphState] = [:]
        for arrangement in arrangements {
            guard arrangementByID.updateValue(arrangement, forKey: arrangement.id) == nil else {
                return .failure(.duplicateArrangementIdentity(arrangement.id))
            }
        }
        var cursors: [UUID: WorkspaceActivePaneCursorWitness] = [:]
        for witness in witnesses {
            guard let arrangement = arrangementByID[witness.arrangementID] else {
                return .failure(.cursorArrangementUnknown(witness.arrangementID))
            }
            guard cursors.updateValue(witness.cursor, forKey: witness.arrangementID) == nil else {
                return .failure(.cursorArrangementDuplicate(witness.arrangementID))
            }
            guard cursorIsValid(witness.cursor, arrangement: arrangement) else {
                return .failure(.cursorInvalid(arrangementID: witness.arrangementID, cursor: witness.cursor))
            }
        }
        for arrangement in arrangements where cursors[arrangement.id] == nil {
            return .failure(.cursorMissing(arrangement.id))
        }
        return .success(cursors)
    }

    private static func cursorIsValid(
        _ cursor: WorkspaceActivePaneCursorWitness,
        arrangement: PaneArrangementGraphState
    ) -> Bool {
        switch cursor {
        case .missing: return false
        case .present(.noSelection): return arrangement.layout.isEmpty
        case .present(.selected(let paneID)):
            return arrangement.layout.contains(paneID) && !arrangement.minimizedPaneIds.contains(paneID)
        }
    }
}

private func firstDuplicate(_ values: [UUID]) -> UUID? {
    var seen: Set<UUID> = []
    return values.first { !seen.insert($0).inserted }
}
