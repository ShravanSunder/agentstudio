enum PaneMessageCountFold {
    static func summarize(messages: [PaneContextStoredMessage], sourceOrder: [PaneId]) -> PaneMessageCounts {
        let sourceRanks = Dictionary(uniqueKeysWithValues: sourceOrder.enumerated().map { ($0.element, $0.offset) })
        var approvals = 0
        var replies = 0
        var attention = 0
        var informational = 0
        var newest: PaneContextStoredMessage?
        for message in messages where !message.displayHidden && sourceRanks[message.detail.sourcePaneId] != nil {
            switch message.detail.shape {
            case .ask(_, _, let waiting, .open):
                if case .blocking = waiting {
                    approvals += 1
                    if newest.map({ isNewer(message, than: $0, sourceRanks: sourceRanks) }) ?? true {
                        newest = message
                    }
                } else {
                    replies += 1
                }
            case .notice(.unread):
                switch message.detail.importance {
                case .attention, .failure: attention += 1
                case .info, .done: informational += 1
                }
            default: break
            }
        }
        return PaneMessageCounts(
            needsApprovalCount: approvals, needsReplyCount: replies, attentionCount: attention,
            informationalCount: informational, newestOpenBlockingAskId: newest?.detail.id)
    }

    private static func isNewer(
        _ candidate: PaneContextStoredMessage, than current: PaneContextStoredMessage,
        sourceRanks: [PaneId: Int]
    ) -> Bool {
        if candidate.detail.sentAt != current.detail.sentAt { return candidate.detail.sentAt > current.detail.sentAt }
        if candidate.detail.sourcePaneId != current.detail.sourcePaneId {
            return (sourceRanks[candidate.detail.sourcePaneId] ?? sourceRanks.count)
                < (sourceRanks[current.detail.sourcePaneId] ?? sourceRanks.count)
        }
        return candidate.position > current.position
    }
}
