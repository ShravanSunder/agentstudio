import Foundation
import Observation
import os.log

private let workspacePaneLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePaneAtom")

@MainActor
@Observable
final class WorkspacePaneAtom {
    private(set) var panes: [UUID: Pane] = [:]

    func hydrate(persistedPanes: [Pane], validWorktreeIds: Set<UUID>) {
        panes = Dictionary(persistedPanes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        panes = panes.filter { _, pane in
            guard let worktreeId = pane.worktreeId else { return true }
            return validWorktreeIds.contains(worktreeId)
        }

        let validPaneIds = Set(panes.keys)
        for paneId in panes.keys {
            guard panes[paneId]?.drawer != nil else { continue }
            panes[paneId]!.withDrawer { drawer in
                let stalePaneIds = drawer.paneIds.filter { !validPaneIds.contains($0) }
                guard !stalePaneIds.isEmpty else { return }
                drawer.paneIds.removeAll { !validPaneIds.contains($0) }
                for staleId in stalePaneIds {
                    drawer.layout = drawer.layout.removing(paneId: staleId) ?? Layout()
                }
                if let activeId = drawer.activePaneId, !validPaneIds.contains(activeId) {
                    drawer.activePaneId = drawer.paneIds.first
                }
            }
        }
    }

    func pane(_ id: UUID) -> Pane? {
        guard let pane = panes[id] else {
            workspacePaneLogger.warning("pane(\(id)): not found in store")
            return nil
        }
        return pane
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        panes.values.filter { $0.worktreeId == worktreeId }
    }

    func addPane(_ pane: Pane) {
        panes[pane.id] = pane
    }

    func paneCount(for worktreeId: UUID) -> Int {
        panes.values.filter { $0.worktreeId == worktreeId }.count
    }

    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        panes.values.contains { $0.worktreeId == worktreeId && $0.residency == .active }
    }

    func orphanedPanes(excluding layoutPaneIds: Set<UUID>) -> [Pane] {
        panes.values.filter {
            guard !layoutPaneIds.contains($0.id) else { return false }
            return $0.residency == .backgrounded || $0.residency.isOrphaned
        }
    }

