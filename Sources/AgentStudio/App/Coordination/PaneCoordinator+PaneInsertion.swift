import AppKit

@MainActor
extension PaneCoordinator {
    func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        switch source {
        case .existingPane(let paneId, let sourceTabId):
            guard store.paneAtom.pane(paneId) != nil else {
                Self.logger.warning("insertPane existingPane: pane \(paneId) not found")
                return
            }
            guard store.tabLayoutAtom.tab(sourceTabId) != nil else {
                Self.logger.warning("insertPane existingPane: source tab \(sourceTabId) not found")
                return
            }
            guard store.tabLayoutAtom.tab(targetTabId) != nil else {
                Self.logger.warning("insertPane existingPane: target tab \(targetTabId) not found")
                return
            }
            guard
                store.tabLayoutAtom.tab(targetTabId)?.activeArrangement.layout.contains(targetPaneId) == true
            else {
                Self.logger.warning(
                    "insertPane existingPane: target pane \(targetPaneId) is not in the active arrangement for tab \(targetTabId)"
                )
                return
            }
            store.tabLayoutAtom.removePaneFromLayout(paneId, inTab: sourceTabId)
            if !store.tabLayoutAtom.insertPane(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position, sizingMode: sizingMode
            ) {
                Self.logger.error(
                    "insertPane existingPane: failed inserting pane \(paneId) into tab \(targetTabId)"
                )
            }

        case .newTerminal:
            let targetPane = store.paneAtom.pane(targetPaneId)
            if let resolved = resolvedWorktreeContext(for: targetPane) {
                let pane = store.paneAtom.createPane(
                    source: .worktree(
                        worktreeId: resolved.worktree.id,
                        repoId: resolved.repo.id,
                        launchDirectory: targetPane?.metadata.cwd ?? targetPane?.metadata.launchDirectory
                            ?? resolved.worktree.path
                    ),
                    provider: .zmx,
                    facets: targetPane?.metadata.facets ?? .empty
                )
                prepareTerminalPaneSlot(pane)

                guard
                    store.tabLayoutAtom.insertPane(
                        pane.id, inTab: targetTabId, at: targetPaneId,
                        direction: layoutDirection, position: position, sizingMode: sizingMode
                    )
                else {
                    Self.logger.error(
                        "insertPane newTerminal: failed inserting pane \(pane.id) into tab \(targetTabId)")
                    store.mutationCoordinator.removePane(pane.id)
                    viewRegistry.removeSlot(for: pane.id)
                    return
                }
                traceTerminalLayoutInsertedAndViewCreateStarted(pane)
                ensureTerminalPaneView(pane)
                return
            }

            let pane = store.paneAtom.createPane(
                source: .floating(
                    launchDirectory: targetPane?.metadata.cwd ?? targetPane?.metadata.launchDirectory,
                    title: nil
                ),
                provider: .zmx,
                facets: targetPane?.metadata.facets ?? .empty
            )
            prepareTerminalPaneSlot(pane)

            guard
                store.tabLayoutAtom.insertPane(
                    pane.id, inTab: targetTabId, at: targetPaneId,
                    direction: layoutDirection, position: position, sizingMode: sizingMode
                )
            else {
                Self.logger.error("insertPane newTerminal: failed inserting pane \(pane.id) into tab \(targetTabId)")
                store.mutationCoordinator.removePane(pane.id)
                viewRegistry.removeSlot(for: pane.id)
                return
            }
            traceTerminalLayoutInsertedAndViewCreateStarted(pane)
            ensureTerminalPaneView(pane)
        }
    }
}
