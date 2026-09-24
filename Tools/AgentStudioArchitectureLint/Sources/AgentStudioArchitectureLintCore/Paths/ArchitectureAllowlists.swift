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

    /// MainActor stream consumers the architecture prescribes as thin
    /// adapters: the stream is already contracted off MainActor, so each
    /// element is an admitted outcome, not a raw sample.
    static let mainActorPerElementAdapters = [
        NamedOwnerAllowance(
            pathSuffix: "/Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift",
            functionName: "startRuntimeReducerConsumers",
            owner: "WorkspaceSurfaceCoordinator runtime reducer consumers",
            reason:
                "Consume NotificationReducer's critical and batched outputs after off-main contraction; the "
                + "post-contraction MainActor adapter in pane_runtime_eventbus_design.md#admission-and-hop-shape"
        )
    ]

    /// Test files that own a blocking wait on purpose and document where the
    /// block lands: off the cooperative pool, or on a dispatch queue of their
    /// own such as the socket listener's handler queue. A full lint run fails
    /// when an owner's file is gone or no longer blocks at all.
    ///
    /// Blocking waits outside these owners are frozen per file by count in
    /// the debt ledger (`architecture-debt-ledger.tsv`), not listed here:
    /// this list is ownership, not debt.
    static let blockingTestWaitOwners = [
        BlockingWaitOwner(
            path: "Tests/AgentStudioTestHarness/HeldStep.swift",
            owner: "HeldStep.arriveBlocking",
            reason:
                "The harness-owned blocking arrival: parks only a dedicated thread, and refuses a blocking "
                + "arrival made from inside a task"
        ),
        BlockingWaitOwner(
            path: "Tests/AgentStudioAppIPCTests/AgentStudioAppIPCSocketTestSupport.swift",
            owner: "AppIPC synchronous client shims",
            reason:
                "AgentStudioIPCClient blocks in UnixSocketConnection.receive; the shims move that wait to a "
                + "libdispatch thread so the server's connection handler keeps its cooperative thread"
        ),
        BlockingWaitOwner(
            path: "Tests/AgentStudioAppIPCTests/CLISubprocessTestRunner.swift",
            owner: "CLI subprocess runner",
            reason:
                "Waits for the CLI child on a semaphore and reaps it with waitUntilExit on a dispatch thread, "
                + "bounded by the runner's hang guard"
        ),
    ]

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

/// A test file allowed to block, with who owns the blocking wait and why.
struct BlockingWaitOwner: Sendable {
    /// Repository-relative path.
    let path: String
    let owner: String
    let reason: String
}

/// One code site a rule allows on purpose, with who owns it and why. This is
/// ownership, reviewed with the lint tool's source; debt lives in the ledger.
struct NamedOwnerAllowance: Sendable {
    let pathSuffix: String
    let functionName: String
    let owner: String
    let reason: String
}
