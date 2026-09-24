import AgentStudioBridge
import AgentStudioCore
import Foundation

/// The mounted controller surface the navigation handler drives for one
/// receiver: the editor barrier, exact File activation, collection search and
/// surface requests.
@MainActor
protocol BridgeReceiverPresentation: AnyObject {
    func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome
    func activateFileDocument(_ location: BridgeDocumentLocation) async -> BridgeFileActivationArrival
    func searchFilesCollection(_ criteria: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome
    @discardableResult
    func requestViewerSurface(_ surface: BridgeProductSurface) -> Bool
}

extension BridgePaneController: BridgeReceiverPresentation {}

/// App composition the navigation handler needs to reach mounted Bridges and
/// persistence. The handler never looks controllers up by focus.
@MainActor
struct BridgeReceiverPresentationPorts {
    /// The receiver's mounted controller: its companion for a terminal
    /// receiver, the pane's own controller for a standalone Bridge.
    let mountedPresentation: (BridgeReceiver) -> (any BridgeReceiverPresentation)?
    /// Replace the receiver's controller after its Review input changed and
    /// request `surface` on the replacement. False when nothing is mounted to
    /// replace.
    let replaceReviewSource: (BridgeReceiver, BridgeProductSurface) -> Bool
    /// The member the receiver's owner terminal currently sits in, which is
    /// protected from removal; nil for standalone Bridges and unknown CWDs.
    let knownCWDWorktreeId: (BridgeReceiver) -> UUID?
    /// Push the receiver's current Files input to its mounted collection.
    let refreshFilesSource: (BridgeReceiver) -> Void
    /// Persist accepted navigation through the workspace save path; false when
    /// the save failed.
    let persistNavigation: () async -> Bool
}
