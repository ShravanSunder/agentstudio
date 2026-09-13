/// Pipeline-owned ordering keeps an earlier awaited physical mutation from resuming after a later one.
actor FilesystemPipelineScopeOrder {
    private var tail: Task<Void, Never>?
    private var tailGeneration: UInt64 = 0
    private var latestTopologyGeneration: UInt64 = 0
    private(set) var submissionCount: UInt64 = 0

    func perform(topologyGeneration: UInt64? = nil, _ operation: @escaping @Sendable () async -> Void) async {
        if let topologyGeneration {
            guard topologyGeneration >= latestTopologyGeneration else { return }
            latestTopologyGeneration = topologyGeneration
        }
        submissionCount &+= 1
        tailGeneration &+= 1
        let generation = tailGeneration
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            if let topologyGeneration, topologyGeneration < latestTopologyGeneration { return }
            await operation()
        }
        tail = task
        await task.value
        if tailGeneration == generation { tail = nil }
    }
}
