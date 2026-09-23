enum ArchitectureAllowlists {
    static let broadObservationReadNames = Set([
        "paneSnapshot",
        "paneStateSnapshot",
        "snapshot",
        "values",
    ])
    static let observationCaptureAllowedPathSuffixes: [String] = []

    static let unboundedCollectionCallNames = Set([
        "grouped",
        "hash",
        "reduce",
        "sort",
        "sorted",
    ])
    static let mainActorCollectionWorkAllowedPathSuffixes: [String] = []

    static let performanceConstantNameFragments = [
        "cadence",
        "debounce",
        "interval",
        "threshold",
        "timeout",
    ]
    static let performanceConstantAllowedPathSuffixes: [String] = []
    static let concurrentIOAllowedPathSuffixes: [String] = []

    /// Test files that own a blocking wait on purpose and document where the
    /// block lands: off the cooperative pool, or on a dispatch queue of their
    /// own such as the socket listener's handler queue.
    static let blockingTestWaitOwners = [
        "/Tests/AgentStudioTests/TestSupport/BlockingWorkOffCooperativePool.swift",
        "/Tests/AgentStudioAppIPCTests/AgentStudioAppIPCSocketTestSupport.swift",
        "/Tests/AgentStudioAppIPCTests/CLISubprocessTestRunner.swift",
    ]

    /// Blocking waits outside these owners are frozen per file by count in
    /// the debt ledger (`architecture-debt-ledger.tsv`), not listed here:
    /// this list is ownership, not debt.
    static let blockingTestWaitAllowedPathSuffixes = blockingTestWaitOwners

    static let rawRepoCacheMembers = Set([
        "repoEnrichmentByRepoId",
        "worktreeEnrichmentByWorktreeId",
        "pullRequestFactsByBranch",
    ])

    static let repoCacheAllowedPathSuffixes = [
        "/Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift",
        "/Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift",
        "/Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift",
        "/Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift",
        "/Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Storage.swift",
        "/Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift",
        "/Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift",
    ]

    static let stateActorGrandfatheredPathFragments = [
        "/Sources/AgentStudio/Features/Bridge/State/",
        "/Sources/AgentStudio/Features/InboxNotification/State/",
        "/Sources/AgentStudio/Features/EditorChooser/State/",
    ]

    static let concreteAppRuntimeOwnerNames = Set([
        "WorkspaceActionExecutor",
        "AppCommandDispatcher",
        "WorkspaceSurfaceCoordinator",
        "PaneRuntime",
        "RuntimeRegistry",
        "SurfaceManager",
        "TerminalRuntime",
        "WorkspaceCommandValidator",
    ])

    static let rawRuntimePayloadNames = Set([
        "PaneMetadata",
        "PaneRuntimeSnapshot",
        "RuntimeEnvelope",
        "TerminalRuntime",
        "ZmxBackend",
    ])

    static let atomAccessNames = Set([
        "AtomRegistry",
        "CoreAtoms",
        "CoreAtomScope",
    ])
}
