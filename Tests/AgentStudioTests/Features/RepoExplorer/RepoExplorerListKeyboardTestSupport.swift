import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
final class RepoExplorerListKeyboardRecorder {
    private(set) var commandRequests: [RepoExplorerCommandPresentationRequest] = []
    private(set) var toggledGroupIDs: [String] = []
    private(set) var focusedPaneIDs: [UUID] = []
    private(set) var expansionRequests: [RepoExplorerGroupExpansionRequest] = []

    func recordCommand(_ request: RepoExplorerCommandPresentationRequest) {
        commandRequests.append(request)
    }

    func recordToggle(groupID: String) {
        toggledGroupIDs.append(groupID)
    }

    func recordFocus(paneID: UUID) {
        focusedPaneIDs.append(paneID)
    }

    func recordExpansion(groupID: String, isExpanded: Bool) {
        expansionRequests.append(
            RepoExplorerGroupExpansionRequest(groupID: groupID, isExpanded: isExpanded)
        )
    }
}

struct RepoExplorerGroupExpansionRequest: Equatable {
    let groupID: String
    let isExpanded: Bool
}

@MainActor
final class RepoExplorerListKeyboardFixture {
    let recorder: RepoExplorerListKeyboardRecorder
    let materializer: RepoExplorerTableMaterializer
    let host: RepoExplorerMaterializationHost
    let interaction: RepoExplorerKeyboardInteraction
    let textField: NSTextField
    let window: NSWindow

    init(windowHeight: CGFloat = 240, focusListInitially: Bool = true) {
        let lifetimeID = RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate())
        let recorder = RepoExplorerListKeyboardRecorder()
        var interactions = RepoExplorerTableInteractions(
            onCommandRequest: { recorder.recordCommand($0) },
            onToggleGroup: { recorder.recordToggle(groupID: $0) },
            onFocusPane: { recorder.recordFocus(paneID: $0) }
        )
        interactions.onSetGroupExpanded = {
            recorder.recordExpansion(groupID: $0, isExpanded: $1)
        }
        let materializer = RepoExplorerTableMaterializer(
            materializationHostLifetimeID: lifetimeID,
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            interactions: interactions,
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let host = RepoExplorerMaterializationHost(
            lifetimeID: lifetimeID,
            initialDemandEpoch: 1,
            initialPresentation: .noRepositories,
            makeContentChild: { materializer },
            onFeedback: { _ in }
        )
        let interaction = RepoExplorerKeyboardInteraction()
        interaction.configure(
            RepoExplorerKeyboardCallbacks(canInterpretListInput: { true })
        )
        host.installKeyboardInteraction(interaction)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: windowHeight))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        container.addSubview(textField)
        let window = NSWindow(
            contentRect: container.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.layoutIfNeeded()
        if focusListInitially {
            precondition(window.makeFirstResponder(host))
        }

        self.recorder = recorder
        self.materializer = materializer
        self.host = host
        self.interaction = interaction
        self.textField = textField
        self.window = window
    }

    func candidate(
        snapshot: RepoExplorerMaterializationSnapshot,
        generation: UInt64
    ) throws -> RepoExplorerMaterializationCandidate {
        try candidate(presentation: nativePlanContent(snapshot), generation: generation)
    }

    func apply(
        snapshot: RepoExplorerMaterializationSnapshot,
        generation: UInt64
    ) throws -> RepoExplorerMaterializationApplyDisposition {
        host.apply(try candidate(snapshot: snapshot, generation: generation))
    }

    func apply(
        rowless: RepoExplorerRowlessPresentation,
        generation: UInt64
    ) throws -> RepoExplorerMaterializationApplyDisposition {
        host.apply(try candidate(presentation: .rowless(rowless), generation: generation))
    }

    func send(
        _ action: RepoExplorerListKeyboardAction,
        directlyToHost: Bool = true
    ) throws {
        let event = try #require(repoExplorerKeyEvent(for: action, windowNumber: window.windowNumber))
        if directlyToHost {
            host.keyDown(with: event)
        } else {
            window.sendEvent(event)
        }
    }

    func nativeSelectedRowID(
        in snapshot: RepoExplorerMaterializationSnapshot
    ) -> RepoExplorerRowID? {
        guard let tableView = firstRepoExplorerKeyboardDescendant(NSTableView.self, in: host),
            snapshot.rows.indices.contains(tableView.selectedRow)
        else { return nil }
        return snapshot.rows[tableView.selectedRow].id
    }

    func close() {
        host.detach()
        window.close()
    }

    private func candidate(
        presentation: RepoExplorerMaterializationPresentation,
        generation: UInt64
    ) throws -> RepoExplorerMaterializationCandidate {
        let baseline = try #require(host.acceptedBaseline)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: presentation,
            requestGeneration: generation
        ).get()
        let proposedRevision: UInt64
        switch plan.kind {
        case .equal: proposedRevision = baseline.revision
        case .changed: proposedRevision = baseline.revision + 1
        }
        return RepoExplorerMaterializationCandidate(
            id: RepoExplorerMaterializationCandidateID(rawValue: generation),
            lifetimeID: host.lifetimeID,
            demandEpoch: baseline.demandEpoch,
            requestGeneration: generation,
            visibleGeneration: generation,
            expectedRevision: baseline.revision,
            proposedRevision: proposedRevision,
            presentation: presentation,
            nativeUpdatePlan: plan
        )
    }
}

@MainActor
func firstRepoExplorerKeyboardDescendant<ViewType: NSView>(
    _ type: ViewType.Type,
    in view: NSView
) -> ViewType? {
    if let match = view as? ViewType { return match }
    for subview in view.subviews {
        if let match = firstRepoExplorerKeyboardDescendant(type, in: subview) { return match }
    }
    return nil
}

private func repoExplorerKeyEvent(
    for action: RepoExplorerListKeyboardAction,
    windowNumber: Int
) -> NSEvent? {
    let keyCode: UInt16
    let characters: String
    switch action.trigger.key {
    case .arrow(.left):
        keyCode = 123
        characters = "\u{F702}"
    case .arrow(.right):
        keyCode = 124
        characters = "\u{F703}"
    case .arrow(.down):
        keyCode = 125
        characters = "\u{F701}"
    case .arrow(.up):
        keyCode = 126
        characters = "\u{F700}"
    case .enter:
        keyCode = 36
        characters = "\r"
    case .escape:
        keyCode = 53
        characters = "\u{1b}"
    case .character(let key):
        let digitKeyCodes: [String: UInt16] = [
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
        ]
        guard let digitKeyCode = digitKeyCodes[key.rawValue] else { return nil }
        keyCode = digitKeyCode
        characters = key.rawValue
    }
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )
}
