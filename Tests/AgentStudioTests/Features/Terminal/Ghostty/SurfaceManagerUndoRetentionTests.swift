import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("SurfaceManagerUndoRetentionTests", .serialized)
struct SurfaceManagerUndoRetentionTests {
    @Test("exact pane restore does not restart a nonmatching close deadline")
    func exactPaneRestoreDoesNotRestartNonmatchingCloseDeadline() throws {
        // Arrange
        var currentTime = Date(timeIntervalSince1970: 1000)
        let manager = makeManager(now: { currentTime })
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()
        let firstSurface = try makeAttachedSurface(for: firstPaneID, in: manager)
        manager.detach(firstSurface.id, reason: .close)
        currentTime = Date(timeIntervalSince1970: 1010)
        let secondSurface = try makeAttachedSurface(for: secondPaneID, in: manager)
        manager.detach(secondSurface.id, reason: .close)

        // Act — restore the older pane out of global LIFO order.
        currentTime = Date(timeIntervalSince1970: 1020)
        let restoredFirst = manager.restoreClosedSurface(forPaneID: firstPaneID)

        // Assert
        #expect(restoredFirst?.id == firstSurface.id)

        // Act — the untouched second entry reaches its original exact deadline.
        currentTime = Date(timeIntervalSince1970: 1310)
        let restoredSecond = manager.restoreClosedSurface(forPaneID: secondPaneID)

        // Assert
        #expect(restoredSecond == nil)
        #expect(manager.managedSurface(for: secondSurface.id) == nil)
    }

    @Test("close retention is eligible at 299 seconds and expired at exactly 300")
    func closeRetentionIsEligibleAt299SecondsAndExpiredAtExactly300() throws {
        // Arrange — first close.
        var currentTime = Date(timeIntervalSince1970: 2000)
        let manager = makeManager(now: { currentTime })
        let eligiblePaneID = UUIDv7.generate()
        let eligibleSurface = try makeAttachedSurface(for: eligiblePaneID, in: manager)
        manager.detach(eligibleSurface.id, reason: .close)

        // Act and assert — strictly before the boundary is eligible.
        currentTime = Date(timeIntervalSince1970: 2299)
        let restoredEligible = manager.restoreClosedSurface(forPaneID: eligiblePaneID)
        #expect(restoredEligible?.id == eligibleSurface.id)

        // Arrange — second close with an independent exact boundary.
        currentTime = Date(timeIntervalSince1970: 3000)
        let expiredPaneID = UUIDv7.generate()
        let expiredSurface = try makeAttachedSurface(for: expiredPaneID, in: manager)
        manager.detach(expiredSurface.id, reason: .close)

        // Act and assert — equality with the deadline is expired.
        currentTime = Date(timeIntervalSince1970: 3300)
        #expect(manager.restoreClosedSurface(forPaneID: expiredPaneID) == nil)
        #expect(manager.managedSurface(for: expiredSurface.id) == nil)
    }

    @Test("permanent repair replacement never enters close undo across repeated replacements")
    func permanentRepairReplacementNeverEntersCloseUndo() throws {
        let manager = makeManager(now: { Date(timeIntervalSince1970: 4000) })

        for _ in 0..<20 {
            let paneID = UUIDv7.generate()
            let managed = try makeAttachedSurface(for: paneID, in: manager)

            let releaseResult = manager.permanentlyRelease(
                managed.id,
                reason: .repairReplacement
            )

            #expect(releaseResult == .released)
            #expect(manager.managedSurface(for: managed.id) == nil)
            #expect(manager.activeSurfaceCount == 0)
            #expect(manager.hiddenSurfaceCount == 0)
            #expect(!manager.canUndo)
        }
    }

    private func makeManager(now: @escaping @MainActor () -> Date) -> SurfaceManager {
        SurfaceManager(
            undoTTL: 300,
            maxCreationRetries: 0,
            healthCheckInterval: 3600,
            delayScheduler: AsyncDelay { _ in },
            now: now,
            rendererStateDelivery: UndoRetentionRendererStateDelivery()
        )
    }

    private func makeAttachedSurface(
        for paneID: UUID,
        in manager: SurfaceManager
    ) throws -> ManagedSurface {
        let surface = Ghostty.SurfaceView(
            bareManagedSurfaceID: UUIDv7.generate(),
            appCommandDispatcher: UndoRetentionAppCommandDispatcher()
        )
        let managed = try manager.acceptCreatedSurface(
            surface,
            metadata: SurfaceMetadata(paneId: paneID)
        ).get()
        #expect(manager.attach(managed.id, to: paneID) === surface)
        return managed
    }
}

@MainActor
private final class UndoRetentionRendererStateDelivery: SurfaceRendererStateDelivery {
    func deliverVisibility(_: Bool, to _: Ghostty.SurfaceView) -> Bool { true }
    func deliverFocus(_: Bool, to _: Ghostty.SurfaceView) -> Bool { true }
}

@MainActor
private final class UndoRetentionAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
