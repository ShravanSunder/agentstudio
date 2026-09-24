import AgentStudioInfrastructure
import Foundation

@MainActor
extension BridgePaneController {
    /// Search this pane's Files collection in its comm worker and resolve every
    /// match back through the collection that listed it.
    package func searchFilesCollection(_ criteria: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome {
        guard isBridgeReady, let fileCollectionSource,
            let bootstrapBefore = await productSessionOwner.activeBootstrap()
        else {
            return .unavailable(.noLivePage)
        }
        // A membership update still being delivered changes what can match.
        await filesSourceUpdateTail?.value
        let exchange = BridgeFilesSearchExchange(
            source: fileCollectionSource,
            callPage: { [page] script in
                try await page.callJavaScript(script, contentWorld: .page)
            },
            pageSessionIsUnchanged: { [weak self] in
                guard let self, self.isBridgeReady,
                    let bootstrapAfter = await self.productSessionOwner.activeBootstrap()
                else { return false }
                return bootstrapAfter.paneSessionId == bootstrapBefore.paneSessionId
                    && bootstrapAfter.workerInstanceId == bootstrapBefore.workerInstanceId
            }
        )
        return await exchange.run(criteria, requestId: UUIDv7.generate().uuidString)
    }
}
