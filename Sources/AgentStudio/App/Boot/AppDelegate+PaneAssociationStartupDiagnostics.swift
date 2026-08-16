import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import AppKit
import Foundation

#if DEBUG
    private struct PaneAssociationRuntimeProofFixture {
        let root: URL
        let firstRepositoryRoot: URL
        let secondRepositoryRoot: URL
        let freePaneRoot: URL
    }

    private struct PaneAssociationRuntimeProofResult {
        let initialAssociationSucceeded: Bool
        let cwdMoveSucceeded: Bool
        let topologyClearSucceeded: Bool
        let topologyOrphanSucceeded: Bool
        let topologyAdoptSucceeded: Bool
        let freePaneRemainedNil: Bool

        var succeeded: Bool {
            initialAssociationSucceeded && cwdMoveSucceeded
                && topologyClearSucceeded && topologyOrphanSucceeded
                && topologyAdoptSucceeded && freePaneRemainedNil
        }
    }

    @MainActor
    extension AppDelegate {
        func runPaneAssociationRuntimeProofDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()
            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordPaneAssociationProofBlocked(action: action, reason: "missing_bounds")
                return
            }
            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "paneAssociationRuntimeProofPreflight"
                )
            }

            let fixture: PaneAssociationRuntimeProofFixture
            do {
                fixture = try makePaneAssociationRuntimeProofFixture()
            } catch {
                recordPaneAssociationProofBlocked(action: action, reason: "fixture_creation_failed")
                return
            }
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            let firstRepository = store.mutationCoordinator.addRepo(at: fixture.firstRepositoryRoot)
            let secondRepository = store.mutationCoordinator.addRepo(at: fixture.secondRepositoryRoot)
            guard
                let firstWorktree = firstRepository.worktrees.first,
                let secondWorktree = secondRepository.worktrees.first,
                let associatedPane = workspaceSurfaceCoordinator.openFloatingTerminal(
                    launchDirectory: firstWorktree.path,
                    title: "Pane Association Runtime Proof"
                ),
                let freePane = workspaceSurfaceCoordinator.openFloatingTerminal(
                    launchDirectory: fixture.freePaneRoot,
                    title: "Free Pane Association Runtime Proof"
                )
            else {
                recordPaneAssociationProofBlocked(action: action, reason: "terminal_fixture_failed")
                return
            }

            let initialAssociationSucceeded = paneAssociationMatches(
                associatedPane.id,
                repoId: firstRepository.id,
                worktreeId: firstWorktree.id,
                cwd: firstWorktree.path
            )
            guard
                case .success = await workspaceSurfaceCoordinator.dispatchRuntimeCommand(
                    .terminal(.sendInput("cd \(secondWorktree.path.path)\n")),
                    target: .pane(PaneId(existingUUID: associatedPane.id))
                )
            else {
                recordPaneAssociationProofBlocked(action: action, reason: "terminal_cwd_command_failed")
                return
            }
            let cwdMoveSucceeded = await waitForPaneAssociation(
                associatedPane.id,
                repoId: secondRepository.id,
                worktreeId: secondWorktree.id,
                cwd: secondWorktree.path
            )

            workspaceCacheCoordinator.handleRepoRemoval(repoId: secondRepository.id)
            let topologyClearSucceeded = paneAssociationMatches(
                associatedPane.id,
                repoId: nil,
                worktreeId: nil,
                cwd: secondWorktree.path
            )
            let topologyOrphanSucceeded =
                store.paneAtom.pane(associatedPane.id)?.residency
                == .orphaned(reason: .worktreeNotFound(path: secondWorktree.path.path))

            guard
                let topologyAdoptSucceeded = adoptPaneAssociationAfterTopologyReadd(
                    paneId: associatedPane.id,
                    repositoryRoot: fixture.secondRepositoryRoot
                )
            else {
                recordPaneAssociationProofBlocked(action: action, reason: "topology_readoption_failed")
                return
            }
            let freePaneRemainedNil = paneAssociationMatches(
                freePane.id,
                repoId: nil,
                worktreeId: nil,
                cwd: fixture.freePaneRoot
            )
            recordPaneAssociationProofResult(
                action: action,
                result: PaneAssociationRuntimeProofResult(
                    initialAssociationSucceeded: initialAssociationSucceeded,
                    cwdMoveSucceeded: cwdMoveSucceeded,
                    topologyClearSucceeded: topologyClearSucceeded,
                    topologyOrphanSucceeded: topologyOrphanSucceeded,
                    topologyAdoptSucceeded: topologyAdoptSucceeded,
                    freePaneRemainedNil: freePaneRemainedNil
                )
            )
        }

        private func makePaneAssociationRuntimeProofFixture() throws
            -> PaneAssociationRuntimeProofFixture
        {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "agentstudio-pane-association-proof-\(UUIDv7.generate().uuidString)"
            )
            let fixture = PaneAssociationRuntimeProofFixture(
                root: root,
                firstRepositoryRoot: root.appending(path: "first"),
                secondRepositoryRoot: root.appending(path: "second"),
                freePaneRoot: root.appending(path: "free")
            )
            for directory in [
                fixture.firstRepositoryRoot,
                fixture.secondRepositoryRoot,
                fixture.freePaneRoot,
            ] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return fixture
        }

        private func adoptPaneAssociationAfterTopologyReadd(
            paneId: UUID,
            repositoryRoot: URL
        ) -> Bool? {
            let repository = store.mutationCoordinator.addRepo(at: repositoryRoot)
            guard let worktree = repository.worktrees.first else { return nil }
            workspaceSurfaceCoordinator.topologyDidChange(
                WorktreeTopologyDelta(
                    repoId: repository.id,
                    addedWorktreeIds: [worktree.id],
                    removedWorktrees: [],
                    preservedWorktreeIds: [],
                    didChange: true,
                    traceId: nil
                )
            )
            return paneAssociationMatches(
                paneId,
                repoId: repository.id,
                worktreeId: worktree.id,
                cwd: worktree.path
            )
        }

        private func recordPaneAssociationProofResult(
            action: AgentStudioStartupDiagnosticAction,
            result: PaneAssociationRuntimeProofResult
        ) {
            let attributes = startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.created_pane.count": .int(2),
                "agentstudio.startup_diagnostic.association.initial_succeeded": .bool(
                    result.initialAssociationSucceeded
                ),
                "agentstudio.startup_diagnostic.association.cwd_move_succeeded": .bool(result.cwdMoveSucceeded),
                "agentstudio.startup_diagnostic.association.topology_clear_succeeded": .bool(
                    result.topologyClearSucceeded
                ),
                "agentstudio.startup_diagnostic.association.topology_orphan_succeeded": .bool(
                    result.topologyOrphanSucceeded
                ),
                "agentstudio.startup_diagnostic.association.topology_adopt_succeeded": .bool(
                    result.topologyAdoptSucceeded
                ),
                "agentstudio.startup_diagnostic.association.free_pane_remained_nil": .bool(result.freePaneRemainedNil),
                "agentstudio.startup_diagnostic.association_proof.succeeded": .bool(result.succeeded),
            ]) { _, newValue in newValue }
            let outcome = result.succeeded ? "succeeded" : "blocked"
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
            startupTraceRecorder.recordAppStartup(
                result.succeeded ? "app.startup_diagnostic_action.completed" : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: attributes
            )
        }

        private func waitForPaneAssociation(
            _ paneId: UUID,
            repoId: UUID?,
            worktreeId: UUID?,
            cwd: URL?
        ) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: AppPolicies.StartupDiagnostic.appActivationTimeout)
            repeat {
                if paneAssociationMatches(paneId, repoId: repoId, worktreeId: worktreeId, cwd: cwd) {
                    return true
                }
                await Task.yield()
            } while clock.now < deadline
            return false
        }

        private func paneAssociationMatches(
            _ paneId: UUID,
            repoId: UUID?,
            worktreeId: UUID?,
            cwd: URL?
        ) -> Bool {
            guard let facets = store.paneAtom.graphAtom.paneState(paneId)?.durableContextFacets else {
                return false
            }
            return facets.repoId == repoId
                && facets.worktreeId == worktreeId
                && facets.cwd?.standardizedFileURL == cwd?.standardizedFileURL
        }

        private func recordPaneAssociationProofBlocked(
            action: AgentStudioStartupDiagnosticAction,
            reason: String
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: "blocked",
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.skip_reason": .string(reason)
                ]) { _, newValue in newValue }
            )
        }
    }
#endif
