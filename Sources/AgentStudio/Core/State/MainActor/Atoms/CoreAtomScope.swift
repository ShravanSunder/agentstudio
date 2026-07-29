nonisolated package enum CoreAtomScope {
    @MainActor
    private static var production: CoreAtoms?

    @TaskLocal
    package static var override: CoreAtoms?

    @MainActor
    package static var store: CoreAtoms {
        if let override {
            return override
        }
        guard let production else {
            preconditionFailure("CoreAtomScope.store accessed before CoreAtomScope.setUp(_:)")
        }
        return production
    }

    @MainActor
    package static func setUp(_ store: CoreAtoms) {
        precondition(production == nil, "CoreAtomScope.setUp(_:) called more than once")
        production = store
    }
}
