import Foundation
import os.log

enum TabArrangementValidation {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "TabArrangementValidation")

    static func pruningInvalidPaneIds(
        validPaneIds: Set<UUID>,
        from arrangementStates: [TabArrangementState],
        drawerParentPaneIdByDrawerId: [UUID: UUID]? = nil
    ) -> [TabArrangementState] {
        var updatedStates = arrangementStates
        for tabIndex in updatedStates.indices {
            let originalPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            updatedStates[tabIndex].allPaneIds.removeAll { !validPaneIds.contains($0) }
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: updatedStates[tabIndex].arrangements
            )
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                from: updatedStates[tabIndex].arrangements
            )
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: updatedStates[tabIndex].arrangements
            )
            if !updatedStates[tabIndex].arrangements.isEmpty,
                activeArrangement(for: tabIndex, arrangementStates: updatedStates).layout.isEmpty,
                let liveArrangement = updatedStates[tabIndex].arrangements.first(where: { !$0.layout.isEmpty })
            {
                updatedStates[tabIndex].activeArrangementId = liveArrangement.id
            }
            let removedPaneIds = originalPaneIds.subtracting(updatedStates[tabIndex].allPaneIds)
            if !removedPaneIds.isEmpty {
                logger.warning(
                    "pruningInvalidPaneIds: removed \(removedPaneIds.count) invalid pane(s) from tab \(updatedStates[tabIndex].tabId)"
                )
            }
        }

        updatedStates.removeAll { state in
            let shouldDrop = !TabArrangementRepairRules.hasLivePaneReferences(in: state.arrangements)
            if shouldDrop {
                logger.warning(
                    "pruningInvalidPaneIds: dropping tab \(state.tabId) because it has no live pane references")
            }
            return shouldDrop
        }
        return updatedStates
    }

    static func validating(
        _ arrangementStates: [TabArrangementState],
        drawerParentPaneIdByDrawerId: [UUID: UUID]? = nil
    ) -> [TabArrangementState] {
        var updatedStates = arrangementStates
        var seenPaneIds: Set<UUID> = []

        for tabIndex in updatedStates.indices {
            if updatedStates[tabIndex].arrangements.isEmpty {
                updatedStates[tabIndex].arrangements = [
                    PaneArrangement(name: "Default", isDefault: true, layout: Layout())
                ]
            }

            if !updatedStates[tabIndex].arrangements.contains(where: \.isDefault) {
                updatedStates[tabIndex].arrangements[0].isDefault = true
            }
            for arrangementIndex in updatedStates[tabIndex].arrangements.indices.dropFirst() {
                if updatedStates[tabIndex].arrangements[arrangementIndex].isDefault {
                    updatedStates[tabIndex].arrangements[arrangementIndex].isDefault = false
                }
            }

            let allArrangementPaneIds = Set(
                updatedStates[tabIndex].arrangements.flatMap { arrangement in
                    arrangement.layout.paneIds + arrangement.drawerViews.flatMap { $0.value.layout.paneIds }
                })
            updatedStates[tabIndex].allPaneIds = Array(allArrangementPaneIds)

            let duplicatePaneIds = allArrangementPaneIds.intersection(seenPaneIds)
            if !duplicatePaneIds.isEmpty {
                logger.warning(
                    "validating: removing \(duplicatePaneIds.count) duplicate pane(s) from tab \(updatedStates[tabIndex].tabId)"
                )
                updatedStates[tabIndex].allPaneIds.removeAll { duplicatePaneIds.contains($0) }
                updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                    validPaneIds: Set(updatedStates[tabIndex].allPaneIds),
                    from: updatedStates[tabIndex].arrangements
                )
                updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                    drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                    from: updatedStates[tabIndex].arrangements
                )
            }

            let validPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            for arrangementIndex in updatedStates[tabIndex].arrangements.indices {
                let arrangementPaneIds = Set(updatedStates[tabIndex].arrangements[arrangementIndex].layout.paneIds)
                updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews =
                    TabArrangementRepairRules.pruningInvalidDrawerViewPaneIds(
                        validPaneIds: validPaneIds,
                        from: updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews
                    )
                updatedStates[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.formIntersection(validPaneIds)
                updatedStates[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.formIntersection(
                    arrangementPaneIds)
                if let activePaneId = updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId,
                    !arrangementPaneIds.contains(activePaneId)
                {
                    updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId =
                        TabArrangementSelectionRules.firstUnminimizedPaneId(
                            in: updatedStates[tabIndex].arrangements[arrangementIndex]
                        )
                }
            }
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                from: updatedStates[tabIndex].arrangements
            )
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: updatedStates[tabIndex].arrangements
            )
            if activeArrangement(for: tabIndex, arrangementStates: updatedStates).layout.isEmpty,
                let liveArrangement = updatedStates[tabIndex].arrangements.first(where: { !$0.layout.isEmpty })
            {
                updatedStates[tabIndex].activeArrangementId = liveArrangement.id
            }

            if !updatedStates[tabIndex].arrangements.contains(where: {
                $0.id == updatedStates[tabIndex].activeArrangementId
            }) {
                updatedStates[tabIndex].activeArrangementId =
                    defaultArrangement(for: tabIndex, arrangementStates: updatedStates).id
            }
            if let zoomedPaneId = updatedStates[tabIndex].zoomedPaneId, !validPaneIds.contains(zoomedPaneId) {
                updatedStates[tabIndex].zoomedPaneId = nil
            }

            seenPaneIds.formUnion(validPaneIds)
        }

        updatedStates.removeAll { state in
            let shouldDrop = !TabArrangementRepairRules.hasLivePaneReferences(in: state.arrangements)
            if shouldDrop {
                logger.warning("validating: dropping tab \(state.tabId) because it has no live pane references")
            }
            return shouldDrop
        }
        return updatedStates
    }

    private static func defaultArrangement(for tabIndex: Int, arrangementStates: [TabArrangementState])
        -> PaneArrangement
    {
        arrangementStates[tabIndex].arrangements[
            defaultArrangementIndex(for: tabIndex, arrangementStates: arrangementStates)]
    }

    private static func activeArrangement(for tabIndex: Int, arrangementStates: [TabArrangementState])
        -> PaneArrangement
    {
        arrangementStates[tabIndex].arrangements[
            activeArrangementIndex(for: tabIndex, arrangementStates: arrangementStates)]
    }

    private static func defaultArrangementIndex(for tabIndex: Int, arrangementStates: [TabArrangementState]) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    private static func activeArrangementIndex(for tabIndex: Int, arrangementStates: [TabArrangementState]) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex {
            $0.id == arrangementStates[tabIndex].activeArrangementId
        } ?? defaultArrangementIndex(for: tabIndex, arrangementStates: arrangementStates)
    }
}
