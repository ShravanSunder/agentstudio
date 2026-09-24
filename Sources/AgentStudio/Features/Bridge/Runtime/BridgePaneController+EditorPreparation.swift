import AgentStudioInfrastructure
import Foundation

/// Outcome of the native navigation barrier that makes every active annotation
/// editor on the page durable (`draft.flush`) before content leaves the page or
/// a source is replaced.
package enum BridgeEditorPreparationOutcome: Equatable, Sendable {
    /// Every active editor acknowledged its flush.
    case prepared
    /// The page has not completed its bridge handshake (or has no product
    /// session), so no page editor can hold unflushed text.
    case noLivePage
    /// A flush failed, the page did not answer this request, or the page
    /// session changed while waiting. The old content stays usable.
    case failed

    package var allowsContentToLeave: Bool {
        self != .failed
    }
}

private struct BridgeEditorPreparationProbe: Decodable {
    let requestId: String
    let status: String
}

@MainActor
extension BridgePaneController {
    /// Ask the page to flush its active editors and await the answer in the
    /// same page call, so the answer is bound to this request on this page.
    /// The answer only counts while the same pane session and worker instance
    /// stay installed; cancellation never authorizes content to leave.
    package func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome {
        guard isBridgeReady, let bootstrapBefore = await productSessionOwner.activeBootstrap() else {
            return .noLivePage
        }
        let requestId = UUIDv7.generate().uuidString
        let result: Any?
        do {
            result = try await page.callJavaScript(
                Self.editorPreparationJavaScript(requestId: requestId),
                contentWorld: .page
            )
        } catch {
            return .failed
        }
        guard !Task.isCancelled, isBridgeReady,
            let bootstrapAfter = await productSessionOwner.activeBootstrap(),
            bootstrapAfter.paneSessionId == bootstrapBefore.paneSessionId,
            bootstrapAfter.workerInstanceId == bootstrapBefore.workerInstanceId,
            let json = result as? String,
            let data = json.data(using: .utf8),
            let probe = try? JSONDecoder().decode(BridgeEditorPreparationProbe.self, from: data),
            probe.requestId == requestId
        else {
            return .failed
        }
        return probe.status == "prepared" ? .prepared : .failed
    }

    /// The request id is a UUID string, so it is embedded as a plain literal.
    nonisolated static func editorPreparationJavaScript(requestId: String) -> String {
        """
        window.bridgeEditorPreparationProbe = undefined;
        window.dispatchEvent(new CustomEvent('__bridge_editor_preparation', {
          detail: { requestId: '\(requestId)' }
        }));
        const pendingPreparation = window.bridgeEditorPreparationProbe;
        window.bridgeEditorPreparationProbe = undefined;
        if (!pendingPreparation) {
          return JSON.stringify({ requestId: '\(requestId)', status: 'missing_page_handler' });
        }
        return JSON.stringify(await pendingPreparation);
        """
    }
}
