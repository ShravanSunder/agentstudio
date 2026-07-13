import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
// swiftlint:disable:next type_name
struct FilesystemObservationSlotRegistryOwnershipRuleTests {
    private let ruleID = "agentstudio_filesystem_observation_slot_registry_ownership"

    @Test("accepts the sole primary owner and immutable contracts")
    func acceptsPrimaryOwnerAndImmutableContracts() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource()
                ),
                source(
                    path: contractsPath,
                    contents: """
                        struct FilesystemObservationSlotBindingIdentity {
                            let value: Int
                            var isCurrent: Bool { value > 0 }

                            init(value: Int) {
                                self.value = value
                            }
                        }

                        enum FilesystemObservationNativeLifetimeCommitResult {
                            case committed
                            case stale
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.isEmpty)
    }

    @Test("allows local mutable accumulators in read-only computed projections")
    func acceptsComputedProjectionLocalAccumulator() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: contractsPath,
                    contents: """
                        struct FilesystemSourceConfigurationReceipt {
                            let dispositionsBySourceID: [FilesystemSourceID: Disposition]

                            var currentness: Currentness {
                                var retrySources: Set<FilesystemSourceID> = []
                                for (sourceID, disposition) in dispositionsBySourceID
                                where disposition.requiresRetry {
                                    retrySources.insert(sourceID)
                                }
                                return retrySources.isEmpty
                                    ? .current
                                    : .nonCurrent(retrySources: retrySources)
                            }
                        }
                        """
                ),
            ]
        )

        #expect(!diagnostics.contains { $0.message == mutableContractMessage })
    }

    @Test("rejects construction in a plain owner helper")
    func rejectsPlainHelperConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        extraOwnerMembers: """
                            private func mintAnotherBinding() {
                                _ = FilesystemObservationSlotBinding(value: 2)
                            }
                            """
                    )
                )
            ]
        )

        #expect(diagnostics.contains { $0.message == outsideTransitionMessage })
        #expect(diagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("rejects same-file owner extension construction")
    func rejectsSameFileOwnerExtensionConstruction() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource()
                        + """

                        extension FilesystemObservationSlotRegistry {
                            func mintFromExtension() {
                                _ = FilesystemObservationSlotBindingIdentity(value: 2)
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.contains { $0.message == ownerExtensionMessage })
        #expect(diagnostics.contains { $0.message == outsideTransitionMessage })
        #expect(diagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("rejects a second issuer or factory")
    func rejectsSecondIssuerFactory() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: filesystemSourcePath("FilesystemObservationSlotBindingFactory.swift"),
                    contents: """
                        struct FilesystemObservationSlotBindingFactory {
                            func issue() {
                                _ = FilesystemObservationControlBlockIdentity(value: 2)
                            }
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == outsideTransitionMessage })
        #expect(diagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("rejects missing and duplicate lifetime constructors")
    func rejectsMissingAndDuplicateConstructors() {
        let missingDiagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        nativeGenerationConstruction: "let nativeGeneration = existingGeneration"
                    )
                )
            ]
        )
        let duplicateDiagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        extraSelectedStatements: """
                            _ = FilesystemObservationNativeGenerationIdentity(value: 2)
                            """
                    )
                )
            ]
        )

        #expect(missingDiagnostics.contains { $0.message == constructorCardinalityMessage })
        #expect(duplicateDiagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("rejects aliases and initializer references for lifetime constructors")
    func rejectsAliasAndInitializerEscapes() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: filesystemSourcePath("FilesystemObservationSlotEscapes.swift"),
                    contents: """
                        typealias HiddenBinding = FilesystemObservationSlotBinding

                        let escapedInitializer = FilesystemObservationNativeGenerationIdentity.init
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == constructorAliasMessage })
        #expect(diagnostics.contains { $0.message == initializerEscapeMessage })
    }

    @Test("rejects metatype and contextual initializer construction escapes")
    func rejectsMetatypeAndContextualInitializerEscapes() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: filesystemSourcePath("FilesystemObservationMetatypeEscapes.swift"),
                    contents: """
                        let bindingType = FilesystemObservationSlotBinding.self
                        let escapedBinding = bindingType.init(value: 2)

                        extension FilesystemObservationSlotBindingIdentity {
                            static func forgedWithSelf() -> Self {
                                Self.init(value: 3)
                            }

                            static func forgedContextually() -> Self {
                                .init(value: 4)
                            }
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == constructorAliasMessage })
        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count >= 2)
    }

    @Test("rejects registry aliases that could extend the owner indirectly")
    func rejectsRegistryAliasExtensionEscape() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: filesystemSourcePath("FilesystemObservationSlotRegistryAlias.swift"),
                    contents: """
                        typealias HiddenRegistry = FilesystemObservationSlotRegistry

                        extension HiddenRegistry {
                            func bypassOwnerBoundary() {}
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == ownerAliasMessage })
    }

    @Test("requires the exact selected enum case rather than a textual lookalike")
    func rejectsSelectedCaseNameLookalike() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(selectedCaseName: "selectedFake")
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("requires selected to be the top-level enum case pattern")
    func rejectsNestedSelectedPatternLookalike() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        selectedCaseName: "selectedFake(.selected)"
                    )
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("rejects construction in a nested selected switch unrelated to the slot transition")
    func rejectsNestedSelectedSwitch() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ slotState: SlotState, other: OtherState) {
                                switch slotState {
                                case .selected:
                                    break
                                case .vacant:
                                    switch other {
                                    case .selected:
                                        _ = FilesystemObservationSlotBindingIdentity(value: 1)
                                        _ = FilesystemObservationControlBlockIdentity(value: 1)
                                        _ = FilesystemObservationSlotBinding(value: 1)
                                        _ = FilesystemObservationNativeGenerationIdentity(value: 1)
                                    }
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("binds approved construction to the canonical slot-state switch")
    func rejectsDirectUnrelatedSelectedSwitch() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ slotState: SlotState, other: OtherState) {
                                switch other {
                                case .selected:
                                    _ = FilesystemObservationSlotBindingIdentity(value: 1)
                                    _ = FilesystemObservationControlBlockIdentity(value: 1)
                                    _ = FilesystemObservationSlotBinding(value: 1)
                                    _ = FilesystemObservationNativeGenerationIdentity(value: 1)
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("requires slot state to come from the reservation physical-slot lookup")
    func rejectsShadowSlotStateParameter() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(
                                _ reservation: Reservation,
                                slotState: SlotState
                            ) {
                                switch slotState {
                                case .vacant:
                                    break
                                case .selected:
                                    _ = FilesystemObservationSlotBindingIdentity(value: 1)
                                    _ = FilesystemObservationControlBlockIdentity(value: 1)
                                    _ = FilesystemObservationSlotBinding(value: 1)
                                    _ = FilesystemObservationNativeGenerationIdentity(value: 1)
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("rejects an unrelated local slot-state binding")
    func rejectsUnrelatedLocalSlotStateBinding() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ reservation: Reservation) {
                                let slotState = unrelatedState
                                switch slotState {
                                case .vacant:
                                    break
                                case .selected:
                                    _ = FilesystemObservationSlotBindingIdentity(value: 1)
                                    _ = FilesystemObservationControlBlockIdentity(value: 1)
                                    _ = FilesystemObservationSlotBinding(value: 1)
                                    _ = FilesystemObservationNativeGenerationIdentity(value: 1)
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == outsideTransitionMessage }.count == 4)
    }

    @Test("rejects mutable contracts and mutating contract extensions")
    func rejectsMutableContractsAndExtensions() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: contractsPath,
                    contents: """
                        struct FilesystemObservationSlotProjection {
                            var storedState = 0
                            var writableState: Int {
                                get { storedState }
                                set { storedState = newValue }
                            }

                            mutating func replaceState() {
                                storedState = 1
                            }
                        }

                        final class FilesystemObservationReferenceContract {}
                        """
                ),
                source(
                    path: filesystemSourcePath("FilesystemObservationSlotProjection+Mutation.swift"),
                    contents: """
                        extension FilesystemObservationSlotProjection {
                            mutating func resetState() {
                                storedState = 0
                            }
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.filter { $0.message == mutableContractMessage }.count == 5)
    }

    @Test("rejects mutating extensions through contract aliases")
    func rejectsMutatingContractAliasExtension() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: contractsPath,
                    contents: """
                        struct FilesystemObservationSlotProjection {
                            let state: Int
                        }
                        """
                ),
                source(
                    path: filesystemSourcePath("FilesystemObservationProjectionAlias.swift"),
                    contents: """
                        typealias ProjectionAlias = FilesystemObservationSlotProjection

                        extension ProjectionAlias {
                            mutating func reset() {}
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == mutableContractMessage })
    }

    @Test("rejects mutable global nested and writable-protocol contracts")
    func rejectsCanonicalContractMutationAtEveryDeclarationDepth() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: contractsPath,
                    contents: """
                        var globalState = 0

                        struct OuterContract {
                            struct NestedContract {
                                var storedState = 0
                            }

                            init() {
                                var initializerLocalState = 0
                                initializerLocalState += 1
                            }
                        }

                        protocol WritableProjection {
                            var value: Int { get set }
                        }

                        protocol ReadOnlyProjection {
                            var value: Int { get }
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.filter { $0.message == mutableContractMessage }.count == 3)
    }

    @Test("missing canonical owner anchors owner and constructor diagnostics to contracts")
    func rejectsMissingCanonicalOwnerFile() {
        let diagnostics = validate(
            sources: [
                source(
                    path: contractsPath,
                    contents: """
                        struct FilesystemObservationSlotBindingIdentity {
                            let value: Int
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == primaryOwnerMessage }.count == 1)
        #expect(diagnostics.filter { $0.message == constructorCardinalityMessage }.count == 4)
        #expect(diagnostics.allSatisfy { $0.path.hasSuffix(contractsPath) })
    }

    @Test("rejects non-final, nested, and additional registry owners")
    func rejectsInvalidRegistryOwnerShapes() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(ownerDeclaration: "class")
                ),
                source(
                    path: filesystemSourcePath("AdditionalRegistry.swift"),
                    contents: """
                        enum Namespace {
                            final class FilesystemObservationSlotRegistry {}
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.filter { $0.message == primaryOwnerMessage }.count == 2)
    }

    @Test("ignores matching vocabulary outside production AgentStudio sources")
    func ignoresNonProductionVocabulary() {
        let diagnostics = validate(
            sources: [
                source(
                    path: "Tests/AgentStudioTests/FilesystemObservationSlotRegistryProbe.swift",
                    contents: """
                        extension FilesystemObservationSlotRegistry {
                            func testOnlyBinding() {
                                _ = FilesystemObservationSlotBinding(value: 1)
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.isEmpty)
    }

    private func validate(sources: [SourceProbe]) -> [ArchitectureDiagnostic] {
        let contexts = sources.map { source in
            ArchitectureLintContext(
                path: "/workspace/\(source.path)",
                source: source.contents,
                sourceFile: Parser.parse(source: source.contents),
                workspaceRootPath: "/workspace"
            )
        }
        let rule = FilesystemObservationSlotRegistryOwnershipRule().prepared(for: contexts)
        return
            contexts
            .flatMap { rule.validate(context: $0) }
            .filter { $0.ruleID == ruleID }
            .sorted()
    }

    private func source(path: String, contents: String) -> SourceProbe {
        SourceProbe(path: path, contents: contents)
    }

    private func filesystemSourcePath(_ fileName: String) -> String {
        "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/\(fileName)"
    }

    private func approvedRegistrySource(
        ownerDeclaration: String = "final class",
        selectedCaseName: String = "selected",
        nativeGenerationConstruction: String =
            "let nativeGeneration = FilesystemObservationNativeGenerationIdentity(value: 1)",
        extraSelectedStatements: String = "",
        extraOwnerMembers: String = ""
    ) -> String {
        """
        \(ownerDeclaration) FilesystemObservationSlotRegistry {
            private var statesByPhysicalSlotID: [PhysicalSlotID: SlotState] = [:]

            func beginNativeLifetime(_ reservation: Reservation) {
                guard let slotState =
                    statesByPhysicalSlotID[reservation.physicalSlotID]
                else {
                    return
                }
                switch slotState {
                case .vacant:
                    break
                case .\(selectedCaseName):
                    let bindingIdentity = FilesystemObservationSlotBindingIdentity(value: 1)
                    let controlBlockIdentity = FilesystemObservationControlBlockIdentity(value: 1)
                    let binding = FilesystemObservationSlotBinding(value: 1)
                    \(nativeGenerationConstruction)
                    _ = (bindingIdentity, controlBlockIdentity, binding, nativeGeneration)
                    \(extraSelectedStatements)
                }
            }

            \(extraOwnerMembers)
        }
        """
    }

    private var registryPath: String {
        filesystemSourcePath("FilesystemObservationSlotRegistry.swift")
    }

    private var contractsPath: String {
        filesystemSourcePath("FilesystemObservationSlotRegistryContracts.swift")
    }

    private var primaryOwnerMessage: String {
        "FilesystemObservationSlotRegistry must remain exactly one top-level final primary class in its owner file"
    }

    private var ownerExtensionMessage: String {
        "FilesystemObservationSlotRegistry must not have production extensions"
    }

    private var ownerAliasMessage: String {
        "FilesystemObservationSlotRegistry must not be aliased in production"
    }

    private var outsideTransitionMessage: String {
        "Filesystem observation binding/control/native construction must occur directly in beginNativeLifetime's selected transition"
    }

    private var constructorCardinalityMessage: String {
        "Each filesystem observation binding/control/native constructor must have exactly one production call site"
    }

    private var constructorAliasMessage: String {
        "Filesystem observation binding/control/native constructor types must not be aliased"
    }

    private var initializerEscapeMessage: String {
        "Filesystem observation binding/control/native initializers must not escape as values"
    }

    private var mutableContractMessage: String {
        "Filesystem observation slot-registry contracts must remain immutable value contracts with read-only projections"
    }
}

private struct SourceProbe {
    let path: String
    let contents: String
}
