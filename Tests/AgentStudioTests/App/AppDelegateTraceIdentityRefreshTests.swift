import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateTraceIdentityRefreshTests {
    @Test("concurrent producer requests share one pre-capture refresh")
    func concurrentProducerRequestsShareOneFleetCapture() async {
        let traceRuntime = AgentStudioTraceRuntime.fromEnvironment([
            "AGENTSTUDIO_TRACE_TAGS": "off"
        ])
        let appDelegate = AppDelegate(
            traceRuntime: traceRuntime,
            startupTraceRecorder: AgentStudioStartupTraceRecorder(traceRuntime: traceRuntime)
        )
        appDelegate.atomStore = makeInstalledTestAtomRegistry()
        appDelegate.store = WorkspaceStore()
        let initialFleetCaptureCount = appDelegate.traceIdentityFleetCaptureCount

        appDelegate.requestTraceIdentityRefresh()
        appDelegate.requestTraceIdentityRefresh()
        await appDelegate.waitForTraceIdentityRefreshIdle()

        #expect(appDelegate.traceIdentityFleetCaptureCount == initialFleetCaptureCount + 1)
    }
}
