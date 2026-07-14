import Foundation
import Testing

@Suite("Filesystem observation lease transfer architecture")
struct FilesystemLeaseTransferArchitectureTests {
    @Test("whole lease transfer dispositions require an opaque credential")
    func wholeLeaseTransferDispositionsRequireOpaqueCredential() throws {
        // Arrange
        let source = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailboxContracts.swift"
        )
        let disposition = try #require(
            source.proofSlice(
                from: "enum FilesystemObservationDrainDisposition:",
                to: "enum FilesystemObservationLifecycleStateSnapshot:"
            )
        )

        // Act
        let hasUncredentialedAuthoritativeTransfer = disposition.contains(
            "case transferredAuthoritative\n"
        )
        let hasCredentialedAuthoritativeTransfer = disposition.contains(
            "case transferredAuthoritative("
        )
        let hasCredentialedRecoveryTransfer =
            disposition.contains(
                "case transferredRecovery("
            )
            && disposition.contains("FilesystemObservationWholeLeaseTransferAuthority")

        // Assert
        #expect(!hasUncredentialedAuthoritativeTransfer)
        #expect(hasCredentialedAuthoritativeTransfer)
        #expect(hasCredentialedRecoveryTransfer)
    }

    @Test("task free transfer component excludes scheduling and heavy dependencies")
    func taskFreeTransferComponentExcludesSchedulingAndHeavyDependencies() throws {
        // Arrange
        let source = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationLeaseTransfer.swift"
        )
        let detachedTaskFragment = ["Task", "detached"].joined(separator: ".")
        let forbiddenFragments = [
            "Task {",
            detachedTaskFragment,
            "actor FilesystemObservationLeaseTransfer",
            "await ",
            "AsyncStream",
            "@MainActor",
            "FileManager",
            "GitWorkingDirectory",
            "Bridge",
            "actorWaiterPort",
            ".nextSignal(",
        ]

        // Act / Assert
        #expect(source.contains("struct FilesystemObservationLeaseTransfer"))
        for fragment in forbiddenFragments {
            #expect(!source.contains(fragment), "Forbidden transfer dependency: \(fragment)")
        }
    }

    @Test("retirement receipt uses a strict zero or one recovery revision disposition")
    func retirementReceiptUsesStrictRecoveryDisposition() throws {
        // Arrange
        let source = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistryContracts.swift"
        )
        let disposition = try #require(
            source.proofSlice(
                from: "enum FilesystemObservationSlotRetirementDisposition:",
                to: "struct FilesystemObservationSlotRetirementReceipt:"
            )
        )

        // Act / Assert
        #expect(disposition.contains("case quiescentWithoutRecovery"))
        #expect(disposition.contains("case quiescentAfterRecovery("))
        #expect(disposition.contains("FixedFilesystemRecoveryEvidenceRevision"))
        #expect(!disposition.contains("?"))
        #expect(!disposition.contains("Bool"))
        #expect(!disposition.contains("Set<"))
    }

    @Test("H2 leaves the production filesystem actor on legacy ingress")
    func h2LeavesProductionFilesystemActorOnLegacyIngress() throws {
        // Arrange
        let source = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift"
        )

        // Act / Assert
        #expect(!source.contains("FilesystemObservationLeaseTransfer"))
        #expect(!source.contains("FilesystemObservationDrainHarnessActor"))
    }

    @Test("retirement planner is called only by the primary registry owner")
    func retirementPlannerIsCalledOnlyByPrimaryRegistryOwner() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let filesystemDirectory = projectRoot.appending(
            path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem"
        )
        let registryFileName = "FilesystemObservationSlotRegistry.swift"
        let plannerFileName = "FilesystemObservationRetirementTransitionPlanner.swift"
        let registrySource = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/\(registryFileName)"
        )
        let sourceFileNames = try FileManager.default.contentsOfDirectory(
            atPath: filesystemDirectory.path
        ).filter { $0.hasSuffix(".swift") }

        // Act / Assert
        #expect(!registrySource.contains("extension FilesystemObservationSlotRegistry {"))
        #expect(registrySource.contains("FilesystemObservationRetirementTransitionPlanner."))
        for sourceFileName in sourceFileNames
        where sourceFileName != registryFileName && sourceFileName != plannerFileName {
            let source = try String(
                contentsOf: filesystemDirectory.appending(path: sourceFileName),
                encoding: .utf8
            )
            #expect(
                !source.contains("FilesystemObservationRetirementTransitionPlanner."),
                "Only the primary registry owner may call the retirement planner"
            )
        }
    }

    @Test("test harness is the sole dormant consumer and waiter owner")
    func testHarnessIsSoleDormantConsumerAndWaiterOwner() throws {
        // Arrange
        let source = try readSource(
            "Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemObservationDrainHarnessActor.swift"
        )

        // Act
        let actorDeclarationCount =
            source.components(
                separatedBy: "actor FilesystemObservationDrainHarnessActor"
            ).count - 1
        let ownedConsumerPortCount =
            source.components(
                separatedBy:
                    "private let consumerPort: FilesystemObservationActorConsumerPort"
            ).count - 1
        let ownedWaiterPortCount =
            source.components(
                separatedBy:
                    "private let waiterPort: FilesystemObservationActorWaiterPort"
            ).count - 1

        // Assert
        #expect(actorDeclarationCount == 1)
        #expect(ownedConsumerPortCount == 1)
        #expect(ownedWaiterPortCount == 1)
    }

    private func readSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}

extension String {
    fileprivate func proofSlice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
            let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
