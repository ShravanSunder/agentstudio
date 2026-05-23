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

            let canonicalPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            let duplicatePaneIds = canonicalPaneIds.intersection(seenPaneIds)
            if !duplicatePaneIds.isEmpty {
                logger.warning(
                    "validating: removing \(duplicatePaneIds.count) duplicate pane(s) from tab \(updatedStates[tabIndex].tabId)"
                )
                updatedStates[tabIndex].allPaneIds.removeAll { duplicatePaneIds.contains($0) }
                updatedStates[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                    validPaneIds: Set(updatedStates[tabIndex].allPaneIds),
                    from: updatedStates[tabIndex].arrangements
                )
            }

            let validPaneIds = Set(updatedStates[tabIndex].allPaneIds)
            for arrangementIndex in updatedStates[tabIndex].arrangements.indices {
                updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews =
                    TabArrangementRepairRules.pruningInvalidDrawerViewPaneIds(
                        validPaneIds: validPaneIds,
                        from: updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews
                    )
                let drawerPaneIds = Set(
                    updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews.flatMap {
                        $0.value.layout.paneIds
                    }
                )
                let canonicalMainPaneIds = updatedStates[tabIndex].allPaneIds.filter {
                    !drawerPaneIds.contains($0)
                }
                updatedStates[tabIndex].arrangements[arrangementIndex].layout = reconcilingMainLayout(
                    updatedStates[tabIndex].arrangements[arrangementIndex].layout,
                    canonicalMainPaneIds: canonicalMainPaneIds
                )
                let arrangementPaneIds = Set(updatedStates[tabIndex].arrangements[arrangementIndex].layout.paneIds)
                updatedStates[tabIndex].arrangements[arrangementIndex].minimizedPaneIds =
                    updatedStates[tabIndex].arrangements[arrangementIndex].minimizedPaneIds.filtering(
                        toRawPaneIds: validPaneIds.intersection(arrangementPaneIds)
                    )
                if let activePaneId = updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId,
                    !arrangementPaneIds.contains(activePaneId.rawValue)
                {
                    updatedStates[tabIndex].arrangements[arrangementIndex].activePaneId =
                        TabArrangementSelectionRules.firstUnminimizedPaneId(
                            in: updatedStates[tabIndex].arrangements[arrangementIndex]
                        ).map(MainPaneId.init)
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

    private static func reconcilingMainLayout(
        _ layout: Layout,
        canonicalMainPaneIds: [UUID]
    ) -> Layout {
        var updatedLayout = layout
        let canonicalSet = Set(canonicalMainPaneIds)

        for paneId in updatedLayout.paneIds where !canonicalSet.contains(paneId) {
            updatedLayout =
                updatedLayout.removing(
                    paneId: paneId,
                    sizingMode: .proportional
                ) ?? Layout.autoTiled(updatedLayout.paneIds.filter { $0 != paneId })
        }

        for paneId in canonicalMainPaneIds where !updatedLayout.contains(paneId) {
            updatedLayout = appendingPane(paneId, to: updatedLayout)
        }

        return updatedLayout
    }

    private static func appendingPane(_ paneId: UUID, to layout: Layout) -> Layout {
        guard let targetPaneId = layout.paneIds.last else {
            return Layout(paneId: paneId)
        }

        return layout.inserting(
            paneId: paneId,
            at: targetPaneId,
            direction: .horizontal,
            position: .after,
            sizingMode: .proportional
        ) ?? Layout.autoTiled(layout.paneIds + [paneId])
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
