import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Pane context detail paging")
struct PaneContextDetailPagingTests {
    @Test("Many-source traversal budgets every header and reaches every live message once")
    func sourceListAndMessageContinuationsCompose() async throws {
        try await withPaneContextService { fixture, service in
            let drawers = (0..<160).map { _ in PaneId.generateUUIDv7() }
            fixture.membership.setDrawers(drawers, for: fixture.paneId)
            var expected = Set<AgentMessageId>()
            for source in [fixture.paneId] + drawers {
                try await fixture.bind(fixture.sender, to: source)
                let ask = fixture.ask(paneId: source, body: String(repeating: "x", count: 4096))
                try await fixture.sendCreated(ask, to: service)
                expected.insert(ask.messageId)
            }
            // Leave several messages in each source so both continuation kinds
            // can be required by the same composed page.
            for drawer in drawers {
                let notice = fixture.message(
                    paneId: drawer, sender: .pane(drawer), body: String(repeating: "x", count: 4096))
                try await fixture.sendCreated(notice, to: service)
                expected.insert(notice.messageId)
            }
            var sourcePage = PaneContextReadPage.first
            var seen = Set<AgentMessageId>()
            var sourceCursors = Set<PaneId>()
            var hasSourceContinuation = false
            repeat {
                let result = await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: sourcePage), maximumDetailBytes: 0)
                guard case .detail(let detail) = result else {
                    Issue.record("Expected source page: \(result)")
                    return
                }
                #expect(PaneContextDetailBudget.detailBytes(detail) <= AppPolicies.PaneContext.minimumDetailBytes)
                for message in flatMessages(detail) { #expect(seen.insert(message.id).inserted) }
                for source in detail.truncation?.omitted ?? [] {
                    var cursor = source.next
                    var cursors: [LiveMessageCursor] = []
                    repeat {
                        try #require(!cursors.contains(cursor))
                        cursors.append(cursor)
                        let result = await service.readDetail(
                            PaneContextReadRequest(
                                paneId: fixture.paneId, page: .more(source: source.source, after: cursor)),
                            maximumDetailBytes: 0)
                        guard case .detail(let page) = result else {
                            Issue.record("Expected live page: \(result)")
                            return
                        }
                        try #require(!flatMessages(page).isEmpty)
                        #expect(PaneContextDetailBudget.detailBytes(page) <= AppPolicies.PaneContext.minimumDetailBytes)
                        for message in flatMessages(page) { #expect(seen.insert(message.id).inserted) }
                        guard let remaining = page.truncation?.omitted.first else { break }
                        cursor = remaining.next
                    } while true
                }
                guard let after = detail.truncation?.nextSourcesAfter else {
                    #expect(detail.truncation?.remainingLiveSources ?? 0 == 0)
                    break
                }
                hasSourceContinuation = true
                try #require(sourceCursors.insert(after).inserted, "The source list must advance")
                #expect(detail.truncation?.remainingLiveSources ?? 0 > 0)
                sourcePage = .moreSources(after: after)
            } while true
            #expect(hasSourceContinuation)
            #expect(seen == expected)
        }
    }

