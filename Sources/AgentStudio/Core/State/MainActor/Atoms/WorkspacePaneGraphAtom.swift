import Foundation
import Observation
import os.log

private let workspacePaneLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePaneGraphAtom")

struct DrawerGraphState: Hashable, Sendable {
    let drawerId: UUID
    let parentPaneId: UUID
    var paneIds: [UUID]

    init(drawerId: UUID = UUID(), parentPaneId: UUID, paneIds: [UUID] = []) {
        self.drawerId = drawerId
        self.parentPaneId = parentPaneId
        self.paneIds = paneIds
    }

    init(drawer: Drawer) {
        self.init(drawerId: drawer.drawerId, parentPaneId: drawer.parentPaneId, paneIds: drawer.paneIds)
    }

    func drawer(isExpanded: Bool) -> Drawer {
        Drawer(drawerId: drawerId, parentPaneId: parentPaneId, paneIds: paneIds, isExpanded: isExpanded)
    }
}

enum PaneGraphKind: Hashable, Sendable {
    case layout(drawer: DrawerGraphState)
    case drawerChild(parentPaneId: UUID)

    init(kind: PaneKind) {
        switch kind {
        case .layout(let drawer):
            self = .layout(drawer: DrawerGraphState(drawer: drawer))
        case .drawerChild(let parentPaneId):
            self = .drawerChild(parentPaneId: parentPaneId)
        }
    }

    func paneKind(isDrawerExpanded: Bool) -> PaneKind {
        switch self {
        case .layout(let drawer):
            return .layout(drawer: drawer.drawer(isExpanded: isDrawerExpanded))
        case .drawerChild(let parentPaneId):
            return .drawerChild(parentPaneId: parentPaneId)
        }
    }
}

struct PaneGraphFacets: Hashable, Sendable {
    var repoId: UUID?
    var worktreeId: UUID?
    var cwd: URL?

    init(repoId: UUID? = nil, worktreeId: UUID? = nil, cwd: URL? = nil) {
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.cwd = cwd
    }

    init(contextFacets: PaneContextFacets) {
        self.init(
            repoId: contextFacets.repoId,
            worktreeId: contextFacets.worktreeId,
            cwd: contextFacets.cwd
        )
    }

    var paneContextFacets: PaneContextFacets {
        PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: cwd)
    }
}

struct PaneGraphMetadata: Hashable, Sendable {
    let paneId: PaneId
    let contentType: PaneContentType
    let launchDirectory: URL?
    let executionBackend: ExecutionBackend
    let createdAt: Date
    var title: String
    var facets: PaneGraphFacets
    var checkoutRef: String?
    var note: String?

    init(metadata: PaneMetadata) {
        self.paneId = metadata.paneId
        self.contentType = metadata.contentType
        self.launchDirectory = metadata.launchDirectory
        self.executionBackend = metadata.executionBackend
        self.createdAt = metadata.createdAt
        self.title = metadata.title
        self.facets = PaneGraphFacets(contextFacets: metadata.facets)
        self.checkoutRef = metadata.checkoutRef
        self.note = metadata.note
    }

    mutating func updateNote(_ newNote: String?) {
        let trimmed = newNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        note = trimmed?.isEmpty == true ? nil : trimmed
    }

    var paneMetadata: PaneMetadata {
        PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            launchDirectory: launchDirectory,
            executionBackend: executionBackend,
            createdAt: createdAt,
            title: title,
            facets: facets.paneContextFacets,
            checkoutRef: checkoutRef,
            note: note,
            fillNilLaunchDirectoryFacet: false
        )
    }
}

/// Core pane graph state. This is the write-owner shape for pane identity,
/// content, residency, durable metadata, drawer identity, and drawer
/// membership. It intentionally excludes drawer expansion and display/cache
/// facets, which are composed by cursor and derived read models.
struct PaneGraphState: Identifiable, Hashable, Sendable {
    let id: UUID
    var content: PaneContent
    var metadata: PaneGraphMetadata
    var residency: SessionResidency
    var kind: PaneGraphKind

    init(
        id: UUID,
        content: PaneContent,
        metadata: PaneGraphMetadata,
        residency: SessionResidency,
        kind: PaneGraphKind
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.residency = residency
        self.kind = kind
    }

