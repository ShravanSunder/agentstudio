import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)

final class SurfaceTypesTests {

    // MARK: - SurfaceHealth isHealthy

    @Test
    func test_surfaceHealth_isHealthy_healthyCase_returnsTrue() {
        // Assert
        #expect(SurfaceHealth.healthy.isHealthy)
    }

    @Test
    func test_surfaceHealth_isHealthy_unhealthyCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceHealth.unhealthy(reason: .rendererUnhealthy).isHealthy))
    }

    @Test
    func test_surfaceHealth_isHealthy_processExitedCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceHealth.processExited(exitCode: 0).isHealthy))
    }

    @Test
    func test_surfaceHealth_isHealthy_deadCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceHealth.dead.isHealthy))
    }

    // MARK: - SurfaceHealth canRestart

    @Test
    func test_surfaceHealth_canRestart_healthyCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceHealth.healthy.canRestart))
    }

    @Test
    func test_surfaceHealth_canRestart_unhealthyCase_returnsTrue() {
        // Assert
        #expect(SurfaceHealth.unhealthy(reason: .initializationFailed).canRestart)
    }

    @Test
    func test_surfaceHealth_canRestart_processExitedCase_returnsTrue() {
        // Assert
        #expect(SurfaceHealth.processExited(exitCode: 1).canRestart)
    }

    @Test
    func test_surfaceHealth_canRestart_deadCase_returnsTrue() {
        // Assert
        #expect(SurfaceHealth.dead.canRestart)
    }

    // MARK: - SurfaceHealth Equatable

    @Test
    func test_surfaceHealth_equatable_sameReason() {
        // Assert
        #expect(SurfaceHealth.unhealthy(reason: .rendererUnhealthy) == SurfaceHealth.unhealthy(reason: .rendererUnhealthy))
    }

    @Test
    func test_surfaceHealth_equatable_differentReason() {
        // Assert
        #expect(SurfaceHealth.unhealthy(reason: .rendererUnhealthy) != SurfaceHealth.unhealthy(reason: .unknown))
    }

    // MARK: - SurfaceState isActive

    @Test
    func test_surfaceState_isActive_activeCase_returnsTrue() {
        // Assert
        #expect(SurfaceState.active(paneId: UUID()).isActive)
    }

    @Test
    func test_surfaceState_isActive_hiddenCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceState.hidden.isActive))
    }

    @Test
    func test_surfaceState_isActive_pendingUndoCase_returnsFalse() {
        // Assert
        #expect(!(SurfaceState.pendingUndo(expiresAt: Date()).isActive))
    }

    // MARK: - SurfaceState Equatable

    @Test
    func test_surfaceState_equatable_samePaneAttachmentId() {
        // Arrange
        let id = UUID()

        // Assert
        #expect(SurfaceState.active(paneId: id) == SurfaceState.active(paneId: id))
    }

    @Test
    func test_surfaceState_equatable_differentPaneAttachmentId() {
        // Assert
        #expect(SurfaceState.active(paneId: UUID()) != SurfaceState.active(paneId: UUID()))
    }

    // MARK: - SurfaceMetadata Codable

    @Test
    func test_surfaceMetadata_codable_roundTrip() throws {
        // Arrange
        let wtId = UUID()
        let pId = UUID()
        let original = makeSurfaceMetadata(
            workingDirectory: "/tmp/work",
            command: "zsh",
            title: "My Terminal",
            worktreeId: wtId,
            repoId: pId
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurfaceMetadata.self, from: data)

        // Assert
        #expect(decoded.title == "My Terminal")
        #expect(decoded.command == "zsh")
        #expect(decoded.worktreeId == wtId)
        #expect(decoded.repoId == pId)
    }

    @Test
    func test_surfaceMetadata_codable_nilOptionals_roundTrip() throws {
        // Arrange
        let original = SurfaceMetadata(
            workingDirectory: nil,
            command: nil,
            title: "Terminal",
            worktreeId: nil,
            repoId: nil
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurfaceMetadata.self, from: data)

        // Assert
        #expect(decoded.workingDirectory == nil)
        #expect(decoded.command == nil)
        #expect(decoded.worktreeId == nil)
    }

    // MARK: - SurfaceMetadata Equatable

    @Test
    func test_surfaceMetadata_equatable_differentTitles() {
        // Arrange
        let md1 = makeSurfaceMetadata(title: "A")
        let md2 = makeSurfaceMetadata(title: "B")

        // Assert
        #expect(md1 != md2)
    }

    // MARK: - SurfaceCheckpoint.SurfaceData Codable

    @Test
    func test_surfaceData_codable_roundTrip() throws {
        // Arrange
        let metadata = makeSurfaceMetadata(title: "Test")
        let id = UUID()
        let paneId = UUID()
        let original = SurfaceCheckpoint.SurfaceData(
            id: id,
            metadata: metadata,
            wasActive: true,
            paneId: paneId
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurfaceCheckpoint.SurfaceData.self, from: data)

        // Assert
        #expect(decoded.id == id)
        #expect(decoded.wasActive == true)
        #expect(decoded.paneId == paneId)
        #expect(decoded.metadata.title == "Test")
    }

    @Test
    func test_surfaceData_codable_nilPaneAttachmentId_roundTrip() throws {
        // Arrange
        let original = SurfaceCheckpoint.SurfaceData(
            id: UUID(),
            metadata: makeSurfaceMetadata(),
            wasActive: false,
            paneId: nil
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurfaceCheckpoint.SurfaceData.self, from: data)

        // Assert
        #expect(!(decoded.wasActive))
        #expect(decoded.paneId == nil)
    }

    // MARK: - SurfaceError

    @Test
    func test_surfaceError_errorDescription_allCasesNonEmpty() {
        // Arrange
        let errors: [SurfaceError] = [
            .surfaceNotFound,
            .surfaceNotInitialized,
            .surfaceDied,
            .creationFailed(retries: 3),
            .operationFailed("test"),
            .ghosttyNotInitialized,
        ]

        // Assert
        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have a description")
            #expect(!(error.errorDescription!.isEmpty), "\(error) description should not be empty")
        }
    }

    @Test
    func test_surfaceError_creationFailed_includesRetryCount() {
        // Arrange
        let error = SurfaceError.creationFailed(retries: 5)

        // Assert
        #expect(error.errorDescription!.contains("5"))
    }

    @Test
    func test_surfaceError_operationFailed_includesMessage() {
        // Arrange
        let error = SurfaceError.operationFailed("timeout exceeded")

        // Assert
        #expect(error.errorDescription!.contains("timeout exceeded"))
    }
}
