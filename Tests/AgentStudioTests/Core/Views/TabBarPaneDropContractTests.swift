import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class TabBarPaneDropContractTests {

    @Test
    func test_paneDropInsertionIndex_returnsNilOutsideTabRowVerticalBounds() {
        let tabIds = [UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            tabIds[0]: CGRect(x: 0, y: 0, width: 220, height: 36),
            tabIds[1]: CGRect(x: 224, y: 0, width: 220, height: 36),
        ]

        let result = DraggableTabBarHostingView.paneDropInsertionIndex(
            dropPoint: NSPoint(x: 120, y: 100),
            boundsHeight: 36,
            tabFrames: frames,
            orderedTabIds: tabIds
        )

        #expect(result == nil)
    }

    @Test
    func test_paneDropInsertionIndex_returnsInsertionPointFromMidpoints() {
        let tabIds = [UUID(), UUID(), UUID()]
        let frames: [UUID: CGRect] = [
            tabIds[0]: CGRect(x: 0, y: 0, width: 220, height: 36),
            tabIds[1]: CGRect(x: 224, y: 0, width: 220, height: 36),
            tabIds[2]: CGRect(x: 448, y: 0, width: 220, height: 36),
        ]

        let beforeSecond = DraggableTabBarHostingView.paneDropInsertionIndex(
            dropPoint: NSPoint(x: 280, y: 18),
            boundsHeight: 36,
            tabFrames: frames,
            orderedTabIds: tabIds
        )
        let atEnd = DraggableTabBarHostingView.paneDropInsertionIndex(
            dropPoint: NSPoint(x: 900, y: 18),
            boundsHeight: 36,
            tabFrames: frames,
            orderedTabIds: tabIds
        )

        #expect(beforeSecond == 1)
        #expect(atEnd == 3)
    }
}
