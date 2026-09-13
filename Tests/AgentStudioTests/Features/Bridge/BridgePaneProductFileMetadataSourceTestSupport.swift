import AgentStudioCore
import Foundation

@testable import AgentStudioBridge

struct ProductFileSourceStatusProvider: GitWorkingTreeStatusProvider {
    func statusResult(
        for _: URL,
        pathspecs _: [String]?
    ) async -> GitWorkingTreeStatusResult {
        .available(
            GitWorkingTreeStatus(
                summary: .init(changed: 1, staged: 2, untracked: 3),
                branch: "main",
                origin: nil
            )
        )
    }
}

enum ProductFileSourceFixtureError: Error {
    case invalidContentRequest
    case invalidControlRequest
    case invalidDemandedIndex
    case missingSubscription
}

struct ProductFileSourceFixture {
    let demandedFileURL: URL
    let demandedPath: String
    let paneId = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    let productAdmission: BridgeProductAdmissionTestContext
    let repoId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let rootURL: URL
    let worktreeId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    init(
        fileCount: Int,
        demandedLineCount: Int = 2,
        demandedIndex: Int = 0,
        productAdmission suppliedProductAdmission: BridgeProductAdmissionTestContext? = nil
    ) throws {
        guard fileCount == 0 || (0..<fileCount).contains(demandedIndex) else {
            throw ProductFileSourceFixtureError.invalidDemandedIndex
        }
        productAdmission = try suppliedProductAdmission ?? BridgeProductAdmissionTestContext.make()
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-product-file-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        demandedPath = String(format: "File-%04d.swift", demandedIndex)
        demandedFileURL = rootURL.appending(path: demandedPath)
        for index in 0..<fileCount {
            let fileURL = rootURL.appending(path: String(format: "File-%04d.swift", index))
            let contents =
                index == demandedIndex
                ? String(repeating: "line\n", count: demandedLineCount)
                : "let value = \(index)\n"
            try Data(contents.utf8).write(to: fileURL)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeSource(
        paneId: UUID? = nil,
        constructionCoordinator: BridgeWorktreeProductConstructionCoordinator? = nil,
        sourceAcceptedObserver: @escaping @Sendable (BridgeProductFileSourceIdentity) async -> Void = { _ in },
        snapshotPreparationLoader: BridgePaneProductFileSnapshotPreparationLoader? = nil,
        sharedSnapshotBuilder: @escaping BridgePaneProductFileSharedSnapshotBuilder =
            BridgeWorktreeFileMaterializer.buildSharedSnapshot,
        ignorePolicyLoader: @escaping BridgePaneProductFileIgnorePolicyLoader = loadTestBridgeFileIgnorePolicy,
        treeRowRefresher: BridgePaneProductFileTreeRowRefresher? = nil,
        descriptorMaterializer: @escaping BridgePaneProductFileDescriptorMaterializer =
            BridgePaneProductFileContentSource.materialize
    ) -> BridgePaneProductFileMetadataSource {
        BridgePaneProductFileMetadataSource(
            authority: .init(
                paneId: paneId ?? self.paneId,
                worktree: Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "fixture",
                    path: rootURL
                )
            ),
            gitReadContext: makeBridgeGitReadContext(rootURL: rootURL),
            constructionCoordinator: constructionCoordinator ?? BridgeWorktreeProductConstructionCoordinator(),
            sourceAcceptedObserver: sourceAcceptedObserver,
            statusProvider: ProductFileSourceStatusProvider(),
            snapshotPreparationLoader: snapshotPreparationLoader,
            sharedSnapshotBuilder: sharedSnapshotBuilder,
            ignorePolicyLoader: ignorePolicyLoader,
            treeRowRefresher: treeRowRefresher,
            descriptorMaterializer: descriptorMaterializer
        )
    }

    func openSnapshot(
        cwdScope: String? = nil,
        subscriptionId: String = "file-subscription-1"
    ) throws -> BridgeProductSubscriptionSnapshot {
        let cwdScopeValue: Any
        if let cwdScope {
            cwdScopeValue = cwdScope
        } else {
            cwdScopeValue = NSNull()
        }
        let request = try controlRequest(
            kind: "subscription.open",
            requestSequence: 2,
            values: [
                "subscription": [
                    "source": [
                        "cwdScope": cwdScopeValue,
                        "freshness": "live",
                        "includeStatuses": true,
                        "repoId": repoId.uuidString,
                        "rootPathToken": StableKey.fromPath(rootURL),
                        "worktreeId": worktreeId.uuidString,
                    ],
                    "subscriptionKind": "file.metadata",
                ],
                "subscriptionId": subscriptionId,
            ]
        )
        guard case .subscriptionOpen(let openRequest) = request else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        var state = BridgeProductSubscriptionState()
        _ = try state.open(openRequest)
        return try requiredSnapshot(from: state, subscriptionId: subscriptionId)
    }

    func updatedSnapshot(
        from openSnapshot: BridgeProductSubscriptionSnapshot,
        visiblePaths: [String] = []
    ) throws -> BridgeProductSubscriptionSnapshot {
        var interests = [
            try BridgeProductFileMetadataInterestStateGroup(
                lane: .foreground,
                paths: [demandedPath]
            )
        ]
        if !visiblePaths.isEmpty {
            interests.append(try .init(lane: .visible, paths: visiblePaths))
        }
        let targetState = BridgeProductSubscriptionInterestState.fileMetadata(
            interests: interests,
            pathScope: []
        )
        let targetSHA256 = try targetState.sha256Hex()
        let request = try controlRequest(
            kind: "subscription.updateBatch",
            requestSequence: 3,
            values: [
                "baseInterestRevision": 0,
                "baseInterestSha256": openSnapshot.interestSha256,
                "batchCount": 1,
                "batchIndex": 0,
                "delta": [
                    "add": [
                        ["lane": "foreground", "path": demandedPath]
                    ] + visiblePaths.map { ["lane": "visible", "path": $0] },
                    "addPathScope": [],
                    "removePathScope": [],
                    "removePaths": [],
                    "subscriptionKind": "file.metadata",
                ],
                "subscriptionId": openSnapshot.subscriptionId,
                "subscriptionKind": "file.metadata",
                "targetInterestRevision": 1,
                "targetInterestSha256": targetSHA256,
                "totalDeltaItemCount": 1 + visiblePaths.count,
                "updateId": "file-update-1",
            ]
        )
        guard case .subscriptionUpdateBatch(let updateRequest) = request else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        var state = BridgeProductSubscriptionState()
        guard
            case .subscriptionOpen(let openRequest) = try controlRequest(
                kind: "subscription.open",
                requestSequence: 2,
                values: [
                    "subscription": openSnapshotSubscriptionObject,
                    "subscriptionId": openSnapshot.subscriptionId,
                ]
            )
        else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        _ = try state.open(openRequest)
        _ = try state.apply(updateRequest)
        return try requiredSnapshot(from: state, subscriptionId: openSnapshot.subscriptionId)
    }

    func contentRequest(
        descriptor: BridgeProductFileContentDescriptor
    ) throws -> BridgeProductFileContentRequest {
        let descriptorObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(descriptor)
        )
        let data = try JSONSerialization.data(
            withJSONObject: [
                "contentKind": "file.content",
                "contentRequestId": "file-content-request-1",
                "descriptor": descriptorObject,
                "kind": "content.open",
                "leaseId": "file-content-lease-1",
                "operationCorrelationId": NSNull(),
                "paneSessionId": "pane-session-1",
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": 1,
                "workerInstanceId": "worker-instance-1",
            ],
            options: [.sortedKeys]
        )
        let request = try BridgeProductStrictJSON.decode(BridgeProductContentRequest.self, from: data)
        guard case .fileContent(let fileRequest) = request else {
            throw ProductFileSourceFixtureError.invalidContentRequest
        }
        return fileRequest
    }

    private var openSnapshotSubscriptionObject: [String: Any] {
        [
            "source": [
                "cwdScope": NSNull(),
                "freshness": "live",
                "includeStatuses": true,
                "repoId": repoId.uuidString,
                "rootPathToken": StableKey.fromPath(rootURL),
                "worktreeId": worktreeId.uuidString,
            ],
            "subscriptionKind": "file.metadata",
        ]
    }

    private func requiredSnapshot(
        from state: BridgeProductSubscriptionState,
        subscriptionId: String
    ) throws -> BridgeProductSubscriptionSnapshot {
        guard let snapshot = state.snapshot(subscriptionId: subscriptionId) else {
            throw ProductFileSourceFixtureError.missingSubscription
        }
        return snapshot
    }

    private func controlRequest(
        kind: String,
        requestSequence: Int,
        values: [String: Any]
    ) throws -> BridgeProductControlRequest {
        let object: [String: Any] = [
            "kind": kind,
            "paneSessionId": "pane-session-1",
            "requestId": "request-\(requestSequence)",
            "requestSequence": requestSequence,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ].merging(values) { _, new in new }
        return try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }
}
