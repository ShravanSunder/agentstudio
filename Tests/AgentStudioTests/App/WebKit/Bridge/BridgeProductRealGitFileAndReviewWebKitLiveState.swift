struct BridgeProductWebKitLiveReviewState {
    let dom: BridgeProductWebKitCarrierDOMSnapshot
    let expectedSelectedContentHashes: String
    let initialGeneration: Int
    let itemCount: Int
    let successorGeneration: Int
}

struct BridgeProductWebKitLiveFileState: CustomStringConvertible, Sendable {
    let activated: Bool
    let displayPath: String
    let displaySourceId: String?
    let documentVisibilityState: String?
    let initialDisplayItemCount: Int
    let initialTreeRowCount: Int
    let filteredDisplayItemCount: Int
    let filteredTreeRowCount: Int
    let queryText: String
    let queryStatus: String
    let revealItemId: String?
    let revealPath: String?
    let selectedPath: String?
    let openFilePath: String?
    let openFileState: String?

    var description: String {
        "active=\(activated),path=\(displayPath),source=\(displaySourceId ?? "none"),visibility=\(documentVisibilityState ?? "unknown"),rows=\(initialTreeRowCount)->\(filteredTreeRowCount),items=\(initialDisplayItemCount)->\(filteredDisplayItemCount),query=\(queryStatus):\(queryText),reveal=\(revealPath ?? "none")/\(revealItemId ?? "none"),selected=\(selectedPath ?? "none"),open=\(openFilePath ?? "none")/\(openFileState ?? "idle")"
    }
}
