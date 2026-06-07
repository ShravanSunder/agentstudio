import GRDB

enum WorkspaceSQLiteRecoveryClassifier {
    static func shouldQuarantine(_ error: any Error) -> Bool {
        ResultCode.SQLITE_CORRUPT ~= error || ResultCode.SQLITE_NOTADB ~= error
    }
}
