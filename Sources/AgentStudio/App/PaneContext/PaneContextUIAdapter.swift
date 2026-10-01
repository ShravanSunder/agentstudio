import AgentStudioCore

/// RED shell of the App-owned off-main UI seam.
struct PaneContextUIAdapter: PaneContextDetailReading, PaneContextPersonActing {
    private let service: PaneContextService

    init(service: PaneContextService) { self.service = service }

    func readDetail(_ request: PaneContextReadRequest) async -> PaneContextReadResult {
        .unavailable(.databaseUnavailable)
    }
    func answer(_ request: AnswerAskRequest) async -> AnswerAskResult {
        .unavailable(.databaseUnavailable)
    }
    func dismiss(messageId: AgentMessageId, paneId: PaneId) async -> DismissResult {
        .unavailable(.databaseUnavailable)
    }
    func markRead(messageId: AgentMessageId, paneId: PaneId) async -> MarkReadResult {
        .unavailable(.databaseUnavailable)
    }
    func runAction(_ request: MessageActionRequest) async -> MessageActionResult {
        .unavailable(.databaseUnavailable)
    }
}
