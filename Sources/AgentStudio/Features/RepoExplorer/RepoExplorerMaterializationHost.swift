import AgentStudioCore
import AppKit
import SwiftUI

@MainActor
final class RepoExplorerMaterializationHost: NSView {
    let lifetimeID: RepoExplorerMaterializationHostLifetimeID
    private(set) var acceptedBaseline: RepoExplorerMaterializationBaseline?
    private(set) var isPresentationReady = false
    private(set) var presentedChildView: NSView?
    private(set) var selectedRowID: RepoExplorerRowID?

    var visibleGeneration: UInt64? {
        acceptedBaseline?.visibleGeneration
    }

    override var acceptsFirstResponder: Bool { !isDetached }

    private var keyboardInteraction: RepoExplorerKeyboardInteraction?

    func installKeyboardInteraction(_ interaction: RepoExplorerKeyboardInteraction) {
        if keyboardInteraction !== interaction {
            keyboardInteraction?.detach(self)
            keyboardInteraction = interaction
        }
        interaction.attach(self)
        interaction.selectedPaneTargetDidChange(selectedPaneTarget())
    }

    @discardableResult
    func requestListFocus() -> Bool {
        guard !isDetached, let keyboardInteraction else { return false }
        return keyboardInteraction.requestListFocus()
    }

    @discardableResult
    func requestFilterFocus() -> Bool {
        guard !isDetached, let keyboardInteraction else { return false }
        keyboardInteraction.requestFilterFocus()
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            keyboardInteraction?.listDidBecomeFirstResponder(self)
            ensureInitialSelectionForKeyboardEntry()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { keyboardInteraction?.listDidResignFirstResponder(self) }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if Self.isSpaceKeyDown(event) {
            guard isPresentationReady, let keyboardInteraction,
                keyboardInteraction.isListKeyboardActive
            else {
                super.keyDown(with: event)
                return
            }
            keyboardInteraction.spaceKeyDown(
                isRepeat: event.isARepeat,
                selectedPaneTarget: selectedPaneTarget()
            )
            return
        }
        guard isPresentationReady, keyboardInteraction?.isListKeyboardActive == true,
            let trigger = ShortcutDecoder.decode(event: event)
        else {
            super.keyDown(with: event)
            return
        }
        if let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .sidebarList) {
            keyboardInteraction?.requestCommand(shortcut.command)
            return
        }
        if let action = RepoExplorerListKeyboardAction.resolve(trigger) {
            handleListKeyboardAction(action)
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        // Space-up is the physical end of the gesture. Its modifier snapshot
        // and current list readiness may differ from the corresponding key-down
        // (for example, Shift or Caps Lock can change while Space is held).
        if event.keyCode == 49 {
            keyboardInteraction?.spaceKeyUp()
            return
        }
        super.keyUp(with: event)
    }

