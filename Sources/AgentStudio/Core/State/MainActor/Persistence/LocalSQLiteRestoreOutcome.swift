import Foundation

enum LocalSQLiteRestoreOutcome {
    case restored
    case missing
    case unavailable(any Error)
}
