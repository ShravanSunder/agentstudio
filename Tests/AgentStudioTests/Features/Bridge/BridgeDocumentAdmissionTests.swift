import AgentStudioCore
import AgentStudioInfrastructure
import Darwin
import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeDocumentAdmissionTests {
    @Test("an absolute or base-relative text file outside Git is admitted at its canonical location")
    func admitsAbsoluteAndBaseRelativeFileAtCanonicalLocation() async throws {
        // Arrange
        let directory = try AdmissionTemporaryDirectory()
        defer { directory.remove() }
        let fileURL = try directory.write("notes.md", contents: Data("# Notes\n".utf8))
        let canonicalPath = try #require(realPath(fileURL.path))

        // Act
        let absolute = await BridgeDocumentAdmission.admit(
            .init(requestedPath: fileURL.path, baseDirectory: nil)
        )
        let relative = await BridgeDocumentAdmission.admit(
            .init(requestedPath: "./notes.md", baseDirectory: directory.url)
        )

        // Assert
        let expected = BridgeAdmittedDocument(
            location: try #require(BridgeDocumentLocation(canonicalPath: canonicalPath)),
            byteCount: 8
        )
        #expect(absolute == .success(expected))
        #expect(relative == .success(expected))
        #expect(canonicalPath.hasPrefix("/private/"))
    }

    @Test("a symlinked file is admitted as its target document")
    func admitsSymlinkedFileAsItsTarget() async throws {
        // Arrange
        let directory = try AdmissionTemporaryDirectory()
        defer { directory.remove() }
        let targetURL = try directory.write("target.txt", contents: Data("target\n".utf8))
        let linkURL = directory.url.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        // Act
        let result = await BridgeDocumentAdmission.admit(
            .init(requestedPath: linkURL.path, baseDirectory: nil)
        )

        // Assert
        let targetPath = try #require(realPath(targetURL.path))
        #expect(result.admittedLocation?.canonicalPath == targetPath)
    }

    @Test("admission refuses with the specific reason and never falls back")
    func refusesWithSpecificReasons() async throws {
        // Arrange
        let directory = try AdmissionTemporaryDirectory()
        defer { directory.remove() }
        let binaryURL = try directory.write("image.bin", contents: Data([0x89, 0x50, 0x00, 0x47]))
        let invalidUTF8URL = try directory.write("latin1.txt", contents: Data([0x63, 0x61, 0xE9, 0x0A]))
        let folderURL = directory.url.appending(path: "folder")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        let folderLinkURL = directory.url.appending(path: "folder-link")
        try FileManager.default.createSymbolicLink(at: folderLinkURL, withDestinationURL: folderURL)
        let danglingLinkURL = directory.url.appending(path: "dangling.txt")
        try FileManager.default.createSymbolicLink(
            at: danglingLinkURL,
            withDestinationURL: directory.url.appending(path: "missing-target.txt")
        )
        let pipeURL = directory.url.appending(path: "pipe")
        #expect(mkfifo(pipeURL.path, 0o600) == 0)

        // Act / Assert
        let cases: [(String, URL?, BridgeDocumentAdmissionRefusal)] = [
            ("notes.md", nil, .relativePathWithoutBaseDirectory),
            (directory.url.appending(path: "missing.md").path, nil, .notFound),
            (danglingLinkURL.path, nil, .notFound),
            (folderURL.path, nil, .notRegularFile),
            (folderLinkURL.path, nil, .notRegularFile),
            (pipeURL.path, nil, .notRegularFile),
            (binaryURL.path, nil, .unsupportedContent(.binary)),
            (invalidUTF8URL.path, nil, .unsupportedContent(.unsupportedEncoding)),
        ]
        for (requestedPath, baseDirectory, expectedRefusal) in cases {
            let result = await BridgeDocumentAdmission.admit(
                .init(requestedPath: requestedPath, baseDirectory: baseDirectory)
            )
            #expect(result == .failure(expectedRefusal), "\(requestedPath)")
        }
    }

    @Test("a file removed after one admission is refused as missing on the next")
    func refusesFileRemovedAfterEarlierAdmission() async throws {
        // Arrange
        let directory = try AdmissionTemporaryDirectory()
        defer { directory.remove() }
        let fileURL = try directory.write("transient.md", contents: Data("soon gone\n".utf8))
        let first = await BridgeDocumentAdmission.admit(.init(requestedPath: fileURL.path, baseDirectory: nil))
        try FileManager.default.removeItem(at: fileURL)

        // Act
        let second = await BridgeDocumentAdmission.admit(.init(requestedPath: fileURL.path, baseDirectory: nil))

        // Assert
        #expect(first.admittedLocation != nil)
        #expect(second == .failure(.notFound))
    }
}

extension Result where Success == BridgeAdmittedDocument {
    fileprivate var admittedLocation: BridgeDocumentLocation? {
        if case .success(let document) = self { return document.location }
        return nil
    }
}

private struct AdmissionTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "bridge-document-admission-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ name: String, contents: Data) throws -> URL {
        let fileURL = url.appending(path: name)
        try contents.write(to: fileURL)
        return fileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func realPath(_ path: String) -> String? {
    path.withCString { pointer in
        guard let resolved = Darwin.realpath(pointer, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
