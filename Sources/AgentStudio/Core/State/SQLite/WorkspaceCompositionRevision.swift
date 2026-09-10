struct WorkspaceCompositionRevision: Equatable, Sendable {
    let panes: Int
    let tabShells: Int
    let tabGraphs: Int

    func isAtLeast(_ other: Self) -> Bool {
        panes >= other.panes && tabShells >= other.tabShells && tabGraphs >= other.tabGraphs
    }
}
