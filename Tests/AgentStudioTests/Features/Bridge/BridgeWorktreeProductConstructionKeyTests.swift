import Testing

@testable import AgentStudio

@Suite("Bridge worktree product construction keys")
struct BridgeWorktreeProductConstructionKeyTests {
    @Test("file key includes every semantic owner selector status and ignore dimension")
    func fileCollisionVectors() {
        // Arrange
        let base = makeBridgeFileConstructionKey()
        let variants: [BridgeWorktreeProductConstructionKey] = [
            makeBridgeFileConstructionKey(owner: makeBridgeConstructionOwner(repo: "repo-b")),
            makeBridgeFileConstructionKey(owner: makeBridgeConstructionOwner(worktree: "worktree-b")),
            makeBridgeFileConstructionKey(owner: makeBridgeConstructionOwner(root: "root-b")),
            makeBridgeFileConstructionKey(owner: makeBridgeConstructionOwner(provider: "provider-b")),
            makeBridgeFileConstructionKey(canonicalWorkingDirectoryIdentity: "cwd-b"),
            makeBridgeFileConstructionKey(pathScope: ["Tests"]),
            makeBridgeFileConstructionKey(
                statusSemantics: .init(
                    includesUntracked: false, includesIgnored: false, detectsRenames: true,
                    recursesUntrackedDirectories: true)),
            makeBridgeFileConstructionKey(
                statusSemantics: .init(
                    includesUntracked: true, includesIgnored: true, detectsRenames: true,
                    recursesUntrackedDirectories: true)),
            makeBridgeFileConstructionKey(
                statusSemantics: .init(
                    includesUntracked: true, includesIgnored: false, detectsRenames: false,
                    recursesUntrackedDirectories: true)),
            makeBridgeFileConstructionKey(
                statusSemantics: .init(
                    includesUntracked: true, includesIgnored: false, detectsRenames: true,
                    recursesUntrackedDirectories: false)),
            makeBridgeFileConstructionKey(
                ignoreSemantics: .init(
                    respectsRepositoryIgnore: false, respectsInfoExclude: true, respectsGlobalIgnore: false,
                    additionalPatternIdentity: "patterns-a")),
            makeBridgeFileConstructionKey(
                ignoreSemantics: .init(
                    respectsRepositoryIgnore: true, respectsInfoExclude: false, respectsGlobalIgnore: false,
                    additionalPatternIdentity: "patterns-a")),
            makeBridgeFileConstructionKey(
                ignoreSemantics: .init(
                    respectsRepositoryIgnore: true, respectsInfoExclude: true, respectsGlobalIgnore: true,
                    additionalPatternIdentity: "patterns-a")),
            makeBridgeFileConstructionKey(
                ignoreSemantics: .init(
                    respectsRepositoryIgnore: true, respectsInfoExclude: true, respectsGlobalIgnore: false,
                    additionalPatternIdentity: "patterns-b")),
        ]

        // Act
        let keys = Set([base] + variants)

        // Assert
        #expect(keys.count == variants.count + 1)
        #expect(makeBridgeFileConstructionKey(pathScope: ["Sources", "Sources"]) == base)
    }

