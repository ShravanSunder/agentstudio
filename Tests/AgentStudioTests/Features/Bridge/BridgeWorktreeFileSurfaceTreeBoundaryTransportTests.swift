import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeWorktreeFileTreeBoundaryTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("root scoped open source bounds initial tree metadata window and skips gitignored dependency directories")
        func rootScopedOpenSourceBoundsInitialTreeMetadataWindowAndSkipsDependencyDirectories() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-window-bound-policy")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let sourcesURL = repoURL.appending(path: "Sources")
            let nodeModulesURL =
                repoURL
                .appending(path: "BridgeWeb")
                .appending(path: "node_modules")
                .appending(path: "package")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
            try "node_modules/\n".write(
                to: repoURL.appending(path: ".gitignore"),
                atomically: true,
                encoding: .utf8
            )
            for index in 0..<260 {
                let fileName = String(format: "File%03d.swift", index)
                try "struct File\(index) {}\n".write(
                    to: sourcesURL.appending(path: fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try "ignored dependency\n".write(
                to: nodeModulesURL.appending(path: "index.js"),
                atomically: true,
                encoding: .utf8
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-bounded-root-descriptors",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-bounded-root-descriptors",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(!intakeFrames.isEmpty)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                intakeFrames[0],
                as: BridgeWorktreeSnapshotFrame.self
            )
            #expect(
                snapshotEnvelope.payload.treeRows.count
                    == AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            )
            #expect(
                snapshotEnvelope.payload.treeRows.allSatisfy { row in
                    !row.path.contains("node_modules")
                }
            )
            fixture.controller.teardown()
        }

        @Test("root scoped open source publishes non-ignored dotfiles under git-truth policy")
        func rootScopedOpenSourcePublishesNonIgnoredDotfilesUnderGitTruthPolicy() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-git-truth-policy")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let workflowsURL = repoURL.appending(path: ".github").appending(path: "workflows")
            let nodeModulesURL = repoURL.appending(path: "node_modules").appending(path: "package")
            let sourcesURL = repoURL.appending(path: "Sources")
            try FileManager.default.createDirectory(at: workflowsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try "node_modules/\nignored/\n".write(
                to: repoURL.appending(path: ".gitignore"),
                atomically: true,
                encoding: .utf8
            )
            try "name: ci\n".write(
                to: workflowsURL.appending(path: "ci.yml"),
                atomically: true,
                encoding: .utf8
            )
            try "console.log('dep')\n".write(
                to: nodeModulesURL.appending(path: "index.js"),
                atomically: true,
                encoding: .utf8
            )
            try "struct Visible {}\n".write(
                to: sourcesURL.appending(path: "Visible.swift"),
                atomically: true,
                encoding: .utf8
            )
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-git-truth-policy-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-git-truth-policy-root",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let treePaths = try await allTreePaths(from: eventCapture)
            #expect(treePaths.contains(".github"))
            #expect(treePaths.contains(".github/workflows"))
            #expect(treePaths.contains(".github/workflows/ci.yml"))
            #expect(treePaths.contains(".gitignore"))
            #expect(treePaths.contains("Sources/Visible.swift"))
            #expect(!treePaths.contains("node_modules"))
            #expect(!treePaths.contains("node_modules/package/index.js"))
            #expect(!treePaths.contains(".git"))
            #expect(treePaths.allSatisfy { !$0.hasPrefix(".git/") })

            fixture.controller.teardown()
        }

        @Test("root scoped open source excludes gitignored file tree rows")
        func rootScopedOpenSourceExcludesGitignoredFileTreeRows() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-ignore-policy")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            let ignoredURL = repoURL.appending(path: "ignored")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)
            try "ignored/\n*.log\n".write(
                to: repoURL.appending(path: ".gitignore"),
                atomically: true,
                encoding: .utf8
            )
            try "struct Visible {}\n".write(
                to: sourcesURL.appending(path: "Visible.swift"),
                atomically: true,
                encoding: .utf8
            )
            try "struct Hidden {}\n".write(
                to: ignoredURL.appending(path: "Hidden.swift"),
                atomically: true,
                encoding: .utf8
            )
            try "ignored log\n".write(
                to: repoURL.appending(path: "debug.log"),
                atomically: true,
                encoding: .utf8
            )
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-gitignore-filtered-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-gitignore-filtered-root",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let snapshotJSON = try #require(await eventCapture.intakeFrames().first)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                snapshotJSON,
                as: BridgeWorktreeSnapshotFrame.self
            )
            let treePaths = Set(snapshotEnvelope.payload.treeRows.map(\.path))
            #expect(treePaths.contains("Sources"))
            #expect(treePaths.contains("Sources/Visible.swift"))
            #expect(!treePaths.contains("ignored"))
            #expect(!treePaths.contains("ignored/Hidden.swift"))
            #expect(!treePaths.contains("debug.log"))

            fixture.controller.teardown()
        }

        @Test("root scoped open source streams all continuation rows while excluding gitignored files")
        func rootScopedOpenSourceStreamsAllContinuationRowsWhileExcludingGitignoredFiles() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-continuation-ignore-policy")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            let ignoredURL = repoURL.appending(path: "ignored")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)
            try "ignored/\n*.log\n".write(
                to: repoURL.appending(path: ".gitignore"),
                atomically: true,
                encoding: .utf8
            )
            for index in 0..<260 {
                let fileName = String(format: "Visible%03d.swift", index)
                try "struct Visible\(index) {}\n".write(
                    to: sourcesURL.appending(path: fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }
            for index in 0..<12 {
                let fileName = String(format: "Ignored%03d.swift", index)
                try "struct Ignored\(index) {}\n".write(
                    to: ignoredURL.appending(path: fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try "ignored log\n".write(
                to: repoURL.appending(path: "debug.log"),
                atomically: true,
                encoding: .utf8
            )
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-continuation-gitignore-filtered-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-continuation-gitignore-filtered-root",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let intakeFrames = await eventCapture.intakeFrames()
            #expect(intakeFrames.count == 2)
            let snapshotEnvelope = try decodeIntakeEnvelope(
                try #require(intakeFrames.first),
                as: BridgeWorktreeSnapshotFrame.self
            )
            let continuationEnvelope = try decodeIntakeEnvelope(
                try #require(intakeFrames.last),
                as: BridgeWorktreeTreeWindowFrame.self
            )
            // Published rows: .gitignore + Sources + 260 files = 262 under
            // git-truth publication policy.
            let windowLimit = AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit
            let expectedPublishedRowCount = 262
            #expect(snapshotEnvelope.payload.treeRows.count == windowLimit)
            #expect(continuationEnvelope.payload.frameKind == "worktree.treeWindow")
            #expect(continuationEnvelope.payload.treeSizeFacts.windowStartIndex == windowLimit)
            #expect(continuationEnvelope.payload.rows.count == expectedPublishedRowCount - windowLimit)
            #expect(continuationEnvelope.payload.treeSizeFacts.pathCount == expectedPublishedRowCount)

            let treePaths = try await allTreePaths(from: eventCapture)
            #expect(treePaths.count == expectedPublishedRowCount)
            #expect(treePaths.contains(".gitignore"))
            #expect(treePaths.contains("Sources"))
            #expect(treePaths.contains("Sources/Visible000.swift"))
            #expect(treePaths.contains("Sources/Visible259.swift"))
            #expect(!treePaths.contains("ignored"))
            #expect(!treePaths.contains("ignored/Ignored000.swift"))
            #expect(!treePaths.contains("debug.log"))

            fixture.controller.teardown()
        }

        @Test("root scoped open source does not expand submodule worktree internals")
        func rootScopedOpenSourceDoesNotExpandSubmoduleWorktreeInternals() async throws {
            let submoduleURL = try FilesystemTestGitRepo.create(named: "worktree-file-submodule-child")
            defer { FilesystemTestGitRepo.destroy(submoduleURL) }
            try "struct Child {}\n".write(
                to: submoduleURL.appending(path: "Child.swift"),
                atomically: true,
                encoding: .utf8
            )
            try FilesystemTestGitRepo.runGit(at: submoduleURL, args: ["add", "Child.swift"])
            try FilesystemTestGitRepo.runGit(at: submoduleURL, args: ["commit", "-m", "Seed child"])

            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-submodule-parent")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try "struct Parent {}\n".write(
                to: repoURL.appending(path: "Parent.swift"),
                atomically: true,
                encoding: .utf8
            )
            try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "Parent.swift"])
            try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed parent"])
            try FilesystemTestGitRepo.runGit(
                at: repoURL,
                args: ["-c", "protocol.file.allow=always", "submodule", "add", submoduleURL.path, "vendor/child"]
            )
            try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-am", "Add child submodule"])

            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-submodule-parent-root",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-submodule-parent-root",
                        pathScope: []
                    )
                ).jsonString()
            )

            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let treePaths = try await allTreePaths(from: eventCapture)
            #expect(treePaths.contains("Parent.swift"))
            #expect(treePaths.contains("vendor"))
            #expect(treePaths.contains("vendor/child"))
            #expect(!treePaths.contains("vendor/child/Child.swift"))

            fixture.controller.teardown()
        }

        @Test("metadata interest serves from the manifest index without re-enumerating the worktree")
        func metadataInterestServesFromManifestIndexWithoutReEnumeration() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-index-interest")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            for fileIndex in 0..<8 {
                try "struct F\(fileIndex) {}\n".write(
                    to: sourcesURL.appending(path: "F\(fileIndex).swift"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-index-interest",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-index-interest",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            let manifestIndex = try #require(fixture.controller.activeWorktreeFileManifestIndex)
            #expect(await manifestIndex.enumerationCount == 1)
            #expect(await manifestIndex.isEnumerationComplete)
            #expect(await manifestIndex.count == 9)

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let framesBeforeInterest = (await eventCapture.intakeFrames()).count
            for (probeIndex, lane) in ["foreground", "visible", "nearby"].enumerated() {
                await fixture.controller.dispatchIncomingSchemeCommand(
                    """
                    {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["Sources/F\(probeIndex).swift"],"lane":"\(lane)"},"id":"index-interest-\(lane)"}
                    """
                )
            }
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            #expect((await eventCapture.intakeFrames()).count == framesBeforeInterest + 3)
            #expect(await manifestIndex.enumerationCount == 1)
            fixture.controller.teardown()
        }

        @Test("interest for a deleted path emits a removeRows delta instead of a stale upsert")
        func interestForDeletedPathEmitsRemoveRowsDeltaInsteadOfStaleUpsert() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-index-stat-truth")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try "struct Kept {}\n".write(
                to: sourcesURL.appending(path: "Kept.swift"),
                atomically: true,
                encoding: .utf8
            )
            try "struct Doomed {}\n".write(
                to: sourcesURL.appending(path: "Doomed.swift"),
                atomically: true,
                encoding: .utf8
            )
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-index-stat-truth",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-index-stat-truth",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            let deletedPath = "Sources/Doomed.swift"
            try FileManager.default.removeItem(at: repoURL.appending(path: deletedPath))
            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let framesBeforeInterest = (await eventCapture.intakeFrames()).count
            await fixture.controller.dispatchIncomingSchemeCommand(
                """
                {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["\(deletedPath)"],"lane":"visible"},"id":"index-stat-truth-interest"}
                """
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let framesAfterInterest = Array(
                (await eventCapture.intakeFrames()).dropFirst(framesBeforeInterest)
            )
            var sawRemoveRowsDelta = false
            var sawStaleUpsert = false
            for frameJSON in framesAfterInterest {
                let probe = try decodeIntakeEnvelope(
                    frameJSON,
                    as: BridgeWorktreeFileFrameKindProbe.self
                )
                switch probe.payload.frameKind {
                case "worktree.treeDelta":
                    let delta = try decodeIntakeEnvelope(
                        frameJSON,
                        as: BridgeWorktreeTreeDeltaFrame.self
                    )
                    sawRemoveRowsDelta =
                        sawRemoveRowsDelta
                        || delta.payload.operations.contains { operation in
                            if case .removeRows(_, let paths) = operation {
                                return paths?.contains(deletedPath) == true
                            }
                            return false
                        }
                case "worktree.treeWindow":
                    let window = try decodeIntakeEnvelope(
                        frameJSON,
                        as: BridgeWorktreeTreeWindowFrame.self
                    )
                    sawStaleUpsert =
                        sawStaleUpsert
                        || window.payload.rows.contains { $0.path == deletedPath }
                default:
                    continue
                }
            }
            #expect(sawRemoveRowsDelta)
            #expect(!sawStaleUpsert)
            let manifestIndex = try #require(fixture.controller.activeWorktreeFileManifestIndex)
            let membersAfterRemoval = await manifestIndex.memberPaths(of: [deletedPath])
            #expect(membersAfterRemoval.isEmpty)
            fixture.controller.teardown()
        }

        @Test("watch-event changeset patches the manifest index and emits a treeDelta")
        func watchEventChangesetPatchesManifestIndexAndEmitsTreeDelta() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-watch-index-patch")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            try "struct Kept {}\n".write(
                to: sourcesURL.appending(path: "Kept.swift"),
                atomically: true,
                encoding: .utf8
            )
            try "struct Doomed {}\n".write(
                to: sourcesURL.appending(path: "Doomed.swift"),
                atomically: true,
                encoding: .utf8
            )
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-watch-index-patch",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-watch-index-patch",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            let freshPath = "Sources/Fresh.swift"
            let doomedPath = "Sources/Doomed.swift"
            try "struct Fresh {}\n".write(
                to: repoURL.appending(path: freshPath),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.removeItem(at: repoURL.appending(path: doomedPath))
            try await fixture.controller.publishWorktreeFileSurfaceChangeset(
                FileChangeset(
                    worktreeId: fixture.worktreeId,
                    rootPath: repoURL,
                    paths: [freshPath, doomedPath],
                    timestamp: .now,
                    batchSeq: 7
                )
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            var sawFreshUpsert = false
            var sawDoomedRemoval = false
            for frameJSON in await eventCapture.intakeFrames() {
                guard
                    let probe = try? decodeIntakeEnvelope(
                        frameJSON,
                        as: BridgeWorktreeFileFrameKindProbe.self
                    ),
                    probe.payload.frameKind == "worktree.treeDelta"
                else { continue }
                let delta = try decodeIntakeEnvelope(frameJSON, as: BridgeWorktreeTreeDeltaFrame.self)
                for operation in delta.payload.operations {
                    switch operation {
                    case .upsertRows(let rows):
                        sawFreshUpsert = sawFreshUpsert || rows.contains { $0.path == freshPath }
                    case .removeRows(_, let paths):
                        sawDoomedRemoval = sawDoomedRemoval || paths?.contains(doomedPath) == true
                    }
                }
            }
            #expect(sawFreshUpsert)
            #expect(sawDoomedRemoval)
            let manifestIndex = try #require(fixture.controller.activeWorktreeFileManifestIndex)
            #expect(await manifestIndex.memberPaths(of: [freshPath]) == [freshPath])
            #expect(await manifestIndex.memberPaths(of: [doomedPath]).isEmpty)
            fixture.controller.teardown()
        }

        @Test("delivered intake frame sequences are never descending")
        func deliveredIntakeFrameSequencesAreNeverDescending() async throws {
            let repoURL = try FilesystemTestGitRepo.create(named: "worktree-file-sequence-order")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let sourcesURL = repoURL.appending(path: "Sources")
            try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
            for fileIndex in 0..<260 {
                try "struct S\(fileIndex) {}\n".write(
                    to: sourcesURL.appending(path: String(format: "S%03d.swift", fileIndex)),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let eventCapture = BridgeWorktreeFileSurfaceEventCapture()
            let fixture = try makeControllerFixtureWithIntakeSink(
                rootURL: repoURL,
                intakeFrameSink: { _, frameJSON, _ in
                    await eventCapture.recordIntake(frameJSON)
                }
            )
            let responseCapture = BridgeWorktreeFileSurfaceResponseCapture()
            fixture.controller.schemeCommandDispatcher.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.dispatchIncomingSchemeCommand(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.dispatchIncomingSchemeCommand(
                try BridgeWorktreeFileSurfaceRPCRequest(
                    id: "open-sequence-order",
                    method: "worktreeFileSurface.openSourceStream",
                    params: sourceSpec(
                        fixture: fixture,
                        clientRequestId: "request-sequence-order",
                        pathScope: []
                    )
                ).jsonString()
            )
            let response = try await decodedResponse(from: responseCapture)
            await fixture.controller.activeWorktreeFileTreeWindowTask?.value

            // Pre-ready interest: reserved after the buffered continuation
            // window (higher sequence), reprioritized ahead of it. Delivery
            // order must still be sequence order for the strict monotonic
            // browser receiver.
            await fixture.controller.dispatchIncomingSchemeCommand(
                """
                {"jsonrpc":"2.0","method":"bridge.metadata_interest.update","params":{"protocol":"worktree-file","streamId":"\(response.result.streamId)","generation":\(response.result.generation),"paths":["Sources/S000.swift"],"lane":"visible"},"id":"sequence-order-interest"}
                """
            )
            await fixture.controller.handleBridgeIntakeReady(
                BridgeIntakeReadyMethod.Params(protocolId: "worktree-file", streamId: response.result.streamId)
            )

            await fixture.controller.worktreeFileMetadataScheduler.waitUntilDrained()
            let deliveredSequences = try await eventCapture.intakeFrames().map { frameJSON in
                try decodeIntakeEnvelope(frameJSON, as: BridgeWorktreeFileFrameKindProbe.self).sequence
            }
            #expect(deliveredSequences.count >= 3)
            #expect(deliveredSequences == deliveredSequences.sorted())
            fixture.controller.teardown()
        }

        private func allTreePaths(
            from eventCapture: BridgeWorktreeFileSurfaceEventCapture
        ) async throws -> Set<String> {
            var paths = Set<String>()
            for intakeFrame in await eventCapture.intakeFrames() {
                let frameKindProbe = try decodeIntakeEnvelope(
                    intakeFrame,
                    as: BridgeWorktreeFileFrameKindProbe.self
                )
                switch frameKindProbe.payload.frameKind {
                case "worktree.snapshot":
                    let snapshot = try decodeIntakeEnvelope(
                        intakeFrame,
                        as: BridgeWorktreeSnapshotFrame.self
                    )
                    paths.formUnion(snapshot.payload.treeRows.map(\.path))
                case "worktree.treeWindow":
                    let window = try decodeIntakeEnvelope(
                        intakeFrame,
                        as: BridgeWorktreeTreeWindowFrame.self
                    )
                    paths.formUnion(window.payload.rows.map(\.path))
                default:
                    continue
                }
            }
            return paths
        }
    }
}

private struct BridgeWorktreeFileFrameKindProbe: Decodable {
    let frameKind: String
}
