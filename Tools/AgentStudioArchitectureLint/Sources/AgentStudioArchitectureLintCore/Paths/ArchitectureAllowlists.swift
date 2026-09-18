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

    /// Blocking waits that predate this rule, recorded so a new one fails the
    /// build instead of hanging a lane. Not an endorsement and not audited: some
    /// of these park a cooperative thread the way the three converted AppIPC
    /// suites did, and some are fine because nothing they wait on needs that
    /// pool. Each wants a look, and the list should only ever get shorter.
    ///
    /// The ratchet is per file, so a new blocking wait added to a file already
    /// listed here still slips through. Prefer removing a file from the list to
    /// adding a wait to it.
    static let blockingTestWaitKnownDebt = [
        "/Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTests.swift",
        "/Tests/AgentStudioIPCClientTests/IPCDescriptorClientTestFixtures.swift",
        "/Tests/AgentStudioIPCClientTests/IPCDescriptorClientTests.swift",
        "/Tests/AgentStudioIPCTransportTests/JSONRPCCodecTests.swift",
        "/Tests/AgentStudioIPCTransportTests/UnixSocketTransportTests.swift",
        "/Tests/AgentStudioTests/App/Panes/TabBarAdapterMaterializationTestSupport.swift",
        "/Tests/AgentStudioTests/App/Windows/MainWindowControllerPresentationFactsTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceStrictStartupSubprocessTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientActivationTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverFailureTests.swift",
        "/Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerNativeTablePilotTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionAdapterDrainTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTestSupport.swift",
        "/Tests/AgentStudioTests/Infrastructure/ProcessExecutorTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/SQLite/SQLiteDatabaseFactoryTests.swift",
        "/Tests/AgentStudioTests/Integration/RepositoryRetentionCommitBoundaryRecoveryTests.swift",
        "/Tests/AgentStudioTests/Scripts/ObservabilityLaunchScriptTestSupport.swift",
    ]

    static let blockingTestWaitAllowedPathSuffixes = blockingTestWaitOwners + blockingTestWaitKnownDebt

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
