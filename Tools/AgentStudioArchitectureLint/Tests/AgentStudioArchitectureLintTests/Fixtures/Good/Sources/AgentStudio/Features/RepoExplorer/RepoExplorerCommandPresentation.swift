struct GoodRepoExplorerCommandPresentation {
    func resolve(graph: WorkspacePaneGraphAtom, paneID: UUID, paneCollection: PaneCollection) {
        _ = graph.paneStructuralFacts(paneID)
        _ = paneCollection.panes
        _ = paneCollection.panes(matching: paneID)
    }
}
