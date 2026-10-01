import AgentStudioCore
import AgentStudioTestHarness
import GRDB

package actor HeldPaneContextSQLiteAccess: PaneContextSQLiteAccess {
    private let databasePool: DatabasePool
    private var beforeNextWrite: HeldStep<Void>?
    private var afterNextWrite: HeldStep<Void>?
    private var operations = 0

    package init(databasePool: DatabasePool) {
        self.databasePool = databasePool
    }

    package func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        operations += 1
        return try await databasePool.read(operation)
    }

    package func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        operations += 1
        let before = beforeNextWrite
        let after = afterNextWrite
        beforeNextWrite = nil
        afterNextWrite = nil
        try await before?.arrive(())
        let output = try await databasePool.write(operation)
        try await after?.arrive(())
        return output
    }

    package func holdNextWrite(_ step: HeldStep<Void>) {
        beforeNextWrite = step
    }

    package func observeNextCommit(_ step: HeldStep<Void>) {
        afterNextWrite = step
    }

    package func operationCount() -> Int { operations }
}
