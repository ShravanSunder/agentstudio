import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemPathFilter")
struct FilesystemPathFilterTests {
    @Test("classifies git internals before ignore policy")
    func classifiesGitInternalsBeforeIgnorePolicy() throws {
        let rootPath = try makeRootWithGitIgnore(lines: ["*"])
        defer { try? FileManager.default.removeItem(at: rootPath) }
        let filter = FilesystemPathFilter.load(forRootPath: rootPath)

        #expect(filter.classify(relativePath: ".git/index") == .gitInternal)
        #expect(filter.classify(relativePath: "src/.git/config") == .gitInternal)
    }

    @Test("gitignore supports negation, root anchoring, directory patterns, and single-char wildcard")
    func supportsNegationAnchoringDirectoryAndSingleWildcard() throws {
        let rootPath = try makeRootWithGitIgnore(
            lines: [
                "*.log",
                "!important.log",
                "/root-only.txt",
                "build/",
                "foo?.txt",
            ]
        )
        defer { try? FileManager.default.removeItem(at: rootPath) }
        let filter = FilesystemPathFilter.load(forRootPath: rootPath)

        #expect(filter.isIgnored(relativePath: "debug.log"))
        #expect(!filter.isIgnored(relativePath: "important.log"))
        #expect(filter.isIgnored(relativePath: "root-only.txt"))
        #expect(!filter.isIgnored(relativePath: "src/root-only.txt"))
        #expect(filter.isIgnored(relativePath: "build/output.o"))
        #expect(filter.isIgnored(relativePath: "foo1.txt"))
        #expect(!filter.isIgnored(relativePath: "foo12.txt"))
    }

    @Test("double-star glob and regex metacharacters in file names are handled correctly")
    func supportsDoubleStarAndRegexMetacharacters() throws {
        let rootPath = try makeRootWithGitIgnore(
            lines: [
                "docs/**/*.tmp",
                "file[1].txt",
            ]
        )
        defer { try? FileManager.default.removeItem(at: rootPath) }
        let filter = FilesystemPathFilter.load(forRootPath: rootPath)

        #expect(filter.isIgnored(relativePath: "docs/a/b/c.tmp"))
        #expect(!filter.isIgnored(relativePath: "docs/a/b/c.txt"))
        #expect(filter.isIgnored(relativePath: "file[1].txt"))
        #expect(!filter.isIgnored(relativePath: "filea.txt"))
    }

    private func makeRootWithGitIgnore(lines: [String]) throws -> URL {
        let fileManager = FileManager.default
        let rootPath = fileManager.temporaryDirectory.appending(path: "path-filter-\(UUID().uuidString)")
        try fileManager.createDirectory(at: rootPath, withIntermediateDirectories: true)
        let contents = lines.joined(separator: "\n")
        try contents.write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        return rootPath
    }
}
