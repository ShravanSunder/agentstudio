struct BadPaneTabViewController {
    func resolve(paneAtom: WorkspacePaneAtom, worktreeID: UUID, layoutPaneIDs: Set<UUID>) {
        _ = paneAtom.paneSnapshot()
        _ = paneAtom.panes(for: worktreeID)
        _ = paneAtom.isWorktreeActive(worktreeID)
        _ = paneAtom.orphanedPanes(excluding: layoutPaneIDs)
    }
}
