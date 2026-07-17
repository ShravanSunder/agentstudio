import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Integration tests for the current Bridge product-session path.
///
/// These tests cover bootstrap readiness, packaged app loading, and native
/// Review sources flowing through the pane's product streams into the React UI.
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeTransportIntegrationTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test
        func test_bridgeReady_gatesAndIsIdempotent() async {
            // Arrange
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                initialPaneActivity: .foreground
            )

            // Act / Assert
            #expect(!controller.isBridgeReady)
            #expect(controller.handleBridgeReady())
            #expect(controller.isBridgeReady)
            #expect(!controller.handleBridgeReady())
            #expect(controller.isBridgeReady)

            await teardownBridgeControllerForTest(controller)
        }

        @Test
        func test_teardown_resetsBridgeReady() async {
            // Arrange
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                initialPaneActivity: .foreground
            )
            #expect(controller.handleBridgeReady())

            // Act
            controller.teardown()

            // Assert
            #expect(!controller.isBridgeReady)
            await WebPageTestHarness.settle()
        }

        @Test
        func test_schemeHandler_servesPackagedReactApp() async throws {
            // Arrange
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                initialPaneActivity: .foreground
            )

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                // Act
                controller.loadApp()
                let didNavigateToAppURL = await waitUntil {
                    page.url?.absoluteString == "agentstudio://app/index.html"
                }
                try await waitForPageLoad(page)
                let didResolveTitle = await waitForTitle(page, equals: "AgentStudio Bridge")
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }

                // Assert
                #expect(didNavigateToAppURL)
                #expect(didResolveTitle)
                #expect(didCompleteBridgeReadyHandshake)

                _ = try await page.callJavaScript(
                    """
                    document.title = document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null
                      ? 'AgentStudio Bridge Visible'
                      : 'AgentStudio Bridge Missing Shell'
                    """
                )
                #expect(await waitForTitle(page, equals: "AgentStudio Bridge Visible"))
            }

            await teardownBridgeControllerForTest(controller)
        }

        @Test
        func test_handleDiffCommandWithSmokeProvider_rendersReviewViewerShell() async throws {
            // Arrange
            let paneId = UUIDv7.generate()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                reviewSourceProvider: BridgeObservabilitySmokeReviewSourceProvider(),
                initialPaneActivity: .foreground
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)
                #expect(await waitUntil { controller.isBridgeReady })
                try await installPageErrorProbe(page)

                // Act
                let commandResult = await controller.handleDiffCommand(
                    .loadDiff(
                        DiffArtifact(
                            diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                            worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                            patchData: Data()
                        )
                    ),
                    commandId: UUIDv7.generate(),
                    correlationId: nil
                )

                // Assert
                guard case .success = commandResult else {
                    Issue.record("Expected smoke provider diff command to succeed")
                    return
                }
                #expect(
                    await waitUntil(timeout: .seconds(1)) {
                        (try? await controller.renderStateForIPC().summary.hasReviewShell) == true
                    }
                )
                let renderState = try await controller.renderStateForIPC()
                #expect(renderState.summary.hasReviewShell)
                #expect(!renderState.summary.hasEmptyShell)
                #expect(renderState.diagnostics.evaluateSucceeded)
                #expect(renderState.diagnostics.pageErrorCount == 0)
                #expect(await pageErrorProbeDescription(page) == "[]")
            }
        }

        @Test
        func test_sourceBackedInitialReviewLoad_rendersReviewViewerShell() async throws {
            // Arrange
            let paneId = UUIDv7.generate()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: paneId),
                    contentType: .diff,
                    launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
                    title: "Bridge Review",
                    facets: PaneContextFacets(
                        repoId: BridgeObservabilitySmokeReviewSourceProvider.repoId,
                        worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                        cwd: URL(fileURLWithPath: "/tmp/worktree")
                    )
                ),
                reviewSourceProvider: BridgeObservabilitySmokeReviewSourceProvider(),
                initialPaneActivity: .foreground
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)
                #expect(await waitUntil { controller.isBridgeReady })
                try await installPageErrorProbe(page)

                // Act / Assert
                #expect(
                    await waitUntil(timeout: .seconds(1)) {
                        (try? await controller.renderStateForIPC().summary.hasReviewShell) == true
                    }
                )
                let renderState = try await controller.renderStateForIPC()
                #expect(renderState.summary.hasReviewShell)
                #expect(!renderState.summary.hasEmptyShell)
                #expect(renderState.diagnostics.evaluateSucceeded)
                #expect(renderState.diagnostics.pageErrorCount == 0)
                #expect(await pageErrorProbeDescription(page) == "[]")
            }
        }
    }
}

@MainActor
private func waitForTitle(
    _ page: WebPage,
    equals expectedTitle: String,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if page.title == expectedTitle {
            return true
        }
        await Task.yield()
    }
    return page.title == expectedTitle
}

@MainActor
private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if !page.isLoading {
            break
        }
        await Task.yield()
    }
    try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
    for _ in 0..<40 {
        await Task.yield()
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

@MainActor
private func installPageErrorProbe(_ page: WebPage) async throws {
    _ = try await page.callJavaScript(
        """
        window.__bridgeErrorProbe = [];
        window.addEventListener('error', function(event) {
          window.__bridgeErrorProbe.push({
            kind: 'error',
            message: String(event.message)
          });
        });
        window.addEventListener('unhandledrejection', function(event) {
          window.__bridgeErrorProbe.push({
            kind: 'unhandledrejection',
            message: String(event.reason?.message || event.reason)
          });
        });
        """
    )
}

@MainActor
private func pageErrorProbeDescription(_ page: WebPage) async -> String {
    do {
        let result = try await page.callJavaScript(
            """
            return JSON.stringify(window.__bridgeErrorProbe ?? [])
            """
        )
        return (result as? String) ?? String(describing: result)
    } catch {
        return String(describing: error)
    }
}

@MainActor
private func teardownBridgeControllerForTest(_ controller: BridgePaneController) async {
    controller.teardown()
    await WebPageTestHarness.settle()
}
