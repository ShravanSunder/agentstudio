import Foundation

enum WorkspaceTabCursorSelection: Equatable, Sendable {
    case noSelection
    case selected(UUID)
}

enum WorkspaceTabShellTransition: Equatable, Sendable {
    case insert(TabShell, at: Int)
}

enum WorkspaceActiveTabTransition: Equatable, Sendable {
    case select(UUID)
}

enum WorkspaceTabGraphTransition: Equatable, Sendable {
    case insert(TabGraphState, at: Int)
}

enum WorkspaceActiveArrangementTransition: Equatable, Sendable {
    case insert(tabID: UUID, arrangementID: UUID)
}

enum WorkspaceActivePaneTransition: Equatable, Sendable {
    case insert(arrangementID: UUID, selection: WorkspaceTabCursorSelection)
}

enum WorkspaceActiveDrawerChildTransition: Equatable, Sendable {
    case insert(key: ArrangementDrawerCursorKey, selection: WorkspaceTabCursorSelection)
}

struct WorkspaceTabTransition: Equatable, Sendable {
    let shell: WorkspaceTabShellTransition
    let activeTab: WorkspaceActiveTabTransition
    let graph: WorkspaceTabGraphTransition
    let activeArrangement: WorkspaceActiveArrangementTransition
    let activePanes: [WorkspaceActivePaneTransition]
    let activeDrawerChildren: [WorkspaceActiveDrawerChildTransition]

    private init(
        shell: WorkspaceTabShellTransition,
        activeTab: WorkspaceActiveTabTransition,
        graph: WorkspaceTabGraphTransition,
        activeArrangement: WorkspaceActiveArrangementTransition,
        activePanes: [WorkspaceActivePaneTransition],
        activeDrawerChildren: [WorkspaceActiveDrawerChildTransition]
    ) {
        self.shell = shell
        self.activeTab = activeTab
        self.graph = graph
        self.activeArrangement = activeArrangement
        self.activePanes = activePanes
        self.activeDrawerChildren = activeDrawerChildren
    }

    fileprivate static func appending(
        _ validatedTab: WorkspaceValidatedAppendTab,
        shellIndex: Int,
        graphIndex: Int
    ) -> Self {
        Self(
            shell: .insert(validatedTab.shell, at: shellIndex),
            activeTab: .select(validatedTab.tabID),
            graph: .insert(validatedTab.graph, at: graphIndex),
            activeArrangement: .insert(
                tabID: validatedTab.tabID,
                arrangementID: validatedTab.activeArrangementID
            ),
            activePanes: validatedTab.activePanes,
            activeDrawerChildren: validatedTab.activeDrawerChildren
        )
    }
}

enum WorkspaceTabTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabTransition)
    case unchanged
    case rejected(WorkspaceTabTransitionRejection)
}

