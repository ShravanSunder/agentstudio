import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge source path containment")
struct BridgeSourcePathContainmentTests {
    private static let corpusRelativePath =
        "Tests/BridgeContractFixtures/edge/bridge-product-source-path-corpus.json"
    private static let mirroredCorpusRelativePath =
        "BridgeWeb/src/test-fixtures/bridge-contract-fixtures/edge/bridge-product-source-path-corpus.json"

    @Test("Swift and TypeScript source path corpora are exact mirrors")
    func sourcePathCorporaAreExactMirrors() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))

        // Act
        let swiftBytes = try Data(contentsOf: projectRoot.appending(path: Self.corpusRelativePath))
        let typeScriptBytes = try Data(
            contentsOf: projectRoot.appending(path: Self.mirroredCorpusRelativePath)
        )

        // Assert
        #expect(swiftBytes == typeScriptBytes)
    }

    @Test("shared corpus admits only contained regular files before byte reads")
    func sharedCorpusAdmitsOnlyContainedRegularFilesBeforeByteReads() throws {
        // Arrange
        let corpus = try loadCorpus()
        let fixture = try SourcePathFilesystemFixture(cases: corpus.cases)
        defer { fixture.remove() }
        #expect(corpus.schemaVersion == 1)
        #expect(Set(corpus.cases.map(\.name)).count == corpus.cases.count)

        // Act / Assert
        for fixtureCase in corpus.cases {
            try assertDisposition(fixtureCase, fixture: fixture)
        }
    }

    private func assertDisposition(
        _ fixtureCase: SourcePathCorpusCase,
        fixture: SourcePathFilesystemFixture
    ) throws {
        var byteReadActionCount = 0
        do {
            let containedFileURL = try BridgeSourcePathContainment.resolveRegularFile(
                rootURL: fixture.rootURL,
                relativePath: fixtureCase.relativePath
            )
            let bytes = try performByteRead(at: containedFileURL) {
                byteReadActionCount += 1
            }

            #expect(
                fixtureCase.expectedDisposition == .allow,
                Comment(rawValue: fixtureCase.name)
            )
            #expect(byteReadActionCount == 1, Comment(rawValue: fixtureCase.name))
            #expect(
                String(bytes: bytes, encoding: .utf8) == fixtureCase.expectedContents,
                Comment(rawValue: fixtureCase.name)
            )
        } catch let error as BridgeSourcePathContainmentError {
            #expect(
                fixtureCase.expectedDisposition == .reject,
                Comment(rawValue: fixtureCase.name)
            )
            #expect(error.corpusFailure == fixtureCase.expectedFailure, Comment(rawValue: fixtureCase.name))
            #expect(byteReadActionCount == 0, Comment(rawValue: fixtureCase.name))
            assertSanitized(
                error,
                submittedPath: fixtureCase.relativePath,
                rootURL: fixture.rootURL,
                externalURL: fixture.externalURL,
                caseName: fixtureCase.name
            )
        }
    }

    private func performByteRead(
        at fileURL: URL,
        willRead: () -> Void
    ) throws -> Data {
        willRead()
        return try Data(contentsOf: fileURL)
    }

    private func assertSanitized(
        _ error: BridgeSourcePathContainmentError,
        submittedPath: String,
        rootURL: URL,
        externalURL: URL,
        caseName: String
    ) {
        let description = String(describing: error)
        #expect(!description.contains(rootURL.path), Comment(rawValue: caseName))
        #expect(!description.contains(externalURL.path), Comment(rawValue: caseName))
        if !submittedPath.isEmpty {
            #expect(!description.contains(submittedPath), Comment(rawValue: caseName))
        }
    }

    private func loadCorpus() throws -> SourcePathCorpus {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(contentsOf: projectRoot.appending(path: Self.corpusRelativePath))
        return try JSONDecoder().decode(SourcePathCorpus.self, from: data)
    }
}

