import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TestPathResolverTests {

    @Test
    func test_projectRoot_fromTestsFilePath_findsPackageSwift() {
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let packagePath = URL(fileURLWithPath: projectRoot).appendingPathComponent("Package.swift").path

        #expect(FileManager.default.fileExists(atPath: packagePath))
    }

    @Test
    func test_projectRoot_findsNearestAncestorContainingPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-pathresolver-tests-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("level1").appendingPathComponent("level2")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let packagePath = root.appendingPathComponent("Package.swift")
        let markerPath = nested.appendingPathComponent("fixture.swift")

        let packageContents = "import PackageDescription\nlet package = Package(...)"
        let packageContentsData = Data("\(packageContents)".utf8)
        let markerData = Data("let fixture = true".utf8)
        try packageContentsData.write(to: packagePath)
        try markerData.write(to: markerPath)

        let resolvedRoot = TestPathResolver.projectRoot(from: markerPath.path)

        #expect(resolvedRoot == root.path)
    }
}
