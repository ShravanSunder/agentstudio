import Foundation
import Testing

@Suite("Filesystem observation retirement fence architecture")
struct FilesystemRetirementFenceArchitectureTests {
    @Test("retirement fence wake proof rejects an additional in-lock apply")
    func retirementFenceWakeProofRejectsAdditionalInLockApply() {
        // Arrange
        let mutatedRequestBody = """
                func requestRetirementFence() {
                    let lockedResult = lock.withLock {
                        doorbell.ownerPort.apply(lockedResult.1)
                    }
                    doorbell.ownerPort.apply(lockedResult.1)
                }
            """

        // Act / Assert
        #expect(
            !mutatedRequestBody.hasExactlyOneRetirementFenceWakeApplication(
                afterUnlockAnchor:
                    "        }\n        doorbell.ownerPort.apply(lockedResult.1)"
            )
        )
    }

    @Test("retirement fence wakes remain outside wrapper lock regions")
    func retirementFenceWakesRemainOutsideWrapperLockRegions() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let coreSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailboxCore.swift"
            ),
            encoding: .utf8
        )
        let requestBody = try #require(
            coreSource.retirementFenceProofSlice(
                from: "    func requestRetirementFence(\n",
                to: "    fileprivate func acceptingNativeLifetimeMismatch(\n"
            )
        )
        let acknowledgementBody = try #require(
            coreSource.retirementFenceProofSlice(
                from: "    func acknowledge(\n",
                to: "    func performCleanup() -> AdmissionCleanupTurnResult {\n"
            )
        )
        let cleanupBody = try #require(
            coreSource.retirementFenceProofSlice(
                from: "    func performCleanup() -> AdmissionCleanupTurnResult {\n",
                to:
                    "    private func performFleetShutdownGenericCleanupTurn() "
                    + "-> AdmissionCleanupTurnResult {\n"
            )
        )

        // Act / Assert
        #expect(
            requestBody.hasExactlyOneRetirementFenceWakeApplication(
                afterUnlockAnchor:
                    "        }\n        doorbell.ownerPort.apply(lockedResult.1)"
            )
        )
        #expect(
            acknowledgementBody.hasExactlyOneRetirementFenceWakeApplication(
                afterUnlockAnchor:
                    "        }\n        doorbell.ownerPort.apply(result.wake)"
            )
        )
        #expect(
            cleanupBody.hasExactlyOneRetirementFenceWakeApplication(
                afterUnlockAnchor:
                    "        }\n        if case .performed(let turn) = result {\n"
                    + "            doorbell.ownerPort.apply(turn.wake)"
            )
        )
    }
}

extension String {
    fileprivate func hasExactlyOneRetirementFenceWakeApplication(
        afterUnlockAnchor: String
    ) -> Bool {
        components(separatedBy: "doorbell.ownerPort.apply(").count - 1 == 1
            && contains(afterUnlockAnchor)
    }

    fileprivate func retirementFenceProofSlice(
        from start: String,
        to end: String
    ) -> String? {
        guard let startRange = range(of: start),
            let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
