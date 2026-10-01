import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Pane context detail paging")
struct PaneContextDetailPagingTests {
    @Test("Open asks precede unread notices, with newest position first within each kind")
    func liveMessageOrder() async throws {
        try await withPaneContextService { fixture, service in
            let oldNotice = fixture.message(body: "old notice")
            let oldAsk = fixture.ask(body: "old ask")
            let newNotice = fixture.message(body: "new notice")
            let newAsk = fixture.ask(body: "new ask")
            for request in [oldNotice, oldAsk, newNotice, newAsk] {
                try await fixture.sendCreated(request, to: service)
            }

            let detail = try await fixture.detail(service)

            #expect(
                detail.messages.map(\.id) == [
                    newAsk.messageId, oldAsk.messageId, newNotice.messageId, oldNotice.messageId,
                ])
            #expect(detail.truncation == nil)
        }
    }

    @Test("Drawer messages are labeled by their source and do not appear in unrelated panes")
    func drawerAttributionIsScoped() async throws {
        try await withPaneContextService { fixture, service in
            let drawer = PaneId.generateUUIDv7()
            let unrelated = PaneId.generateUUIDv7()
            fixture.membership.setDrawers([drawer], for: fixture.paneId)
            fixture.membership.addPane(unrelated)
            try await fixture.bind(fixture.sender, to: drawer)
            let request = fixture.ask(paneId: drawer)
            try await fixture.sendCreated(request, to: service)

            let owner = try await fixture.detail(service)
            #expect(owner.messages.isEmpty)
            #expect(owner.drawerMessages.map(\.sourcePaneId) == [drawer])
            #expect(owner.drawerMessages.first?.messages.map(\.id) == [request.messageId])
            #expect(try await fixture.detail(service, paneId: unrelated).drawerMessages.isEmpty)
            #expect(try await fixture.detail(service, paneId: drawer).messages.map(\.id) == [request.messageId])
        }
    }

    @Test("Composed overflow pages every owner and drawer live message without duplication")
    func composedBudgetKeepsEveryLiveMessageReachable() async throws {
        try await withPaneContextService { fixture, service in
            let drawer = PaneId.generateUUIDv7()
            fixture.membership.setDrawers([drawer], for: fixture.paneId)
            try await fixture.bind(fixture.sender, to: drawer)
            let body = String(repeating: "x", count: 4096)
            var expected = Set<AgentMessageId>()
            for source in [fixture.paneId, drawer] {
                for _ in 0..<32 {
                    let ask = fixture.ask(paneId: source, body: body)
                    try await fixture.sendCreated(ask, to: service)
                    expected.insert(ask.messageId)
                }
                for _ in 0..<200 {
                    let notice = fixture.message(paneId: source, body: body)
                    try await fixture.sendCreated(notice, to: service)
                    expected.insert(notice.messageId)
                }
            }
            let first = try await fixture.detail(service)
            let omitted = try #require(first.truncation?.omitted)
            try #require(!omitted.isEmpty)
            var seen = Set(flatMessages(first).map(\.id))
            #expect(seen.count < expected.count)
            #expect(omitted.reduce(0) { $0 + $1.openAsks + $1.unreadNotices } == expected.count - seen.count)
            #expect(flatMessages(first).reduce(0) { $0 + $1.body.utf8.count } <= 1_048_576)
            #expect(first.messages.prefix(32).count == 32)
            #expect(first.messages.prefix(32).allSatisfy { if case .ask = $0.shape { true } else { false } })

            // Traverse returned data cursors, never poll for asynchronous completion.
            for source in omitted {
                var next: LiveMessageCursor? = source.next
                var seenCursors: [LiveMessageCursor] = []
                while let cursor = next {
                    try #require(!seenCursors.contains(cursor), "Pagination must advance its cursor")
                    seenCursors.append(cursor)
                    let page = try await fixture.detail(service, page: .more(source: source.source, after: cursor))
                    let messages = flatMessages(page)
                    try #require(!messages.isEmpty, "A live continuation must return messages")
                    #expect(messages.allSatisfy { $0.sourcePaneId == source.source })
                    #expect(messages.reduce(0) { $0 + $1.body.utf8.count } <= 1_048_576)
                    for message in messages {
                        #expect(seen.insert(message.id).inserted, "Duplicate live message across pages")
                    }
                    next = page.truncation?.omitted.first { $0.source == source.source }?.next
                }
            }

            #expect(seen == expected)
        }
    }

    @Test("Continuation refuses an unrelated pane and a drawer that moved since the previous page")
    func sourceIsRevalidatedAtReadTime() async throws {
        try await withPaneContextService { fixture, service in
            let drawer = PaneId.generateUUIDv7()
            let otherOwner = PaneId.generateUUIDv7()
            fixture.membership.addPane(otherOwner)
            fixture.membership.setDrawers([drawer], for: fixture.paneId)
            try await fixture.bind(fixture.sender, to: drawer)
            try await fixture.sendCreated(fixture.ask(paneId: drawer), to: service)
            let cursor = LiveMessageCursor(rank: 0, position: UInt64.max)

            #expect(
                await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: .more(source: otherOwner, after: cursor)))
                    == .sourceNotInView)
            fixture.membership.setDrawers([], for: fixture.paneId)
            fixture.membership.setDrawers([drawer], for: otherOwner)
            #expect(
                await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: .more(source: drawer, after: cursor)))
                    == .sourceNotInView)
            #expect(try await fixture.detail(service, paneId: otherOwner).drawerMessages.first?.sourcePaneId == drawer)
        }
    }

    @Test("Only the newest twenty settled messages are visible; live messages are never aged out")
    func settledDisplayRetentionIsBounded() async throws {
        try await withPaneContextService { fixture, service in
            let live = fixture.message()
            try await fixture.sendCreated(live, to: service)
            var settled: [AgentMessageId] = []
            for index in 0..<25 {
                let ask = fixture.ask(body: "settled-\(index)")
                try await fixture.sendCreated(ask, to: service)
                try #require(await service.dismiss(messageId: ask.messageId, paneId: fixture.paneId) == .done)
                settled.append(ask.messageId)
            }
            let first = try await fixture.detail(service)
            #expect(Set(first.messages.map(\.id)) == Set(settled.suffix(20)).union([live.messageId]))

            fixture.clock.advance(by: .seconds(1801))
            let aged = try await fixture.detail(service)

            #expect(aged.messages.map(\.id) == [live.messageId])
            #expect(aged.revision.value > first.revision.value)
        }
    }
}

private func flatMessages(_ detail: PaneContextDetail) -> [AgentMessageDetail] {
    detail.messages + detail.drawerMessages.flatMap(\.messages)
}
