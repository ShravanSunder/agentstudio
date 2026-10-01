import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Pane context retirement and lazy open")
struct PaneContextRetirementTests {
    @Test("Construction performs no database work; the first demand opens the service")
    func serviceOpensLazily() async throws {
        try await withPaneContextService { fixture, service in
            #expect(await fixture.sqliteAccess.operationCount() == 0)

            let result = await service.readDetail(PaneContextReadRequest(paneId: fixture.paneId, page: .first))

            let hasDetail: Bool
            if case .detail = result { hasDetail = true } else { hasDetail = false }
            #expect(hasDetail)
            #expect(await fixture.sqliteAccess.operationCount() > 0)
            #expect(fixture.clock.pendingSleepCount == 0)
        }
    }

    @Test("Retirement refuses reads and late writes before permanent purge")
    func retirementMakesPaneGone() async throws {
        try await withPaneContextService { fixture, service in
            let notice = fixture.message()
            try await fixture.sendCreated(notice, to: service)
            fixture.membership.removePane(fixture.paneId)

            service.retire([fixture.paneId])

            #expect(await service.readDetail(PaneContextReadRequest(paneId: fixture.paneId, page: .first)) == .paneGone)
            #expect(await service.send(fixture.message()) == .refused(.paneGone))
            let count = try await fixture.databasePool.read { database in
                try Int.fetchOne(
                    database, sql: "SELECT COUNT(*) FROM pane_retirement WHERE pane_id = ?",
                    arguments: [fixture.paneId.uuidString])
            }
            #expect(count == 1)
        }
    }

    @Test("Retirement keeps records until its horizon, then purges every category and reports unknown message ids")
    func purgeDeletesOnlyRetiredPane() async throws {
        try await withPaneContextService { fixture, service in
            let ask = fixture.ask()
            try await fixture.sendCreated(ask, to: service)
            try #require(
                await service.answer(
                    AnswerAskRequest(
                        messageId: ask.messageId, paneId: fixture.paneId, by: .localUser, value: .text("stored")))
                    == .answered)
            let epoch = try await fixture.epoch(service)
            try #require(await service.setTitle(fixture.title("stored title", epoch: epoch, counter: 1)) == .applied)
            _ = try await fixture.changes(service)
            let survivor = PaneId.generateUUIDv7()
            fixture.membership.addPane(survivor)
            let notice = fixture.message(paneId: survivor, sender: .pane(survivor))
            try await fixture.sendCreated(notice, to: service)
            fixture.membership.removePane(fixture.paneId)
            service.retire([fixture.paneId])
            _ = await service.readDetail(PaneContextReadRequest(paneId: fixture.paneId, page: .first))

            await service.purgeRetired()
            #expect(try await requestCount(fixture) == 1)
            fixture.clock.advance(by: .seconds(86_401))
            await service.purgeRetired()

            for table in paneContextServiceTables {
                let count = try await fixture.databasePool.read { database in
                    try Int.fetchOne(
                        database, sql: "SELECT COUNT(*) FROM \(table) WHERE pane_id = ?",
                        arguments: [fixture.paneId.uuidString])
                }
                #expect(count == 0, "Purged pane left rows in \(table)")
            }
            #expect(
                await service.answer(
                    AnswerAskRequest(
                        messageId: ask.messageId, paneId: fixture.paneId, by: .localUser, value: .text("late")))
                    == .refused(.notFound))
            #expect(await service.dismiss(messageId: ask.messageId, paneId: fixture.paneId) == .notFound)
            #expect(try await fixture.detail(service, paneId: survivor).messages.first?.id == notice.messageId)
        }
    }

    @Test("Reads of absent panes return paneGone rather than inventing a view")
    func absentPaneIsGone() async throws {
        try await withPaneContextService { _, service in
            #expect(
                await service.readDetail(PaneContextReadRequest(paneId: .generateUUIDv7(), page: .first)) == .paneGone)
        }
    }
}

private func requestCount(_ fixture: PaneContextServiceFixture) async throws -> Int {
    try await fixture.databasePool.read { database in
        try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM pane_request WHERE pane_id = ?", arguments: [fixture.paneId.uuidString]
        ) ?? 0
    }
}
