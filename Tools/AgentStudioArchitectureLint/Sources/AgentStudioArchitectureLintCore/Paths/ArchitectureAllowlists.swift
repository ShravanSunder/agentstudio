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
        "/Tests/AgentStudioTests/Integration/RepositoryRetentionCommitBoundaryRecoveryTests.swift",
        "/Tests/AgentStudioTests/Scripts/ObservabilityLaunchScriptTestSupport.swift",
    ]

    static let blockingTestWaitAllowedPathSuffixes = blockingTestWaitOwners + blockingTestWaitKnownDebt

    /// Files that still contain a polling wait, recorded so a new one fails the
    /// build instead of deciding a test by machine speed.
    ///
    /// Not an endorsement. Each file is converted under PR 2; the list only
    /// shrinks. A file listed here that no longer polls fails the gate until its
    /// entry is removed. A new polling wait in a listed file still slips
    /// through — prefer removing the file to adding a wait to it.
    static let pollingWaitKnownDebt: [String] = [
        "/Tests/AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift",
        "/Tests/AgentStudioIPCClientTests/PaneNotificationSpoolWriterTests.swift",
        "/Tests/AgentStudioTests/App/AppDelegateRepositoryFactUpdateTests.swift",
        "/Tests/AgentStudioTests/App/IPC/PaneReportSpoolDrainTests.swift",
        "/Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift",
        "/Tests/AgentStudioTests/App/ObservableStoreTests.swift",
        "/Tests/AgentStudioTests/App/Panes/TabBarAdapterMaterializationTests.swift",
        "/Tests/AgentStudioTests/App/PaneTabViewControllerBridgeCommandTests.swift",
        "/Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift",
        "/Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift",
        "/Tests/AgentStudioTests/App/RecordingCommandPaneRuntime.swift",
        "/Tests/AgentStudioTests/App/RepositoryBootBaselineTests.swift",
        "/Tests/AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerProductBootstrapDeliveryTests.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRealGitReviewLoadTests.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/BridgePaneProductActiveViewerModeTests.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionRequestTestSupport.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitCarrierTestSupport.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift",
        "/Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/WebPageTestHarness.swift",
        "/Tests/AgentStudioTests/App/WebKit/Webview/WebviewPaneControllerTests.swift",
        "/Tests/AgentStudioTests/App/Windows/RepoExplorerCommandPresentationBatchCoalescingTests.swift",
        "/Tests/AgentStudioTests/App/Windows/RepoExplorerCommandPresentationBatchTests.swift",
        "/Tests/AgentStudioTests/App/Windows/SidebarSurfaceHostSwitchGuardTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift",
        "/Tests/AgentStudioTests/App/WorkspacePaneRecencyObserverTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityIntegrationTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityTestSupport.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneRefreshIntegrationTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorGeometryReevaluationIntegrationTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorPullRequestDemandTests.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTests+Filesystem.swift",
        "/Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorZoomRuntimeDispatchTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverFailureTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorActivityTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorFilteringTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorAdmissionEdgeTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorCapacityReservationTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorExplicitUpdateTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorProviderTestSupport.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorAdmissionTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorAutomaticPacingTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorContinuityTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorExplicitUpdateTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/RemoteReferenceRefreshActorTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/RemoteReferenceRefreshRecomputationTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/WatchedFolderScanSchedulerTests.swift",
        "/Tests/AgentStudioTests/Core/PaneRuntime/Sources/WatchedFolderScanSchedulerValidationTests.swift",
        "/Tests/AgentStudioTests/Core/State/PaneActivityStatusAtomTests.swift",
        "/Tests/AgentStudioTests/Core/Stores/RepositoryTopologyStoreTests.swift",
        "/Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeContentDemandAdmissionTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeDevelopmentProductHostSharedConstructionTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeFileContentStreamPacingTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeGitReadSchedulerConstructionCapacityIntegrationTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductComparisonTargetContentLifecycleTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductContentActivityAdmissionTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductFileMetadataSourceTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductMetadataActivityAdmissionTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductMetadataCoordinatorAvailabilityTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductMetadataCoordinatorProducerTaskTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductMetadataCoordinatorTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneReviewSharedConstructionTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneWorktreeRefreshDriverSessionIntegrationTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgePaneWorktreeRefreshDriverTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeProductSessionProducerOwnershipTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/BridgeProductSessionReentrancyTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/ObservationSpikeTests.swift",
        "/Tests/AgentStudioTests/Features/Bridge/WorktreeAnnotations/WorktreeAnnotationNotificationSourceTests.swift",
        "/Tests/AgentStudioTests/Features/CommandBar/CommandBarProductionProbeWiringTests.swift",
        "/Tests/AgentStudioTests/Features/CommandBar/CommandBarWorktreeRowBuilderTests.swift",
        "/Tests/AgentStudioTests/Features/CommandBar/TestSupport/CommandBarTestHelpers.swift",
        "/Tests/AgentStudioTests/Features/EditorChooser/Stores/UIStateStoreTests.swift",
        "/Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneObservationTests.swift",
        "/Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift",
        "/Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterPayloadTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerPresentationHostViewTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionActivityDemandTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionDemandTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionLifetimeTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionObservationDemandTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionResidencyDemandTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionWorkerTests.swift",
        "/Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerRenderedEqualityTests.swift",
        "/Tests/AgentStudioTests/Features/Terminal/Restore/TerminalActivationSchedulerSettlementRaceTests.swift",
        "/Tests/AgentStudioTests/Helpers/TestPushClockTests.swift",
        "/Tests/AgentStudioTests/Helpers/WorkspaceSurfaceCoordinatorTestHelpers.swift",
        "/Tests/AgentStudioTests/Helpers/ZmxTestHarness.swift",
        "/Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomFamilyTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceEventQueueTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/PopoverToggleGateTests.swift",
        "/Tests/AgentStudioTests/Infrastructure/ProcessExecutorTests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemFetchHeadGitPipelineIntegrationTests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemGitPipelineDemandIntegrationTests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemGitPipelineRegistrationTests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift",
        "/Tests/AgentStudioTests/Integration/FilesystemToPrimarySidebarIntegrationTests.swift",
        "/Tests/AgentStudioTests/Integration/ZmxE2ETests.swift",
        "/Tests/AgentStudioTests/Scripts/ObservabilityLaunchScriptTestSupport.swift",
        "/Tests/AgentStudioTests/SharedComponents/SidebarGroupingPopoverTests.swift",
        "/Tests/AgentStudioTests/TestSupport/EventBusHarness.swift",
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
