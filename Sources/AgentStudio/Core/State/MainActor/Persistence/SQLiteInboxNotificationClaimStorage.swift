enum SQLiteInboxNotificationClaimStorage {
    static let laneActionNeeded = "actionNeeded"
    static let laneActivity = "activity"
    static let laneSafety = "safety"

    static let allLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded, laneSafety]
    static let allLaneSQLValues = sqlValueList([laneActivity, laneActionNeeded, laneSafety])

    static let mergeableLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded]
    static let mergeableLaneSQLValues = sqlValueList([laneActivity, laneActionNeeded])

    private static func sqlValueList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }
}
