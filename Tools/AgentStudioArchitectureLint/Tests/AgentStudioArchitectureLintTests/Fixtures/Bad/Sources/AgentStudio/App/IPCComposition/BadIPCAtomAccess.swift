struct BadIPCAtomAccess {
    func run() {
        let _ = AtomScope.self
        atom()
    }
}