    @discardableResult
    func createPane(
        source: TerminalSource,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> Pane {
        let pane = Pane(
            content: .terminal(TerminalState(provider: provider, lifetime: lifetime)),
            metadata: PaneMetadata(source: .init(source), title: title, facets: facets),
            residency: residency
        )
        panes[pane.id] = pane
        return pane
    }

    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> Pane {
        let pane = Pane(content: content, metadata: metadata, residency: residency)
        panes[pane.id] = pane
        return pane
    }

    @discardableResult
    func insertRestoredPane(_ pane: Pane) -> Bool {
        guard panes[pane.id] == nil else { return false }
        panes[pane.id] = pane
        return true
    }

    @discardableResult
    func deletePaneAndOwnedDrawerChildren(_ paneId: UUID) -> Bool {
        guard panes[paneId] != nil else { return false }
        if let drawer = panes[paneId]?.drawer {
            for childId in drawer.paneIds {
                panes.removeValue(forKey: childId)
            }
        }
        panes.removeValue(forKey: paneId)
        return true
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        guard panes[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneTitle: pane \(paneId) not found")
            return
        }
        panes[paneId]!.metadata.updateTitle(title)
    }

    func renamePane(_ paneId: UUID, title: String) {
        updatePaneTitle(paneId, title: title)
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        guard panes[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneCWD: pane \(paneId) not found")
            return
        }
        guard panes[paneId]!.metadata.facets.cwd != cwd else { return }
        panes[paneId]!.metadata.updateCWD(cwd)
    }

    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard panes[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneWebviewState: pane \(paneId) not found")
            return
        }
        panes[paneId]!.content = .webview(state)
    }

    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard panes[paneId] != nil else { return }
        panes[paneId]!.content = .webview(state)
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        guard panes[paneId] != nil else {
            workspacePaneLogger.warning("setResidency: pane \(paneId) not found")
            return
        }
        panes[paneId]!.residency = residency
    }

    func purgeOrphanedPane(_ paneId: UUID) {
        guard let pane = panes[paneId], pane.residency == .backgrounded else {
            workspacePaneLogger.warning("purgeOrphanedPane: pane \(paneId) is not backgrounded")
            return
        }
        panes.removeValue(forKey: paneId)
    }

    @discardableResult
    func addDrawerPane(to parentPaneId: UUID, parentFallbackCWD: URL?) -> Pane? {
        guard let parentPane = panes[parentPaneId] else {
            workspacePaneLogger.warning("addDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }

        let parentCwd: URL? = parentPane.metadata.facets.cwd ?? parentFallbackCWD
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))
        let metadata = PaneMetadata(
            source: .floating(launchDirectory: parentCwd, title: nil),
            title: "Drawer"
        )

        let drawerPane = Pane(
            content: content,
            metadata: metadata,
            kind: .drawerChild(parentPaneId: parentPaneId)
        )

        panes[drawerPane.id] = drawerPane
        panes[parentPaneId]!.withDrawer { drawer in
            if let existingLeaf = drawer.layout.paneIds.last {
                drawer.layout = drawer.layout.inserting(
                    paneId: drawerPane.id,
                    at: existingLeaf,
                    direction: .horizontal,
                    position: .after
                )
            } else {
                drawer.layout = Layout(paneId: drawerPane.id)
            }
            drawer.paneIds.append(drawerPane.id)
            drawer.activePaneId = drawerPane.id
            drawer.isExpanded = true
        }
        return drawerPane
    }

    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        parentFallbackCWD: URL?
    ) -> Pane? {
        guard let parentPane = panes[parentPaneId], parentPane.drawer != nil else {
            workspacePaneLogger.warning("insertDrawerPane: parent pane \(parentPaneId) has no drawer")
            return nil
        }
        guard parentPane.drawer!.layout.contains(targetDrawerPaneId) else {
            workspacePaneLogger.warning("insertDrawerPane: target \(targetDrawerPaneId) not in drawer layout")
            return nil
        }

        let parentCwd: URL? = parentPane.metadata.facets.cwd ?? parentFallbackCWD
        let content = PaneContent.terminal(TerminalState(provider: .zmx, lifetime: .persistent))
        let metadata = PaneMetadata(
            source: .floating(launchDirectory: parentCwd, title: nil),
            title: "Drawer"
        )

        let drawerPane = Pane(
            content: content,
            metadata: metadata,
            kind: .drawerChild(parentPaneId: parentPaneId)
        )

        panes[drawerPane.id] = drawerPane
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.layout = drawer.layout.inserting(
                paneId: drawerPane.id,
                at: targetDrawerPaneId,
                direction: direction,
                position: position
            )
            drawer.paneIds.append(drawerPane.id)
            drawer.activePaneId = drawerPane.id
            drawer.isExpanded = true
        }
        return drawerPane
    }

    func moveDrawerPane(
        _ drawerPaneId: UUID,
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard panes[parentPaneId] != nil, panes[parentPaneId]!.drawer != nil else {
            workspacePaneLogger.warning("moveDrawerPane: parent pane \(parentPaneId) has no drawer")
            return
        }
        guard drawerPaneId != targetDrawerPaneId else { return }

        var didMove = false
        panes[parentPaneId]!.withDrawer { drawer in
            guard drawer.layout.contains(drawerPaneId) else { return }
            guard drawer.layout.contains(targetDrawerPaneId) else { return }
            guard let layoutWithoutSource = drawer.layout.removing(paneId: drawerPaneId) else { return }

            let movedLayout = layoutWithoutSource.inserting(
                paneId: drawerPaneId,
                at: targetDrawerPaneId,
                direction: direction,
                position: position
            )
            guard movedLayout != layoutWithoutSource else { return }

            drawer.layout = movedLayout
            drawer.paneIds = movedLayout.paneIds
            drawer.activePaneId = drawerPaneId
            didMove = true
        }

        if !didMove {
            workspacePaneLogger.warning(
                "moveDrawerPane: failed moving pane \(drawerPaneId) near \(targetDrawerPaneId) in \(parentPaneId)"
            )
        }
    }

    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        guard panes[parentPaneId] != nil, panes[parentPaneId]!.drawer != nil else {
            workspacePaneLogger.warning("removeDrawerPane: parent pane \(parentPaneId) has no drawer")
            return
        }

        panes[parentPaneId]!.withDrawer { drawer in
            drawer.paneIds.removeAll { $0 == drawerPaneId }
            drawer.minimizedPaneIds.remove(drawerPaneId)
            if drawer.layout.contains(drawerPaneId) {
                drawer.layout = drawer.layout.removing(paneId: drawerPaneId) ?? Layout()
            }
            if drawer.activePaneId == drawerPaneId {
                drawer.activePaneId = drawer.paneIds.first
            }
        }

        if panes[parentPaneId]!.drawer!.paneIds.isEmpty {
            let wasExpanded = panes[parentPaneId]!.drawer!.isExpanded
            panes[parentPaneId]!.kind = .layout(drawer: Drawer(isExpanded: wasExpanded))
        }

        panes.removeValue(forKey: drawerPaneId)
    }

    func toggleDrawer(for paneId: UUID) {
        guard panes[paneId] != nil, panes[paneId]!.drawer != nil else {
            workspacePaneLogger.warning("toggleDrawer: pane \(paneId) has no drawer")
            return
        }

        let willExpand = !panes[paneId]!.drawer!.isExpanded
        if willExpand {
            for otherPaneId in panes.keys where otherPaneId != paneId {
                if panes[otherPaneId]?.drawer?.isExpanded == true {
                    panes[otherPaneId]!.withDrawer { $0.isExpanded = false }
                }
            }
        }

        panes[paneId]!.withDrawer { $0.isExpanded = willExpand }
    }

    func collapseAllDrawers() {
        for paneId in panes.keys where panes[paneId]?.drawer?.isExpanded == true {
            panes[paneId]!.withDrawer { $0.isExpanded = false }
        }
    }

    func setActiveDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard panes[parentPaneId] != nil,
            let drawer = panes[parentPaneId]!.drawer,
            drawer.paneIds.contains(drawerPaneId)
        else {
            workspacePaneLogger.warning(
                "setActiveDrawerPane: drawer pane \(drawerPaneId) not found in pane \(parentPaneId)"
            )
            return
        }
        panes[parentPaneId]!.withDrawer { $0.activePaneId = drawerPaneId }
    }

    func resizeDrawerPane(parentPaneId: UUID, splitId: UUID, ratio: Double) {
        guard panes[parentPaneId] != nil, panes[parentPaneId]!.drawer != nil else {
            workspacePaneLogger.warning("resizeDrawerPane: parent pane \(parentPaneId) not found or has no drawer")
            return
        }
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.layout = drawer.layout.resizing(splitId: splitId, ratio: ratio)
        }
    }

    func equalizeDrawerPanes(parentPaneId: UUID) {
        guard panes[parentPaneId] != nil, panes[parentPaneId]!.drawer != nil else {
            workspacePaneLogger.warning("equalizeDrawerPanes: parent pane \(parentPaneId) not found or has no drawer")
            return
        }
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.layout = drawer.layout.equalized()
        }
    }

    @discardableResult
    func minimizeDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) -> Bool {
        guard panes[parentPaneId] != nil,
            let drawer = panes[parentPaneId]!.drawer,
            drawer.paneIds.contains(drawerPaneId)
        else { return false }

        panes[parentPaneId]!.withDrawer { drawer in
            drawer.minimizedPaneIds.insert(drawerPaneId)
            if drawer.activePaneId == drawerPaneId {
                drawer.activePaneId = drawer.paneIds.first { !drawer.minimizedPaneIds.contains($0) }
            }
        }
        return true
    }

    func expandDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard panes[parentPaneId] != nil else {
            workspacePaneLogger.warning("expandDrawerPane: parent pane \(parentPaneId) not found")
            return
        }
        guard panes[parentPaneId]!.drawer?.minimizedPaneIds.contains(drawerPaneId) == true else { return }
        panes[parentPaneId]!.withDrawer { drawer in
            drawer.minimizedPaneIds.remove(drawerPaneId)
        }
    }

    @discardableResult
    func orphanPanes(forUnavailableWorktreePathsById unavailablePathByWorktreeId: [UUID: String]) -> [UUID] {
        let affectedPaneIds = panes.values
            .filter { pane in
                guard let worktreeId = pane.worktreeId else { return false }
                return unavailablePathByWorktreeId[worktreeId] != nil
            }
            .map(\.id)

        guard !affectedPaneIds.isEmpty else { return [] }
        for paneId in affectedPaneIds {
            guard let worktreeId = panes[paneId]?.worktreeId,
                let missingPath = unavailablePathByWorktreeId[worktreeId]
            else { continue }
            guard panes[paneId]?.residency.isPendingUndo != true else { continue }
            panes[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: missingPath))
        }
        return affectedPaneIds
    }

    @discardableResult
    func orphanPanesForWorktree(_ worktreeId: UUID, path: String) -> [UUID] {
        let affectedPaneIds = panes.values
            .filter { $0.worktreeId == worktreeId }
            .filter { pane in
                switch pane.residency {
                case .active, .backgrounded:
                    return true
                case .pendingUndo, .orphaned:
                    return false
                }
            }
            .map(\.id)

        guard !affectedPaneIds.isEmpty else { return [] }
        for paneId in affectedPaneIds {
            panes[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: path))
        }
        return affectedPaneIds
    }

    @discardableResult
    func restoreOrphanedPaneResidency(
        forWorktreeIds worktreeIds: Set<UUID>,
        activeLayoutPaneIds: Set<UUID>
    ) -> Bool {
        var didRestore = false
        for paneId in panes.keys {
            guard let worktreeId = panes[paneId]?.worktreeId else { continue }
            guard worktreeIds.contains(worktreeId) else { continue }
            guard panes[paneId]?.residency.isOrphaned == true else { continue }
            panes[paneId]?.residency = activeLayoutPaneIds.contains(paneId) ? .active : .backgrounded
            didRestore = true
        }
        return didRestore
    }

    func snapshotPanes(with ids: [UUID]) -> [Pane] {
        ids.compactMap { panes[$0] }
    }

    func restoreDrawerPane(_ drawerPane: Pane, to parentPaneId: UUID) {
        panes[drawerPane.id] = drawerPane
        panes[parentPaneId]?.withDrawer { drawer in
            drawer.paneIds.append(drawerPane.id)
            if let existingLeaf = drawer.layout.paneIds.last {
                drawer.layout = drawer.layout.inserting(
                    paneId: drawerPane.id,
                    at: existingLeaf,
                    direction: .horizontal,
                    position: .after
                )
            } else {
                drawer.layout = Layout(paneId: drawerPane.id)
            }
            drawer.activePaneId = drawerPane.id
            drawer.isExpanded = true
        }
    }
}
