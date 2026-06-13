import Foundation
import Testing

@testable import AgentStudio

@Suite("TerminalPaneMountView displaySurface")
struct TerminalPaneMountViewDisplaySurfaceTests {
    @Test("same-surface display skips rewrap only when the current scroll wrapper is mounted")
    func sameSurfaceDisplaySkipsRewrapOnlyForMountedCurrentWrapper() {
        #expect(
            TerminalPaneMountView.shouldReuseMountedSurfaceWrapper(
                currentSurfaceMatchesIncoming: true,
                currentWrapperExists: true,
                currentWrapperIsMounted: true
            )
        )
        #expect(
            !TerminalPaneMountView.shouldReuseMountedSurfaceWrapper(
                currentSurfaceMatchesIncoming: false,
                currentWrapperExists: true,
                currentWrapperIsMounted: true
            )
        )
        #expect(
            !TerminalPaneMountView.shouldReuseMountedSurfaceWrapper(
                currentSurfaceMatchesIncoming: true,
                currentWrapperExists: false,
                currentWrapperIsMounted: false
            )
        )
        #expect(
            !TerminalPaneMountView.shouldReuseMountedSurfaceWrapper(
                currentSurfaceMatchesIncoming: true,
                currentWrapperExists: true,
                currentWrapperIsMounted: false
            )
        )
    }

    @Test("same-surface display plan preserves required post-display effects without rewrap reset")
    func sameSurfaceDisplayPlanPreservesSkipPathEffects() {
        let plan = TerminalPaneMountView.surfaceDisplayPlan(
            currentSurfaceMatchesIncoming: true,
            currentWrapperExists: true,
            currentWrapperIsMounted: true,
            hasBoundRuntime: true,
            observedRuntimeMatchesBoundRuntime: true,
            runtimeBoundToDisplayedSurfaceMatchesBoundRuntime: true
        )

        #expect(plan.reusesMountedWrapper)
        #expect(plan.resetsGeometryReportDedup)
        #expect(!plan.resetsTerminationFlags)
        #expect(!plan.observesRuntime)
        #expect(plan.appliesRuntimeSnapshot)
        #expect(!plan.bindsRuntimeToSurface)
        #expect(plan.installsCloseCallback)
        #expect(!plan.beginsRestorePresentation)
    }

    @Test("same-surface display plan binds runtime when the surface has not been bound yet")
    func sameSurfaceDisplayPlanBindsRuntimeWhenNeeded() {
        let plan = TerminalPaneMountView.surfaceDisplayPlan(
            currentSurfaceMatchesIncoming: true,
            currentWrapperExists: true,
            currentWrapperIsMounted: true,
            hasBoundRuntime: true,
            observedRuntimeMatchesBoundRuntime: false,
            runtimeBoundToDisplayedSurfaceMatchesBoundRuntime: false
        )

        #expect(plan.reusesMountedWrapper)
        #expect(plan.observesRuntime)
        #expect(plan.appliesRuntimeSnapshot)
        #expect(plan.bindsRuntimeToSurface)
        #expect(!plan.resetsTerminationFlags)
        #expect(!plan.beginsRestorePresentation)
    }

    @Test("rewrap display plan resets termination state and binds runtime")
    func rewrapDisplayPlanResetsTerminationStateAndBindsRuntime() {
        let plan = TerminalPaneMountView.surfaceDisplayPlan(
            currentSurfaceMatchesIncoming: false,
            currentWrapperExists: true,
            currentWrapperIsMounted: true,
            hasBoundRuntime: true,
            observedRuntimeMatchesBoundRuntime: true,
            runtimeBoundToDisplayedSurfaceMatchesBoundRuntime: true
        )

        #expect(!plan.reusesMountedWrapper)
        #expect(plan.resetsGeometryReportDedup)
        #expect(plan.resetsTerminationFlags)
        #expect(!plan.observesRuntime)
        #expect(plan.appliesRuntimeSnapshot)
        #expect(plan.bindsRuntimeToSurface)
        #expect(plan.installsCloseCallback)
        #expect(plan.beginsRestorePresentation)
    }

    @Test("same-surface display branch returns before unmounting or rewrapping")
    func sameSurfaceDisplayBranchReturnsBeforeUnmountingOrRewrapping() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceURL = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let reuseBranchStart = try #require(source.range(of: "if displayPlan.reusesMountedWrapper {"))
        let rewrapBranchStart = try #require(source.range(of: "// Remove existing surface if any"))
        let reuseBranch = String(source[reuseBranchStart.lowerBound..<rewrapBranchStart.lowerBound])

        #expect(reuseBranch.contains("finishSurfaceDisplay(surfaceView, displayPlan: displayPlan)"))
        #expect(reuseBranch.contains("return"))
        #expect(!reuseBranch.contains("ghosttyMountView.unmountCurrentView()"))
        #expect(!reuseBranch.contains("TerminalSurfaceScrollView("))

        let finishStart = try #require(source.range(of: "private func finishSurfaceDisplay("))
        let removeSurfaceStart = try #require(source.range(of: "func removeSurface()"))
        let finishBody = String(source[finishStart.lowerBound..<removeSurfaceStart.lowerBound])

        #expect(finishBody.contains("if displayPlan.beginsRestorePresentation"))
        #expect(finishBody.contains("applyRuntimeStateSnapshot(boundRuntime)"))
        #expect(finishBody.contains("surfaceView.bindRuntime(boundRuntime)"))
        #expect(finishBody.contains("surfaceView.onCloseRequested"))
    }
}
