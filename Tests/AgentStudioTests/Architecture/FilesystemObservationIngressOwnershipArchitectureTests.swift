import Foundation
import Testing

@Suite("Filesystem observation ingress ownership architecture")
// The plan names this exact proof selector.
// swiftlint:disable:next type_name
struct FilesystemObservationIngressOwnershipArchitectureTests {
    @Test("pre-W2b production remains wholly on the legacy filesystem ingress")
    func preW2bProductionRemainsWhollyLegacy() throws {
        // Arrange
        let filesystemActorSource = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift"
        )
        let darwinStreamClientSource = try readSource(
            "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift"
        )
        let dormantFixedIngressTypeNames = [
            "DarwinFSEventRegistrationGeneration",
            "DarwinFSEventObservationAdapter",
            "FilesystemObservationMailbox",
        ]

        // Act / Assert
        #expect(
            filesystemActorSource.contains(
                "let fseventStreamClient: any FSEventStreamClient"
            )
        )
        #expect(
            filesystemActorSource.contains(
                "fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient()"
            )
        )
        #expect(darwinStreamClientSource.contains("private final class CallbackContext"))
        #expect(darwinStreamClientSource.contains("let stream = FSEventStreamCreate("))

        for dormantTypeName in dormantFixedIngressTypeNames {
            #expect(
                !filesystemActorSource.contains(dormantTypeName),
                "FilesystemActor must remain legacy-only before W2b: \(dormantTypeName)"
            )
            #expect(
                !darwinStreamClientSource.contains(dormantTypeName),
                "DarwinFSEventStreamClient must remain legacy-only before W2b: \(dormantTypeName)"
            )
        }
    }

    @Test("dormant harness is the sole fixed-ingress mailbox and doorbell consumer owner")
    func dormantHarnessIsSoleFixedIngressMailboxAndDoorbellConsumerOwner() throws {
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
        let ownedDoorbellConsumerPortCount =
            source.components(
                separatedBy:
                    "private let doorbellConsumerPort: FilesystemObservationDoorbellConsumerPort"
            ).count - 1

        // Assert
        #expect(actorDeclarationCount == 1)
        #expect(ownedConsumerPortCount == 1)
        #expect(ownedDoorbellConsumerPortCount == 1)
    }

    private func readSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
