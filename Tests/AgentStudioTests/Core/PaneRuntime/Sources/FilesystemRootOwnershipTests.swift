import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemRootOwnership")
struct FilesystemRootOwnershipTests {
    @Test("routes to deepest matching root across nested ownership")
    func routesToDeepestMatchingRoot() {
        let parentWorktreeId = UUID()
        let nestedWorktreeId = UUID()
        let deepestWorktreeId = UUID()

        let ownership = FilesystemRootOwnership(
            rootsByWorktree: [
                parentWorktreeId: URL(fileURLWithPath: "/tmp/root"),
                nestedWorktreeId: URL(fileURLWithPath: "/tmp/root/nested"),
                deepestWorktreeId: URL(fileURLWithPath: "/tmp/root/nested/deep"),
            ]
        )

        let owned = ownership.route(
            sourceWorktreeId: parentWorktreeId,
            rawPath: "/tmp/root/nested/deep/src/File.swift"
        )

        #expect(owned?.worktreeId == deepestWorktreeId)
        #expect(owned?.relativePath == "src/File.swift")
    }

    @Test("exact root boundary resolves relative path to dot")
    func exactRootBoundaryResolvesToDot() {
        let worktreeId = UUID()
        let ownership = FilesystemRootOwnership(
            rootsByWorktree: [worktreeId: URL(fileURLWithPath: "/tmp/repo/")]
        )

        let owned = ownership.route(
            sourceWorktreeId: worktreeId,
            rawPath: "/tmp/repo"
        )

        #expect(owned?.worktreeId == worktreeId)
        #expect(owned?.relativePath == ".")
    }

    @Test("comparison is case-insensitive for canonical path ownership")
    func ownershipComparisonIsCaseInsensitive() {
        let worktreeId = UUID()
        let ownership = FilesystemRootOwnership(
            rootsByWorktree: [worktreeId: URL(fileURLWithPath: "/tmp/RepoCase")]
        )

        let owned = ownership.route(
            sourceWorktreeId: worktreeId,
            rawPath: "/tmp/repocase/Sources/App.swift"
        )

        #expect(owned?.worktreeId == worktreeId)
        #expect(owned?.relativePath == "Sources/App.swift")
    }

    @Test("symlinked root canonicalization routes to same owner")
    func symlinkedRootCanonicalizationRoutesToOwner() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appending(path: "ownership-\(UUID().uuidString)")
        let realRoot = tempRoot.appending(path: "real")
        let linkRoot = tempRoot.appending(path: "link")
        defer { try? fileManager.removeItem(at: tempRoot) }

        try fileManager.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: linkRoot, withDestinationURL: realRoot)

        let worktreeId = UUID()
        let ownership = FilesystemRootOwnership(
            rootsByWorktree: [worktreeId: linkRoot]
        )

        let owned = ownership.route(
            sourceWorktreeId: worktreeId,
            rawPath: realRoot.appending(path: "src/main.swift").path
        )

        #expect(owned?.worktreeId == worktreeId)
        #expect(owned?.relativePath == "src/main.swift")
    }

    @Test("unknown source worktree returns nil route")
    func unknownSourceWorktreeReturnsNilRoute() {
        let worktreeId = UUID()
        let ownership = FilesystemRootOwnership(
            rootsByWorktree: [worktreeId: URL(fileURLWithPath: "/tmp/repo")]
        )

        let owned = ownership.route(
            sourceWorktreeId: UUID(),
            rawPath: "/tmp/repo/Sources/App.swift"
        )

        #expect(owned == nil)
    }
}
