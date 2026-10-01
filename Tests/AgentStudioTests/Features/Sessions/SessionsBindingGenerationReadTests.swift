import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioSessions

@Suite("Sessions commit-time binding generation read")
struct SessionsBindingGenerationReadTests {
    @Test("the same transaction sees no binding, its binding id, then the replacement binding id")
    func currentBindingGenerationIsWriterIncarnation() async throws {
        let fixture = try SessionsFileDatabaseFixture()
        defer { fixture.removeFiles() }
        let database = try makeBindingReadAccess(fixture)
        let repository = SessionsRepository(sqliteAccess: database)
        try await withSessionsIngestion(repository: repository) { ingestion in
            let paneId = UUIDv7.generate()
            #expect(
                try await database.read {
                    try SessionsRepositoryStorage.currentBindingGeneration(paneId: paneId, in: $0)
                } == nil)
            let sourceA = UUIDv7.generate()
            let first = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "first", sourceGenerationId: sourceA, reportedAt: 1)))
            guard case .binding(.established(let bindingA)) = first else {
                throw SessionsTestError.unexpectedOutcome("Expected first binding")
            }
            #expect(bindingA.bindingGenerationId != sourceA)
            #expect(
                try await database.write {
                    try SessionsRepositoryStorage.currentBindingGeneration(paneId: paneId, in: $0)
                } == bindingA.bindingGenerationId)
            let sourceB = UUIDv7.generate()
            let replaced = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "second", sourceGenerationId: sourceB, reportedAt: 2)))
            guard case .binding(.replaced(_, let bindingB)) = replaced else {
                throw SessionsTestError.unexpectedOutcome("Expected replacement binding")
            }
            #expect(bindingB.bindingGenerationId != sourceB)
            #expect(bindingB.bindingGenerationId != bindingA.bindingGenerationId)
            #expect(
                try await database.write {
                    try SessionsRepositoryStorage.currentBindingGeneration(paneId: paneId, in: $0)
                } == bindingB.bindingGenerationId)
        }
    }
}

private func makeBindingReadAccess(_ fixture: SessionsFileDatabaseFixture) throws -> TestSessionsSQLiteAccess {
    let queue = try DatabaseQueue(path: fixture.databaseURL.path)
    try WorkspaceLocalMigrations.migrate(queue)
    return TestSessionsSQLiteAccess(databaseQueue: queue)
}