    @Test("review key includes every semantic owner endpoint filter grouping provenance and checkpoint dimension")
    func reviewCollisionVectors() {
        // Arrange
        let base = makeBridgeReviewConstructionKey()
        let variants: [BridgeWorktreeProductConstructionKey] = [
            makeBridgeReviewConstructionKey(owner: makeBridgeConstructionOwner(repo: "repo-b")),
            makeBridgeReviewConstructionKey(owner: makeBridgeConstructionOwner(worktree: "worktree-b")),
            makeBridgeReviewConstructionKey(owner: makeBridgeConstructionOwner(root: "root-b")),
            makeBridgeReviewConstructionKey(owner: makeBridgeConstructionOwner(provider: "provider-b")),
            makeBridgeReviewConstructionKey(queryKind: .browseTree),
            makeBridgeReviewConstructionKey(comparisonSemantics: .twoDot),
            makeBridgeReviewConstructionKey(canonicalWorkingDirectoryIdentity: "cwd-b"),
            makeBridgeReviewConstructionKey(
                baseEndpoint: .init(kind: .gitObject, providerIdentity: "provider-a", contentIdentity: "base-oid-b")),
            makeBridgeReviewConstructionKey(
                baseEndpoint: .init(kind: .checkpoint, providerIdentity: "provider-a", contentIdentity: "base-oid")),
            makeBridgeReviewConstructionKey(
                baseEndpoint: .init(kind: .gitObject, providerIdentity: "provider-b", contentIdentity: "base-oid")),
            makeBridgeReviewConstructionKey(
                headEndpoint: .init(kind: .workingTree, providerIdentity: "provider-a", contentIdentity: "head-oid")),
            makeBridgeReviewConstructionKey(
                headEndpoint: .init(kind: .gitObject, providerIdentity: "provider-b", contentIdentity: "head-oid")),
            makeBridgeReviewConstructionKey(
                headEndpoint: .init(kind: .gitObject, providerIdentity: "provider-a", contentIdentity: "head-oid-b")),
            makeBridgeReviewConstructionKey(pathScope: ["Tests"]),
            makeBridgeReviewConstructionKey(fileTarget: "Sources/App.swift"),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(includedPathGlobs: ["Tests/**"])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(excludedPathGlobs: [])),
            makeBridgeReviewConstructionKey(
                viewFilter: makeBridgeReviewViewFilterKey(includedFileClasses: ["documentation"])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(excludedFileClasses: [])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(includedExtensions: ["md"])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(excludedExtensions: [])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(changeKinds: ["added"])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(reviewStates: ["reviewed"])),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(showsHiddenFiles: true)),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(showsBinaryFiles: true)),
            makeBridgeReviewConstructionKey(viewFilter: makeBridgeReviewViewFilterKey(showsLargeFiles: false)),
            makeBridgeReviewConstructionKey(grouping: .init(kind: .fileClass, label: "Folder")),
            makeBridgeReviewConstructionKey(grouping: .init(kind: .folder, label: "Directory")),
            makeBridgeReviewConstructionKey(provenance: makeBridgeReviewProvenanceFilterKey(paneIdentities: [])),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(agentSessionIdentities: ["session-b"])),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(promptIdentities: ["prompt-b"])),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(operationIdentities: ["operation-b"])),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(createdAfterUnixMilliseconds: 11)),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(createdBeforeUnixMilliseconds: 21)),
            makeBridgeReviewConstructionKey(
                provenance: makeBridgeReviewProvenanceFilterKey(sourceKinds: ["gitStatus"])),
            makeBridgeReviewConstructionKey(
                checkpoint: .init(
                    kind: .manual, contentIdentity: "checkpoint-a", eventSequenceBounds: 1...2,
                    batchSequenceBounds: 3...4)),
            makeBridgeReviewConstructionKey(
                checkpoint: .init(
                    kind: .session, contentIdentity: "checkpoint-b", eventSequenceBounds: 1...2,
                    batchSequenceBounds: 3...4)),
            makeBridgeReviewConstructionKey(
                checkpoint: .init(
                    kind: .session, contentIdentity: "checkpoint-a", eventSequenceBounds: 1...3,
                    batchSequenceBounds: 3...4)),
            makeBridgeReviewConstructionKey(
                checkpoint: .init(
                    kind: .session, contentIdentity: "checkpoint-a", eventSequenceBounds: 1...2,
                    batchSequenceBounds: 3...5)),
            makeBridgeReviewConstructionKey(checkpoint: nil),
        ]

        // Act
        let keys = Set([base] + variants)

        // Assert
        #expect(keys.count == variants.count + 1)
        #expect(makeBridgeReviewConstructionKey(pathScope: ["Sources", "Sources"]) == base)
    }
}
