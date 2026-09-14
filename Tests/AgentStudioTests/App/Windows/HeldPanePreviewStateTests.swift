import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Held pane preview state", .serialized)
struct HeldPanePreviewStateTests {
    @Test("a fresh Space hold mints one generation and repeat does not mint another")
    func spaceHoldSuppressesRepeatGeneration() {
        let state = HeldPanePreviewState()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let target = ValidatedPanePreviewTarget(
            paneID: paneID,
            owningTabID: tabID,
            provider: .zmx,
            sessionID: .generateUUIDv7()
        )

        #expect(state.beginSpaceHold(requestedTarget: target))
        #expect(state.lifecycle == .held(generation: 1, requestedTarget: target))
        #expect(!state.beginSpaceHold(requestedTarget: target, isRepeat: true))
        #expect(state.lifecycle == .held(generation: 1, requestedTarget: target))
    }

    @Test("commit suppresses a later Space key-up")
    func commitWinsBeforeKeyUp() {
        let state = HeldPanePreviewState()
        #expect(state.beginSpaceHold(requestedTarget: nil))
        state.commitBeforeActivation()
        #expect(state.lifecycle == .suppressedUntilSpaceRelease(generation: 1))
        state.endSpaceHold()
        #expect(state.lifecycle == .idle(nextGeneration: 2))
    }

    @Test("selection replacement keeps the hold generation and rejects a stale completion")
    func selectionReplacementRejectsStalePresentedTarget() {
        let state = HeldPanePreviewState()
        let firstTarget = target()
        let secondTarget = target()
        #expect(state.beginSpaceHold(requestedTarget: firstTarget))
        #expect(state.acceptPresentedTarget(firstTarget, generation: 1))

        state.updateRequestedTarget(secondTarget)

        #expect(state.lifecycle == .held(generation: 1, requestedTarget: secondTarget))
        #expect(state.presentedTarget == nil)
        #expect(!state.acceptPresentedTarget(firstTarget, generation: 1))
        #expect(state.acceptPresentedTarget(secondTarget, generation: 1))
    }

    @Test("non-pane selection clears the target without ending the held session")
    func nonPaneSelectionRetainsHeldSession() {
        let state = HeldPanePreviewState()
        #expect(state.beginSpaceHold(requestedTarget: target()))
        state.updateRequestedTarget(nil)

        #expect(state.lifecycle == .held(generation: 1, requestedTarget: nil))
        #expect(state.generation == 1)
        #expect(state.requestedTarget == nil)
        #expect(state.presentedTarget == nil)
    }

    @Test("focus loss cancels the hold and an autorepeat after reentry cannot restart it")
    func focusLossRequiresFreshNonrepeatKeyDown() {
        let state = HeldPanePreviewState()
        #expect(state.beginSpaceHold(requestedTarget: nil))
        state.cancelIfHeld()
        #expect(state.lifecycle == .idle(nextGeneration: 2))
        #expect(!state.beginSpaceHold(requestedTarget: nil, isRepeat: true))
        #expect(state.lifecycle == .idle(nextGeneration: 2))
        #expect(state.beginSpaceHold(requestedTarget: nil))
        #expect(state.lifecycle == .held(generation: 2, requestedTarget: nil))
    }

    @Test("stale or mismatched targets cannot publish after invalidation")
    func invalidationRejectsLateTargetCompletion() {
        let state = HeldPanePreviewState()
        let selectedTarget = target()
        let mismatchedTarget = target()
        #expect(state.beginSpaceHold(requestedTarget: selectedTarget))
        #expect(!state.acceptPresentedTarget(mismatchedTarget, generation: 1))
        #expect(state.invalidateTarget(generation: 1, target: selectedTarget))
        #expect(state.requestedTarget == nil)
        #expect(!state.acceptPresentedTarget(selectedTarget, generation: 1))
        #expect(!state.markPresentationUnavailable(generation: 1, target: selectedTarget))
    }

    @Test("eligibility reads are pure while explicit focus loss cancels the hold")
    func eligibilityQueryDoesNotMutatePreviewState() throws {
        let state = HeldPanePreviewState()
        let interaction = RepoExplorerKeyboardInteraction()
        var lossCount = 0
        interaction.configure(
            RepoExplorerKeyboardCallbacks(
                canInterpretListInput: { true },
                onPreviewEligibilityLoss: {
                    lossCount += 1
                    state.cancelIfHeld()
                }
            )
        )
        let host = RepoExplorerMaterializationHost(
            lifetimeID: RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate()),
            initialDemandEpoch: 1,
            initialPresentation: .noRepositories,
            makeContentChild: { preconditionFailure("rowless eligibility fixture must not create content") },
            onFeedback: { _ in }
        )
        host.installKeyboardInteraction(interaction)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            host.detach()
            window.close()
        }

        #expect(window.makeFirstResponder(host))
        #expect(state.beginSpaceHold(requestedTarget: nil))
        let lifecycleBeforeQuery = state.lifecycle

        #expect(interaction.isListKeyboardActive)
        #expect(state.lifecycle == lifecycleBeforeQuery)

        interaction.clearFocusReporting()
        #expect(state.lifecycle == .idle(nextGeneration: 2))
        #expect(lossCount == 1)
    }

    private func target() -> ValidatedPanePreviewTarget {
        ValidatedPanePreviewTarget(
            paneID: UUIDv7.generate(),
            owningTabID: UUIDv7.generate(),
            provider: .zmx,
            sessionID: .generateUUIDv7()
        )
    }
}
