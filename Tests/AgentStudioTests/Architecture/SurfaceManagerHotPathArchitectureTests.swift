import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("SurfaceManagerHotPathArchitectureTests")
struct SurfaceManagerHotPathArchitectureTests {
    @Test("updateHealth guards unchanged health before observable writes")
    func updateHealthGuardsUnchangedHealthBeforeObservableWrites() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift"
            ),
            encoding: .utf8
        )

        let updateHealthBody = try #require(
            source.slice(
                from: "private func updateHealth(_ id: UUID, _ health: SurfaceHealth)",
                to: "private func handleDeadSurface"
            )
        )
        let guardRange = try #require(updateHealthBody.range(of: "guard previousHealth != health else { return }"))
        let cacheWriteRange = try #require(updateHealthBody.range(of: "surfaceHealth[id] = health"))
        let activeWriteRange = try #require(updateHealthBody.range(of: "activeSurfaces[id] = managed"))
        let delegateNotifyRange = try #require(updateHealthBody.range(of: "notifyHealthDelegates"))

        #expect(guardRange.lowerBound < cacheWriteRange.lowerBound)
        #expect(guardRange.lowerBound < activeWriteRange.lowerBound)
        #expect(cacheWriteRange.lowerBound < delegateNotifyRange.lowerBound)
    }

    @Test("surface manager injects performance recorder before initial surface size sync")
    func surfaceManagerInjectsPerformanceRecorderBeforeInitialSurfaceSizeSync() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let surfaceManagerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift"
            ),
            encoding: .utf8
        )
        let surfaceViewSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift"
            ),
            encoding: .utf8
        )

        let createSurfaceBody = try #require(
            surfaceManagerSource.slice(
                from: "func createSurface(",
                to: "// Verify surface was created successfully"
            )
        )
        #expect(createSurfaceBody.contains("performanceTraceRecorder: performanceTraceRecorder"))

        let surfaceViewInitBody = try #require(
            surfaceViewSource.slice(
                from: "init(",
                to: "required init?"
            )
        )
        let recorderAssignmentRange = try #require(
            surfaceViewInitBody.range(of: "self.performanceTraceRecorder = performanceTraceRecorder")
        )
        let initialSizeSyncRange = try #require(
            surfaceViewInitBody.range(of: "sizeDidChange(frame.size, source: \"init\")")
        )
        #expect(recorderAssignmentRange.lowerBound < initialSizeSyncRange.lowerBound)
    }

    @Test("manager collections are excluded from Observation and attach never asserts visibility")
    func managerCollectionsAreIgnoredAndAttachNeverAssertsVisibility() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift"
            ),
            encoding: .utf8
        )

        for collectionName in [
            "activeSurfaces",
            "hiddenSurfaces",
            "undoStack",
            "surfaceHealth",
            "surfaceViewToId",
        ] {
            let ignoredInternalDeclaration = "@ObservationIgnored var \(collectionName)"
            let ignoredPrivateDeclaration = "@ObservationIgnored private var \(collectionName)"
            #expect(
                source.contains(ignoredInternalDeclaration)
                    || source.contains(ignoredPrivateDeclaration)
            )
        }

        let attachBody = try #require(
            source.slice(
                from: "package func attach(_ surfaceId: UUID, to paneId: UUID)",
                to: "/// Detach a surface from its container"
            )
        )
        #expect(!attachBody.contains("visible: true"))
        #expect(!attachBody.contains("ghostty_surface_set_occlusion"))
    }

    @Test("native focus writes live only in the renderer delivery owner")
    func nativeFocusWritesLiveOnlyInRendererDeliveryOwner() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let surfaceManagerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift"
            ),
            encoding: .utf8
        )
        let surfaceViewSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift"
            ),
            encoding: .utf8
        )
        let deliverySource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceRendererStateDelivery.swift"
            ),
            encoding: .utf8
        )

        #expect(!surfaceManagerSource.contains("ghostty_surface_set_focus"))
        #expect(!surfaceViewSource.contains("ghostty_surface_set_focus"))
        #expect(deliverySource.contains("ghostty_surface_set_focus"))
    }

    @Test("surface deinit is MainActor isolated and frees synchronously")
    func surfaceDeinitIsIsolatedAndFreesSynchronously() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift"
            ),
            encoding: .utf8
        )
        let deinitBody = try #require(
            source.slice(from: "isolated deinit", to: "/// Called when the title changes")
        )

        #expect(deinitBody.contains("ghostty_surface_free(surface)"))
        #expect(!deinitBody.contains("Task {"))
    }
}

extension String {
    fileprivate func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
