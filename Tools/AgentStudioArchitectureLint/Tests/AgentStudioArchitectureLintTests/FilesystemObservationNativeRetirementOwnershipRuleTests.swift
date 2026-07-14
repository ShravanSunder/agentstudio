import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

private struct NativeRetirementSourceProbe {
    let path: String
    let contents: String
}

@Suite
// swiftlint:disable:next type_name
struct FilesystemObservationNativeRetirementOwnershipRuleTests {
    private let ruleID = "agentstudio_filesystem_observation_native_retirement_ownership"

    @Test("accepts exact registry and native-owner retirement construction")
    func acceptsExactOwnerConstruction() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: nativeOwnerPath, contents: approvedNativeOwnerSource()),
            ]
        )

        #expect(diagnostics.isEmpty)
    }

    @Test("rejects registry retirement construction in a same-file extension")
    func rejectsRegistrySameFileExtensionConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource()
                        + """

                        extension FilesystemObservationSlotRegistry {
                            func finalizeUnpublishedNativeGenerationFromExtension() {
                                _ = FilesystemObservationUnpublishedFinalReceipt(
                                    retiringLifetime: retiringLifetime,
                                    completion: completion,
                                    retirementAuthority: FilesystemUnpublishedRetirementAuthority(
                                        value: UUIDv7.generate()
                                    )
                                )
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == registryOwnerMessage }.count == 2)
    }

    @Test("rejects native acknowledgement construction in a same-file extension")
    func rejectsNativeOwnerSameFileExtensionConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: nativeOwnerPath,
                    contents: approvedNativeOwnerSource()
                        + """

                        extension DarwinFSEventRegistrationNativeOwner {
                            func makeReleasedContextAcknowledgement(
                                for permit: FilesystemObservationNativeRetirementPermit
                            ) -> FilesystemObservationContextReleaseAcknowledgement {
                                let finalization = FilesystemObservationReleasedContextFinalization(
                                    startingNativeLifetime: startingNativeLifetime
                                )
                                let releaseAuthority = FilesystemObservationContextReleaseAuthority(
                                    value: UUIDv7.generate()
                                )
                                return .fenceBacked(
                                    FilesystemFenceContextReleaseAcknowledgement(
                                        receipt: receipt,
                                        finalization: finalization,
                                        releaseAuthority: releaseAuthority
                                    )
                                )
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == nativeOwnerMessage }.count == 3)
    }

    @Test("rejects an exact-name overload outside the approved owner symbol")
    func rejectsExactNameOverloadConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: nativeOwnerPath,
                    contents: approvedNativeOwnerSource()
                        .replacingOccurrences(
                            of: "\n}",
                            with: """

                                    private func makeReleasedContextAcknowledgement() {
                                        _ = FilesystemObservationContextReleaseAuthority(
                                            value: UUIDv7.generate()
                                        )
                                    }
                                }
                                """,
                            options: .backwards
                        )
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == nativeOwnerMessage }.count == 1)
    }

    @Test("rejects foreign unpublished acknowledgement case construction")
    func rejectsForeignUnpublishedAcknowledgementConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: filesystemPath("ForeignAcknowledgementFactory.swift"),
                    contents: """
                        enum ForeignAcknowledgementFactory {
                            static func forge() {
                                _ = FilesystemUnpublishedReleaseAcknowledgement
                                    .releasedRetainedContext(
                                        receipt: receipt,
                                        finalization: finalization,
                                        releaseAuthority: releaseAuthority
                                    )
                                _ = FilesystemUnpublishedReleaseAcknowledgement
                                    .neverMaterialized(
                                        receipt: receipt,
                                        finalization: neverMaterializedFinalization,
                                        releaseAuthority: releaseAuthority
                                    )
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == nativeOwnerMessage }.count == 2)
    }

    @Test("rejects aliases metatypes and initializer escapes")
    func rejectsConstructionEscapes() {
        let diagnostics = validate(
            sources: [
                source(
                    path: filesystemPath("NativeRetirementConstructionEscapes.swift"),
                    contents: """
                        typealias HiddenReleaseAuthority = FilesystemObservationContextReleaseAuthority
                        let releaseAuthorityType = FilesystemObservationContextReleaseAuthority.self
                        let escapedInitializer = FilesystemObservationUnpublishedFinalReceipt.init
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == constructionEscapeMessage }.count == 3)
    }

    @Test("requires UUIDv7 for owner-minted retirement authorities")
    func rejectsNonUUIDv7AuthorityConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(uuidExpression: "UUID()")
                ),
                source(
                    path: nativeOwnerPath,
                    contents: approvedNativeOwnerSource(uuidExpression: "UUID()")
                ),
            ]
        )

        #expect(diagnostics.filter { $0.message == uuidV7Message }.count == 3)
    }

    @Test("ignores deliberate foreign construction in tests")
    func ignoresTestConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: "Tests/AgentStudioTests/ForeignRetirementAuthority.swift",
                    contents: """
                        let foreign = FilesystemObservationContextReleaseAuthority(value: UUID())
                        """
                )
            ]
        )

        #expect(diagnostics.isEmpty)
    }

    private func validate(sources: [NativeRetirementSourceProbe]) -> [ArchitectureDiagnostic] {
        let contexts = sources.map { source in
            ArchitectureLintContext(
                path: "/workspace/\(source.path)",
                source: source.contents,
                sourceFile: Parser.parse(source: source.contents),
                workspaceRootPath: "/workspace"
            )
        }
        let rule = FilesystemObservationNativeRetirementOwnershipRule().prepared(for: contexts)
        return
            contexts
            .flatMap { rule.validate(context: $0) }
            .filter { $0.ruleID == ruleID }
            .sorted()
    }

    private func source(path: String, contents: String) -> NativeRetirementSourceProbe {
        NativeRetirementSourceProbe(path: path, contents: contents)
    }

    private func filesystemPath(_ fileName: String) -> String {
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/\(fileName)"
    }

    private var registryPath: String {
        filesystemPath("FilesystemObservationSlotRegistry+NativeRetirement.swift")
    }

    private var nativeOwnerPath: String {
        filesystemPath("DarwinFSEventRegistrationNativeOwner.swift")
    }

    private func approvedRegistrySource(
        uuidExpression: String = "UUIDv7.generate()"
    ) -> String {
        """
        extension FilesystemObservationSlotRegistry {
            func finalizeUnpublishedNativeGeneration(
                _ retiringLifetime: FilesystemObservationRetiringUnpublishedNativeLifetime,
                completion: DarwinFSEventUnpublishedNativeCompletion
            ) {
                _ = FilesystemObservationUnpublishedFinalReceipt(
                    retiringLifetime: retiringLifetime,
                    completion: completion,
                    retirementAuthority: FilesystemUnpublishedRetirementAuthority(
                        value: \(uuidExpression)
                    )
                )
            }
        }
        """
    }

    private func approvedNativeOwnerSource(
        uuidExpression: String = "UUIDv7.generate()"
    ) -> String {
        """
        final class DarwinFSEventRegistrationNativeOwner {
            private func makeReleasedContextAcknowledgement(
                for permit: FilesystemObservationNativeRetirementPermit
            ) -> FilesystemObservationContextReleaseAcknowledgement {
                let finalization = FilesystemObservationReleasedContextFinalization(
                    startingNativeLifetime: startingNativeLifetime
                )
                let releaseAuthority = FilesystemObservationContextReleaseAuthority(
                    value: \(uuidExpression)
                )
                return .fenceBacked(
                    FilesystemFenceContextReleaseAcknowledgement(
                        receipt: receipt,
                        finalization: finalization,
                        releaseAuthority: releaseAuthority
                    )
                )
            }

            private func makeNeverMaterializedAcknowledgement(
                for permit: FilesystemObservationNativeRetirementPermit
            ) -> FilesystemObservationContextReleaseAcknowledgement {
                return .unpublished(
                    .neverMaterialized(
                        receipt: receipt,
                        finalization: FilesystemObservationNeverMaterializedFinalization(
                            startingNativeLifetime: startingNativeLifetime
                        ),
                        releaseAuthority: FilesystemObservationContextReleaseAuthority(
                            value: \(uuidExpression)
                        )
                    )
                )
            }
        }
        """
    }

    private var registryOwnerMessage: String {
        "Filesystem observation unpublished final receipt and retirement authority construction must occur directly in FilesystemObservationSlotRegistry.finalizeUnpublishedNativeGeneration"
    }

    private var nativeOwnerMessage: String {
        "Filesystem observation context finalization and release acknowledgement construction must occur directly in DarwinFSEventRegistrationNativeOwner"
    }

    private var constructionEscapeMessage: String {
        "Filesystem observation native-retirement constructors must not be aliased or escape as metatype/initializer values"
    }

    private var uuidV7Message: String {
        "Filesystem observation retirement authorities must be minted with a direct UUIDv7.generate() value"
    }
}