private struct SourcePathFilesystemFixture {
    let containerURL: URL
    let externalURL: URL
    let rootURL: URL

    init(cases: [SourcePathCorpusCase]) throws {
        let fileManager = FileManager.default
        containerURL = fileManager.temporaryDirectory.appending(
            path: "agentstudio-bridge-source-containment-\(UUID().uuidString)"
        )
        externalURL = containerURL.appending(path: "external")
        rootURL = containerURL.appending(path: "worktree")
        try fileManager.createDirectory(at: externalURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        for fixtureCase in cases where fixtureCase.fixtureKind == .ordinaryNestedFile {
            try write(
                fixtureCase.expectedContents ?? "",
                to: rootURL.appending(path: fixtureCase.relativePath)
            )
        }
        for fixtureCase in cases where fixtureCase.fixtureKind == .caseAlias {
            guard
                let fixtureTargetPath = fixtureCase.fixtureTargetPath,
                let fixtureTargetContents = fixtureCase.fixtureTargetContents
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try write(
                fixtureTargetContents,
                to: rootURL.appending(path: fixtureTargetPath)
            )
        }

        let internalTargetURL = rootURL.appending(path: "targets/internal.txt")
        try write("internal symlink target", to: internalTargetURL)
        let externalTargetURL = externalURL.appending(path: "secret.txt")
        try write("external secret", to: externalTargetURL)
        let internalGitConfigURL = rootURL.appending(path: ".git/config")
        try write("internal git config", to: internalGitConfigURL)
        let linksURL = rootURL.appending(path: "links")
        try fileManager.createDirectory(at: linksURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: linksURL.appending(path: "internal-file.txt"),
            withDestinationURL: internalTargetURL
        )
        try fileManager.createSymbolicLink(
            at: linksURL.appending(path: "external-file.txt"),
            withDestinationURL: externalTargetURL
        )
        try fileManager.createSymbolicLink(
            at: linksURL.appending(path: "external-directory"),
            withDestinationURL: externalURL
        )
        try fileManager.createSymbolicLink(
            at: linksURL.appending(path: "internal-git-config"),
            withDestinationURL: internalGitConfigURL
        )
        try fileManager.createDirectory(
            at: rootURL.appending(path: "ordinary-directory"),
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: containerURL)
    }

    private func write(_ value: String, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: fileURL)
    }
}

private struct SourcePathCorpus: Decodable {
    let schemaVersion: Int
    let cases: [SourcePathCorpusCase]
}

private struct SourcePathCorpusCase: Decodable {
    let name: String
    let fixtureKind: SourcePathFixtureKind
    let relativePath: String
    let fixtureTargetPath: String?
    let fixtureTargetContents: String?
    let expectedDisposition: SourcePathExpectedDisposition
    let expectedFailure: SourcePathExpectedFailure?
    let expectedContents: String?
}

private enum SourcePathFixtureKind: String, Decodable {
    case lexical
    case ordinaryNestedFile = "ordinary-nested-file"
    case internalFileSymlink = "internal-file-symlink"
    case externalFileSymlink = "external-file-symlink"
    case externalDirectorySymlink = "external-directory-symlink"
    case internalGitFileSymlink = "internal-git-file-symlink"
    case caseAlias = "case-alias"
    case directory
    case missingFile = "missing-file"
}

private enum SourcePathExpectedDisposition: String, Decodable {
    case allow
    case reject
}

private enum SourcePathExpectedFailure: String, Decodable {
    case invalidSelector = "invalid-selector"
    case outsideRoot = "outside-root"
    case notRegularFile = "not-regular-file"
}

extension BridgeSourcePathContainmentError {
    fileprivate var corpusFailure: SourcePathExpectedFailure {
        switch self {
        case .invalidRoot, .invalidSelector:
            .invalidSelector
        case .outsideRoot:
            .outsideRoot
        case .notRegularFile:
            .notRegularFile
        }
    }
}
