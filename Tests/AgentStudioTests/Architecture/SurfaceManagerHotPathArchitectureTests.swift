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

    @Test("manager membership collections are excluded from Observation")
    func managerMembershipCollectionsAreExcludedFromObservation() throws {
        // Reconciliation reads `activeSurfaces` inside `withObservationTracking`; if the
        // collections were observable, every health or CWD rewrite would re-arm the observer.
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
                source.contains(ignoredInternalDeclaration) || source.contains(ignoredPrivateDeclaration),
                "\(collectionName) must be @ObservationIgnored"
            )
        }
    }

    @Test("native occlusion delivery lives only in the renderer state delivery seam")
    func nativeOcclusionDeliveryLivesOnlyInRendererStateDeliverySeam() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let terminalRoot = projectRoot.appending(path: "Sources/AgentStudio/Features/Terminal")
        let deliveryPath = terminalRoot.appending(path: "Ghostty/SurfaceRendererStateDelivery.swift")
        let deliverySource = try String(contentsOf: deliveryPath, encoding: .utf8)
        #expect(deliverySource.contains("ghostty_surface_set_occlusion"))

        let enumerator = try #require(
            FileManager.default.enumerator(at: terminalRoot, includingPropertiesForKeys: nil)
        )
        var offendingFiles: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard fileURL.standardizedFileURL != deliveryPath.standardizedFileURL else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("ghostty_surface_set_occlusion") {
                offendingFiles.append(fileURL.lastPathComponent)
            }
        }
        #expect(offendingFiles.isEmpty, "occlusion delivered outside the seam by \(offendingFiles)")
    }

    @Test("native focus delivery lives only in the renderer state delivery seam")
    func nativeFocusDeliveryLivesOnlyInRendererStateDeliverySeam() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let terminalRoot = projectRoot.appending(path: "Sources/AgentStudio/Features/Terminal")
        let deliveryPath = terminalRoot.appending(path: "Ghostty/SurfaceRendererStateDelivery.swift")
        let deliverySource = try String(contentsOf: deliveryPath, encoding: .utf8)
        #expect(deliverySource.contains("ghostty_surface_set_focus"))

        let enumerator = try #require(
            FileManager.default.enumerator(at: terminalRoot, includingPropertiesForKeys: nil)
        )
        var offendingFiles: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard fileURL.standardizedFileURL != deliveryPath.standardizedFileURL else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("ghostty_surface_set_focus") {
                offendingFiles.append(fileURL.lastPathComponent)
            }
        }
        #expect(offendingFiles.isEmpty, "focus delivered outside the seam by \(offendingFiles)")
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