    private static func isSpaceKeyDown(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }
        let conventionalCommandModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .option,
            .shift,
        ]
        return event.modifierFlags.isDisjoint(with: conventionalCommandModifiers)
    }

    private let makeContentChild: @MainActor () -> any RepoExplorerMaterializationContentChild
    private let onFeedback: @MainActor (RepoExplorerMaterializationFeedback) -> Void
    private let onInvariantViolation: @MainActor (String) -> Void
    private var rowlessChild: NSHostingView<RepoExplorerEmptyStateView>?
    private var contentChild: (any RepoExplorerMaterializationContentChild)?
    private var activeCandidate: RepoExplorerMaterializationCandidate?
    private var isDetached = false

    init(
        lifetimeID: RepoExplorerMaterializationHostLifetimeID,
        initialDemandEpoch: UInt64,
        initialPresentation: RepoExplorerRowlessPresentation,
        makeContentChild:
            @escaping @MainActor () -> any RepoExplorerMaterializationContentChild,
        onFeedback: @escaping @MainActor (RepoExplorerMaterializationFeedback) -> Void,
        onInvariantViolation: @escaping @MainActor (String) -> Void = {
            preconditionFailure($0)
        }
    ) {
        self.lifetimeID = lifetimeID
        self.makeContentChild = makeContentChild
        self.onFeedback = onFeedback
        self.onInvariantViolation = onInvariantViolation
        super.init(frame: .zero)

        let presentation = RepoExplorerMaterializationPresentation.rowless(initialPresentation)
        installInitialRowlessChild(initialPresentation)
        let baseline = RepoExplorerMaterializationBaseline(
            lifetimeID: lifetimeID,
            demandEpoch: initialDemandEpoch,
            revision: 0,
            visibleGeneration: 0,
            presentation: presentation
        )
        acceptedBaseline = baseline
        isPresentationReady = true
        onFeedback(.accepted(identity: .initial, baseline: baseline))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(
        _ candidate: RepoExplorerMaterializationCandidate
    ) -> RepoExplorerMaterializationApplyDisposition {
        guard !isDetached, let currentBaseline = acceptedBaseline else {
            return reject(candidate, reason: .hostDetached)
        }
        guard isPresentationReady else {
            return reject(candidate, reason: .demandSuspended)
        }
        guard activeCandidate == nil else {
            return reject(candidate, reason: .candidateInProgress)
        }
        guard candidate.lifetimeID == lifetimeID else {
            return reject(candidate, reason: .lifetimeMismatch)
        }
        guard candidate.demandEpoch == currentBaseline.demandEpoch else {
            return reject(candidate, reason: .demandEpochMismatch)
        }
        guard candidate.expectedRevision == currentBaseline.revision else {
            return reject(candidate, reason: .revisionMismatch)
        }
        guard candidate.visibleGeneration > currentBaseline.visibleGeneration else {
            return reject(candidate, reason: .generationNotNewer)
        }

        guard candidate.id.rawValue > 0,
            candidate.nativeUpdatePlan.matchesDelivery(
                baseline: currentBaseline,
                presentation: candidate.presentation,
                requestGeneration: candidate.requestGeneration,
                visibleGeneration: candidate.visibleGeneration,
                expectedRevision: candidate.expectedRevision,
                proposedRevision: candidate.proposedRevision
            )
        else {
            return reject(candidate, reason: .nativePlanMismatch)
        }

        if case .equal = candidate.nativeUpdatePlan.kind {
            guard candidate.proposedRevision == currentBaseline.revision else {
                return reject(candidate, reason: .invalidRevisionTransition)
            }
            return .equal(currentBaseline)
        }

        guard candidate.proposedRevision == currentBaseline.revision &+ 1 else {
            return reject(candidate, reason: .invalidRevisionTransition)
        }
        let reconciledSelectionRowID: RepoExplorerRowID?
        if selectedRowID != nil || keyboardInteraction?.isListKeyboardActive == true {
            reconciledSelectionRowID = candidate.nativeUpdatePlan.reconciledSelectionRowID(
                for: selectedRowID
            )
        } else {
            reconciledSelectionRowID = nil
        }

        activeCandidate = candidate
        defer { activeCandidate = nil }
        let transitionDisposition = applyChangedPresentation(
            candidate,
            selectedRowID: reconciledSelectionRowID
        )
        guard transitionDisposition == .accepted else {
            return reject(candidate, reason: transitionDisposition.rejectionReason)
        }

        let acceptedBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: lifetimeID,
            demandEpoch: candidate.demandEpoch,
            revision: candidate.proposedRevision,
            visibleGeneration: candidate.visibleGeneration,
            presentation: candidate.presentation
        )
        self.acceptedBaseline = acceptedBaseline
        selectedRowID = reconciledSelectionRowID
        isPresentationReady = true
        keyboardInteraction?.selectedPaneTargetDidChange(selectedPaneTarget())
        onFeedback(.accepted(identity: .candidate(candidate.id), baseline: acceptedBaseline))
        return .accepted(acceptedBaseline)
    }

    func suspendDemand() {
        guard !isDetached else { return }
        contentChild?.suspendDemand()
        isPresentationReady = false
    }

    func reacknowledgeRetainedPresentation(
        demandEpoch: UInt64
    ) -> RepoExplorerMaterializationBaseline? {
        guard !isDetached,
            !isPresentationReady,
            let baseline = acceptedBaseline,
            demandEpoch > baseline.demandEpoch
        else {
            return nil
        }
        let reacknowledgedBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: baseline.lifetimeID,
            demandEpoch: demandEpoch,
            revision: baseline.revision,
            visibleGeneration: baseline.visibleGeneration,
            presentation: baseline.presentation
        )
        acceptedBaseline = reacknowledgedBaseline
        isPresentationReady = true
        onFeedback(.accepted(identity: .reentry, baseline: reacknowledgedBaseline))
        contentChild?.resumeDemand(
            visibleGeneration: reacknowledgedBaseline.visibleGeneration
        )
        return reacknowledgedBaseline
    }

    func detach() {
        guard !isDetached else { return }
        keyboardInteraction?.detach(self)
        keyboardInteraction = nil
        isDetached = true
        isPresentationReady = false
        acceptedBaseline = nil
        selectedRowID = nil
        activeCandidate = nil
        contentChild?.detach()
        contentChild = nil
        rowlessChild = nil
        presentedChildView?.removeFromSuperview()
        presentedChildView = nil
    }

    private func applyChangedPresentation(
        _ candidate: RepoExplorerMaterializationCandidate,
        selectedRowID: RepoExplorerRowID?
    ) -> ChangedTransitionDisposition {
        switch candidate.presentation {
        case .rowless(let rowlessPresentation):
            return applyRowlessPresentation(
                rowlessPresentation,
                visibleGeneration: candidate.visibleGeneration
            )
        case .content(let snapshot, _):
            guard let tableUpdatePlan = candidate.nativeUpdatePlan.tableUpdatePlan() else {
                return .rejected(.nativePlanMismatch)
            }
            return applyContentSnapshot(
                RepoExplorerMaterializationContentCandidate(
                    candidateID: candidate.id,
                    requestGeneration: candidate.requestGeneration,
                    visibleGeneration: candidate.visibleGeneration,
                    snapshot: snapshot,
                    tableUpdatePlan: tableUpdatePlan,
                    selectedRowID: selectedRowID
                )
            )
        }
    }

    private func applyRowlessPresentation(
        _ presentation: RepoExplorerRowlessPresentation,
        visibleGeneration: UInt64
    ) -> ChangedTransitionDisposition {
        guard let contentChild else {
            updateExistingRowlessChild(presentation)
            return .accepted
        }

        let replacementRowlessChild = makeRowlessChild(presentation)
        installChildView(replacementRowlessChild, hidden: true)
        let childDisposition = performChildTransaction("content removal") { completion in
            contentChild.prepareForRemoval(
                visibleGeneration: visibleGeneration,
                completion: completion
            )
        }
        guard childDisposition == .accepted else {
            replacementRowlessChild.removeFromSuperview()
            return childDisposition
        }

        contentChild.detach()
        contentChild.view.removeFromSuperview()
        self.contentChild = nil
        rowlessChild = replacementRowlessChild
        presentedChildView = replacementRowlessChild
        replacementRowlessChild.isHidden = false
        return .accepted
    }

    private func applyContentSnapshot(
        _ candidate: RepoExplorerMaterializationContentCandidate
    ) -> ChangedTransitionDisposition {
        if let contentChild {
            return performChildTransaction("content apply") { completion in
                contentChild.apply(candidate, completion: completion)
            }
        }

        let newContentChild = makeContentChild()
        installChildView(newContentChild.view, hidden: true)
        let childDisposition = performChildTransaction("initial content apply") { completion in
            newContentChild.apply(candidate, completion: completion)
        }
        guard childDisposition == .accepted else {
            newContentChild.detach()
            newContentChild.view.removeFromSuperview()
            return childDisposition
        }

        rowlessChild?.removeFromSuperview()
        rowlessChild = nil
        contentChild = newContentChild
        presentedChildView = newContentChild.view
        newContentChild.view.isHidden = false
        return .accepted
    }

    private func performChildTransaction(
        _ operation: String,
        invoke: (@escaping (RepoExplorerMaterializationChildDisposition) -> Void) -> Void
    ) -> ChangedTransitionDisposition {
        let latch = ChildDispositionLatch(
            operation: operation,
            onInvariantViolation: onInvariantViolation
        )
        invoke { disposition in
            latch.receive(disposition)
        }
        return latch.close()
    }

    private func installInitialRowlessChild(_ presentation: RepoExplorerRowlessPresentation) {
        let child = makeRowlessChild(presentation)
        rowlessChild = child
        presentedChildView = child
        installChildView(child, hidden: false)
    }

    private func updateExistingRowlessChild(_ presentation: RepoExplorerRowlessPresentation) {
        guard let rowlessChild else {
            installInitialRowlessChild(presentation)
            return
        }
        rowlessChild.rootView = RepoExplorerEmptyStateView(emptyState: presentation.emptyState)
        configureAccessibility(of: rowlessChild, presentation: presentation)
        rowlessChild.layoutSubtreeIfNeeded()
    }

    private func makeRowlessChild(
        _ presentation: RepoExplorerRowlessPresentation
    ) -> NSHostingView<RepoExplorerEmptyStateView> {
        let child = NSHostingView(
            rootView: RepoExplorerEmptyStateView(emptyState: presentation.emptyState)
        )
        configureAccessibility(of: child, presentation: presentation)
        return child
    }

    private func configureAccessibility(
        of view: NSView,
        presentation: RepoExplorerRowlessPresentation
    ) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func installChildView(_ childView: NSView, hidden: Bool) {
        childView.translatesAutoresizingMaskIntoConstraints = false
        childView.isHidden = hidden
        addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: trailingAnchor),
            childView.topAnchor.constraint(equalTo: topAnchor),
            childView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        layoutSubtreeIfNeeded()
    }

    private func handleListKeyboardAction(_ action: RepoExplorerListKeyboardAction) {
        switch action {
        case .moveSelectionUp:
            moveSelection(verticalDirection: .previous)
        case .moveSelectionDown:
            moveSelection(verticalDirection: .next)
        case .moveToParentOrCollapseGroup:
            moveToParentOrCollapseGroup()
        case .moveToFirstChildOrExpandGroup:
            moveToFirstChildOrExpandGroup()
        case .activateSelection:
            activateSelectedRow()
        case .returnFocus:
            keyboardInteraction?.returnFromList()
        case .activateNumberedDestination(let digit):
            activateNumberedDestination(digit)
        }
    }

    private enum VerticalSelectionDirection {
        case previous
        case next
    }

    private var acceptedContentSnapshot: RepoExplorerMaterializationSnapshot? {
        acceptedBaseline?.presentation.contentSnapshot
    }

    private func ensureInitialSelectionForKeyboardEntry() {
        guard selectedRowID == nil,
            let initialRowID = acceptedContentSnapshot?.navigationIndex.initialSelectionRowID,
            contentChild?.applySelection(rowID: initialRowID, scrollIntoView: true) == true
        else { return }
        selectedRowID = initialRowID
        keyboardInteraction?.selectedPaneTargetDidChange(selectedPaneTarget())
    }

    private func moveSelection(verticalDirection: VerticalSelectionDirection) {
        guard let snapshot = acceptedContentSnapshot else { return }
        let targetRowID: RepoExplorerRowID?
        if let selectedRowID {
            switch verticalDirection {
            case .previous:
                targetRowID = snapshot.navigationIndex.previousSelectableRowID(before: selectedRowID)
            case .next:
                targetRowID = snapshot.navigationIndex.nextSelectableRowID(after: selectedRowID)
            }
        } else {
            targetRowID = snapshot.navigationIndex.initialSelectionRowID
        }
        guard let targetRowID else { return }
        applyKeyboardSelection(targetRowID)
    }

    private func moveToParentOrCollapseGroup() {
        guard let snapshot = acceptedContentSnapshot,
            let selectedRowID,
            let row = snapshot.row(id: selectedRowID)
        else { return }
        if case .groupHeader(let group) = row.presentation {
            guard group.isExpanded else { return }
            contentChild?.performListKeyboardEffect(
                .setGroupExpanded(groupID: group.groupID, isExpanded: false)
            )
            return
        }
        guard let parentRowID = snapshot.navigationIndex.parentRowID(for: selectedRowID) else {
            return
        }
        applyKeyboardSelection(parentRowID)
    }

    private func moveToFirstChildOrExpandGroup() {
        guard let snapshot = acceptedContentSnapshot,
            let selectedRowID,
            let row = snapshot.row(id: selectedRowID),
            case .groupHeader(let group) = row.presentation
        else { return }
        if group.isExpanded {
            if let firstChildRowID = snapshot.navigationIndex.firstChildRowID(for: selectedRowID) {
                applyKeyboardSelection(firstChildRowID)
            }
            return
        }
        contentChild?.performListKeyboardEffect(
            .setGroupExpanded(groupID: group.groupID, isExpanded: true)
        )
    }

    private func activateSelectedRow() {
        guard let selectedRowID else { return }
        activate(rowID: selectedRowID)
    }

    private func activateNumberedDestination(_ digit: Int) {
        guard let rowID = acceptedContentSnapshot?.navigationIndex.rowID(forDigit: digit) else {
            return
        }
        activate(rowID: rowID)
    }

    private func activate(rowID: RepoExplorerRowID) {
        guard let row = acceptedContentSnapshot?.row(id: rowID),
            let effect = Self.keyboardEffect(for: row)
        else { return }
        keyboardInteraction?.commitPreviewBeforeActivation()
        contentChild?.performListKeyboardEffect(effect)
    }

    private func applyKeyboardSelection(_ rowID: RepoExplorerRowID) {
        guard rowID != selectedRowID,
            contentChild?.applySelection(rowID: rowID, scrollIntoView: true) == true
        else { return }
        selectedRowID = rowID
        keyboardInteraction?.selectedPaneTargetDidChange(selectedPaneTarget())
    }

    private func selectedPaneTarget() -> RepoExplorerSelectedPaneTarget? {
        guard let selectedRowID,
            let row = acceptedContentSnapshot?.row(id: selectedRowID)
        else { return nil }
        switch row.presentation {
        case .pane(let pane):
            return RepoExplorerSelectedPaneTarget(
                paneID: pane.destination.paneId,
                owningTabID: pane.destination.tabId
            )
        case .unassociatedPane(let pane):
            return RepoExplorerSelectedPaneTarget(
                paneID: pane.destination.paneId,
                owningTabID: pane.destination.tabId
            )
        case .activitySubgroup, .sectionHeader, .loadingSectionHeader, .loadingRepository,
            .groupHeader, .worktree, .topologyFault, .unresolved:
            return nil
        }
    }

    private static func keyboardEffect(
        for row: RepoExplorerMaterializedRow
    ) -> RepoExplorerListKeyboardEffect? {
        switch row.presentation {
        case .groupHeader(let group):
            .toggleGroup(groupID: group.groupID)
        case .worktree(let worktree):
            .commandRequest(
                RepoExplorerCommandPresentationRequest(
                    command: .openWorktree,
                    surface: .inlineControl,
                    target: worktree.worktree.id,
                    targetType: .worktree,
                    arguments: .noArguments
                )
            )
        case .pane(let pane):
            .focusPane(paneID: pane.destination.paneId)
        case .unassociatedPane(let pane):
            .focusPane(paneID: pane.destination.paneId)
        case .activitySubgroup, .sectionHeader, .loadingSectionHeader, .loadingRepository,
            .topologyFault, .unresolved:
            nil
        }
    }

    private func reject(
        _ candidate: RepoExplorerMaterializationCandidate,
        reason: RepoExplorerMaterializationRejectionReason
    ) -> RepoExplorerMaterializationApplyDisposition {
        onFeedback(.rejected(candidateID: candidate.id, reason: reason))
        return .rejected(reason)
    }
}

