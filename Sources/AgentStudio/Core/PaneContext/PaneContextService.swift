import Foundation
import GRDB

/// RED shell: deliberately performs no work until the service tests prove the missing behavior.
package actor PaneContextService: PaneContextDetailReading, PaneContextPersonActing {
    package init(
        sqliteAccess: any PaneContextSQLiteAccess,
        clock: any Clock<Duration>,
        wallNow: @escaping @Sendable () -> Date,
        membership: any PaneContextMembershipReading,
        currentBindingGeneration: @escaping @Sendable (PaneId, Database) throws -> UUID?
    ) {}

    package func send(_ request: PaneMessageSendRequest) async -> PaneMessageSendResult {
        .unavailable(.databaseUnavailable)
    }

    package func readDetail(_ request: PaneContextReadRequest) async -> PaneContextReadResult {
        .unavailable(.databaseUnavailable)
    }

    package func answer(_ request: AnswerAskRequest) async -> AnswerAskResult {
        .unavailable(.databaseUnavailable)
    }

    package func dismiss(messageId: AgentMessageId, paneId: PaneId) async -> DismissResult {
        .unavailable(.databaseUnavailable)
    }

    package func markRead(messageId: AgentMessageId, paneId: PaneId) async -> MarkReadResult {
        .unavailable(.databaseUnavailable)
    }

    package func runAction(_ request: MessageActionRequest) async -> MessageActionResult {
        .unavailable(.databaseUnavailable)
    }

    package func settleAsk(_ id: AgentMessageId, paneId: PaneId, cause: AskSettlementCause) async -> AskSettlementResult
    {
        .unavailable(.databaseUnavailable)
    }

    package func waitForAskOutcome(messageId: AgentMessageId, paneId: PaneId) async -> AskOutcome {
        .stale
    }

    package func withdraw(messageId: AgentMessageId, paneId: PaneId, writer: AgentMessageSender) async
        -> PaneMessageWithdrawResult
    {
        .unavailable(.databaseUnavailable)
    }

    package func claimEpoch(_ request: PaneEpochClaimRequest) async -> PaneEpochClaimResult {
        .unavailable(.databaseUnavailable)
    }

    package func setTitle(_ request: PaneTitleWriteRequest) async -> PaneOrderedWriteResult {
        .unavailable(.databaseUnavailable)
    }

    package func setLine(_ request: PaneLineWriteRequest) async -> PaneOrderedWriteResult {
        .unavailable(.databaseUnavailable)
    }

    package func changes(_ request: PaneMessageChangesRequest) async -> PaneMessageChangesResult {
        .unavailable(.databaseUnavailable)
    }

    package func sessionEnded(_ sessionKey: AgentMessageSender) async {}

    package nonisolated func retire(_ paneIds: [PaneId]) {}

    package func purgeRetired() async {}

    package func stop() async {}
}
