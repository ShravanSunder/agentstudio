import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragDwellStateTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let tabC = UUID()

    @Test
    func step_cursorLeavesTabBar_resets() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: nil,
            now: 10.05,
            dwellDuration: 0.1
        )

        #expect(next.hoveredTabId == nil)
        #expect(next.dwellStartTime == nil)
        #expect(commit == nil)
    }

    @Test
    func step_newTab_startsDwell_doesNotCommit() {
        let (next, commit) = DragDwellState.step(
            current: .idle,
            hoveredTabId: tabA,
            now: 10.0,
            dwellDuration: 0.1
        )

        #expect(next.hoveredTabId == tabA)
        #expect(next.dwellStartTime == 10.0)
        #expect(commit == nil)
    }

    @Test
    func step_sameTab_underThreshold_doesNotCommit() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabA,
            now: 10.05,
            dwellDuration: 0.1
        )

        #expect(next.dwellStartTime == 10.0)
        #expect(commit == nil)
    }

    @Test
    func step_sameTab_atThreshold_commits() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabA,
            now: 10.1,
            dwellDuration: 0.1
        )

        #expect(commit == tabA)
        #expect(next.lastCommittedTabId == tabA)
    }

    @Test
    func step_sameTab_overThreshold_commits() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabA,
            now: 10.5,
            dwellDuration: 0.1
        )

        #expect(commit == tabA)
        #expect(next.lastCommittedTabId == tabA)
    }

    @Test
    func step_switchToDifferentTab_resetsDwell() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabB,
            now: 10.05,
            dwellDuration: 0.1
        )

        #expect(next.hoveredTabId == tabB)
        #expect(next.dwellStartTime == 10.05)
        #expect(commit == nil)
    }

    @Test
    func step_afterCommit_sameTab_doesNotReCommit() {
        let state = DragDwellState.committed(tabId: tabA, startTime: 10.0)

        let (_, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabA,
            now: 11.0,
            dwellDuration: 0.1
        )

        #expect(commit == nil)
    }

    @Test
    func step_afterCommit_differentTab_startsNewDwell() {
        let state = DragDwellState.committed(tabId: tabA, startTime: 10.0)

        let (next, commit) = DragDwellState.step(
            current: state,
            hoveredTabId: tabB,
            now: 11.0,
            dwellDuration: 0.1
        )

        #expect(next.hoveredTabId == tabB)
        #expect(next.dwellStartTime == 11.0)
        #expect(next.lastCommittedTabId == tabA)
        #expect(commit == nil)
    }

    @Test
    func step_rapidPassAcrossTabs_noCommits() {
        var state = DragDwellState.idle
        (state, _) = DragDwellState.step(current: state, hoveredTabId: tabA, now: 10.00, dwellDuration: 0.1)

        let (afterB, commitB) = DragDwellState.step(
            current: state,
            hoveredTabId: tabB,
            now: 10.05,
            dwellDuration: 0.1
        )
        let (afterC, commitC) = DragDwellState.step(
            current: afterB,
            hoveredTabId: tabC,
            now: 10.08,
            dwellDuration: 0.1
        )

        #expect(commitB == nil)
        #expect(commitC == nil)
        #expect(afterC.lastCommittedTabId == nil)
    }

    @Test
    func progress_zeroAtDwellStart() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)
        let progress = DragDwellProgress.progress(state: state, now: 10.0, dwellDuration: 0.1)

        #expect(progress == 0)
    }

    @Test
    func progress_halfAtHalfDuration() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)
        let progress = DragDwellProgress.progress(state: state, now: 10.05, dwellDuration: 0.1)

        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test
    func progress_oneAtDuration() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)
        let progress = DragDwellProgress.progress(state: state, now: 10.1, dwellDuration: 0.1)

        #expect(progress == 1)
    }

    @Test
    func progress_clampedToOne_overDuration() {
        let state = DragDwellState.hovering(tabId: tabA, startTime: 10.0, lastCommittedTabId: nil)
        let progress = DragDwellProgress.progress(state: state, now: 10.5, dwellDuration: 0.1)

        #expect(progress == 1)
    }

    @Test
    func progress_zeroWhenCommitted() {
        let state = DragDwellState.committed(tabId: tabA, startTime: 10.0)
        let progress = DragDwellProgress.progress(state: state, now: 10.05, dwellDuration: 0.1)

        #expect(progress == 0)
    }

    @Test
    func progress_zeroWhenIdle() {
        let progress = DragDwellProgress.progress(state: .idle, now: 10.0, dwellDuration: 0.1)

        #expect(progress == 0)
    }
}
