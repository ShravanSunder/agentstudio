enum SQLiteInboxNotificationClaimStorage {
    static let laneActionNeeded = "actionNeeded"
    static let laneActivity = "activity"
    static let laneSafety = "safety"
    static let laneSettledAgent = "settledAgent"

    static let allLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded, laneSafety, laneSettledAgent]
    static let allLaneSQLValues = sqlValueList([laneActivity, laneActionNeeded, laneSafety, laneSettledAgent])

    static let mergeableLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded, laneSettledAgent]
    static let mergeableLaneSQLValues = sqlValueList([laneActivity, laneActionNeeded, laneSettledAgent])

    private static func sqlValueList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }
}
