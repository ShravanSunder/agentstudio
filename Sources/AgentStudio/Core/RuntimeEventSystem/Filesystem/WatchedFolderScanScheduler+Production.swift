import Foundation

extension WatchedFolderScanScheduler {
    static func production() -> WatchedFolderScanScheduler {
        let validationExecutor: RepoScannerValidationExecutor
        do {
            validationExecutor = try RepoScannerValidationExecutor(
                validationClient: RepoScannerGitDiscoveryClient()
            )
        } catch {
            preconditionFailure("Invalid production repo validation policy: \(error)")
        }

        do {
            return try WatchedFolderScanScheduler(
                maximumConcurrentScans:
                    AppPolicies.WatchedFolderScanning.maximumConcurrentTraversalQuanta,
                now: RepoDiscoveryValidationClock.productionNow(),
                validationExecutor: validationExecutor,
                sessionFactory: { request, _ in
                    let session = RepoScanner().makeSession(
                        in: URL(
                            fileURLWithPath:
                                request.canonicalRoot.aliases.onceResolvedCanonical.path
                        )
                    )
                    return WatchedFolderScannerSessionPort(
                        id: session.id,
                        advanceOneQuantum: session.advanceOneQuantum,
                        cancel: session.cancel,
                        consumeValidationCompletion: session.consumeValidationCompletion
                    )
                }
            )
        } catch {
            preconditionFailure("Invalid production watched-folder scheduler policy: \(error)")
        }
    }
}
