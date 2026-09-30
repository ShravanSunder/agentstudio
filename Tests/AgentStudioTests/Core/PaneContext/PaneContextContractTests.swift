import AgentStudioCore
import Foundation
import Testing

@Suite("Pane context contracts")
struct PaneContextContractTests {
    @Test("Paging retains the owner, source, rank and event position")
    func pagingRetainsSourceAndCursor() {
        let owner = PaneId.generateUUIDv7()
        let source = PaneId.generateUUIDv7()
        let cursor = LiveMessageCursor(rank: 1, position: 42)
        let request = PaneContextReadRequest(paneId: owner, page: .more(source: source, after: cursor))

        guard case .more(let readSource, let readCursor) = request.page else {
            Issue.record("A continuation request must retain its source and cursor")
            return
        }
        #expect(request == PaneContextReadRequest(paneId: owner, page: .more(source: readSource, after: readCursor)))
        #expect(readSource == source)
        #expect(readCursor == LiveMessageCursor(rank: 1, position: 42))
        #expect(request != PaneContextReadRequest(paneId: owner, page: .more(source: owner, after: cursor)))
        #expect(request != PaneContextReadRequest(paneId: owner, page: .first))
    }

    @Test("An answered ask retains the value, person and receipt independently")
    func answeredAskRetainsReceipt() throws {
        let choiceId = try AskChoiceId("allow")
        let answeredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AskState.answered(by: .localUser, value: .choices([choiceId]), receipt: .confirmed(at: answeredAt))

        guard case .answered(let person, let value, let receipt) = state else {
            Issue.record("An answered ask must retain the answer and receipt")
            return
        }
        #expect(state == .answered(by: person, value: value, receipt: receipt))
        #expect(value == .choices([choiceId]))
        #expect(receipt == .confirmed(at: answeredAt))
        #expect(state != .answered(by: person, value: value, receipt: .notYetConfirmed))
        #expect(state != .answered(by: person, value: value, receipt: .unconfirmed))
    }

    @Test("Storage failures and settled refusals remain distinct")
    func refusalChannelsRemainDistinct() {
        #expect(AnswerAskResult.refused(.expired) != .refused(.stale))
        #expect(AnswerAskResult.refused(.withdrawn) != .refused(.handedBack))
        #expect(AnswerAskResult.refused(.alreadyAnswered) != .refused(.dismissed))
        #expect(AnswerAskResult.refused(.notFound) != .unavailable(.databaseUnavailable))
        #expect(StorageFailureSummary.commitFailed != .databaseUnavailable)
        #expect(StorageFailureSummary.decodeFailed("shape") != .decodeFailed("sender"))
    }
}
