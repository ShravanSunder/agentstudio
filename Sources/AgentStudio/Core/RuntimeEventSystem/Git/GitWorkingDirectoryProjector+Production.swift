import AgentStudioInfrastructure

extension GitWorkingDirectoryProjector {
    package static func production(
        bus: EventBus<RuntimeEnvelope>
    ) -> GitWorkingDirectoryProjector {
        GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: AgentStudioGitWorkingTreeStatusProvider(),
            coalescingWindow: AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow,
            periodicRefreshInterval: AppPolicies.GitRefresh.defaultPolicy.activeCadence,
            refreshPolicy: AppPolicies.GitRefresh.defaultPolicy,
            pathExistenceProbe: liveRootPathProbe
        )
    }
}
