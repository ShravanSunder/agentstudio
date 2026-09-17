struct WorkspaceCompositionRevision: Equatable, Sendable {
    let panes: Int
    let tabShells: Int
    let tabGraphs: Int
    let topologyContextRevision: UInt64?

    init(
        panes: Int,
        tabShells: Int,
        tabGraphs: Int,
        topologyContextRevision: UInt64? = nil
    ) {
        self.panes = panes
        self.tabShells = tabShells
        self.tabGraphs = tabGraphs
        self.topologyContextRevision = topologyContextRevision
    }

    func isAtLeast(_ other: Self) -> Bool {
        panes >= other.panes && tabShells >= other.tabShells && tabGraphs >= other.tabGraphs
    }
}
