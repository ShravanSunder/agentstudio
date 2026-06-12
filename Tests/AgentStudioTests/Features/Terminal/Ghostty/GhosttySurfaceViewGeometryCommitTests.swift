import AppKit
import Testing

@testable import AgentStudio

@Suite("GhosttySurfaceView geometry commit")
struct GhosttySurfaceViewGeometryCommitTests {
    @Test("geometry commit plan commits new valid geometry")
    func geometryCommitPlanCommitsNewValidGeometry() {
        let expectedGeometry = Ghostty.SurfaceView.SurfaceGeometry(
            contentScaleX: 2,
            contentScaleY: 2,
            widthPx: 800,
            heightPx: 600
        )

        let plan = Ghostty.SurfaceView.geometryCommitPlan(
            contentScale: (x: 2, y: 2),
            backingSize: NSSize(width: 800, height: 600),
            lastCommittedGeometry: nil
        )

        #expect(plan == .commit(expectedGeometry))
    }

    @Test("geometry commit plan skips identical scale and pixel size")
    func geometryCommitPlanSkipsIdenticalGeometry() {
        let committedGeometry = Ghostty.SurfaceView.SurfaceGeometry(
            contentScaleX: 2,
            contentScaleY: 2,
            widthPx: 800,
            heightPx: 600
        )

        let plan = Ghostty.SurfaceView.geometryCommitPlan(
            contentScale: (x: 2, y: 2),
            backingSize: NSSize(width: 800, height: 600),
            lastCommittedGeometry: committedGeometry
        )

        #expect(plan == .skip(committedGeometry))
    }

    @Test("geometry commit plan rejects missing or invalid scale")
    func geometryCommitPlanRejectsMissingOrInvalidScale() {
        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: nil,
                backingSize: NSSize(width: 800, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.missingContentScale)
        )

        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: .nan, y: 2),
                backingSize: NSSize(width: 800, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.invalidContentScale)
        )
    }

    @Test("geometry commit plan rejects degenerate backing size")
    func geometryCommitPlanRejectsDegenerateBackingSize() {
        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: 2, y: 2),
                backingSize: NSSize(width: 0, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.invalidBackingSize)
        )

        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: 2, y: 2),
                backingSize: NSSize(width: CGFloat.infinity, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.invalidBackingSize)
        )

        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: 2, y: 2),
                backingSize: NSSize(width: 0.5, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.invalidBackingSize)
        )
    }

    @Test("geometry commit plan protects the UInt32 pixel boundary")
    func geometryCommitPlanProtectsPixelBoundary() {
        let maxPixelDimension = CGFloat(UInt32.max)

        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: 2, y: 2),
                backingSize: NSSize(width: maxPixelDimension, height: maxPixelDimension),
                lastCommittedGeometry: nil
            )
                == .commit(
                    Ghostty.SurfaceView.SurfaceGeometry(
                        contentScaleX: 2,
                        contentScaleY: 2,
                        widthPx: UInt32.max,
                        heightPx: UInt32.max
                    )
                )
        )

        #expect(
            Ghostty.SurfaceView.geometryCommitPlan(
                contentScale: (x: 2, y: 2),
                backingSize: NSSize(width: maxPixelDimension + 1, height: 600),
                lastCommittedGeometry: nil
            ) == .reject(.invalidBackingSize)
        )
    }

    @Test("geometry coherence comparator accepts matching geometry within tolerance")
    func geometryCoherenceComparatorAcceptsMatchingGeometryWithinTolerance() {
        let committedGeometry = Ghostty.SurfaceView.SurfaceGeometry(
            contentScaleX: 2,
            contentScaleY: 2,
            widthPx: 800,
            heightPx: 600
        )

        let status = Ghostty.SurfaceView.geometryCoherenceStatus(
            committedGeometry: committedGeometry,
            expectedContentScale: (x: 2.0005, y: 1.9995),
            expectedBackingSize: NSSize(width: 800.9, height: 599.2)
        )

        #expect(status == .coherent)
    }

    @Test("geometry coherence comparator reports scale and size drift")
    func geometryCoherenceComparatorReportsScaleAndSizeDrift() {
        let committedGeometry = Ghostty.SurfaceView.SurfaceGeometry(
            contentScaleX: 2,
            contentScaleY: 2,
            widthPx: 800,
            heightPx: 600
        )

        let status = Ghostty.SurfaceView.geometryCoherenceStatus(
            committedGeometry: committedGeometry,
            expectedContentScale: (x: 1.5, y: 2),
            expectedBackingSize: NSSize(width: 804, height: 600)
        )

        #expect(status == .incoherent(scaleDrift: true, sizeDrift: true))
    }

    @Test("geometry coherence comparator reports no-window as unavailable")
    func geometryCoherenceComparatorReportsNoWindowAsUnavailable() {
        let committedGeometry = Ghostty.SurfaceView.SurfaceGeometry(
            contentScaleX: 2,
            contentScaleY: 2,
            widthPx: 800,
            heightPx: 600
        )

        let status = Ghostty.SurfaceView.geometryCoherenceStatus(
            committedGeometry: committedGeometry,
            expectedContentScale: nil,
            expectedBackingSize: NSSize(width: 800, height: 600)
        )

        #expect(status == .unavailable(.missingWindow))
    }

    @Test("geometry verification expected size prefers live bounds over cached content size")
    func geometryVerificationExpectedSizePrefersLiveBounds() {
        let expectedSize = Ghostty.SurfaceView.contentSizeForGeometryVerification(
            contentSize: NSSize(width: 800, height: 600),
            boundsSize: NSSize(width: 1024, height: 768),
            frameSize: NSSize(width: 900, height: 700)
        )

        #expect(expectedSize == NSSize(width: 1024, height: 768))
    }

    @Test("geometry verification expected size falls back after degenerate live sizes")
    func geometryVerificationExpectedSizeFallsBackAfterDegenerateLiveSizes() {
        let expectedSize = Ghostty.SurfaceView.contentSizeForGeometryVerification(
            contentSize: NSSize(width: 800, height: 600),
            boundsSize: .zero,
            frameSize: .zero
        )

        #expect(expectedSize == NSSize(width: 800, height: 600))
    }
}
