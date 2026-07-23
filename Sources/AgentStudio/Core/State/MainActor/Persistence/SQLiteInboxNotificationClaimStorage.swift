enum SQLiteInboxNotificationClaimStorage {
    static let laneActionNeeded = "actionNeeded"
    static let laneActivity = "activity"
    static let laneSafety = "safety"
    static let laneSettledAgent = "settledAgent"

    static let allLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded, laneSafety, laneSettledAgent]
    static let mergeableLaneStorageValues: Set<String> = [laneActivity, laneActionNeeded, laneSettledAgent]

    static func storageValue(for lane: InboxNotificationClaimLane) -> String {
        switch lane {
        case .actionNeeded:
            laneActionNeeded
        case .activity:
            laneActivity
        case .safety:
            laneSafety
        case .settledAgent:
            laneSettledAgent
        }
    }
}
