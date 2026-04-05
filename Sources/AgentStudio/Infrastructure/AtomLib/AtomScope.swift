nonisolated enum AtomScope {
    @MainActor
    private static var production: AtomStore!

    @TaskLocal
    static var override: AtomStore?

    @MainActor
    static var store: AtomStore {
        if let override {
            return override
        }
        guard let production else {
            preconditionFailure("AtomScope.store accessed before AtomScope.setUp(_:)")
        }
        return production
    }

    @MainActor
    static func setUp(_ store: AtomStore) {
        precondition(production == nil, "AtomScope.setUp(_:) called more than once")
        production = store
    }
}
