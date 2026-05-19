import Foundation

struct PaneOrdinalMap: Equatable, Sendable {
    let paneIdByOrdinal: [Int: UUID]
    let ordinalByPaneId: [UUID: Int]

    init(orderedPaneIds: [UUID]) {
        var paneIdByOrdinal: [Int: UUID] = [:]
        var ordinalByPaneId: [UUID: Int] = [:]

        for (index, paneId) in orderedPaneIds.prefix(9).enumerated() {
            let ordinal = index + 1
            paneIdByOrdinal[ordinal] = paneId
            ordinalByPaneId[paneId] = ordinal
        }

        self.paneIdByOrdinal = paneIdByOrdinal
        self.ordinalByPaneId = ordinalByPaneId
    }

    func paneId(forOrdinal ordinal: Int) -> UUID? {
        paneIdByOrdinal[ordinal]
    }

    func ordinal(forPaneId paneId: UUID) -> Int? {
        ordinalByPaneId[paneId]
    }
}
