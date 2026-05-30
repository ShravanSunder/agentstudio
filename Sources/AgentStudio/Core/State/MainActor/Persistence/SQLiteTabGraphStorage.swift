import Foundation
import GRDB

enum SQLiteTabGraphStorage {
    static let topRow = "top"
    static let bottomRow = "bottom"

    static func rowKind(isBottomRow: Bool) -> String {
        isBottomRow ? bottomRow : topRow
    }

    static func placeholders(count: Int) -> String {
        precondition(count > 0, "placeholder count must be positive")
        return Array(repeating: "?", count: count).joined(separator: ", ")
    }

    static func sortedUUIDStrings(_ ids: Set<UUID>) -> [String] {
        ids.map(\.uuidString).sorted()
    }
}

struct SQLiteTabGraphLayoutRow: Equatable {
    let paneId: UUID
    let ratio: Double
    let sortIndex: Int
}

struct SQLiteTabGraphDividerRow: Equatable {
    let dividerId: UUID
    let sortIndex: Int
}
