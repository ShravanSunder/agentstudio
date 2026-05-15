import Foundation
import os.log

enum TabArrangementValidation {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "TabArrangementValidation")

    static func pruningInvalidPaneIds(
        validPaneIds: Set<UUID>,
        from arrangementStates: [TabArrangementState]
    ) -> [TabArrangementState] {
        var updatedStates = arrangementStates
        for tabIndex in updatedStates.indices {
            let originalPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            updatedStates[tabIndex].allPaneIds.removeAll { !validPaneIds.contains($0) }
            updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: updatedStates[tabIndex].arrangements
            )
            let removedPaneIds = originalPaneIds.subtracting(updatedStates[tabIndex].allPaneIds)
            if !removedPaneIds.isEmpty {
                logger.warning(
                    "pruningInvalidPaneIds: removed \(removedPaneIds.count) invalid pane(s) from tab \(updatedStates[tabIndex].tabId)"
                )
            }
        }

        updatedStates.removeAll { state in
            let shouldDrop =
                (state.arrangements.first(where: \.isDefault) ?? state.arrangements.first)?.layout.isEmpty
                ?? true
            if shouldDrop {
                logger.warning("pruningInvalidPaneIds: dropping tab \(state.tabId) because its default layout is empty")
            }
            return shouldDrop
        }
        return updatedStates
    }

    static func validating(_ arrangementStates: [TabArrangementState]) -> [TabArrangementState] {
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

            let allArrangementPaneIds = Set(updatedStates[tabIndex].arrangements.flatMap { $0.layout.paneIds })
            updatedStates[tabIndex].allPaneIds = Array(allArrangementPaneIds)

            let duplicatePaneIds = allArrangementPaneIds.intersection(seenPaneIds)
            if !duplicatePaneIds.isEmpty {
                logger.warning(
                    "validating: removing \(duplicatePaneIds.count) duplicate pane(s) from tab \(updatedStates[tabIndex].tabId)"
                )
                updatedStates[tabIndex].allPaneIds.removeAll { duplicatePaneIds.contains($0) }
                for arrangementIndex in updatedStates[tabIndex].arrangements.indices {
                    for paneId in duplicatePaneIds {
                        updatedStates[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.remove(paneId)
                        if updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId == paneId {
                            updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId =
                                TabArrangementSelectionRules.firstUnminimizedPaneId(
                                    in: updatedStates[tabIndex].arrangements[arrangementIndex]
                                )
                        }
                        guard updatedStates[tabIndex].arrangements[arrangementIndex].layout.contains(paneId) else {
                            continue
                        }
                        if let newLayout = updatedStates[tabIndex].arrangements[arrangementIndex].layout.removing(
                            paneId: paneId,
                            sizingMode: .halveTarget
                        ) {
                            updatedStates[tabIndex].arrangements[arrangementIndex].layout = newLayout
                        } else {
                            updatedStates[tabIndex].arrangements[arrangementIndex].layout = Layout()
                        }
                    }
                }
            }

            let validPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            for arrangementIndex in updatedStates[tabIndex].arrangements.indices {
                let arrangementPaneIds = Set(updatedStates[tabIndex].arrangements[arrangementIndex].layout.paneIds)
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
            let shouldDrop = state.arrangements.first(where: \.isDefault)?.layout.isEmpty ?? true
            if shouldDrop {
                logger.warning("validating: dropping tab \(state.tabId) because its default layout is empty")
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
