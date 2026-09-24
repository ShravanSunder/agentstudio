import AgentStudioCore
import Foundation

/// A File selection the page displayed, mapped back through the collection it
/// was issued from. The location is the admitted canonical document; member
/// files also carry their member-relative path.
package struct BridgeFilesDisplayedSelection: Equatable, Sendable {
    package let location: BridgeDocumentLocation
    package let memberWorktreeId: UUID?
    package let memberRelativePath: String?
}

/// How one native Files activation ended at the page.
package enum BridgeFileActivationArrival: Equatable, Sendable {
    /// The page displayed the document.
    case displayed
    /// The page selected the document but cannot render it.
    case unavailable
    /// An active editor could not be flushed, so the old document stays.
    case refused
    /// A newer selection replaced this one before it arrived.
    case superseded
    /// The Files collection does not list the document.
    case notListed
    /// No live page or Files source, or the controller retired.
    case cancelled
}

struct BridgePendingFileActivation {
    let commandId: String
    let continuation: CheckedContinuation<BridgeFileActivationArrival, Never>
}

@MainActor
extension BridgePaneController {
    /// Ask the page to display `location` in Files and wait for its
    /// generation-matched displayed receipt. The page gates the selection
    /// behind its active editors, so a refused flush keeps the old document.
    /// A newer activation or a human selection supersedes this one.
    package func activateFileDocument(_ location: BridgeDocumentLocation) async -> BridgeFileActivationArrival {
        guard let fileCollectionSource else { return .notListed }
        // A membership update still being delivered may add the document's tree.
        await filesSourceUpdateTail?.value
        guard let displayPath = await fileCollectionSource.displayPath(for: location),
            await fileCollectionSource.listing(displayPath: displayPath) != .notListed
        else {
            return .notListed
        }
        guard let productSchemeProvider,
            let source = await fileCollectionSource.currentNavigationSource(),
            let productAdmission = productAdmissionGate.acquire()
        else {
            return .cancelled
        }
        let target = BridgeProductNavigationFileTarget(path: displayPath, version: .current)
        guard
            let commandId = productAdmission.withValidAdmission({
                surfaceSelectionAuthority.retainFileTarget(source: source, target: target)
            })
        else {
            return .cancelled
        }
        return await withCheckedContinuation { continuation in
            settlePendingFileActivation(.superseded)
            pendingFileActivation = BridgePendingFileActivation(
                commandId: commandId,
                continuation: continuation
            )
            let precedingTransition = surfaceSelectionTransitionTail
            let transition = Task { @MainActor [weak self] in
                if let precedingTransition {
                    _ = await precedingTransition.value
                }
                guard let self else { return false }
                let published = await self.bindAndPublishRetainedSurfaceSelection(
                    commandId: commandId,
                    productAdmission: productAdmission,
                    productSchemeProvider: productSchemeProvider
                )
                if !published, self.pendingFileActivation?.commandId == commandId {
                    self.settlePendingFileActivation(.cancelled)
                }
                return published
            }
            surfaceSelectionTransitionTail = transition
        }
    }

    /// Settle the waiting activation, if any, exactly once.
    func settlePendingFileActivation(_ arrival: BridgeFileActivationArrival) {
        guard let pending = pendingFileActivation else { return }
        pendingFileActivation = nil
        pending.continuation.resume(returning: arrival)
    }

    /// A displayed-selection receipt from the page. Receipts from an older
    /// collection source, or naming keys the collection never issued, are
    /// ignored. A receipt for another native command than the waiting one is
    /// stale; a receipt with no command is a human selection and supersedes a
    /// waiting activation.
    func handleCommittedFileSelectionReceipt(
        _ receipt: BridgeProductFileSelectionReceiptRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard (productAdmission.withValidAdmission { true }) == true, let fileCollectionSource else {
            return
        }
        let document = await fileCollectionSource.displayedDocument(
            displayPath: receipt.displayPath,
            sourceId: receipt.source.sourceId,
            subscriptionGeneration: receipt.source.subscriptionGeneration
        )
        guard (productAdmission.withValidAdmission { true }) == true else { return }

        if let commandId = receipt.nativeNavigationCommandId {
            guard pendingFileActivation?.commandId == commandId else { return }
            guard let document else {
                settlePendingFileActivation(.cancelled)
                return
            }
            switch receipt.outcome {
            case .displayed:
                publishDisplayedFilesSelection(document)
                settlePendingFileActivation(.displayed)
            case .unavailable:
                settlePendingFileActivation(.unavailable)
            case .refused:
                settlePendingFileActivation(.refused)
            case .notListed:
                settlePendingFileActivation(.notListed)
            }
            return
        }

        guard receipt.outcome == .displayed, let document else { return }
        settlePendingFileActivation(.superseded)
        publishDisplayedFilesSelection(document)
    }

    private func publishDisplayedFilesSelection(_ document: BridgeFileCollectionDisplayedDocument) {
        let selection: BridgeFilesDisplayedSelection
        switch document {
        case .memberFile(let worktreeId, let relativePath, let location):
            selection = BridgeFilesDisplayedSelection(
                location: location,
                memberWorktreeId: worktreeId,
                memberRelativePath: relativePath
            )
        case .openedDocument(let location):
            selection = BridgeFilesDisplayedSelection(
                location: location,
                memberWorktreeId: nil,
                memberRelativePath: nil
            )
        }
        onFilesSelectionDisplayed?(selection)
    }
}