@MainActor
private final class ChildDispositionLatch {
    private let operation: String
    private let onInvariantViolation: @MainActor (String) -> Void
    private var dispositions: [RepoExplorerMaterializationChildDisposition] = []
    private var isClosed = false

    init(
        operation: String,
        onInvariantViolation: @escaping @MainActor (String) -> Void
    ) {
        self.operation = operation
        self.onInvariantViolation = onInvariantViolation
    }

    func receive(_ disposition: RepoExplorerMaterializationChildDisposition) {
        guard !isClosed else {
            onInvariantViolation("Repo Explorer \(operation) disposition arrived asynchronously")
            return
        }
        dispositions.append(disposition)
    }

    func close() -> ChangedTransitionDisposition {
        isClosed = true
        guard dispositions.count == 1 else {
            onInvariantViolation(
                "Repo Explorer \(operation) must synchronously return exactly one disposition"
            )
            return .rejected(.childDispositionInvariant)
        }
        switch dispositions[0] {
        case .accepted: return .accepted
        case .rejected: return .rejected(.childRejected)
        }
    }
}

private enum ChangedTransitionDisposition: Equatable {
    case accepted
    case rejected(RepoExplorerMaterializationRejectionReason)

    var rejectionReason: RepoExplorerMaterializationRejectionReason {
        switch self {
        case .accepted:
            preconditionFailure("Accepted materialization has no rejection reason")
        case .rejected(let reason):
            reason
        }
    }
}
