import Darwin
import Foundation
import GRDB

@main
struct AgentStudioSQLiteCrashFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: agentstudio-sqlite-crash-fixture <database-path>\n".utf8))
            Darwin.exit(64)
        }

        let databaseQueue = try DatabaseQueue(path: CommandLine.arguments[1])
        try databaseQueue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode=WAL")
            try database.execute(sql: "PRAGMA wal_autocheckpoint=0")
            try database.execute(sql: "CREATE TABLE startup_probe (value TEXT NOT NULL)")
            try database.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try database.execute(sql: "BEGIN IMMEDIATE")
            try database.execute(
                sql: "INSERT INTO startup_probe(value) VALUES (?)",
                arguments: ["committed-in-wal"]
            )
            try database.execute(sql: "COMMIT")
        }

        _exit(0)
    }
}