enum WorkspaceTabTransitionRejection: Equatable, Sendable {
    case duplicateTabShellID(UUID)
    case invalidExistingActiveTabSelection(UUID)
    case emptyTabName(UUID)
    case invalidTabColorHex(tabID: UUID, colorHex: String)
    case duplicatePaneMembership(UUID)
    case paneAlreadyOwned(paneID: UUID, ownerTabID: UUID)
    case tabHasNoPanes(UUID)
    case missingArrangement(tabID: UUID)
    case invalidDefaultArrangementCount(tabID: UUID, count: Int)
    case defaultArrangementLayoutIsEmpty(tabID: UUID, arrangementID: UUID)
    case duplicateArrangementID(UUID)
    case existingArrangementID(UUID)
    case invalidActiveArrangement(tabID: UUID, arrangementID: UUID)
    case duplicateLayoutPaneID(arrangementID: UUID, paneID: UUID)
    case duplicateLayoutDividerID(arrangementID: UUID, dividerID: UUID)
    case duplicateDrawerLayoutPaneID(key: ArrangementDrawerCursorKey, paneID: UUID)
    case duplicateDrawerLayoutDividerID(key: ArrangementDrawerCursorKey, dividerID: UUID)
    case drawerViewLayoutIsEmpty(key: ArrangementDrawerCursorKey)
    case duplicatePanePlacement(arrangementID: UUID, paneID: UUID)
    case panePlacementMissing(UUID)
    case arrangementLayoutUsesDrawerChild(arrangementID: UUID, paneID: UUID, parentPaneID: UUID)
    case drawerCapabilityMissing(key: ArrangementDrawerCursorKey)
    case drawerParentPaneMissingFromLayout(key: ArrangementDrawerCursorKey, parentPaneID: UUID)
    case drawerViewUsesMainLayoutPane(key: ArrangementDrawerCursorKey, paneID: UUID)
    case drawerViewChildParentMismatch(
        key: ArrangementDrawerCursorKey,
        paneID: UUID,
        expectedParentPaneID: UUID,
        actualParentPaneID: UUID
    )
    case drawerViewPaneNotInDrawer(key: ArrangementDrawerCursorKey, paneID: UUID)
    case paneMissingFromTabMembership(arrangementID: UUID, paneID: UUID)
    case drawerPaneMissingFromTabMembership(key: ArrangementDrawerCursorKey, paneID: UUID)
    case minimizedPaneMissingFromLayout(arrangementID: UUID, paneID: UUID)
    case minimizedDrawerPaneMissingFromLayout(key: ArrangementDrawerCursorKey, paneID: UUID)
    case invalidActivePaneSelection(arrangementID: UUID, paneID: UUID)
    case invalidActiveDrawerChildSelection(key: ArrangementDrawerCursorKey, paneID: UUID)
    case mismatchedPaneMembership(declared: Set<UUID>, referenced: Set<UUID>)
    case existingActiveArrangementCursor(tabID: UUID)
    case existingActivePaneCursor(arrangementID: UUID)
    case existingActiveDrawerChildCursor(key: ArrangementDrawerCursorKey)
}

