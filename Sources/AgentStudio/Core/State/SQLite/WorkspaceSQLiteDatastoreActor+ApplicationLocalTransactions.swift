import GRDB

extension WorkspaceSQLiteDatastoreActor {
    /// Feature repositories share the prepared application database without borrowing
    /// a workspace-specific save lane or retaining a database connection.
    package func performApplicationLocalWrite<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        let repository = try preparedApplicationLocalRepository()
        return try await repository.databaseWriter.write(operation)
    }

    package func performApplicationLocalRead<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        let repository = try preparedApplicationLocalRepository()
        return try await repository.databaseWriter.read(operation)
    }
}
