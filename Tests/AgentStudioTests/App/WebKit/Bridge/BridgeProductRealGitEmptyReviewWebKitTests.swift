import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    @Test("clean real-git Review publishes the loaded empty presentation")
    func cleanRealGitReviewPublishesLoadedEmptyPresentation() async throws {
        // Arrange
        let repoURL = try FilesystemTestGitRepo.create(named: "bridge-product-empty-review-webkit")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "tracked\n".write(
            to: repoURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Initial commit"])
        let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
        let controller = makeController(repoURL: repoURL, traceRecorder: traceRecorder)

        // Act
        let run = try await BridgeProductWebKitCarrierTestSupport.withHostedController(
            controller
        ) { hostedController in
            hostedController.loadApp()
            let didLoadEmptyPackage = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                timeout: .seconds(15)
            ) {
                guard let package = try? hostedController.ipcReviewPackageSnapshot() else {
                    return false
                }
                return package.status == "ready" && package.items.isEmpty
            }
            let didActivateReview =
                (try? await hostedController.page.callJavaScript(
                    """
                    const button = document.querySelector('[data-testid="bridge-viewer-context-review"]');
                    if (!(button instanceof HTMLElement)) return false;
                    button.click();
                    return true;
                    """
                ) as? Bool) == true
            let didMountReviewMode = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                timeout: .seconds(10)
            ) {
                guard
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                else {
                    return false
                }
                return didActivateReview && dom.hasReviewModeHost
            }
            let didRenderEmptyShell = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                timeout: .seconds(15)
            ) {
                guard
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                else {
                    return false
                }
                guard didMountReviewMode, dom.hasReviewShell else { return false }
                return
                    (try? await hostedController.page.callJavaScript(
                        "return document.querySelector('[data-testid=\\\"bridge-review-empty-canvas\\\"]')?.textContent === 'Nothing to review'"
                    ) as? Bool) == true
            }
            return (didLoadEmptyPackage && didMountReviewMode, didRenderEmptyShell)
        }

        // Assert
        #expect(run.value.0)
        #expect(run.value.1)
        #expect(run.teardownSnapshot.hasZeroResidue)
    }
}
