struct BadPaneTabViewController {
    func resolve(paneAtom: WorkspacePaneAtom) {
        _ = paneAtom.paneSnapshot()
    }
}
