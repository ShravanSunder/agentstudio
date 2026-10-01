package enum AgentMessageAttentionType: Sendable, Equatable {
    case needsApproval
    case needsReply
    case attention
    case informational

    package static func classify(
        shape: AgentMessageShape,
        importance: MessageImportance
    ) -> Self {
        switch shape {
        case .ask(_, _, .blocking, _):
            return .needsApproval
        case .ask(_, _, .nonBlocking, _):
            return .needsReply
        case .notice:
            switch importance {
            case .attention, .failure: return .attention
            case .info, .done: return .informational
            }
        }
    }
}
