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
            fixture.controller.router.onResponse = { responseJSON in
                await eventCapture.recordResponse()
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )

            await fixture.controller.handleIncomingRPC(
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
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
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
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
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
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
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
            fixture.controller.router.onResponse = { responseJSON in
                await responseCapture.set(responseJSON)
            }
            await fixture.controller.handleIncomingRPC(
                #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
            )
            await fixture.controller.handleIncomingRPC(
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
            let treePaths = try await allTreePaths(from: eventCapture)
            #expect(treePaths.contains("Parent.swift"))
            #expect(treePaths.contains("vendor"))
            #expect(treePaths.contains("vendor/child"))
            #expect(!treePaths.contains("vendor/child/Child.swift"))

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
