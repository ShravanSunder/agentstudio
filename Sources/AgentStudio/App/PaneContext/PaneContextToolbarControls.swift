import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AgentStudioSharedComponents
import SwiftUI

struct PaneContextToolbarControls: View {
    struct RefreshInput: Equatable {
        let display: PaneContextDisplay?
        let isDrawer: Bool
        let isVisible: Bool
    }
    let paneId: PaneId
    let readers: PaneContextUIReaders
    let octiconLoader: OcticonLoader
    let onGoToPane: @MainActor (UUID) -> Void
    @Environment(\.paneContextHostVisible) private var isHostVisible
    @State private var messageChip: PaneMessageChipModel?

    var body: some View {
        let display = readers.contextDisplayForPane(paneId)
        let input = RefreshInput(display: display, isDrawer: readers.isDrawerPane(paneId), isVisible: isHostVisible)
        Group {
            if let display, let messageChip {
                PaneContextPopoverHost(
                    paneId: paneId, presentation: .messages(messageChip), location: .pane, readers: readers,
                    octiconLoader: octiconLoader, onGoToPane: onGoToPane,
                    autoOpenAskId: input.isDrawer
                        ? display.own.newestOpenBlockingAskId : display.includingDrawers.newestOpenBlockingAskId,
                    isHostVisible: isHostVisible)
            }
        }
        .task(id: input) {
            let shaped = await Self.shapeMessages(display: input.display, isDrawer: input.isDrawer)
            guard !Task.isCancelled else { return }
            messageChip = shaped
        }
    }

    @concurrent nonisolated static func shapeMessages(display: PaneContextDisplay?, isDrawer: Bool) async
        -> PaneMessageChipModel?
    {
        display.map { RepoExplorerPaneMessageCountProjection.make(display: $0, isDrawer: isDrawer) }
    }
}
