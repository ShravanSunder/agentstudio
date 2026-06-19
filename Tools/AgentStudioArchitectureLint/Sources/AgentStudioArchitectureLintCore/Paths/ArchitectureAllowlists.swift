enum ArchitectureAllowlists {
    static let rawRepoCacheMembers = Set([
        "repoEnrichmentByRepoId",
        "worktreeEnrichmentByWorktreeId",
        "pullRequestCountByWorktreeId",
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
        "AtomReader",
        "AtomScope",
        "TestAtomRegistry",
        "withTestAtomRegistry",
    ])
}
