import Foundation

struct BridgeReviewDelta: Codable, Equatable, Sendable {
    struct Operations: Codable, Equatable, Sendable {
        let addItems: [BridgeReviewItemDescriptor]
        let updateItems: [BridgeReviewItemDescriptor]
        let removeItems: [String]
        let moveItems: [String]
        let updateGroups: [BridgeReviewGroup]?
        let updateSummary: BridgeReviewPackageSummary?
        let invalidateContent: [String]

        init(
            addItems: [BridgeReviewItemDescriptor] = [],
            updateItems: [BridgeReviewItemDescriptor] = [],
            removeItems: [String] = [],
            moveItems: [String] = [],
            updateGroups: [BridgeReviewGroup]? = nil,
            updateSummary: BridgeReviewPackageSummary? = nil,
            invalidateContent: [String] = []
        ) {
            self.addItems = addItems
            self.updateItems = updateItems
            self.removeItems = removeItems
            self.moveItems = moveItems
            self.updateGroups = updateGroups
            self.updateSummary = updateSummary
            self.invalidateContent = invalidateContent
        }
    }

    let packageId: String
    let reviewGeneration: BridgeReviewGeneration
    let revision: Int
    let operations: Operations
}
