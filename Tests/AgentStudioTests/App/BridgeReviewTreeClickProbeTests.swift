import Testing

@testable import AgentStudio

extension AgentStudioStartupDiagnosticActionTests {
    @Test("Bridge smoke render proof emits review tree click probe breadcrumbs")
    func bridgeSmokeRenderProofEmitsReviewTreeClickProbeBreadcrumbs() {
        var proof = makeFullyHydratedBridgeSmokeRenderProof()
        proof.reviewTreeClickProbeTargetRowPathAtFind = "Sources/App/ReviewTreeClick.swift"
        proof.reviewTreeClickProbeTargetRowIdAtFind = "review-tree-click-row"
        proof.reviewTreeClickProbeTargetRowIdAtDispatch = "review-tree-click-row"
        proof.reviewTreeClickProbeTargetRowConnectedAtDispatch = true
        proof.reviewTreeClickProbeTargetRowSameIdAtDispatch = true
        proof.reviewTreeClickProbeRenderedRowCountAtFind = 7
        proof.reviewTreeClickProbeRenderedRowCountAtDispatch = 8
        proof.reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch = 1
        proof.reviewTreeClickProbeDispatchResult = "completed"
        proof.reviewTreeClickProbeSelectionPollTrace = "0:initial-item|1:review-tree-click-item"
        proof.reviewTreeClickProbeSelectionPollCount = 2
        proof.reviewTreeClickProbeSelectionPollLastIndex = 1
        proof.reviewTreeClickProbeSecondClickAttempted = false

        let attributes = proof.attributes

        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_path_at_find"]
                == .string("Sources/App/ReviewTreeClick.swift"))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_find"]
                == .string("review-tree-click-row"))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_dispatch"]
                == .string("review-tree-click-row"))
        #expect(
            attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_connected_at_dispatch"
            ] == .bool(true))
        #expect(
            attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_same_id_at_dispatch"
            ] == .bool(true))
        #expect(
            attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_find"
            ] == .int(7))
        #expect(
            attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_dispatch"
            ] == .int(8))
        #expect(
            attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_delta_before_dispatch"
            ] == .int(1))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.dispatch_result"]
                == .string("completed"))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll_trace"]
                == .string("0:initial-item|1:review-tree-click-item"))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.count"]
                == .int(2))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.last_index"]
                == .int(1))
        #expect(
            attributes["agentstudio.startup_diagnostic.bridge.review_tree_click.probe.second_click_attempted"]
                == .bool(false))
    }

    @Test("Bridge smoke render JavaScript captures review tree click probe without timing changes")
    func bridgeSmokeRenderJavaScriptCapturesReviewTreeClickProbeWithoutTimingChanges() {
        let probe = AppDelegate.bridgeReviewObservabilitySmokeRenderStateJavaScript

        #expect(probe.contains("reviewTreeClickProbeSelectionPollTrace"))
        #expect(probe.contains("reviewTreeClickProbeTargetRowConnectedAtDispatch"))
        #expect(probe.contains("reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch"))
        #expect(probe.contains("reviewTreeClickProbeDispatchResult"))
        #expect(probe.contains("reviewTreeClickProbeSecondClickAttempted"))
        #expect(probe.contains("targetRowConnectedAtDispatch"))
        #expect(probe.contains("targetRowSameIdAtDispatch"))
        #expect(probe.contains("dispatchResult"))
        #expect(probe.contains("selectionPollTrace"))
        #expect(probe.contains("secondClickAttempted"))
        #expect(!probe.contains("setTimeout"))
    }
}
