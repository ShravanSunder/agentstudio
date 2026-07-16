import Foundation
import Testing

@Suite("Bridge product admission static contract")
struct BridgeProductAdmissionStaticContractTests {
    @Test("pane composition is the sole product admission gate constructor")
    func paneCompositionSolelyConstructsProductAdmissionGate() throws {
        // Arrange
        let projectRoot = URL(
            fileURLWithPath: TestPathResolver.projectRoot(from: #filePath)
        )
        let bridgeProductionSources = try bridgeProductAdmissionSwiftSources(
            under: projectRoot.appendingPathComponent(
                "Sources/AgentStudio/Features/Bridge"
            )
        )
        let bootstrapSource = try bridgeProductAdmissionSource(
            projectRoot: projectRoot,
            relativePath:
                "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift"
        )
        let sessionOwnerSource = try bridgeProductAdmissionSource(
            projectRoot: projectRoot,
            relativePath:
                "Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductSessionOwner.swift"
        )
        let sessionRouterSource = try bridgeProductAdmissionSource(
            projectRoot: projectRoot,
            relativePath:
                "Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeSessionRouter.swift"
        )

        // Act
        let normalizedBootstrapSource = bridgeProductAdmissionNormalizeWhitespace(bootstrapSource)
        let normalizedSessionOwnerSource = bridgeProductAdmissionNormalizeWhitespace(
            sessionOwnerSource
        )
        let normalizedSessionRouterSource = bridgeProductAdmissionNormalizeWhitespace(
            sessionRouterSource
        )
        let constructorCount =
            bridgeProductionSources
            .reduce(into: 0) { count, source in
                count += source.components(separatedBy: "BridgeProductAdmissionGate()").count - 1
            }

        // Assert
        #expect(
            constructorCount == 1,
            "BridgePaneController.makeProductSessionDependencies must be the sole production pane admission gate constructor"
        )
        #expect(
            !normalizedBootstrapSource.contains(
                "productAdmissionGate: BridgeProductAdmissionGate = BridgeProductAdmissionGate()"
            ),
            "BridgePaneController.makeInitialProductSessionInstallation must require the composed pane gate"
        )
        #expect(
            !normalizedSessionOwnerSource.contains(
                "productAdmissionGate: BridgeProductAdmissionGate = BridgeProductAdmissionGate()"
            ),
            "BridgeProductSessionInstallation.make must require the composed pane gate"
        )
        #expect(
            !normalizedSessionOwnerSource.contains("?? BridgeProductAdmissionGate()"),
            "BridgePaneProductSessionOwner must not synthesize a fallback pane gate"
        )
        #expect(
            !normalizedSessionRouterSource.contains("?? BridgeProductAdmissionGate()"),
            "BridgeProductSchemeSessionRouter must not synthesize a fallback pane gate"
        )
    }

    @Test("adapter product publication has one admission-gated yield boundary")
    func adapterProductPublicationUsesOneAdmissionGatedYieldBoundary() throws {
        // Arrange
        let projectRoot = URL(
            fileURLWithPath: TestPathResolver.projectRoot(from: #filePath)
        )
        let adapterSource = try bridgeProductAdmissionSource(
            projectRoot: projectRoot,
            relativePath:
                "Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeAdapter.swift"
        )

        // Act
        let normalizedAdapterSource = bridgeProductAdmissionNormalizeWhitespace(adapterSource)
        let yieldCount =
            adapterSource.components(separatedBy: "continuation.yield(result)").count - 1

        // Assert
        #expect(
            yieldCount == 1,
            "Every adapter response and frame must publish through one auditable yield boundary"
        )
        #expect(
            normalizedAdapterSource.contains(
                "productAdmission.withValidAdmission({ continuation.yield(result) })"
            ),
            "The sole adapter yield boundary must atomically validate the original admission context"
        )
    }

    @Test("only product ingress owners acquire pane admission")
    func onlyProductIngressOwnersAcquirePaneAdmission() throws {
        // Arrange
        let projectRoot = URL(
            fileURLWithPath: TestPathResolver.projectRoot(from: #filePath)
        )
        let agentStudioSources = projectRoot.appendingPathComponent(
            "Sources/AgentStudio"
        )

        // Act
        let acquisitionCountBySource = try bridgeProductAdmissionAcquisitionCountBySource(
            under: agentStudioSources
        )

        // Assert
        #expect(
            acquisitionCountBySource == [
                "App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift": 1,
                "Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift": 1,
                "Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift": 2,
                "Features/Bridge/Runtime/BridgePaneController+IPCProjection.swift": 1,
                "Features/Bridge/Transport/BridgeProductSchemeSessionRouter.swift": 1,
            ],
            "Downstream product owners must carry the original context instead of reacquiring pane admission"
        )
    }
}

private func bridgeProductAdmissionSource(
    projectRoot: URL,
    relativePath: String
) throws -> String {
    try String(
        contentsOf: projectRoot.appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

private func bridgeProductAdmissionNormalizeWhitespace(_ source: String) -> String {
    source.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
}

private func bridgeProductAdmissionSwiftSources(
    under directory: URL
) throws -> [String] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
    else {
        throw CocoaError(.fileReadUnknown)
    }
    return try enumerator.compactMap { element in
        guard let fileURL = element as? URL, fileURL.pathExtension == "swift" else {
            return nil
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

private func bridgeProductAdmissionAcquisitionCountBySource(
    under directory: URL
) throws -> [String: Int] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
    else {
        throw CocoaError(.fileReadUnknown)
    }
    var acquisitionCountBySource: [String: Int] = [:]
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let acquisitionCount =
            source.components(separatedBy: "productAdmissionGate.acquire()").count - 1
        guard acquisitionCount > 0 else { continue }
        let relativePath = String(fileURL.path.dropFirst(directory.path.count + 1))
        acquisitionCountBySource[relativePath] = acquisitionCount
    }
    return acquisitionCountBySource
}
