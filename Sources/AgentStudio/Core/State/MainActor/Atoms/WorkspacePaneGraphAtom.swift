import AgentStudioInfrastructure
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
    var cwd: URL?

    init(cwd: URL? = nil) {
        self.cwd = cwd
    }

    init(contextFacets: PaneContextFacets) {
        self.init(cwd: contextFacets.cwd)
    }

    var paneContextFacets: PaneContextFacets {
        PaneContextFacets(cwd: cwd)
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
package struct PaneGraphState: Identifiable, Hashable, Sendable {
    package let id: UUID
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

    package var isDrawerChild: Bool {
        if case .drawerChild = kind { return true }
        return false
    }

    package var paneContent: PaneContent {
        content
    }

    package var durableContextFacets: PaneContextFacets {
        metadata.facets.paneContextFacets
    }

    package var parentPaneId: UUID? {
        if case .drawerChild(let parentPaneId) = kind { return parentPaneId }
        return nil
    }

    package var ownedDrawerId: UUID? {
        drawer?.drawerId
    }

    package func ownsDrawerChild(_ paneId: UUID) -> Bool {
        drawer?.paneIds.contains(paneId) == true
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

package enum WorkspacePaneGraphReplacementRejection: Error, Equatable, Sendable {
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

package enum BridgePaneStateMutationResult: Equatable, Sendable {
    case applied(BridgePaneState)
    case unchanged(BridgePaneState)
    case paneMissing
    case notBridgePane
    case notWorkspaceSource
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
package final class WorkspacePaneGraphAtom {
    @ObservationIgnored private let paneStateMap = AtomEntityMap<UUID, PaneGraphState>(
        telemetryLabel: "pane_graph_canonical",
        isContentEqual: ==
    )
    @ObservationIgnored private let paneStructuralFactsMap = AtomEntityMap<UUID, PaneStructuralFacts>(
        telemetryLabel: "pane_graph_structural",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()
    private var parentPaneIDByDrawerID: [UUID: UUID] = [:]

    package init() {}

    package var paneIDs: Set<UUID> {
        _ = paneStateMap.membershipRevision.value
        return paneStateMap.membershipKeys()
    }

    package var paneAcceptedCommitRevision: Int {
        acceptedCommitRevision.value
    }

    var drawerIds: Set<UUID> {
        Set(paneStructuralFactsMap.snapshot().values.compactMap(\.ownedDrawerID))
    }

    package func paneState(_ id: UUID) -> PaneGraphState? {
        paneStateMap.value(for: id)
    }

    package func paneStructuralFacts(_ id: UUID) -> PaneStructuralFacts? {
        paneStructuralFactsMap.value(for: id)
    }

    package func paneStateSnapshot() -> [UUID: PaneGraphState] {
        paneStateMap.snapshot()
    }

    func parentPaneID(containingDrawer drawerID: UUID) -> UUID? {
        parentPaneIDByDrawerID[drawerID]
    }

    func replacePaneStates(_ replacement: WorkspacePaneGraphReplacement) {
        let previousPaneStates = paneStateMap.snapshot()
        commitPaneStates(
            previousPaneStates: previousPaneStates,
            nextPaneStates: replacement.paneStates,
            pruneNilSlotsAfterCommit: true
        )
    }

    func addPane(_ pane: Pane) {
        mutatePaneStates { paneStates in
            paneStates[pane.id] = PaneGraphState(pane: pane)
        }
    }

    @discardableResult
    func createPane(
        launchDirectory: URL? = nil,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        zmxSessionID: ZmxSessionID,
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> PaneGraphState {
        let admittedCWD =
            [facets.cwd, launchDirectory, FileManager.default.homeDirectoryForCurrentUser]
            .compactMap { candidate -> URL? in
                guard case .accepted(let cwd) = PaneFilesystemLocationPolicy.runtimeCWDUpdate(candidate) else {
                    return nil
                }
                return cwd
            }
            .first ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var admittedFacets = facets
        admittedFacets.cwd = admittedCWD
        let pane = Pane(
            content: .terminal(
                TerminalState(provider: provider, lifetime: lifetime, zmxSessionID: zmxSessionID)
            ),
            metadata: PaneMetadata(
                launchDirectory: admittedCWD,
                title: title,
                facets: admittedFacets
            ),
            residency: residency
        )
        let state = PaneGraphState(pane: pane)
        mutatePaneStates { paneStates in
            paneStates[state.id] = state
        }
        return state
    }

    private func admittedMetadata(
        for content: PaneContent,
        metadata: PaneMetadata
    ) -> PaneMetadata? {
        var admittedMetadata = metadata
        switch PaneFilesystemLocationPolicy.resolveRestoredCWD(
            for: content,
            cwd: metadata.cwd,
            launchDirectory: metadata.launchDirectory
        ) {
        case .valid(let cwd):
            admittedMetadata.updateCWD(cwd)
            return admittedMetadata
        case .repaired(let cwd):
            admittedMetadata.updateCWD(cwd)
            return admittedMetadata
        case .degradedRequired:
            workspacePaneLogger.warning("pane admission: required content has no trustworthy filesystem location")
            return nil
        }
    }

    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> PaneGraphState? {
        guard let admittedMetadata = admittedMetadata(for: content, metadata: metadata) else { return nil }

        let pane = Pane(content: content, metadata: admittedMetadata, residency: residency)
        let state = PaneGraphState(pane: pane)
        mutatePaneStates { paneStates in
            paneStates[state.id] = state
        }
        return state
    }

    @discardableResult
    func insertRestoredPane(_ pane: Pane) -> Bool {
        guard paneStateMap.snapshotValue(for: pane.id) == nil else { return false }
        mutatePaneStates { paneStates in
            paneStates[pane.id] = PaneGraphState(pane: pane)
        }
        return true
    }

    @discardableResult
    func deletePaneAndOwnedDrawerChildren(_ paneId: UUID) -> Bool {
        guard let paneState = paneStateMap.snapshotValue(for: paneId) else { return false }
        mutatePaneStates(pruneNilSlotsAfterCommit: true) { paneStates in
            if let drawer = paneState.drawer {
                for childId in drawer.paneIds {
                    paneStates.removeValue(forKey: childId)
                }
            }
            paneStates.removeValue(forKey: paneId)
        }
        return true
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        guard let currentState = paneStateMap.snapshotValue(for: paneId) else {
            workspacePaneLogger.warning("updatePaneTitle: pane \(paneId) not found")
            return
        }
        guard currentState.metadata.title != title else { return }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.metadata.title = title
        }
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        guard let currentState = paneStateMap.snapshotValue(for: paneId) else {
            workspacePaneLogger.warning("updatePaneCWD: pane \(paneId) not found")
            return
        }
        guard currentState.metadata.facets.cwd != cwd else { return }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.metadata.facets.cwd = cwd
        }
    }

    func updatePaneNote(_ paneId: UUID, note: String?) {
        guard paneStateMap.snapshotValue(for: paneId) != nil else {
            workspacePaneLogger.warning("updatePaneNote: pane \(paneId) not found")
            return
        }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.metadata.updateNote(note)
        }
    }

    func updatePaneCWDAndResolvedContext(
        _ paneId: UUID,
        cwd: URL?,
        resolvedContext _: (repo: Repo, worktree: Worktree)?
    ) -> PaneCWDContextUpdateResult {
        guard let currentState = paneStateMap.snapshotValue(for: paneId) else {
            workspacePaneLogger.warning("updatePaneCWDAndResolvedContext: pane \(paneId) not found")
            return .paneMissing
        }
        guard case .accepted(let acceptedCWD) = PaneFilesystemLocationPolicy.runtimeCWDUpdate(cwd) else {
            return .unchanged
        }

        var facets = currentState.metadata.facets
        facets.cwd = acceptedCWD

        guard facets != currentState.metadata.facets else {
            return .unchanged
        }

        mutatePaneStates { paneStates in
            paneStates[paneId]?.metadata.facets = facets
        }
        return .applied
    }

    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard paneStateMap.snapshotValue(for: paneId) != nil else {
            workspacePaneLogger.warning("updatePaneWebviewState: pane \(paneId) not found")
            return
        }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.content = .webview(state)
        }
    }

    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        guard let paneState = paneStateMap.snapshotValue(for: paneId) else {
            workspacePaneLogger.warning("syncPaneWebviewState: pane \(paneId) not found")
            return
        }
        guard paneState.content != .webview(state) else { return }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.content = .webview(state)
        }
    }

    @discardableResult
    package func updateBridgePaneState(
        _ paneId: UUID,
        state: BridgePaneState
    ) -> BridgePaneStateMutationResult {
        mutatePaneStates { paneStates in
            guard let paneState = paneStates[paneId] else {
                return .paneMissing
            }
            guard case .bridgePanel(let currentState) = paneState.content else {
                return .notBridgePane
            }
            guard currentState != state else {
                return .unchanged(currentState)
            }
            paneStates[paneId]?.content = .bridgePanel(state)
            return .applied(state)
        }
    }

    @discardableResult
    package func setInitialBridgeContributionTargetIfAbsent(
        _ paneId: UUID,
        target: WorkspaceReviewContributionTarget
    ) -> BridgePaneStateMutationResult {
        mutatePaneStates { paneStates in
            guard let paneState = paneStates[paneId] else {
                return .paneMissing
            }
            guard case .bridgePanel(let currentState) = paneState.content else {
                return .notBridgePane
            }
            guard case .workspace(let rootPath, let baseline) = currentState.source else {
                return .notWorkspaceSource
            }
            guard baseline == nil else {
                return .unchanged(currentState)
            }

            let updatedState = BridgePaneState(
                panelKind: currentState.panelKind,
                source: .workspace(
                    rootPath: rootPath,
                    baseline: WorkspaceBaseline(contributionTarget: target)
                )
            )
            paneStates[paneId]?.content = .bridgePanel(updatedState)
            return .applied(updatedState)
        }
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        guard paneStateMap.snapshotValue(for: paneId) != nil else {
            workspacePaneLogger.warning("setResidency: pane \(paneId) not found")
            return
        }
        mutatePaneStates { paneStates in
            paneStates[paneId]?.residency = residency
        }
    }

    func purgeOrphanedPane(_ paneId: UUID) {
        guard let pane = paneStateMap.snapshotValue(for: paneId), pane.residency == .backgrounded else {
            workspacePaneLogger.warning("purgeOrphanedPane: pane \(paneId) is not backgrounded")
            return
        }
        _ = mutatePaneStates(pruneNilSlotsAfterCommit: true) { paneStates in
            paneStates.removeValue(forKey: paneId)
        }
    }

    @discardableResult
    func addDrawerPane(
        to parentPaneId: UUID,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> PaneGraphState? {
        guard paneStateMap.snapshotValue(for: parentPaneId) != nil else {
            workspacePaneLogger.warning("addDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }
        guard let admittedMetadata = admittedMetadata(for: content, metadata: metadata) else { return nil }

        let drawerPane = Pane(
            id: UUIDv7.generate(),
            content: content,
            metadata: admittedMetadata,
            residency: .active,
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
        let drawerState = PaneGraphState(pane: drawerPane)
        mutatePaneStates { paneStates in
            paneStates[drawerState.id] = drawerState
            paneStates[parentPaneId]?.withDrawer { drawer in
                drawer.paneIds.append(drawerState.id)
            }
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
        guard let parentPane = paneStateMap.snapshotValue(for: parentPaneId), let drawer = parentPane.drawer else {
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
        guard paneStateMap.snapshotValue(for: parentPaneId)?.drawer != nil else {
            workspacePaneLogger.warning("removeDrawerPane: parent pane \(parentPaneId) has no drawer")
            return
        }

        mutatePaneStates(pruneNilSlotsAfterCommit: true) { paneStates in
            paneStates[parentPaneId]?.withDrawer { drawer in
                drawer.paneIds.removeAll { $0 == drawerPaneId }
            }
            paneStates.removeValue(forKey: drawerPaneId)
        }
    }

    @discardableResult
    func detachDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) -> PaneGraphState? {
        guard var drawerPane = paneStateMap.snapshotValue(for: drawerPaneId),
            drawerPane.parentPaneId == parentPaneId
        else {
            workspacePaneLogger.warning(
                "detachDrawerPane: pane \(drawerPaneId) is not a child of \(parentPaneId)"
            )
            return nil
        }
        guard paneStateMap.snapshotValue(for: parentPaneId)?.drawer != nil else {
            workspacePaneLogger.warning("detachDrawerPane: parent pane \(parentPaneId) has no drawer")
            return nil
        }

        drawerPane.kind = .layout(drawer: DrawerGraphState(parentPaneId: drawerPaneId))
        mutatePaneStates { paneStates in
            paneStates[parentPaneId]?.withDrawer { drawer in
                drawer.paneIds.removeAll { $0 == drawerPaneId }
            }
            paneStates[drawerPaneId] = drawerPane
        }
        return drawerPane
    }

    @discardableResult
    func orphanPanes(forUnavailableWorktreePathsById unavailablePathByWorktreeId: [UUID: String]) -> [UUID] {
        let unavailablePaths = unavailablePathByWorktreeId.values.sorted { $0.count > $1.count }
        let paneStates = paneStateMap.snapshot()
        let affectedPaneIds = paneStates.values.compactMap { state -> (UUID, String)? in
            guard let cwd = state.metadata.facets.cwd?.standardizedFileURL.path else { return nil }
            guard let path = unavailablePaths.first(where: { pathContains($0, cwd: cwd) }) else { return nil }
            return (state.id, path)
        }

        guard !affectedPaneIds.isEmpty else { return [] }
        mutatePaneStates { paneStates in
            for (paneId, missingPath) in affectedPaneIds {
                guard paneStates[paneId]?.residency.isPendingUndo != true else { continue }
                paneStates[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: missingPath))
            }
        }
        return affectedPaneIds.map(\.0)
    }

    @discardableResult
    func orphanPanesForWorktree(_: UUID, path: String) -> [UUID] {
        let normalizedPath = URL(filePath: path).standardizedFileURL.path
        let affectedPaneIds = paneStateMap.snapshot().values
            .filter { state in
                guard let cwd = state.metadata.facets.cwd?.standardizedFileURL.path else { return false }
                return pathContains(normalizedPath, cwd: cwd)
            }
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
        mutatePaneStates { paneStates in
            for paneId in affectedPaneIds {
                paneStates[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: path))
            }
        }
        return affectedPaneIds
    }

    @discardableResult
    func restoreOrphanedPaneResidency(
        forPaneIds paneIds: Set<UUID>,
        activeLayoutPaneIds: Set<UUID>
    ) -> Bool {
        var didRestore = false
        mutatePaneStates { paneStates in
            for paneId in paneIds {
                guard paneStates[paneId]?.residency.isOrphaned == true else { continue }
                paneStates[paneId]?.residency =
                    activeLayoutPaneIds.contains(paneId) ? .active : .backgrounded
                didRestore = true
            }
        }
        return didRestore
    }

    private func pathContains(_ root: String, cwd: String) -> Bool {
        cwd == root || cwd.hasPrefix(root + "/")
    }

    @discardableResult
    func restoreDrawerPane(_ drawerPane: Pane, to parentPaneId: UUID) -> Bool {
        guard paneStateMap.snapshotValue(for: parentPaneId) != nil else {
            workspacePaneLogger.warning("restoreDrawerPane: parent pane \(parentPaneId) not found")
            return false
        }
        guard paneStateMap.snapshotValue(for: parentPaneId)?.drawer != nil else {
            workspacePaneLogger.warning("restoreDrawerPane: parent pane \(parentPaneId) has no drawer")
            return false
        }

        var restoredPane = drawerPane
        restoredPane.kind = .drawerChild(parentPaneId: parentPaneId)
        mutatePaneStates { paneStates in
            paneStates[restoredPane.id] = PaneGraphState(pane: restoredPane)
            paneStates[parentPaneId]?.withDrawer { drawer in
                drawer.paneIds.removeAll { $0 == restoredPane.id }
                drawer.paneIds.append(restoredPane.id)
            }
        }
        return true
    }

    private func mutatePaneStates<TMutationResult>(
        pruneNilSlotsAfterCommit: Bool = false,
        _ transform: (inout [UUID: PaneGraphState]) -> TMutationResult
    ) -> TMutationResult {
        let previousPaneStates = paneStateMap.snapshot()
        var nextPaneStates = previousPaneStates
        let result = transform(&nextPaneStates)
        commitPaneStates(
            previousPaneStates: previousPaneStates,
            nextPaneStates: nextPaneStates,
            pruneNilSlotsAfterCommit: pruneNilSlotsAfterCommit
        )
        return result
    }

    private func commitPaneStates(
        previousPaneStates: [UUID: PaneGraphState],
        nextPaneStates: [UUID: PaneGraphState],
        pruneNilSlotsAfterCommit: Bool
    ) {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        let previousPaneIDs = Set(previousPaneStates.keys)
        let nextPaneIDs = Set(nextPaneStates.keys)

        for removedPaneID in previousPaneIDs.subtracting(nextPaneIDs) {
            paneStateMap.removeValue(for: removedPaneID, mutation: mutation)
            paneStructuralFactsMap.removeValue(for: removedPaneID, mutation: mutation)
        }
        for (paneID, nextPaneState) in nextPaneStates where previousPaneStates[paneID] != nextPaneState {
            paneStateMap.setValue(nextPaneState, for: paneID, mutation: mutation)
            paneStructuralFactsMap.setValue(
                PaneStructuralFacts(state: nextPaneState),
                for: paneID,
                mutation: mutation
            )
        }

        let nextParentPaneIDByDrawerID = Dictionary(
            uniqueKeysWithValues: nextPaneStates.values.compactMap { paneState in
                paneState.drawer.map { ($0.drawerId, paneState.id) }
            }
        )
        if parentPaneIDByDrawerID != nextParentPaneIDByDrawerID {
            parentPaneIDByDrawerID = nextParentPaneIDByDrawerID
        }
        mutation.commit()

        if pruneNilSlotsAfterCommit {
            paneStateMap.pruneNilSlots(excluding: nextPaneIDs)
            paneStructuralFactsMap.pruneNilSlots(excluding: nextPaneIDs)
        }

        precondition(Set(paneStateMap.snapshot().keys) == nextPaneIDs)
        precondition(Set(paneStructuralFactsMap.snapshot().keys) == nextPaneIDs)
        precondition(
            nextPaneStates.allSatisfy { paneID, paneState in
                paneStructuralFactsMap.snapshotValue(for: paneID) == PaneStructuralFacts(state: paneState)
            }
        )
    }
}
