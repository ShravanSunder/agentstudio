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
        let repoURL = try await FilesystemTestGitRepo.create(named: "bridge-product-empty-review-webkit")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "tracked\n".write(
            to: repoURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try await FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Initial commit"])
        let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
        let controller = makeController(repoURL: repoURL, traceRecorder: traceRecorder)

        // Act
        let run = try await BridgeProductWebKitCarrierTestSupport.withHostedController(
            controller
        ) { hostedController in
            hostedController.loadApp()
            await WebPageEventWaits.waitForNavigationToFinish(hostedController.page)
            try await WebPageEventWaits.waitForDocumentSelector(
                hostedController.page,
                "[data-testid=\"bridge-viewer-context-review\"]"
            )
            let didActivateReview =
                (try? await hostedController.page.callJavaScript(
                    """
                    const button = document.querySelector('[data-testid="bridge-viewer-context-review"]');
                    if (!(button instanceof HTMLElement)) return false;
                    button.click();
                    return true;
                    """
                ) as? Bool) == true

            // Each DOM step waits on the mutation that produces it. A deadline here
            // would be a verdict about machine speed: the hosted page is hidden, so
            // nothing it renders has a sound upper bound.
            try await WebPageEventWaits.waitForDocumentSelector(
                hostedController.page,
                "[data-testid=\"bridge-viewer-mode-host-review\"]"
            )
            let didMountReviewMode = didActivateReview

            // Wait for the empty canvas to exist, then read its copy ONCE. The
            // barrier is the element's arrival; the text is the claim.
            try await WebPageEventWaits.waitForDocumentSelector(
                hostedController.page,
                bridgeReviewShellSelector
            )
            try await WebPageEventWaits.waitForDocumentSelector(
                hostedController.page,
                "[data-testid=\"bridge-review-empty-canvas\"]"
            )
            let package = try hostedController.ipcReviewPackageSnapshot()
            let didLoadEmptyPackage = package.status == "ready" && package.items.isEmpty
            let didRenderEmptyShell =
                (try? await hostedController.page.callJavaScript(
                    """
                    return document.querySelector(
                      '[data-testid="bridge-review-empty-canvas"]'
                    )?.textContent === 'Nothing to review';
                    """
                ) as? Bool) == true
            return (didLoadEmptyPackage && didMountReviewMode, didRenderEmptyShell)
        }

        // Assert
        #expect(run.value.0)
        #expect(run.value.1)
        #expect(run.teardownSnapshot.hasZeroResidue)
    }
}