    init(pane: Pane) {
        self.init(
            id: pane.id,
            content: pane.content,
            metadata: PaneGraphMetadata(metadata: pane.metadata),
            residency: pane.residency,
            kind: PaneGraphKind(kind: pane.kind)
        )
    }

    var drawer: DrawerGraphState? {
        if case .layout(let drawer) = kind { return drawer }
        return nil
    }

    var isDrawerChild: Bool {
        if case .drawerChild = kind { return true }
        return false
    }

    var parentPaneId: UUID? {
        if case .drawerChild(let parentPaneId) = kind { return parentPaneId }
        return nil
    }

    mutating func withDrawer(_ transform: (inout DrawerGraphState) -> Void) {
        guard case .layout(var drawer) = kind else { return }
        transform(&drawer)
        kind = .layout(drawer: drawer)
    }

    func pane(isDrawerExpanded: Bool) -> Pane {
        let graphFacets = metadata.facets.paneContextFacets
        var pane = Pane(
            id: id,
            content: content,
            metadata: metadata.paneMetadata,
            residency: residency,
            kind: kind.paneKind(isDrawerExpanded: isDrawerExpanded)
        )
        pane.metadata.updateFacets(graphFacets)
        return pane
    }
}

enum WorkspacePaneGraphReplacementRejection: Error, Equatable, Sendable {
    case paneKeyIdentityMismatch(key: UUID, paneID: UUID)
    case duplicateDrawerIdentity(UUID)
    case drawerParentMismatch(drawerID: UUID, expectedParentPaneID: UUID, actualParentPaneID: UUID)
    case drawerChildParentMismatch(
        childPaneID: UUID,
        expectedParentPaneID: UUID,
        actualParentPaneID: UUID
    )
    case orphanDrawerChild(childPaneID: UUID, parentPaneID: UUID)
    case duplicateDrawerChildMembership(UUID)
}

/// A complete pane graph that has passed the pane domain's normalization and
/// relational invariants. Its initializer is intentionally private so full
/// atom replacement cannot bypass validation.
struct WorkspacePaneGraphReplacement: Equatable, Sendable {
    let paneStates: [UUID: PaneGraphState]

    private init(paneStates: [UUID: PaneGraphState]) {
        self.paneStates = paneStates
    }

    static func prepare(
        _ proposedPaneStates: [UUID: PaneGraphState]
    ) -> Result<Self, WorkspacePaneGraphReplacementRejection> {
        for (paneID, paneState) in proposedPaneStates where paneID != paneState.id {
            return .failure(.paneKeyIdentityMismatch(key: paneID, paneID: paneState.id))
        }

        let validPaneIDs = Set(proposedPaneStates.keys)
        var normalizedPaneStates = proposedPaneStates
        for paneID in normalizedPaneStates.keys {
            normalizedPaneStates[paneID]?.withDrawer { drawer in
                drawer.paneIds.removeAll { !validPaneIDs.contains($0) }
            }
        }

        var parentPaneIDByDrawerID: [UUID: UUID] = [:]
        var parentPaneIDByChildPaneID: [UUID: UUID] = [:]
        for paneState in normalizedPaneStates.values {
            guard let drawer = paneState.drawer else { continue }
            guard drawer.parentPaneId == paneState.id else {
                return .failure(
                    .drawerParentMismatch(
                        drawerID: drawer.drawerId,
                        expectedParentPaneID: paneState.id,
                        actualParentPaneID: drawer.parentPaneId
                    )
                )
            }
            guard parentPaneIDByDrawerID.updateValue(paneState.id, forKey: drawer.drawerId) == nil else {
                return .failure(.duplicateDrawerIdentity(drawer.drawerId))
            }
            for childPaneID in drawer.paneIds {
                guard parentPaneIDByChildPaneID.updateValue(paneState.id, forKey: childPaneID) == nil else {
                    return .failure(.duplicateDrawerChildMembership(childPaneID))
                }
                guard let childPaneState = normalizedPaneStates[childPaneID],
                    let actualParentPaneID = childPaneState.parentPaneId
                else {
                    preconditionFailure("normalized drawer membership retained a missing pane")
                }
                guard actualParentPaneID == paneState.id else {
                    return .failure(
                        .drawerChildParentMismatch(
                            childPaneID: childPaneID,
                            expectedParentPaneID: paneState.id,
                            actualParentPaneID: actualParentPaneID
                        )
                    )
                }
            }
        }

        for paneState in normalizedPaneStates.values {
            guard let parentPaneID = paneState.parentPaneId else { continue }
            guard parentPaneIDByChildPaneID[paneState.id] == parentPaneID else {
                return .failure(
                    .orphanDrawerChild(
                        childPaneID: paneState.id,
                        parentPaneID: parentPaneID
                    )
                )
            }
        }

        return .success(Self(paneStates: normalizedPaneStates))
    }
}

