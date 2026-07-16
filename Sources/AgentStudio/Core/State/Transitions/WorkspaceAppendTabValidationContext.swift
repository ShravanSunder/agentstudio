import Foundation

enum WorkspaceExistingActiveTabSelection: Equatable, Sendable {
    case noSelection
    case selected(UUID)
}

enum WorkspaceAlignedTabOwnerIndexRejection: Equatable, Sendable {
    case duplicateShellTabID(UUID)
    case duplicateGraphTabID(UUID)
    case duplicateRelevantTabID(UUID)
    case tabOwnerCountMismatch(shellCount: Int, graphCount: Int)
    case relevantTabMembershipMismatch(tabID: UUID, shellContains: Bool, graphContains: Bool)
    case tabIDSetMismatch(shellOnly: Set<UUID>, graphOnly: Set<UUID>)
    case tabOrderMismatch(index: Int, shellTabID: UUID, graphTabID: UUID)
}

enum WorkspaceAlignedTabOwnerIndexPreparation: Equatable, Sendable {
    case validated(WorkspaceAlignedTabOwnerIndex)
    case rejected(WorkspaceAlignedTabOwnerIndexRejection)
}

struct WorkspaceAlignedTabOwnerIndex: Equatable, Sendable {
    private enum Membership: Equatable, Sendable {
        case complete(Set<UUID>)
        case relevant([UUID: Bool])
    }

    private let tabCount: Int
    private let membership: Membership

    private init(tabCount: Int, membership: Membership) {
        self.tabCount = tabCount
        self.membership = membership
    }

    var count: Int { tabCount }

    func contains(_ tabID: UUID) -> Bool {
        switch membership {
        case .complete(let tabIDs):
            return tabIDs.contains(tabID)
        case .relevant(let membershipByTabID):
            guard let containsTab = membershipByTabID[tabID] else {
                preconditionFailure("relevant tab membership must be captured before validation")
            }
            return containsTab
        }
    }

    static func prepare(
        shellTabIDs: [UUID],
        graphTabIDs: [UUID]
    ) -> WorkspaceAlignedTabOwnerIndexPreparation {
        if let duplicateTabID = firstDuplicate(in: shellTabIDs) {
            return .rejected(.duplicateShellTabID(duplicateTabID))
        }
        if let duplicateTabID = firstDuplicate(in: graphTabIDs) {
            return .rejected(.duplicateGraphTabID(duplicateTabID))
        }
        let shellTabIDSet = Set(shellTabIDs)
        let graphTabIDSet = Set(graphTabIDs)
        guard shellTabIDSet == graphTabIDSet else {
            return .rejected(
                .tabIDSetMismatch(
                    shellOnly: shellTabIDSet.subtracting(graphTabIDSet),
                    graphOnly: graphTabIDSet.subtracting(shellTabIDSet)
                )
            )
        }
        for index in shellTabIDs.indices where shellTabIDs[index] != graphTabIDs[index] {
            return .rejected(
                .tabOrderMismatch(
                    index: index,
                    shellTabID: shellTabIDs[index],
                    graphTabID: graphTabIDs[index]
                )
            )
        }
        return .validated(Self(tabCount: shellTabIDs.count, membership: .complete(shellTabIDSet)))
    }

    /// Captures only membership facts the proposed append will query.
    ///
    /// This is valid only after startup established full shell/graph alignment
    /// and the installed steady-state gateway became their sole paired writer.
    static func prepareRelevant(
        shellTabCount: Int,
        graphTabCount: Int,
        memberships: [WorkspaceRelevantTabOwnerMembership]
    ) -> WorkspaceAlignedTabOwnerIndexPreparation {
        guard shellTabCount == graphTabCount else {
            return .rejected(
                .tabOwnerCountMismatch(
                    shellCount: shellTabCount,
                    graphCount: graphTabCount
                )
            )
        }
        var membershipByTabID: [UUID: Bool] = [:]
        membershipByTabID.reserveCapacity(memberships.count)
        for membership in memberships {
            guard membership.shellContains == membership.graphContains else {
                return .rejected(
                    .relevantTabMembershipMismatch(
                        tabID: membership.tabID,
                        shellContains: membership.shellContains,
                        graphContains: membership.graphContains
                    )
                )
            }
            guard membershipByTabID.updateValue(membership.shellContains, forKey: membership.tabID) == nil else {
                return .rejected(.duplicateRelevantTabID(membership.tabID))
            }
        }
        return .validated(Self(tabCount: shellTabCount, membership: .relevant(membershipByTabID)))
    }
}