enum WorkspaceAppendTabTransitionDecider {
    static func decide(
        tab: Tab,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceTabTransitionDecision {
        switch validateContext(for: tab, context: context) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .accepted:
            break
        }

        switch validate(tab: tab, context: context) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .accepted(let validatedTab):
            return .changed(
                .appending(
                    validatedTab,
                    shellIndex: context.alignedTabOwners.count,
                    graphIndex: context.alignedTabOwners.count
                )
            )
        }
    }

    private static func validateContext(
        for tab: Tab,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceAppendContextValidation {
        if context.alignedTabOwners.contains(tab.id) {
            return .rejected(.duplicateTabShellID(tab.id))
        }
        if case .selected(let activeTabID) = context.activeTab,
            !context.alignedTabOwners.contains(activeTabID)
        {
            return .rejected(.invalidExistingActiveTabSelection(activeTabID))
        }
        if context.existingActiveArrangementTabIDs.contains(tab.id) {
            return .rejected(.existingActiveArrangementCursor(tabID: tab.id))
        }
        return .accepted
    }

    private static func validate(
        tab: Tab,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceAppendTabValidation {
        let normalizedName = Tab.normalizedName(tab.name)
        guard !normalizedName.isEmpty else {
            return .rejected(.emptyTabName(tab.id))
        }
        if let colorHex = tab.colorHex, !isCanonicalColorHex(colorHex) {
            return .rejected(.invalidTabColorHex(tabID: tab.id, colorHex: colorHex))
        }
        if let duplicatePaneID = firstDuplicate(in: tab.allPaneIds) {
            return .rejected(.duplicatePaneMembership(duplicatePaneID))
        }
        guard !tab.allPaneIds.isEmpty else {
            return .rejected(.tabHasNoPanes(tab.id))
        }
        for paneID in tab.allPaneIds {
            if let ownerTabID = context.paneOwnerByPaneID[paneID] {
                return .rejected(.paneAlreadyOwned(paneID: paneID, ownerTabID: ownerTabID))
            }
        }
        guard !tab.arrangements.isEmpty else {
            return .rejected(.missingArrangement(tabID: tab.id))
        }
        let defaultArrangementCount = tab.arrangements.count(where: \.isDefault)
        guard defaultArrangementCount == 1 else {
            return .rejected(
                .invalidDefaultArrangementCount(
                    tabID: tab.id,
                    count: defaultArrangementCount
                )
            )
        }
        guard let defaultArrangement = tab.arrangements.first(where: \.isDefault) else {
            return .rejected(.invalidDefaultArrangementCount(tabID: tab.id, count: 0))
        }
        guard !defaultArrangement.layout.isEmpty else {
            return .rejected(
                .defaultArrangementLayoutIsEmpty(
                    tabID: tab.id,
                    arrangementID: defaultArrangement.id
                )
            )
        }

        var seenArrangementIDs: Set<UUID> = []
        for arrangement in tab.arrangements {
            guard seenArrangementIDs.insert(arrangement.id).inserted else {
                return .rejected(.duplicateArrangementID(arrangement.id))
            }
            if context.existingArrangementIDs.contains(arrangement.id) {
                return .rejected(.existingArrangementID(arrangement.id))
            }
        }
        guard seenArrangementIDs.contains(tab.activeArrangementId) else {
            return .rejected(
                .invalidActiveArrangement(
                    tabID: tab.id,
                    arrangementID: tab.activeArrangementId
                )
            )
        }

        return validateArrangementContent(tab: tab, context: context)
    }

    private static func validateArrangementContent(
        tab: Tab,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceAppendTabValidation {
        let declaredPaneIDs = Set(tab.allPaneIds)
        var referencedPaneIDs: Set<UUID> = []
        var activePaneTransitions: [WorkspaceActivePaneTransition] = []
        var activeDrawerTransitions: [WorkspaceActiveDrawerChildTransition] = []
        activePaneTransitions.reserveCapacity(tab.arrangements.count)

        for arrangement in tab.arrangements {
            switch validate(
                arrangement: arrangement,
                declaredPaneIDs: declaredPaneIDs,
                referencedPaneIDs: &referencedPaneIDs,
                context: context
            ) {
            case .rejected(let rejection):
                return .rejected(rejection)
            case .accepted(let cursors):
                activePaneTransitions.append(cursors.activePane)
                activeDrawerTransitions.append(contentsOf: cursors.activeDrawerChildren)
            }
        }

        guard declaredPaneIDs == referencedPaneIDs else {
            return .rejected(
                .mismatchedPaneMembership(
                    declared: declaredPaneIDs,
                    referenced: referencedPaneIDs
                )
            )
        }

        let graph = TabGraphState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements.map(PaneArrangementGraphState.init)
        )
        return .accepted(
            WorkspaceValidatedAppendTab(
                tabID: tab.id,
                shell: TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex),
                graph: graph,
                activeArrangementID: tab.activeArrangementId,
                activePanes: activePaneTransitions,
                activeDrawerChildren: activeDrawerTransitions
            )
        )
    }

    private static func validate(
        arrangement: PaneArrangement,
        declaredPaneIDs: Set<UUID>,
        referencedPaneIDs: inout Set<UUID>,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceArrangementCursorValidation {
        if context.existingActivePaneArrangementIDs.contains(arrangement.id) {
            return .rejected(.existingActivePaneCursor(arrangementID: arrangement.id))
        }

        let layoutPaneIDs = arrangement.layout.paneIds
        if let duplicatePaneID = firstDuplicate(in: layoutPaneIDs) {
            return .rejected(
                .duplicateLayoutPaneID(
                    arrangementID: arrangement.id,
                    paneID: duplicatePaneID
                )
            )
        }
        if let duplicateDividerID = firstDuplicate(in: arrangement.layout.dividerIds) {
            return .rejected(
                .duplicateLayoutDividerID(
                    arrangementID: arrangement.id,
                    dividerID: duplicateDividerID
                )
            )
        }
        let layoutPaneIDSet = Set(layoutPaneIDs)
        var arrangementPanePlacements: Set<UUID> = []
        for paneID in layoutPaneIDs {
            guard declaredPaneIDs.contains(paneID) else {
                return .rejected(
                    .paneMissingFromTabMembership(
                        arrangementID: arrangement.id,
                        paneID: paneID
                    )
                )
            }
            switch context.panePlacements.placement(for: paneID) {
            case .missing:
                return .rejected(.panePlacementMissing(paneID))
            case .mainLayout, .drawerParent:
                break
            case .drawerChild(let parentPaneID):
                return .rejected(
                    .arrangementLayoutUsesDrawerChild(
                        arrangementID: arrangement.id,
                        paneID: paneID,
                        parentPaneID: parentPaneID
                    )
                )
            }
            arrangementPanePlacements.insert(paneID)
            referencedPaneIDs.insert(paneID)
        }
        for paneID in sortedUUIDs(arrangement.minimizedPaneIds) where !layoutPaneIDSet.contains(paneID) {
            return .rejected(
                .minimizedPaneMissingFromLayout(
                    arrangementID: arrangement.id,
                    paneID: paneID
                )
            )
        }

        let activePaneSelection: WorkspaceTabCursorSelection
        switch validateActivePaneSelection(
            arrangement: arrangement,
            layoutPaneIDs: layoutPaneIDSet
        ) {
        case .accepted(let selection):
            activePaneSelection = selection
        case .rejected(let rejection):
            return .rejected(rejection)
        }

        var drawerTransitions: [WorkspaceActiveDrawerChildTransition] = []
        drawerTransitions.reserveCapacity(arrangement.drawerViews.count)
        for drawerID in sortedUUIDs(arrangement.drawerViews.keys) {
            guard let drawerView = arrangement.drawerViews[drawerID] else { continue }
            let key = ArrangementDrawerCursorKey(
                arrangementId: arrangement.id,
                drawerId: drawerID
            )
            switch validate(
                drawerView: drawerView,
                key: key,
                declaredPaneIDs: declaredPaneIDs,
                arrangementPanePlacements: &arrangementPanePlacements,
                referencedPaneIDs: &referencedPaneIDs,
                context: context
            ) {
            case .rejected(let rejection):
                return .rejected(rejection)
            case .accepted(let transition):
                drawerTransitions.append(transition)
            }
        }

        return .accepted(
            WorkspaceValidatedArrangementCursors(
                activePane: .insert(
                    arrangementID: arrangement.id,
                    selection: activePaneSelection
                ),
                activeDrawerChildren: drawerTransitions
            )
        )
    }

    private static func validateActivePaneSelection(
        arrangement: PaneArrangement,
        layoutPaneIDs: Set<UUID>
    ) -> WorkspaceActivePaneSelectionValidation {
        guard let paneID = arrangement.activePaneId else {
            return .accepted(.noSelection)
        }
        guard layoutPaneIDs.contains(paneID), !arrangement.minimizedPaneIds.contains(paneID) else {
            return .rejected(
                .invalidActivePaneSelection(
                    arrangementID: arrangement.id,
                    paneID: paneID
                )
            )
        }
        return .accepted(.selected(paneID))
    }

    private static func validate(
        drawerView: DrawerView,
        key: ArrangementDrawerCursorKey,
        declaredPaneIDs: Set<UUID>,
        arrangementPanePlacements: inout Set<UUID>,
        referencedPaneIDs: inout Set<UUID>,
        context: WorkspaceAppendTabContext
    ) -> WorkspaceDrawerCursorValidation {
        if context.existingActiveDrawerChildKeys.contains(key) {
            return .rejected(.existingActiveDrawerChildCursor(key: key))
        }
        guard !drawerView.layout.topRow.isEmpty else {
            return .rejected(.drawerViewLayoutIsEmpty(key: key))
        }
        if let duplicateDividerID = firstDuplicate(in: drawerView.layout.dividerIds) {
            return .rejected(
                .duplicateDrawerLayoutDividerID(
                    key: key,
                    dividerID: duplicateDividerID
                )
            )
        }
        let drawerPaneIDs = drawerView.layout.paneIds
        if let duplicatePaneID = firstDuplicate(in: drawerPaneIDs) {
            return .rejected(.duplicateDrawerLayoutPaneID(key: key, paneID: duplicatePaneID))
        }
        let drawerPaneIDSet = Set(drawerPaneIDs)
        let drawerCapability: WorkspaceDrawerPlacementCapability
        switch context.panePlacements.drawer(for: key.drawerId) {
        case .missing:
            return .rejected(.drawerCapabilityMissing(key: key))
        case .found(let capability):
            drawerCapability = capability
        }
        guard arrangementPanePlacements.contains(drawerCapability.parentPaneID) else {
            return .rejected(
                .drawerParentPaneMissingFromLayout(
                    key: key,
                    parentPaneID: drawerCapability.parentPaneID
                )
            )
        }
        for paneID in drawerPaneIDs {
            guard declaredPaneIDs.contains(paneID) else {
                return .rejected(.drawerPaneMissingFromTabMembership(key: key, paneID: paneID))
            }
            switch context.panePlacements.placement(for: paneID) {
            case .missing:
                return .rejected(.panePlacementMissing(paneID))
            case .mainLayout, .drawerParent:
                return .rejected(.drawerViewUsesMainLayoutPane(key: key, paneID: paneID))
            case .drawerChild(let actualParentPaneID):
                guard actualParentPaneID == drawerCapability.parentPaneID else {
                    return .rejected(
                        .drawerViewChildParentMismatch(
                            key: key,
                            paneID: paneID,
                            expectedParentPaneID: drawerCapability.parentPaneID,
                            actualParentPaneID: actualParentPaneID
                        )
                    )
                }
            }
            guard drawerCapability.childPaneIDs.contains(paneID) else {
                return .rejected(.drawerViewPaneNotInDrawer(key: key, paneID: paneID))
            }
            guard arrangementPanePlacements.insert(paneID).inserted else {
                return .rejected(
                    .duplicatePanePlacement(
                        arrangementID: key.arrangementId,
                        paneID: paneID
                    )
                )
            }
            referencedPaneIDs.insert(paneID)
        }
        for paneID in sortedUUIDs(drawerView.minimizedPaneIds) where !drawerPaneIDSet.contains(paneID) {
            return .rejected(.minimizedDrawerPaneMissingFromLayout(key: key, paneID: paneID))
        }

        let selection: WorkspaceTabCursorSelection
        switch drawerView.activeChildId {
        case .none:
            selection = .noSelection
        case .some(let paneID):
            guard drawerPaneIDSet.contains(paneID), !drawerView.minimizedPaneIds.contains(paneID) else {
                return .rejected(
                    .invalidActiveDrawerChildSelection(
                        key: key,
                        paneID: paneID
                    )
                )
            }
            selection = .selected(paneID)
        }
        return .accepted(.insert(key: key, selection: selection))
    }

    private static func firstDuplicate(in values: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        for value in values where !seen.insert(value).inserted {
            return value
        }
        return nil
    }

    private static func sortedUUIDs<Values: Collection>(_ values: Values) -> [UUID]
    where Values.Element == UUID {
        values.sorted { $0.uuidString < $1.uuidString }
    }

    private static func isCanonicalColorHex(_ colorHex: String) -> Bool {
        let bytes = Array(colorHex.utf8)
        guard bytes.count == 7, bytes[0] == 35 else { return false }
        return bytes.dropFirst().allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte)
        }
    }
}

