import Foundation
import Testing

@Suite("Filesystem dormant cutover architecture")
struct FilesystemDormantCutoverArchitectureTests {
    @Test("pre-W2b production remains wholly on the legacy filesystem ingress")
    func preW2bProductionRemainsWhollyLegacy() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let filesystemActorSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift"
            ),
            encoding: .utf8
        )
        let darwinStreamClientSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift"
            ),
            encoding: .utf8
        )
        let dormantFixedIngressTypeNames = [
            "DarwinFSEventRegistrationGeneration",
            "DarwinFSEventObservationAdapter",
            "FilesystemObservationMailbox",
        ]

        // Act / Assert
        #expect(
            filesystemActorSource.contains(
                "private let fseventStreamClient: any FSEventStreamClient"
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
}
