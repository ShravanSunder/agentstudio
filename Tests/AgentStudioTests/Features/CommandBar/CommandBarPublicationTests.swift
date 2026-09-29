import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioCommandBar

@MainActor
private final class CommandBarPublicationRecorder {
    private var publications: [(SearchRequestSequence, SearchDocumentGeneration)] = []
    private var waiters: [CheckedContinuation<(SearchRequestSequence, SearchDocumentGeneration), Never>] = []

    func record(sequence: SearchRequestSequence, generation: SearchDocumentGeneration) {
        let publication = (sequence, generation)
        if waiters.isEmpty {
            publications.append(publication)
        } else {
            waiters.removeFirst().resume(returning: publication)
        }
    }

    func next() async -> (SearchRequestSequence, SearchDocumentGeneration) {
        if !publications.isEmpty { return publications.removeFirst() }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@MainActor
@Suite(.serialized)
struct CommandBarPublicationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("a mounted command bar acknowledges each accepted result")
    func mountedViewAcknowledgesTwoQueries() async throws {
        let recorder = CommandBarPublicationRecorder()
        let defaults = CommandBarRecentsDefaultsFixture().makeDefaults()
        let loader = makeCommandBarTestOcticonLoader()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            octiconLoader: loader,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            recentsDefaults: defaults
        )
        controller.state.show(prefix: ">")
        let view = CommandBarView(
            state: controller.state,
            octiconLoader: loader,
            resultSession: controller.resultSession,
            onShortcutTrigger: { _ in false },
            onExecuteItem: { _, _ in },
            onShowActions: { _ in },
            onInitialResultsPublished: {},
            onInputFocusAcknowledged: {},
            onInputChanged: { text, inputAtNanoseconds in
                controller.queryChanged(text: text, inputAtNanoseconds: inputAtNanoseconds)
            },
            onSearchContextChanged: { controller.searchContextChanged() },
            onResultPublished: recorder.record
        )
        let hostingView = NSHostingView(rootView: AnyView(view.frame(width: 540, height: 420)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            hostingView.rootView = AnyView(EmptyView())
            hostingView.layoutSubtreeIfNeeded()
            window.contentView = nil
            window.close()
        }
        hostingView.layoutSubtreeIfNeeded()

        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        hostingView.layoutSubtreeIfNeeded()
        let firstPublication = await recorder.next()
        #expect(firstPublication.0 == controller.state.appliedSearchResult?.sequence)

        controller.state.rawInput = "> new"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        hostingView.layoutSubtreeIfNeeded()
        let secondPublication = await recorder.next()
        #expect(secondPublication.0 == controller.state.appliedSearchResult?.sequence)
        #expect(secondPublication.0 > firstPublication.0)
    }
}
