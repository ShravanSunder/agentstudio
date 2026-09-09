import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import Foundation

enum WorkspaceRemoteReferenceProvider {
    static func configuration(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SystemGitRemoteClient.Configuration {
        #if DEBUG
            if let action = AgentStudioStartupDiagnosticAction.fromEnvironment(environment),
                action.sidebarPerformanceControlRootURL(from: environment) != nil
            {
                // The isolated workload fetches its disposable bare origin locally.
                // Ordinary launches retain the production protocol allowlist.
                return .init(
                    allowedProtocols: [.https, .ssh, .file],
                    operationTimeoutSeconds: AppPolicies.RemoteReferenceRefresh.childProcessTimeoutSeconds
                )
            }
        #endif
        return .init(operationTimeoutSeconds: AppPolicies.RemoteReferenceRefresh.childProcessTimeoutSeconds)
    }

    static func make() -> AgentStudioGitRemoteReferenceRefreshProvider {
        AgentStudioGitRemoteReferenceRefreshProvider(client: SystemGitRemoteClient(configuration: configuration()))
    }
}