    @Test("Source continuation refuses an after-source that moved or disappeared")
    func sourceListContinuationRevalidatesMembership() async throws {
        try await withPaneContextService { fixture, service in
            let drawer = PaneId.generateUUIDv7()
            fixture.membership.setDrawers([drawer], for: fixture.paneId)
            fixture.membership.setDrawers([], for: fixture.paneId)
            #expect(
                await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: .moreSources(after: drawer)))
                    == .sourceNotInView)
            #expect(
                await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: .moreSources(after: .generateUUIDv7())))
                    == .sourceNotInView)
        }
    }

    @Test("Empty sources spend no source continuation or drawer header budget")
    func emptySourcesHaveNoPagingCost() async throws {
        try await withPaneContextService { fixture, service in
            let drawers = (0..<200).map { _ in PaneId.generateUUIDv7() }
            fixture.membership.setDrawers(drawers, for: fixture.paneId)
            let notice = fixture.message()
            try await fixture.sendCreated(notice, to: service)
            let result = await service.readDetail(
                PaneContextReadRequest(paneId: fixture.paneId, page: .first), maximumDetailBytes: 0)
            guard case .detail(let detail) = result else {
                Issue.record("Expected owner detail: \(result)")
                return
            }
            #expect(detail.messages.map(\.id) == [notice.messageId])
            #expect(detail.drawerMessages.isEmpty)
            #expect(detail.truncation == nil)
        }
    }
    @Test("A source contributing no messages receives a finite cursor that reaches every row")
    func entirelyOmittedSourceHasFiniteCursor() async throws {
        try await withPaneContextService { fixture, service in
            let drawer = PaneId.generateUUIDv7()
            fixture.membership.setDrawers([drawer], for: fixture.paneId)
            try await fixture.bind(fixture.sender, to: drawer)
            for _ in 0..<32 {
                try await fixture.sendCreated(fixture.ask(body: String(repeating: "x", count: 4096)), to: service)
            }
            var expected = Set<AgentMessageId>()
            for _ in 0..<12 {
                let ask = fixture.ask(paneId: drawer, body: String(repeating: "x", count: 4096))
                try await fixture.sendCreated(ask, to: service)
                expected.insert(ask.messageId)
            }
            let result = await service.readDetail(
                PaneContextReadRequest(paneId: fixture.paneId, page: .first), maximumDetailBytes: 0)
            guard case .detail(let first) = result else {
                Issue.record("Expected detail, got \(result)")
                return
            }
            #expect(first.drawerMessages.isEmpty)
            var next = try #require(first.truncation?.omitted.first { $0.source == drawer }).next
            #expect(next.position == 13)
            var seen = Set<AgentMessageId>()
            repeat {
                #expect(next.position <= 9_007_199_254_740_991)
                let result = await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: .more(source: drawer, after: next)),
                    maximumDetailBytes: 0)
                guard case .detail(let detail) = result else {
                    Issue.record("Expected continuation, got \(result)")
                    return
                }
                let returned = flatMessages(detail)
                try #require(!returned.isEmpty)
                for message in returned { #expect(seen.insert(message.id).inserted) }
                guard let remaining = detail.truncation?.omitted.first else { break }
                try #require(remaining.next.position < next.position)
                next = remaining.next
            } while true
            #expect(seen == expected)
        }
    }
    @Test(
        "Re-reading the same page at each smaller budget preserves every live cursor",
        arguments: [0, 65_536, 131_072, 1_048_576, Int.max])
    func smallerBudgetTraversesEveryMessage(budget: Int) async throws {
        try await withPaneContextService { fixture, service in
            var expected = Set<AgentMessageId>()
            for _ in 0..<32 {
                let ask = fixture.ask(body: String(repeating: "x", count: 4096))
                try await fixture.sendCreated(ask, to: service)
                expected.insert(ask.messageId)
            }
            for _ in 0..<80 {
                let notice = fixture.message(body: String(repeating: "x", count: 4096))
                try await fixture.sendCreated(notice, to: service)
                expected.insert(notice.messageId)
            }
            let maximum = max(
                AppPolicies.PaneContext.minimumDetailBytes, min(budget, AppPolicies.PaneContext.maximumDetailBytes))
            var page = PaneContextReadPage.first
            var seen = Set<AgentMessageId>()
            var cursors: [LiveMessageCursor] = []
            repeat {
                let result = await service.readDetail(
                    PaneContextReadRequest(paneId: fixture.paneId, page: page), maximumDetailBytes: budget)
                guard case .detail(let detail) = result else {
                    Issue.record("Budget page must return detail: \(result)")
                    return
                }
                try #require(!detail.messages.isEmpty)
                #expect(detail.messages.reduce(0) { $0 + $1.body.utf8.count } <= maximum)
                #expect(PaneContextDetailBudget.detailBytes(detail) <= maximum)
                for message in detail.messages { #expect(seen.insert(message.id).inserted) }
                guard let omitted = detail.truncation?.omitted.first else { break }
                try #require(!cursors.contains(omitted.next), "A smaller page must advance its cursor")
                cursors.append(omitted.next)
                page = .more(source: omitted.source, after: omitted.next)
            } while true
            #expect(seen == expected)
        }
    }
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
            let cursor = LiveMessageCursor(rank: 0, position: 1)

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
