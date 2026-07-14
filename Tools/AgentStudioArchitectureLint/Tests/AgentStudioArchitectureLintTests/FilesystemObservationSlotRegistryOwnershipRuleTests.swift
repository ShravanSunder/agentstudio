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
                    path: admissionPlannerPath,
                    contents: approvedAdmissionPlannerSource()
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
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
                                _ = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                            }
                            """
                    )
                )
            ]
        )

        #expect(diagnostics.contains { $0.message == identityOutsideTransitionMessage })
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
                ),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
            ]
        )

        #expect(diagnostics.contains { $0.message == ownerExtensionMessage })
        #expect(diagnostics.contains { $0.message == identityOutsideTransitionMessage })
        #expect(diagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("accepts only the canonical native-retirement registry extension")
    func acceptsCanonicalNativeRetirementExtension() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
                source(
                    path: nativeRetirementExtensionPath,
                    contents: """
                        extension FilesystemObservationSlotRegistry {
                            func replayNativeRetirement() {
                                _ = statesByPhysicalSlotID
                                _ = retiringGenerationChainsBySourceID
                                _ = lastCompletedReleasesByPhysicalSlotID
                            }
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.isEmpty)
    }

    @Test("rejects other extension files and foreign native-retirement storage access")
    func rejectsForeignNativeRetirementExtensionAndStorageAccess() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
                source(
                    path: filesystemSourcePath("ForeignRegistryExtension.swift"),
                    contents: """
                        extension FilesystemObservationSlotRegistry {
                            func bypassNativeRetirementOwner() {}
                        }
                        """
                ),
                source(
                    path: filesystemSourcePath("ForeignRegistryStorageReader.swift"),
                    contents: """
                        func bypassRegistryStorage(_ registry: FilesystemObservationSlotRegistry) {
                            _ = registry.statesByPhysicalSlotID
                        }
                        """
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == ownerExtensionMessage })
        #expect(diagnostics.contains { $0.message == nativeRetirementStorageMessage })
    }

    @Test("allows unrelated values whose members share registry storage names")
    func acceptsUnrelatedMemberNames() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
                source(
                    path: filesystemSourcePath("UnrelatedSlotStateInput.swift"),
                    contents: """
                        struct UnrelatedSlotStateInput {
                            let statesByPhysicalSlotID: [Int: Int]
                        }

                        func inspectUnrelatedInput(_ input: UnrelatedSlotStateInput) {
                            _ = input.statesByPhysicalSlotID
                        }
                        """
                ),
            ]
        )

        #expect(!diagnostics.contains { $0.message == nativeRetirementStorageMessage })
    }

    @Test("rejects a second issuer or factory")
    func rejectsSecondIssuerFactory() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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

        #expect(diagnostics.contains { $0.message == identityOutsideTransitionMessage })
        #expect(diagnostics.contains { $0.message == constructorCardinalityMessage })
    }

    @Test("rejects missing and duplicate protected constructors")
    func rejectsMissingAndDuplicateConstructors() {
        let missingDiagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        nativeGenerationConstruction: "let nativeGeneration = existingGeneration"
                    )
                ),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
            ]
        )
        let duplicateDiagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: admissionPlannerPath,
                    contents: approvedAdmissionPlannerSource(
                        extraCompletionStatements: """
                            _ = FilesystemObservationStartingNativeLifetime(value: 2)
                            """
                    )
                ),
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
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
        #expect(diagnostics.contains { $0.message == identityOutsideTransitionMessage })
    }

    @Test("rejects registry aliases that could extend the owner indirectly")
    func rejectsRegistryAliasExtensionEscape() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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

    @Test("requires the exact identity-requirement enum case rather than a textual lookalike")
    func rejectsIdentityRequirementCaseNameLookalike() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        identityRequirementCaseName: "requiresNativeLifetimeIdentitiesFake"
                    )
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("requires the identity requirement to be the top-level enum case pattern")
    func rejectsNestedIdentityRequirementPatternLookalike() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: approvedRegistrySource(
                        identityRequirementCaseName:
                            "result(.requiresNativeLifetimeIdentities)"
                    )
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("rejects construction in a nested identity-requirement switch")
    func rejectsNestedIdentityRequirementSwitch() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ reservation: Reservation) {
                                let plan = FilesystemObservationSlotAdmissionPlanner.planNativeCommit(
                                    reservation: reservation,
                                    fleetMailboxIdentity: fleetMailboxIdentity,
                                    slotState: slotState,
                                    pendingRecord: pendingRecord
                                )
                                switch plan {
                                case .requiresNativeLifetimeIdentities:
                                    switch otherPlan {
                                    case .requiresNativeLifetimeIdentities:
                                        _ = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                                        _ = FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
                                        _ = FilesystemObservationNativeGenerationIdentity(value: UUIDv7.generate())
                                    }
                                case .result:
                                    break
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("binds approved construction to the canonical native-commit plan switch")
    func rejectsDirectUnrelatedIdentityRequirementSwitch() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ reservation: Reservation) {
                                switch otherPlan {
                                case .requiresNativeLifetimeIdentities:
                                    _ = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationNativeGenerationIdentity(value: UUIDv7.generate())
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("requires plan to come from the canonical planner call")
    func rejectsShadowPlanParameter() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ reservation: Reservation, plan: NativeCommitPlan) {
                                switch plan {
                                case .result:
                                    break
                                case .requiresNativeLifetimeIdentities:
                                    _ = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationNativeGenerationIdentity(value: UUIDv7.generate())
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("rejects an unrelated local plan binding")
    func rejectsUnrelatedLocalPlanBinding() {
        let diagnostics = validate(
            sources: [
                source(
                    path: registryPath,
                    contents: """
                        final class FilesystemObservationSlotRegistry {
                            func beginNativeLifetime(_ reservation: Reservation) {
                                let plan = unrelatedPlan
                                switch plan {
                                case .result:
                                    break
                                case .requiresNativeLifetimeIdentities:
                                    _ = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
                                    _ = FilesystemObservationNativeGenerationIdentity(value: UUIDv7.generate())
                                }
                            }
                        }
                        """
                )
            ]
        )

        #expect(diagnostics.filter { $0.message == identityOutsideTransitionMessage }.count == 3)
    }

    @Test("rejects mutable contracts and mutating contract extensions")
    func rejectsMutableContractsAndExtensions() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
                source(path: admissionPlannerPath, contents: approvedAdmissionPlannerSource()),
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
        #expect(diagnostics.filter { $0.message == constructorCardinalityMessage }.count == 5)
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

    @Test("rejects binding completion outside the exact admission planner method")
    func rejectsBindingCompletionOutsideExactPlannerMethod() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: admissionPlannerPath,
                    contents: approvedAdmissionPlannerSource(
                        completionFunctionName: "completeNativeCommitLookalike"
                    )
                ),
            ]
        )

        #expect(diagnostics.filter { $0.message == completionOutsidePlannerMessage }.count == 2)
    }

    @Test("rejects UUIDv7 generation in filesystem planners")
    func rejectsPlannerUUIDGeneration() {
        let diagnostics = validate(
            sources: [
                source(path: registryPath, contents: approvedRegistrySource()),
                source(
                    path: admissionPlannerPath,
                    contents: approvedAdmissionPlannerSource(
                        extraCompletionStatements: """
                            _ = UUIDv7.generate()
                            """
                    )
                ),
            ]
        )

        #expect(diagnostics.contains { $0.message == plannerUUIDGenerationMessage })
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
        identityRequirementCaseName: String = "requiresNativeLifetimeIdentities",
        nativeGenerationConstruction: String =
            "let nativeGeneration = FilesystemObservationNativeGenerationIdentity(value: UUIDv7.generate())",
        extraSelectedStatements: String = "",
        extraOwnerMembers: String = ""
    ) -> String {
        """
        \(ownerDeclaration) FilesystemObservationSlotRegistry {
            func beginNativeLifetime(_ reservation: Reservation) {
                let plan = FilesystemObservationSlotAdmissionPlanner.planNativeCommit(
                    reservation: reservation,
                    fleetMailboxIdentity: fleetMailboxIdentity,
                    slotState: slotState,
                    pendingRecord: pendingRecord
                )
                switch plan {
                case .result:
                    break
                case .\(identityRequirementCaseName)(let selection):
                    let bindingIdentity = FilesystemObservationSlotBindingIdentity(value: UUIDv7.generate())
                    let controlBlockIdentity = FilesystemObservationControlBlockIdentity(value: UUIDv7.generate())
                    \(nativeGenerationConstruction)
                    _ = FilesystemObservationSlotAdmissionPlanner.completeNativeCommit(
                        selection: selection,
                        identities: .init(
                            bindingIdentity: bindingIdentity,
                            controlBlockIdentity: controlBlockIdentity,
                            nativeGenerationIdentity: nativeGeneration
                        )
                    )
                    \(extraSelectedStatements)
                }
            }

            \(extraOwnerMembers)
        }
        """
    }

    private func approvedAdmissionPlannerSource(
        completionFunctionName: String = "completeNativeCommit",
        extraCompletionStatements: String = ""
    ) -> String {
        """
        enum FilesystemObservationSlotAdmissionPlanner {
            static func \(completionFunctionName)(
                selection: Selection,
                identities: NativeCommitIdentityBundle
            ) -> NativeCommitTransition {
                let binding = FilesystemObservationSlotBinding(value: 1)
                let startingNativeLifetime = FilesystemObservationStartingNativeLifetime(value: 1)
                \(extraCompletionStatements)
                _ = (selection, identities, binding)
                return NativeCommitTransition(startingNativeLifetime: startingNativeLifetime)
            }
        }
        """
    }

    private var registryPath: String {
        filesystemSourcePath("FilesystemObservationSlotRegistry.swift")
    }

    private var contractsPath: String {
        filesystemSourcePath("FilesystemObservationSlotRegistryContracts.swift")
    }

    private var admissionPlannerPath: String {
        filesystemSourcePath("FilesystemObservationSlotAdmissionPlanner.swift")
    }

    private var nativeRetirementExtensionPath: String {
        filesystemSourcePath("FilesystemObservationSlotRegistry+NativeRetirement.swift")
    }

    private var primaryOwnerMessage: String {
        "FilesystemObservationSlotRegistry must remain exactly one top-level final primary class in its owner file"
    }

    private var ownerExtensionMessage: String {
        "FilesystemObservationSlotRegistry must not have production extensions"
    }

    private var nativeRetirementStorageMessage: String {
        "Filesystem observation native-retirement storage may be used only by the registry owner and its canonical native-retirement extension"
    }

    private var ownerAliasMessage: String {
        "FilesystemObservationSlotRegistry must not be aliased in production"
    }

    private var identityOutsideTransitionMessage: String {
        "Filesystem observation binding/control/native identity issuance must occur directly in beginNativeLifetime's requiresNativeLifetimeIdentities transition"
    }

    private var completionOutsidePlannerMessage: String {
        "Filesystem observation binding and starting-lifetime construction must occur only in FilesystemObservationSlotAdmissionPlanner.completeNativeCommit"
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

    private var plannerUUIDGenerationMessage: String {
        "Filesystem observation planners must not generate UUIDv7 identities"
    }
}

private struct SourceProbe {
    let path: String
    let contents: String
}