private enum WorkspaceAppendContextValidation {
    case accepted
    case rejected(WorkspaceTabTransitionRejection)
}

private enum WorkspaceAppendTabValidation {
    case accepted(WorkspaceValidatedAppendTab)
    case rejected(WorkspaceTabTransitionRejection)
}

private enum WorkspaceArrangementCursorValidation {
    case accepted(WorkspaceValidatedArrangementCursors)
    case rejected(WorkspaceTabTransitionRejection)
}

private enum WorkspaceDrawerCursorValidation {
    case accepted(WorkspaceActiveDrawerChildTransition)
    case rejected(WorkspaceTabTransitionRejection)
}

private enum WorkspaceActivePaneSelectionValidation {
    case accepted(WorkspaceTabCursorSelection)
    case rejected(WorkspaceTabTransitionRejection)
}

private struct WorkspaceValidatedAppendTab {
    let tabID: UUID
    let shell: TabShell
    let graph: TabGraphState
    let activeArrangementID: UUID
    let activePanes: [WorkspaceActivePaneTransition]
    let activeDrawerChildren: [WorkspaceActiveDrawerChildTransition]
}

private struct WorkspaceValidatedArrangementCursors {
    let activePane: WorkspaceActivePaneTransition
    let activeDrawerChildren: [WorkspaceActiveDrawerChildTransition]
}