@MainActor
@Observable
final class WorkspacePaneGraphAtom {
    private(set) var paneStates: [UUID: PaneGraphState] = [:]
    private var parentPaneIDByDrawerID: [UUID: UUID] = [:]

    var paneIds: Set<UUID> {
        Set(paneStates.keys)
    }

    var drawerIds: Set<UUID> {
        Set(paneStates.values.compactMap(\.drawer?.drawerId))
    }

    func paneState(_ id: UUID) -> PaneGraphState? {
        paneStates[id]
    }

    func parentPaneID(containingDrawer drawerID: UUID) -> UUID? {
        parentPaneIDByDrawerID[drawerID]
    }

    /// Durable graph membership only. Use `WorkspacePaneDerived` when callers
    /// need cwd/topology-resolved worktree membership.
    func paneStates(for worktreeId: UUID) -> [PaneGraphState] {
        paneStates.values.filter { $0.metadata.facets.worktreeId == worktreeId }
    }

    func replacePaneStates(_ replacement: WorkspacePaneGraphReplacement) {
        paneStates = replacement.paneStates
        parentPaneIDByDrawerID = Dictionary(
            uniqueKeysWithValues: replacement.paneStates.values.compactMap { paneState in
                paneState.drawer.map { ($0.drawerId, paneState.id) }
            }
        )
    }

    func addPane(_ pane: Pane) {
        setCanonicalPaneState(PaneGraphState(pane: pane))
    }

