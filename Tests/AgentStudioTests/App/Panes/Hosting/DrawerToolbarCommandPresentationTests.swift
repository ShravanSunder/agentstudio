import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("Drawer toolbar command presentation")
struct DrawerToolbarCommandPresentationTests {
    @Test("anchor and location controls request the exact pane toolbar targets")
    func controlsRequestExactPaneToolbarTargets() {
        let anchorPaneId = UUID()
        let locationTargetPaneId = UUID()
        let resolver = RecordingDrawerToolbarActionResolver()

        _ = DrawerToolbarCommandPresentation.resolve(
            anchorPaneId: anchorPaneId,
            locationTargetPaneId: locationTargetPaneId,
            toolbarSurface: .pane,
            actionResolver: resolver.resolve
        )

        #expect(
            resolver.requests == [
                .init(
                    command: .toggleDrawer,
                    surface: .toolbar(.pane),
                    target: anchorPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .addDrawerPane,
                    surface: .toolbar(.pane),
                    target: anchorPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .openPaneLocationInEditorMenu,
                    surface: .toolbar(.pane),
                    target: locationTargetPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .openPaneLocationInFinder,
                    surface: .toolbar(.pane),
                    target: locationTargetPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .copyCurrentPanePath,
                    surface: .toolbar(.pane),
                    target: locationTargetPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .openPullRequest,
                    surface: .toolbar(.pane),
                    target: locationTargetPaneId,
                    targetType: .pane
                ),
                .init(
                    command: .showPaneInboxNotifications,
                    surface: .toolbar(.pane),
                    target: anchorPaneId,
                    targetType: .pane
                ),
            ]
        )
    }

    @Test("Zoom controls request the exact terminal Zoom toolbar surface")
    func controlsRequestExactTerminalZoomToolbarSurface() {
        let resolver = RecordingDrawerToolbarActionResolver()

        _ = DrawerToolbarCommandPresentation.resolve(
            anchorPaneId: UUID(),
            locationTargetPaneId: UUID(),
            toolbarSurface: .terminalZoom,
            actionResolver: resolver.resolve
        )

        #expect(
            resolver.requests.map(\.surface)
                == Array(
                    repeating: .toolbar(.terminalZoom),
                    count: 7
                )
        )
    }

    @Test("unsupported controls are omitted while denied controls stay presented and disabled")
    func omissionAndDisabledStateRemainDistinct() {
        let resolver = RecordingDrawerToolbarActionResolver()
        resolver.omittedCommands = [.addDrawerPane, .openPaneLocationInFinder]
        resolver.disabledCommands = [.toggleDrawer, .copyCurrentPanePath]

        let presentation = DrawerToolbarCommandPresentation.resolve(
            anchorPaneId: UUID(),
            locationTargetPaneId: UUID(),
            toolbarSurface: .pane,
            actionResolver: resolver.resolve
        )

        #expect(presentation.toggleDrawer?.isEnabled == false)
        #expect(presentation.addDrawerPane == nil)
        #expect(presentation.openEditorMenu?.isEnabled == true)
        #expect(presentation.openFinder == nil)
        #expect(presentation.copyPath?.isEnabled == false)
        #expect(presentation.openPullRequest?.isEnabled == true)
        #expect(presentation.showPaneInbox?.isEnabled == true)
    }

    @Test("execution revalidates the exact location pane before targeted dispatch")
    func executionRevalidatesLocationPaneBeforeDispatch() throws {
        let anchorPaneId = UUID()
        let locationTargetPaneId = UUID()
        let dispatcher = RecordingDrawerToolbarDispatcher()
        let finderQuery = DrawerToolbarTargetedQuery(
            command: .openPaneLocationInFinder,
            target: locationTargetPaneId,
            targetType: .pane
        )
        dispatcher.enabledQueries = [finderQuery]

        let presentation = DrawerToolbarCommandPresentation.resolve(
            anchorPaneId: anchorPaneId,
            locationTargetPaneId: locationTargetPaneId,
            toolbarSurface: .pane,
            actionResolver: { command, surface, target, targetType in
                TargetedCommandControlAction.resolve(
                    command: command,
                    surface: surface,
                    target: target,
                    targetType: targetType,
                    dispatcher: dispatcher
                )
            }
        )
        let finderAction = try #require(presentation.openFinder)
        dispatcher.enabledQueries = []

        finderAction.perform()

        #expect(finderAction.isEnabled)
        #expect(
            dispatcher.capabilityQueries.filter { $0 == finderQuery }
                == [finderQuery, finderQuery]
        )
        #expect(dispatcher.dispatchedQueries.isEmpty)
    }
}

private struct DrawerToolbarActionRequest: Equatable {
    let command: AppCommand
    let surface: AppCommandSurface
    let target: UUID
    let targetType: SearchItemType
}

@MainActor
private final class RecordingDrawerToolbarActionResolver {
    var omittedCommands: Set<AppCommand> = []
    var disabledCommands: Set<AppCommand> = []
    private(set) var requests: [DrawerToolbarActionRequest] = []

    func resolve(
        command: AppCommand,
        surface: AppCommandSurface,
        target: UUID,
        targetType: SearchItemType
    ) -> TargetedCommandControlAction? {
        requests.append(
            DrawerToolbarActionRequest(
                command: command,
                surface: surface,
                target: target,
                targetType: targetType
            )
        )
        guard !omittedCommands.contains(command) else { return nil }
        return TargetedCommandControlAction(
            commandSpec: command.definition,
            isEnabled: !disabledCommands.contains(command),
            perform: {}
        )
    }
}

private struct DrawerToolbarTargetedQuery: Equatable, Hashable {
    let command: AppCommand
    let target: UUID
    let targetType: SearchItemType
}

@MainActor
private final class RecordingDrawerToolbarDispatcher: AppCommandDispatching {
    var enabledQueries: Set<DrawerToolbarTargetedQuery> = []
    private(set) var capabilityQueries: [DrawerToolbarTargetedQuery] = []
    private(set) var dispatchedQueries: [DrawerToolbarTargetedQuery] = []

    func dispatch(_: AppCommand) {}

    func dispatch(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) {
        dispatchedQueries.append(
            DrawerToolbarTargetedQuery(
                command: command,
                target: target,
                targetType: targetType
            )
        )
    }

    func canDispatch(_: AppCommand) -> Bool {
        false
    }

    func canDispatch(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> Bool {
        let query = DrawerToolbarTargetedQuery(
            command: command,
            target: target,
            targetType: targetType
        )
        capabilityQueries.append(query)
        return enabledQueries.contains(query)
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }

    func dispatchMovePaneToTab(
        sourcePaneId _: UUID,
        sourceTabId _: UUID?,
        targetTabId _: UUID
    ) {}
}
