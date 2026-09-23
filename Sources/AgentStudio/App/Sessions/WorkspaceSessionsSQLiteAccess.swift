import AgentStudioCore
import AgentStudioSessions
import Foundation
import GRDB

/// App composition hands the Sessions repository Core's prepared
/// application-local database. Sessions owns the SQL inside each transaction;
/// it never learns about the datastore or its connection pool.
struct WorkspaceSessionsSQLiteAccess: SessionsSQLiteAccess {
    private let datastore: WorkspaceSQLiteDatastoreActor

    init(datastore: WorkspaceSQLiteDatastoreActor) {
        self.datastore = datastore
    }

    func read<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        try await datastore.performApplicationLocalRead(operation)
    }

    func write<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        try await datastore.performApplicationLocalWrite(operation)
    }
}
