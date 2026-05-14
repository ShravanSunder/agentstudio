import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FlatPaneDividerResizeTests {

    // MARK: - Pure computation tests

    @Test
    func computeResizeRatio_returnsCorrectRatioForPositiveTranslation() {
        // Arrange: two equal panes, drag 10pt right
        let ratio = FlatPaneDivider.computeResizeRatio(
            initialLeftWidth: 200,
            initialRightWidth: 200,
            translationWidth: 10,
            minSize: 50
        )

        // Act/Assert: left should be 210/400 = 0.525
        #expect(abs(ratio - 0.525) < 0.001)
    }

    @Test
    func computeResizeRatio_clampsToMinSize() {
        // Arrange: drag far left past minimum
        let ratio = FlatPaneDivider.computeResizeRatio(
            initialLeftWidth: 200,
            initialRightWidth: 200,
            translationWidth: -300,
            minSize: 50
        )

        // Assert: clamped to minSize/total = 50/400 = 0.125
        #expect(abs(ratio - 0.125) < 0.001)
    }

    @Test
    func computeResizeRatio_clampsToMaxSize() {
        // Arrange: drag far right past maximum
        let ratio = FlatPaneDivider.computeResizeRatio(
            initialLeftWidth: 200,
            initialRightWidth: 200,
            translationWidth: 300,
            minSize: 50
        )

        // Assert: clamped to (total - minSize)/total = 350/400 = 0.875
        #expect(abs(ratio - 0.875) < 0.001)
    }

    // MARK: - Feedback loop regression test

    @Test
    func simulatedDragSequence_doesNotExhibitFeedbackLoop() {
        // This test simulates the frame-by-frame drag sequence that caused
        // the feedback loop bug. The DragGesture reports cumulative translation
        // from drag start. Between frames, the layout updates and metrics
        // recompute new leftPaneWidth/rightPaneWidth values.
        //
        // BUG (old behavior): using CURRENT leftPaneWidth + cumulative translation
        // double-applies the delta each frame, causing runaway acceleration.
        //
        // FIX: using INITIAL leftPaneWidth (captured at drag start) + cumulative
        // translation gives correct, stable results.

        let minSize: CGFloat = 50
        let initialLeft: CGFloat = 200
        let initialRight: CGFloat = 200
        let totalWidth = initialLeft + initialRight

        // Simulate 5 frames of dragging 4pt per frame (cumulative: 4, 8, 12, 16, 20)
        let cumulativeTranslations: [CGFloat] = [4, 8, 12, 16, 20]

        // CORRECT behavior: ratio should track finger position linearly
        // finger at 204, 208, 212, 216, 220 → ratios 0.51, 0.52, 0.53, 0.54, 0.55
        let expectedRatios: [Double] = [0.51, 0.52, 0.53, 0.54, 0.55]

        // Simulate with FIXED initial widths (the correct approach)
        var fixedRatios: [Double] = []
        for translation in cumulativeTranslations {
            let ratio = FlatPaneDivider.computeResizeRatio(
                initialLeftWidth: initialLeft,
                initialRightWidth: initialRight,
                translationWidth: translation,
                minSize: minSize
            )
            fixedRatios.append(ratio)
        }

        // Simulate the OLD buggy behavior: leftPaneWidth updates between frames
        var buggyRatios: [Double] = []
        var currentLeftWidth = initialLeft
        var currentRightWidth = initialRight
        for translation in cumulativeTranslations {
            // Bug: uses CURRENT (changing) width + cumulative translation
            let clampedLeft = min(
                max(currentLeftWidth + translation, minSize),
                currentLeftWidth + currentRightWidth - minSize
            )
            let ratio = clampedLeft / (currentLeftWidth + currentRightWidth)
            buggyRatios.append(ratio)

            // Simulate store update: layout changes, metrics recompute
            currentLeftWidth = totalWidth * ratio
            currentRightWidth = totalWidth * (1 - ratio)
        }

        // Fixed approach matches expected linear ratios
        for (index, (fixed, expected)) in zip(fixedRatios, expectedRatios).enumerated() {
            #expect(
                abs(fixed - expected) < 0.001,
                "Frame \(index): fixed ratio \(fixed) should match expected \(expected)"
            )
        }

        // Buggy approach diverges significantly from expected
        // By frame 5, the buggy ratio should be much larger than 0.55
        let buggyFinalRatio = buggyRatios.last!
        let expectedFinalRatio = expectedRatios.last!
        #expect(
            abs(buggyFinalRatio - expectedFinalRatio) > 0.01,
            "Buggy simulation should diverge from expected (got \(buggyFinalRatio), expected divergence from \(expectedFinalRatio))"
        )
    }

    @Test
    func simulatedDragSequence_fixedApproachIsStableAcrossManyFrames() {
        // Verify the fixed approach doesn't drift over a long drag sequence
        let minSize: CGFloat = 50
        let initialLeft: CGFloat = 300
        let initialRight: CGFloat = 300

        // 100 frames of 1pt-per-frame drag
        for frame in 1...100 {
            let translation = CGFloat(frame)
            let ratio = FlatPaneDivider.computeResizeRatio(
                initialLeftWidth: initialLeft,
                initialRightWidth: initialRight,
                translationWidth: translation,
                minSize: minSize
            )
            let expectedRatio = (initialLeft + translation) / (initialLeft + initialRight)
            #expect(
                abs(ratio - expectedRatio) < 0.0001,
                "Frame \(frame): ratio \(ratio) should equal \(expectedRatio)"
            )
        }
    }
}