struct WorkspaceRelevantTabOwnerMembership: Equatable, Sendable {
    let tabID: UUID
    let shellContains: Bool
    let graphContains: Bool
}

enum WorkspacePanePlacementDescriptor: Equatable, Sendable {
    case mainLayout(paneID: UUID)
    case drawerParent(paneID: UUID, drawerID: UUID, drawerChildPaneIDs: Set<UUID>)
    case drawerChild(paneID: UUID, parentPaneID: UUID)

    var paneID: UUID {
        switch self {
        case .mainLayout(let paneID), .drawerParent(let paneID, _, _), .drawerChild(let paneID, _):
            paneID
        }
    }
}

enum WorkspacePanePlacementIndexRejection: Equatable, Sendable {
    case duplicatePaneID(UUID)
    case duplicateDrawerID(UUID)
    case duplicateDrawerChildMembership(UUID)
    case drawerChildPaneMissing(childPaneID: UUID, parentPaneID: UUID)
    case drawerChildUsesMainLayoutPane(childPaneID: UUID, parentPaneID: UUID)
    case drawerChildParentMismatch(childPaneID: UUID, expectedParentPaneID: UUID, actualParentPaneID: UUID)
    case drawerChildParentMissing(childPaneID: UUID, parentPaneID: UUID)
    case drawerChildParentHasNoDrawer(childPaneID: UUID, parentPaneID: UUID)
    case drawerChildParentIsDrawerChild(childPaneID: UUID, parentPaneID: UUID)
    case drawerChildMembershipMissing(childPaneID: UUID, parentPaneID: UUID)
}

enum WorkspacePanePlacementIndexPreparation: Equatable, Sendable {
    case validated(WorkspacePanePlacementIndex)
    case rejected(WorkspacePanePlacementIndexRejection)
}

enum WorkspacePanePlacementLookup: Equatable, Sendable {
    case missing
    case mainLayout
    case drawerParent(drawerID: UUID)
    case drawerChild(parentPaneID: UUID)
}

struct WorkspaceDrawerPlacementCapability: Equatable, Sendable {
    let parentPaneID: UUID
    let childPaneIDs: Set<UUID>
}

enum WorkspaceDrawerPlacementLookup: Equatable, Sendable {
    case missing
    case found(WorkspaceDrawerPlacementCapability)
}

struct WorkspacePanePlacementIndex: Equatable, Sendable {
    private let placementByPaneID: [UUID: WorkspacePanePlacementLookup]
    private let drawerByID: [UUID: WorkspaceDrawerPlacementCapability]

    func placement(for paneID: UUID) -> WorkspacePanePlacementLookup {
        placementByPaneID[paneID] ?? .missing
    }

    func drawer(for drawerID: UUID) -> WorkspaceDrawerPlacementLookup {
        drawerByID[drawerID].map(WorkspaceDrawerPlacementLookup.found) ?? .missing
    }

    /// A fixed-cardinality validation context for a prospective one-pane tab.
    /// It deliberately contains no established fleet state because that tab
    /// cannot reference any established pane or drawer placement.
    static func prospectiveLayoutPane(
        paneID: UUID,
        drawerID: UUID
    ) -> Self {
        Self(
            placementByPaneID: [paneID: .drawerParent(drawerID: drawerID)],
            drawerByID: [
                drawerID: WorkspaceDrawerPlacementCapability(
                    parentPaneID: paneID,
                    childPaneIDs: []
                )
            ]
        )
    }

