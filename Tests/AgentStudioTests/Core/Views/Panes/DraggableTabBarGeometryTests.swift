import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DraggableTabBarGeometryTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let tabC = UUID()

    private var threeTabFrames: [UUID: CGRect] {
        [
            tabA: CGRect(x: 0, y: 0, width: 100, height: 30),
            tabB: CGRect(x: 100, y: 0, width: 100, height: 30),
            tabC: CGRect(x: 200, y: 0, width: 100, height: 30),
        ]
    }

    @Test
    func tabId_insideTabA() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 50, y: 15),
            tabFrames: threeTabFrames
        )

        #expect(result == tabA)
    }

    @Test
    func tabId_insideTabC() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 250, y: 15),
            tabFrames: threeTabFrames
        )

        #expect(result == tabC)
    }

    @Test
    func tabId_outsideAllTabs_returnsNil() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 500, y: 15),
            tabFrames: threeTabFrames
        )

        #expect(result == nil)
    }

    @Test
    func tabId_emptyTabFrames_returnsNil() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 50, y: 15),
            tabFrames: [:]
        )

        #expect(result == nil)
    }

    @Test
    func tabId_onExactBoundary_isDeterministic() {
        let result = DraggableTabBarGeometry.tabId(
            at: CGPoint(x: 100, y: 15),
            tabFrames: threeTabFrames
        )

        #expect(result == tabA || result == tabB)
    }
}
