import GRDB

/// App composition supplies access to Core's prepared application-local database.
/// Domain repositories own the SQL inside each transaction, never a connection pool.
package protocol SessionsSQLiteAccess: Sendable {
    func read<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output

    func write<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output
}
