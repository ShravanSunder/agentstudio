struct BadRepoExplorerCommandPresentation {
    func resolve(graph: WorkspacePaneGraphAtom) {
        _ = graph.paneStateSnapshot()
    }
}
