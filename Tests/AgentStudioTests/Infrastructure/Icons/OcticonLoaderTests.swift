import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct OcticonLoaderTests {
    @Test
    func loadsIconFromExplicitResourceRoot() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-octicon-loader-\(UUID().uuidString)")
        let imageSetRoot =
            fixtureRoot
            .appending(path: "Icons.xcassets")
            .appending(path: "octicon-fixture.imageset")
        try FileManager.default.createDirectory(at: imageSetRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        try Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
              <rect width="16" height="16" />
            </svg>
            """.utf8
        ).write(to: imageSetRoot.appending(path: "octicon-fixture.svg"))

        // Act
        let loader = OcticonLoader(resourceRootURL: fixtureRoot)
        let image = loader.image(named: "octicon-fixture")

        // Assert
        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }
}
