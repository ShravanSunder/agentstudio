import XCTest
@testable import AgentStudio

final class SurfaceTypesTests: XCTestCase {

    // MARK: - SurfaceHealth isHealthy

    func test_surfaceHealth_isHealthy_healthyCase_returnsTrue() {
        // Assert
        XCTAssertTrue(SurfaceHealth.healthy.isHealthy)
    }

    func test_surfaceHealth_isHealthy_unhealthyCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceHealth.unhealthy(reason: .rendererUnhealthy).isHealthy)
    }

    func test_surfaceHealth_isHealthy_processExitedCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceHealth.processExited(exitCode: 0).isHealthy)
    }

    func test_surfaceHealth_isHealthy_deadCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceHealth.dead.isHealthy)
    }

    // MARK: - SurfaceHealth canRestart

    func test_surfaceHealth_canRestart_healthyCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceHealth.healthy.canRestart)
    }

    func test_surfaceHealth_canRestart_unhealthyCase_returnsTrue() {
        // Assert
        XCTAssertTrue(SurfaceHealth.unhealthy(reason: .initializationFailed).canRestart)
    }

    func test_surfaceHealth_canRestart_processExitedCase_returnsTrue() {
        // Assert
        XCTAssertTrue(SurfaceHealth.processExited(exitCode: 1).canRestart)
    }

    func test_surfaceHealth_canRestart_deadCase_returnsTrue() {
        // Assert
        XCTAssertTrue(SurfaceHealth.dead.canRestart)
    }

    // MARK: - SurfaceHealth Equatable

    func test_surfaceHealth_equatable_sameReason() {
        // Assert
        XCTAssertEqual(
            SurfaceHealth.unhealthy(reason: .rendererUnhealthy),
            SurfaceHealth.unhealthy(reason: .rendererUnhealthy)
        )
    }

    func test_surfaceHealth_equatable_differentReason() {
        // Assert
        XCTAssertNotEqual(
            SurfaceHealth.unhealthy(reason: .rendererUnhealthy),
            SurfaceHealth.unhealthy(reason: .unknown)
        )
    }

    // MARK: - SurfaceState isActive

    func test_surfaceState_isActive_activeCase_returnsTrue() {
        // Assert
        XCTAssertTrue(SurfaceState.active(paneId: UUID()).isActive)
    }

    func test_surfaceState_isActive_hiddenCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceState.hidden.isActive)
    }

    func test_surfaceState_isActive_pendingUndoCase_returnsFalse() {
        // Assert
        XCTAssertFalse(SurfaceState.pendingUndo(expiresAt: Date()).isActive)
    }

    // MARK: - SurfaceState Equatable

    func test_surfaceState_equatable_samePaneAttachmentId() {
        // Arrange
        let id = UUID()

        // Assert
        XCTAssertEqual(SurfaceState.active(paneId: id), SurfaceState.active(paneId: id))
    }

    func test_surfaceState_equatable_differentPaneAttachmentId() {
        // Assert
        XCTAssertNotEqual(
            SurfaceState.active(paneId: UUID()),
            SurfaceState.active(paneId: UUID())
        )
    }

    // MARK: - SurfaceMetadata Codable

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
        XCTAssertEqual(decoded.title, "My Terminal")
        XCTAssertEqual(decoded.command, "zsh")
        XCTAssertEqual(decoded.worktreeId, wtId)
        XCTAssertEqual(decoded.repoId, pId)
    }

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
        XCTAssertNil(decoded.workingDirectory)
        XCTAssertNil(decoded.command)
        XCTAssertNil(decoded.worktreeId)
    }

    // MARK: - SurfaceMetadata Equatable

    func test_surfaceMetadata_equatable_differentTitles() {
        // Arrange
        let md1 = makeSurfaceMetadata(title: "A")
        let md2 = makeSurfaceMetadata(title: "B")

        // Assert
        XCTAssertNotEqual(md1, md2)
    }

    // MARK: - SurfaceCheckpoint.SurfaceData Codable

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
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.wasActive, true)
        XCTAssertEqual(decoded.paneId, paneId)
        XCTAssertEqual(decoded.metadata.title, "Test")
    }

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
        XCTAssertFalse(decoded.wasActive)
        XCTAssertNil(decoded.paneId)
    }

    // MARK: - SurfaceError

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
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func test_surfaceError_creationFailed_includesRetryCount() {
        // Arrange
        let error = SurfaceError.creationFailed(retries: 5)

        // Assert
        XCTAssertTrue(error.errorDescription!.contains("5"))
    }

    func test_surfaceError_operationFailed_includesMessage() {
        // Arrange
        let error = SurfaceError.operationFailed("timeout exceeded")

        // Assert
        XCTAssertTrue(error.errorDescription!.contains("timeout exceeded"))
    }
}
