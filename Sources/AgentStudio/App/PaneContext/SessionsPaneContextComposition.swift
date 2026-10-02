import AgentStudioCore
import AgentStudioSessions

/// S3c RED declarations. The factory and lifetime cutover follow the Boot proof.
struct SessionsPaneContextComposition: Sendable {
    let ingestion: SessionsIngestion
    let paneContextService: PaneContextService
    let liveSessionsAdapter: AgentStudioIPCSessionsAdapter
    let lateSessionsAdapter: AgentStudioIPCSessionsAdapter
    let paneContextIPCAdapter: AgentStudioIPCPaneContextAdapter
    private let bridge: PaneContextSessionsBridge
}
