import Foundation
import Testing

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
