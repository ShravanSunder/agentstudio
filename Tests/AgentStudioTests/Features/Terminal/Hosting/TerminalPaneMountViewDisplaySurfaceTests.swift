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

    @Test("display epilogue verifies geometry without repairing it first")
    func displayEpilogueVerifiesGeometryWithoutRepairingItFirst() {
        #expect(TerminalPaneMountView.geometryVerificationMode(for: .displayEpilogue) == .verifyOnlyAfterLayout)
        #expect(TerminalPaneMountView.geometryVerificationMode(for: .explicitGeometrySync) == .syncThenVerify)
    }
}
