import AgentStudioCore
import AgentStudioTerminal
import GRDB

struct WorkspaceForegroundObservationSQLiteAccess: ForegroundObservationSQLiteAccess {
    let datastore: WorkspaceSQLiteDatastoreActor

    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await datastore.performApplicationLocalRead(operation)
    }

    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await datastore.performApplicationLocalWrite(operation)
    }
}
