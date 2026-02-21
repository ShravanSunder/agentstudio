import Foundation
import XCTest

@testable import AgentStudio

final class TestPathResolverTests: XCTestCase {

    func test_projectRoot_fromTestsFilePath_findsPackageSwift() {
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let packagePath = URL(fileURLWithPath: projectRoot).appendingPathComponent("Package.swift").path

        XCTAssertTrue(FileManager.default.fileExists(atPath: packagePath))
    }

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
        try packageContents.data(using: .utf8)?.write(to: packagePath)
        try "let fixture = true".data(using: .utf8)?.write(to: markerPath)

        let resolvedRoot = TestPathResolver.projectRoot(from: markerPath.path)

        XCTAssertEqual(resolvedRoot, root.path)
    }
}