    @discardableResult
    func createPane(
        launchDirectory: URL? = nil,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> PaneGraphState {
        createPane(
            content: .terminal(TerminalState(provider: provider, lifetime: lifetime)),
            metadata: PaneMetadata(launchDirectory: launchDirectory, title: title, facets: facets),
            residency: residency
        )
    }

    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> PaneGraphState {
        let pane = Pane(content: content, metadata: metadata, residency: residency)
        let state = PaneGraphState(pane: pane)
        setCanonicalPaneState(state)
        return state
    }

    @discardableResult
    func insertRestoredPane(_ pane: Pane) -> Bool {
        guard paneStates[pane.id] == nil else { return false }
        setCanonicalPaneState(PaneGraphState(pane: pane))
        return true
    }

    @discardableResult
    func deletePaneAndOwnedDrawerChildren(_ paneId: UUID) -> Bool {
        guard paneStates[paneId] != nil else { return false }
        if let drawer = paneStates[paneId]?.drawer {
            for childId in drawer.paneIds {
                removeCanonicalPaneState(for: childId)
            }
        }
        removeCanonicalPaneState(for: paneId)
        return true
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneTitle: pane \(paneId) not found")
            return
        }
        paneStates[paneId]?.metadata.title = title
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneCWD: pane \(paneId) not found")
            return
        }
        guard paneStates[paneId]?.metadata.facets.cwd != cwd else { return }
        paneStates[paneId]?.metadata.facets.cwd = cwd
    }

    func updatePaneNote(_ paneId: UUID, note: String?) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneNote: pane \(paneId) not found")
            return
        }
        paneStates[paneId]?.metadata.updateNote(note)
    }

    func updatePaneCWDAndResolvedContext(
        _ paneId: UUID,
        cwd: URL?,
        resolvedContext: (repo: Repo, worktree: Worktree)?
    ) -> PaneCWDContextUpdateResult {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneCWDAndResolvedContext: pane \(paneId) not found")
            return .paneMissing
        }

        var facets = paneStates[paneId]!.metadata.facets
        facets.cwd = cwd
        if let resolvedContext {
            facets.repoId = resolvedContext.repo.id
            facets.worktreeId = resolvedContext.worktree.id
        } else {
            facets.repoId = nil
            facets.worktreeId = nil
        }

        guard facets != paneStates[paneId]!.metadata.facets else {
            return .unchanged
        }

        paneStates[paneId]?.metadata.facets = facets
        return .applied
    }

    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("updatePaneWebviewState: pane \(paneId) not found")
            return
        }
        paneStates[paneId]?.content = .webview(state)
    }

    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("syncPaneWebviewState: pane \(paneId) not found")
            return
        }
        paneStates[paneId]?.content = .webview(state)
    }

    @discardableResult
    func setTerminalZmxSessionId(_ paneId: UUID, sessionId: String) -> Bool {
        guard var paneState = paneStates[paneId] else {
            workspacePaneLogger.warning("setTerminalZmxSessionId: pane \(paneId) not found")
            return false
        }
        guard case .terminal(var terminalState) = paneState.content else {
            return false
        }
        guard terminalState.provider == .zmx else {
            return false
        }
        guard terminalState.zmxSessionId != sessionId else {
            return false
        }
        terminalState.zmxSessionId = sessionId
        paneState.content = .terminal(terminalState)
        paneStates[paneId] = paneState
        return true
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        guard paneStates[paneId] != nil else {
            workspacePaneLogger.warning("setResidency: pane \(paneId) not found")
            return
        }
        paneStates[paneId]?.residency = residency
    }

    func purgeOrphanedPane(_ paneId: UUID) {
        guard let pane = paneStates[paneId], pane.residency == .backgrounded else {
            workspacePaneLogger.warning("purgeOrphanedPane: pane \(paneId) is not backgrounded")
            return
        }
        removeCanonicalPaneState(for: paneId)
    }

    @discardableResult
    func addDrawerPane(
        to parentPaneId: UUID,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> PaneGraphState? {
        guard paneStates[parentPaneId] != nil else {
            workspacePaneLogger.warning("addDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }

        let drawerPane = Pane(
            content: content,
            metadata: metadata,
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
        let drawerState = PaneGraphState(pane: drawerPane)
        setCanonicalPaneState(drawerState)
        paneStates[parentPaneId]?.withDrawer { drawer in
            drawer.paneIds.append(drawerState.id)
        }
        return drawerState
    }

    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> PaneGraphState? {
        guard let parentPane = paneStates[parentPaneId], let drawer = parentPane.drawer else {
            workspacePaneLogger.warning("insertDrawerPane: parent pane \(parentPaneId) has no drawer")
            return nil
        }
        guard drawer.paneIds.contains(targetDrawerPaneId) else {
            workspacePaneLogger.warning("insertDrawerPane: target \(targetDrawerPaneId) not in drawer")
            return nil
        }

        return addDrawerPane(to: parentPaneId, content: content, metadata: metadata)
    }

    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        guard paneStates[parentPaneId]?.drawer != nil else {
            workspacePaneLogger.warning("removeDrawerPane: parent pane \(parentPaneId) has no drawer")
            return
        }

        paneStates[parentPaneId]?.withDrawer { drawer in
            drawer.paneIds.removeAll { $0 == drawerPaneId }
        }
        removeCanonicalPaneState(for: drawerPaneId)
    }

    @discardableResult
    func detachDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) -> PaneGraphState? {
        guard var drawerPane = paneStates[drawerPaneId], drawerPane.parentPaneId == parentPaneId else {
            workspacePaneLogger.warning(
                "detachDrawerPane: pane \(drawerPaneId) is not a child of \(parentPaneId)"
            )
            return nil
        }
        guard paneStates[parentPaneId]?.drawer != nil else {
            workspacePaneLogger.warning("detachDrawerPane: parent pane \(parentPaneId) has no drawer")
            return nil
        }

        paneStates[parentPaneId]?.withDrawer { drawer in
            drawer.paneIds.removeAll { $0 == drawerPaneId }
        }

        drawerPane.kind = .layout(drawer: DrawerGraphState(parentPaneId: drawerPaneId))
        paneStates[drawerPaneId] = drawerPane
        return drawerPane
    }

    @discardableResult
    func orphanPanes(forUnavailableWorktreePathsById unavailablePathByWorktreeId: [UUID: String]) -> [UUID] {
        let affectedPaneIds = paneStates.values
            .filter { state in
                guard let worktreeId = state.metadata.facets.worktreeId else { return false }
                return unavailablePathByWorktreeId[worktreeId] != nil
            }
            .map(\.id)

        guard !affectedPaneIds.isEmpty else { return [] }
        for paneId in affectedPaneIds {
            guard let worktreeId = paneStates[paneId]?.metadata.facets.worktreeId,
                let missingPath = unavailablePathByWorktreeId[worktreeId]
            else { continue }
            guard paneStates[paneId]?.residency.isPendingUndo != true else { continue }
            paneStates[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: missingPath))
        }
        return affectedPaneIds
    }

    @discardableResult
    func orphanPanesForWorktree(_ worktreeId: UUID, path: String) -> [UUID] {
        let affectedPaneIds = paneStates.values
            .filter { $0.metadata.facets.worktreeId == worktreeId }
            .filter { state in
                switch state.residency {
                case .active, .backgrounded:
                    return true
                case .pendingUndo, .orphaned:
                    return false
                }
            }
            .map(\.id)

        guard !affectedPaneIds.isEmpty else { return [] }
        for paneId in affectedPaneIds {
            paneStates[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: path))
        }
        return affectedPaneIds
    }

    @discardableResult
    func restoreOrphanedPaneResidency(
        forWorktreeIds worktreeIds: Set<UUID>,
        activeLayoutPaneIds: Set<UUID>
    ) -> Bool {
        var didRestore = false
        for paneId in paneStates.keys {
            guard let worktreeId = paneStates[paneId]?.metadata.facets.worktreeId else { continue }
            guard worktreeIds.contains(worktreeId) else { continue }
            guard paneStates[paneId]?.residency.isOrphaned == true else { continue }
            paneStates[paneId]?.residency = activeLayoutPaneIds.contains(paneId) ? .active : .backgrounded
            didRestore = true
        }
        return didRestore
    }

    @discardableResult
    func restoreDrawerPane(_ drawerPane: Pane, to parentPaneId: UUID) -> Bool {
        guard paneStates[parentPaneId] != nil else {
            workspacePaneLogger.warning("restoreDrawerPane: parent pane \(parentPaneId) not found")
            return false
        }
        guard paneStates[parentPaneId]?.drawer != nil else {
            workspacePaneLogger.warning("restoreDrawerPane: parent pane \(parentPaneId) has no drawer")
            return false
        }

        var restoredPane = drawerPane
        restoredPane.kind = .drawerChild(parentPaneId: parentPaneId)
        setCanonicalPaneState(PaneGraphState(pane: restoredPane))
        paneStates[parentPaneId]?.withDrawer { drawer in
            drawer.paneIds.removeAll { $0 == restoredPane.id }
            drawer.paneIds.append(restoredPane.id)
        }
        return true
    }

    func setCanonicalPaneState(_ state: PaneGraphState) {
        let previousDrawerID = paneStates[state.id]?.drawer?.drawerId
        let nextDrawerID = state.drawer?.drawerId
        if let nextDrawerID {
            precondition(
                parentPaneIDByDrawerID[nextDrawerID].map { $0 == state.id } ?? true,
                "drawer identity must have one parent pane owner"
            )
        }
        paneStates[state.id] = state
        if let previousDrawerID, previousDrawerID != nextDrawerID {
            parentPaneIDByDrawerID.removeValue(forKey: previousDrawerID)
        }
        if let nextDrawerID {
            parentPaneIDByDrawerID[nextDrawerID] = state.id
        }
    }

    @discardableResult
    func removeCanonicalPaneState(for paneID: UUID) -> PaneGraphState? {
        guard let removedState = paneStates.removeValue(forKey: paneID) else { return nil }
        if let drawerID = removedState.drawer?.drawerId {
            parentPaneIDByDrawerID.removeValue(forKey: drawerID)
        }
        return removedState
    }
}
