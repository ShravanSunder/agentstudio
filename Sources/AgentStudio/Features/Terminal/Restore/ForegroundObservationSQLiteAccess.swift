import GRDB

/// App owns the prepared database capability; Terminal owns the SQL in each transaction.
package protocol ForegroundObservationSQLiteAccess: Sendable {
    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output
    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output
}
