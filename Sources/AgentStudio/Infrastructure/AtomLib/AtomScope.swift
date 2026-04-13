nonisolated enum AtomScope {
    @MainActor
    private static var production: AtomRegistry?

    @TaskLocal
    static var override: AtomRegistry?

    @MainActor
    static var store: AtomRegistry {
        if let override {
            return override
        }
        guard let production else {
            preconditionFailure("AtomScope.store accessed before AtomScope.setUp(_:)")
        }
        return production
    }

    @MainActor
    static func setUp(_ store: AtomRegistry) {
        precondition(production == nil, "AtomScope.setUp(_:) called more than once")
        production = store
    }
}
