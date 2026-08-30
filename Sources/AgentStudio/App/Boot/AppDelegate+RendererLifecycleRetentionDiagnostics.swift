import AgentStudioCore
import AgentStudioTerminal
import Foundation

#if DEBUG
    private final class RendererLifecycleWeakSurfaceReference {
        weak var surface: Ghostty.SurfaceView?

        init(_ surface: Ghostty.SurfaceView) {
            self.surface = surface
        }
    }

    private struct RendererLifecycleExpiryEntry {
        let paneID: UUID
        let priorSurfaceID: UUID
        let sessionID: ZmxSessionID
        let closeInstant: ContinuousClock.Instant
        let weakSurface: RendererLifecycleWeakSurfaceReference
    }

    private struct RendererLifecycleExpiryBaseline {
        let closeUndo: Int
        let permanentRelease: Int
        let deinitializedFree: Int
        let managerOwned: Int
    }

    @MainActor
    extension AppDelegate {
        func exerciseRendererLifecycleCloseRetention(
            _ fixture: RendererLifecycleContinuityFixture,
            expectedSessionID: ZmxSessionID?
        ) async -> (succeeded: Bool, reason: String) {
            guard let expectedSessionID,
                let immediateSurfaceID = viewRegistry.terminalView(for: fixture.retentionPaneID)?.surfaceId
            else { return (false, "retention_identity_missing") }
            let initialSnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard executor.execute(.closePane(tabId: fixture.firstTabID, paneId: fixture.retentionPaneID)) else {
                return (false, "immediate_close_rejected")
            }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(10),
                    {
                        self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                            == initialSnapshot.closeUndoCurrent + 1
                    })
            else { return (false, "immediate_close_not_retained") }
            executor.undoCloseTab()
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        self.viewRegistry.terminalView(for: fixture.retentionPaneID)?.surfaceId
                            == immediateSurfaceID
                            && self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                                == initialSnapshot.closeUndoCurrent
                    })
            else { return (false, "immediate_undo_did_not_reuse_surface") }
            guard
                rendererLifecycleSessionIDs(for: [fixture.retentionPaneID])[fixture.retentionPaneID]
                    == expectedSessionID
            else { return (false, "immediate_undo_session_changed") }

            guard let expiringSurfaceID = viewRegistry.terminalView(for: fixture.retentionPaneID)?.surfaceId else {
                return (false, "expiry_surface_missing")
            }
            let expiryBaseline = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard executor.execute(.closePane(tabId: fixture.firstTabID, paneId: fixture.retentionPaneID)) else {
                return (false, "expiry_close_rejected")
            }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(10),
                    {
                        self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                            == expiryBaseline.closeUndoCurrent + 1
                    })
            else { return (false, "expiry_close_not_retained") }
            do {
                try await Task.sleep(nanoseconds: Duration.seconds(299).nanosecondsForTaskSleep)
            } catch {
                return (false, "expiry_wait_cancelled")
            }
            let preExpirySnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard preExpirySnapshot.closeUndoCurrent == expiryBaseline.closeUndoCurrent + 1,
                preExpirySnapshot.permanentReleaseTotal == expiryBaseline.permanentReleaseTotal,
                preExpirySnapshot.deinitializedFreeTotal == expiryBaseline.deinitializedFreeTotal
            else { return (false, "retention_expired_before_300_seconds") }
            do {
                try await Task.sleep(nanoseconds: Duration.seconds(2).nanosecondsForTaskSleep)
            } catch {
                return (false, "expiry_boundary_wait_cancelled")
            }
            executor.undoCloseTab()
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        guard
                            let restoredSurfaceID = self.viewRegistry.terminalView(for: fixture.retentionPaneID)?
                                .surfaceId
                        else { return false }
                        let snapshot = self.performanceTraceRecorder.rendererLifecycleSnapshot()
                        return restoredSurfaceID != expiringSurfaceID
                            && snapshot.closeUndoCurrent == expiryBaseline.closeUndoCurrent
                            && snapshot.permanentReleaseTotal == expiryBaseline.permanentReleaseTotal + 1
                            && snapshot.deinitializedFreeTotal == expiryBaseline.deinitializedFreeTotal + 1
                            && snapshot.managerOwnedCurrent == fixture.paneIDs.count
                            && snapshot.orphanCandidateCurrent == 0
                    })
            else { return (false, "post_expiry_undo_did_not_create_surface") }
            guard
                rendererLifecycleSessionIDs(for: [fixture.retentionPaneID])[fixture.retentionPaneID]
                    == expectedSessionID
            else { return (false, "post_expiry_undo_session_changed") }
            return (true, "none")
        }

        func exerciseRendererLifecycleImmediateUndoCycles(
            _ fixture: RendererLifecycleContinuityFixture,
            expectedSessionID: ZmxSessionID?,
            count: Int
        ) async -> (succeeded: Bool, reason: String) {
            guard let expectedSessionID else { return (false, "immediate_undo_session_missing") }
            for _ in 0..<count {
                guard let surfaceID = viewRegistry.terminalView(for: fixture.retentionPaneID)?.surfaceId else {
                    return (false, "immediate_undo_surface_missing")
                }
                let baseline = performanceTraceRecorder.rendererLifecycleSnapshot()
                guard executor.execute(.closePane(tabId: fixture.firstTabID, paneId: fixture.retentionPaneID)) else {
                    return (false, "immediate_undo_close_rejected")
                }
                guard
                    await waitForRendererLifecycleCondition(
                        timeout: .seconds(10),
                        {
                            self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                                == baseline.closeUndoCurrent + 1
                        })
                else { return (false, "immediate_undo_not_retained") }
                executor.undoCloseTab()
                guard
                    await waitForRendererLifecycleCondition(
                        timeout: .seconds(20),
                        {
                            self.viewRegistry.terminalView(for: fixture.retentionPaneID)?.surfaceId == surfaceID
                                && self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                                    == baseline.closeUndoCurrent
                        })
                else { return (false, "immediate_undo_surface_changed") }
                guard
                    rendererLifecycleSessionIDs(for: [fixture.retentionPaneID])[fixture.retentionPaneID]
                        == expectedSessionID
                else { return (false, "immediate_undo_session_changed") }
            }
            return (true, "none")
        }

        func exerciseRendererLifecycleExpiryCohort(
            _ fixture: RendererLifecycleContinuityFixture,
            expectedSessionIDs: [UUID: ZmxSessionID]
        ) async -> (succeeded: Bool, reason: String) {
            guard fixture.expiryPaneIDs.count == RendererLifecycleSoakSchedule.expiryCount else {
                return (false, "expiry_candidate_count_invalid")
            }
            let initialSnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            let clock = ContinuousClock()
            var entries: [RendererLifecycleExpiryEntry] = []
            for paneID in fixture.expiryPaneIDs {
                guard let tabID = store.tabLayoutAtom.tabContaining(paneId: paneID)?.id,
                    let surfaceID = viewRegistry.terminalView(for: paneID)?.surfaceId,
                    let surface = viewRegistry.terminalView(for: paneID)?.ghosttySurface,
                    let sessionID = expectedSessionIDs[paneID]
                else { return (false, "expiry_candidate_identity_missing") }
                guard executor.execute(.closePane(tabId: tabID, paneId: paneID)) else {
                    return (false, "expiry_close_rejected")
                }
                let closeInstant = clock.now
                entries.append(
                    RendererLifecycleExpiryEntry(
                        paneID: paneID,
                        priorSurfaceID: surfaceID,
                        sessionID: sessionID,
                        closeInstant: closeInstant,
                        weakSurface: RendererLifecycleWeakSurfaceReference(surface)
                    ))
            }
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        self.performanceTraceRecorder.rendererLifecycleSnapshot().closeUndoCurrent
                            == initialSnapshot.closeUndoCurrent + entries.count
                    })
            else { return (false, "expiry_cohort_not_retained") }

            for entry in entries {
                let target = entry.closeInstant.advanced(by: .seconds(299))
                let remaining = clock.now.duration(to: target)
                if remaining > .zero {
                    do {
                        try await Task.sleep(nanoseconds: remaining.nanosecondsForTaskSleep)
                    } catch {
                        return (false, "expiry_299_wait_cancelled")
                    }
                }
                guard entry.weakSurface.surface != nil else {
                    return (false, "expiry_released_before_300_seconds")
                }
                let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
                guard snapshot.permanentReleaseTotal == initialSnapshot.permanentReleaseTotal,
                    snapshot.deinitializedFreeTotal == initialSnapshot.deinitializedFreeTotal
                else { return (false, "expiry_cleanup_preceded_normal_undo") }
            }

            return await completeRendererLifecycleExpiryCohort(
                fixture,
                entries: entries,
                clock: clock,
                baseline: RendererLifecycleExpiryBaseline(
                    closeUndo: initialSnapshot.closeUndoCurrent,
                    permanentRelease: initialSnapshot.permanentReleaseTotal,
                    deinitializedFree: initialSnapshot.deinitializedFreeTotal,
                    managerOwned: initialSnapshot.managerOwnedCurrent
                )
            )
        }

        private func completeRendererLifecycleExpiryCohort(
            _ fixture: RendererLifecycleContinuityFixture,
            entries: [RendererLifecycleExpiryEntry],
            clock: ContinuousClock,
            baseline: RendererLifecycleExpiryBaseline
        ) async -> (succeeded: Bool, reason: String) {
            guard let latestCloseInstant = entries.map(\.closeInstant).max() else {
                return (false, "expiry_deadline_missing")
            }
            let postDeadlineTarget = latestCloseInstant.advanced(by: .seconds(300))
            let postDeadlineRemaining = clock.now.duration(to: postDeadlineTarget)
            if postDeadlineRemaining > .zero {
                do {
                    try await Task.sleep(nanoseconds: postDeadlineRemaining.nanosecondsForTaskSleep)
                } catch {
                    return (false, "expiry_boundary_wait_cancelled")
                }
            }
            executor.undoCloseTab()
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        let snapshot = self.performanceTraceRecorder.rendererLifecycleSnapshot()
                        return entries.allSatisfy { $0.weakSurface.surface == nil }
                            && snapshot.closeUndoCurrent == baseline.closeUndo
                            && snapshot.permanentReleaseTotal == baseline.permanentRelease + entries.count
                            && snapshot.deinitializedFreeTotal == baseline.deinitializedFree + entries.count
                            && snapshot.managerOwnedCurrent == baseline.managerOwned - entries.count + 1
                            && snapshot.orphanCandidateCurrent == 0
                    })
            else { return (false, "expiry_first_undo_did_not_expire_cohort") }

            if entries.count > 1 {
                for restoredCount in 2...entries.count {
                    executor.undoCloseTab()
                    guard
                        await waitForRendererLifecycleCondition(
                            timeout: .seconds(20),
                            {
                                self.performanceTraceRecorder.rendererLifecycleSnapshot().managerOwnedCurrent
                                    == baseline.managerOwned - entries.count + restoredCount
                            })
                    else { return (false, "expiry_restore_not_settled") }
                }
            }
            let restoredSurfaceIDs = rendererLifecycleSurfaceIDs(for: fixture.expiryPaneIDs)
            let priorSurfaceIDs = Dictionary(uniqueKeysWithValues: entries.map { ($0.paneID, $0.priorSurfaceID) })
            let finalSnapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard restoredSurfaceIDs.count == entries.count,
                entries.allSatisfy({ restoredSurfaceIDs[$0.paneID] != priorSurfaceIDs[$0.paneID] }),
                entries.allSatisfy({
                    rendererLifecycleSessionIDs(for: [$0.paneID])[$0.paneID] == $0.sessionID
                }),
                finalSnapshot.closeUndoCurrent == 0,
                finalSnapshot.orphanCandidateCurrent == 0,
                finalSnapshot.managerOwnedCurrent == fixture.paneIDs.count,
                finalSnapshot.liveCurrent == fixture.paneIDs.count
            else { return (false, "expiry_restore_identity_invalid") }
            return (true, "none")
        }
    }
#endif
