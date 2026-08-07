struct GoodRepoExplorerCommandPresentation {
    func resolve(graph: WorkspacePaneGraphAtom, paneID: UUID) {
        _ = graph.paneStructuralFacts(paneID)
    }
}