    static func prepare(
        _ descriptors: [WorkspacePanePlacementDescriptor]
    ) -> WorkspacePanePlacementIndexPreparation {
        var descriptorByPaneID: [UUID: WorkspacePanePlacementDescriptor] = [:]
        var drawerByID: [UUID: WorkspaceDrawerPlacementCapability] = [:]
        for descriptor in descriptors {
            guard descriptorByPaneID.updateValue(descriptor, forKey: descriptor.paneID) == nil else {
                return .rejected(.duplicatePaneID(descriptor.paneID))
            }
            guard case .drawerParent(let paneID, let drawerID, let childPaneIDs) = descriptor else { continue }
            guard
                drawerByID.updateValue(
                    .init(parentPaneID: paneID, childPaneIDs: childPaneIDs),
                    forKey: drawerID
                ) == nil
            else {
                return .rejected(.duplicateDrawerID(drawerID))
            }
        }

        switch validateDrawerMembership(
            descriptorByPaneID: descriptorByPaneID,
            drawerByID: drawerByID
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .validated:
            break
        }

        return .validated(
            Self(
                placementByPaneID: descriptorByPaneID.mapValues { descriptor in
                    switch descriptor {
                    case .mainLayout:
                        .mainLayout
                    case .drawerParent(_, let drawerID, _):
                        .drawerParent(drawerID: drawerID)
                    case .drawerChild(_, let parentPaneID):
                        .drawerChild(parentPaneID: parentPaneID)
                    }
                },
                drawerByID: drawerByID
            )
        )
    }

    private static func validateDrawerMembership(
        descriptorByPaneID: [UUID: WorkspacePanePlacementDescriptor],
        drawerByID: [UUID: WorkspaceDrawerPlacementCapability]
    ) -> WorkspacePanePlacementIndexValidation {
        var claimedChildPaneIDs: Set<UUID> = []
        for drawer in drawerByID.values {
            for childPaneID in drawer.childPaneIDs {
                guard claimedChildPaneIDs.insert(childPaneID).inserted else {
                    return .rejected(.duplicateDrawerChildMembership(childPaneID))
                }
                guard let childDescriptor = descriptorByPaneID[childPaneID] else {
                    return .rejected(
                        .drawerChildPaneMissing(
                            childPaneID: childPaneID,
                            parentPaneID: drawer.parentPaneID
                        )
                    )
                }
                switch childDescriptor {
                case .mainLayout, .drawerParent:
                    return .rejected(
                        .drawerChildUsesMainLayoutPane(
                            childPaneID: childPaneID,
                            parentPaneID: drawer.parentPaneID
                        )
                    )
                case .drawerChild(_, let actualParentPaneID):
                    guard actualParentPaneID == drawer.parentPaneID else {
                        return .rejected(
                            .drawerChildParentMismatch(
                                childPaneID: childPaneID,
                                expectedParentPaneID: drawer.parentPaneID,
                                actualParentPaneID: actualParentPaneID
                            )
                        )
                    }
                }
            }
        }

        for descriptor in descriptorByPaneID.values {
            guard case .drawerChild(let childPaneID, let parentPaneID) = descriptor else { continue }
            guard let parentDescriptor = descriptorByPaneID[parentPaneID] else {
                return .rejected(.drawerChildParentMissing(childPaneID: childPaneID, parentPaneID: parentPaneID))
            }
            switch parentDescriptor {
            case .mainLayout:
                return .rejected(
                    .drawerChildParentHasNoDrawer(
                        childPaneID: childPaneID,
                        parentPaneID: parentPaneID
                    )
                )
            case .drawerChild:
                return .rejected(
                    .drawerChildParentIsDrawerChild(
                        childPaneID: childPaneID,
                        parentPaneID: parentPaneID
                    )
                )
            case .drawerParent(_, _, let childPaneIDs):
                guard childPaneIDs.contains(childPaneID) else {
                    return .rejected(
                        .drawerChildMembershipMissing(
                            childPaneID: childPaneID,
                            parentPaneID: parentPaneID
                        )
                    )
                }
            }
        }
        return .validated
    }
}

struct WorkspaceAppendTabContext: Equatable, Sendable {
    let activeTab: WorkspaceExistingActiveTabSelection
    let alignedTabOwners: WorkspaceAlignedTabOwnerIndex
    let panePlacements: WorkspacePanePlacementIndex
    let paneOwnerByPaneID: [UUID: UUID]
    let existingArrangementIDs: Set<UUID>
    let existingActiveArrangementTabIDs: Set<UUID>
    let existingActivePaneArrangementIDs: Set<UUID>
    let existingActiveDrawerChildKeys: Set<ArrangementDrawerCursorKey>
}

private enum WorkspacePanePlacementIndexValidation {
    case validated
    case rejected(WorkspacePanePlacementIndexRejection)
}

private func firstDuplicate(in values: [UUID]) -> UUID? {
    var seen: Set<UUID> = []
    for value in values where !seen.insert(value).inserted {
        return value
    }
    return nil
}
