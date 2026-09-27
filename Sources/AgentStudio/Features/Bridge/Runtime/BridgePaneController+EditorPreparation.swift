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
    /// The page explicitly kept its draft. The old content stays usable.
    case refused
    /// The page explicitly reported a failed save. The old content stays usable.
    case saveFailed
    /// The save result could not be established. The old content stays usable.
    case saveOutcomeUnknown

    package var allowsContentToLeave: Bool {
        switch self {
        case .prepared, .noLivePage: true
        case .refused, .saveFailed, .saveOutcomeUnknown: false
        }
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
            return .saveOutcomeUnknown
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
            return .saveOutcomeUnknown
        }
        // The current page collapses every unsuccessful flush into `failed`.
        // Until PR1 gives native a precise page result, failure remains unknown.
        return probe.status == "prepared" ? .prepared : .saveOutcomeUnknown
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
