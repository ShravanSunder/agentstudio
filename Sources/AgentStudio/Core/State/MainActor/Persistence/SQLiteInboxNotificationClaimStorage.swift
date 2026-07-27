package enum SQLiteInboxNotificationClaimStorage {
    package static let laneActionNeeded = "actionNeeded"
    package static let laneActivity = "activity"
    package static let laneSafety = "safety"
    package static let laneSettledAgent = "settledAgent"

    package static let allLaneStorageValues: Set<String> = [
        laneActivity,
        laneActionNeeded,
        laneSafety,
        laneSettledAgent,
    ]
    package static let mergeableLaneStorageValues: Set<String> = [
        laneActivity,
        laneActionNeeded,
        laneSettledAgent,
    ]

    package static func validatedLaneStorageValue(_ rawValue: String) -> String? {
        allLaneStorageValues.contains(rawValue) ? rawValue : nil
    }
}
