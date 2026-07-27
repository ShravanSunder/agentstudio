extension InboxNotificationClaimLane {
    var sqliteStorageValue: String {
        guard
            let storageValue = SQLiteInboxNotificationClaimStorage.validatedLaneStorageValue(rawValue)
        else {
            preconditionFailure("Inbox claim lane must match the Core-owned SQLite storage vocabulary")
        }
        return storageValue
    }
}
