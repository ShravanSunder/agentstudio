import AgentStudioInfrastructure

extension GitWorkingDirectoryProjector {
    package static func production(
        bus: EventBus<RuntimeEnvelope>,
        statusPhysicalGate: AgentStudioGitStatusPhysicalGate
    ) -> GitWorkingDirectoryProjector {
        GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: AgentStudioGitWorkingTreeStatusProvider(
                physicalGate: statusPhysicalGate
            ),
            coalescingWindow: AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow,
            refreshPolicy: AppPolicies.GitRefresh.defaultPolicy,
            pathExistenceProbe: liveRootPathProbe
        )
    }
}
