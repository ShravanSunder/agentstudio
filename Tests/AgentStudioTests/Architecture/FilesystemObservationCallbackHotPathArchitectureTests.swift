import Foundation
import Testing

@Suite("Filesystem observation callback hot-path architecture")
struct FilesystemCallbackHotPathArchitectureTests {
    @Test("paired factory solely mints callback lease admission authority")
    func callbackLeaseAdmissionAuthorityIsPairedAndPrivate() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let coreSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailboxCore.swift"
            ),
            encoding: .utf8
        )
        let facadeSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailbox.swift"
            ),
            encoding: .utf8
        )
        let callbackPort = try #require(
            coreSource.callbackProofSlice(
                from: "struct FilesystemObservationCallbackAdmissionPort:",
                to: "struct FilesystemObservationNativeLifecyclePort:"
            )
        )
        let callbackOperation = try #require(
            coreSource.callbackProofSlice(
                from: "private final class FilesystemObservationCallbackAdmissionOperation",
                to: "final class FilesystemObservationMailboxCore"
            )
        )
        let pairedFactory = try #require(
            coreSource.callbackProofSlice(
                from: "    private func makeNativeGenerationPorts(\n",
                to: "    var actorConsumerPort:"
            )
        )

        // Act / Assert
        #expect(
            coreSource.callbackProofOccurrenceCount(
                of: "CallbackLeaseAdmissionAuthority(\n            binding:"
            ) == 1
        )
        #expect(
            pairedFactory.callbackProofOccurrenceCount(
                of: "CallbackLeaseAdmissionAuthority(\n            binding:"
            ) == 1
        )
        #expect(
            callbackOperation.callbackProofOccurrenceCount(
                of: "lease.withOneShotCallbackAdmission("
            ) == 1
        )
        #expect(callbackOperation.contains("private let leaseAdmissionAuthority:"))
        #expect(!callbackPort.contains("CallbackLeaseAdmissionAuthority"))
        #expect(!facadeSource.contains("CallbackLeaseAdmissionAuthority"))
    }

    @Test("accepted callback uses one keyed validation and one validated generic offer")
    // swiftlint:disable:next function_body_length
    func acceptedCallbackHasConstantShape() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let coreSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailboxCore.swift"
            ),
            encoding: .utf8
        )
        let slotRegistrySource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistry.swift"
            ),
            encoding: .utf8
        )
        let gatherMailboxSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Admission/BoundedGatherMailbox.swift"
            ),
            encoding: .utf8
        )
        let callbackAdmissionOperation = try #require(
            coreSource.callbackProofSlice(
                from: "private final class FilesystemObservationCallbackAdmissionOperation",
                to: "final class FilesystemObservationMailboxCore"
            )
        )
        let callbackAdmissionBody = try #require(
            callbackAdmissionOperation.callbackProofSlice(
                from: "    func admit(\n        using lease: FSEventCallbackLease,",
                to: "    private func applyWakeAndMap("
            )
        )
        let captureAndOfferBody = try #require(
            coreSource.callbackProofSlice(
                from: "    fileprivate func captureAndOffer(",
                to: "    fileprivate func applyCallbackWake("
            )
        )
        let validatedOfferBody = try #require(
            coreSource.callbackProofSlice(
                from: "    private func offerValidatedBindingLocked(",
                to: "    func bindConsumer()"
            )
        )
        let applyCallbackWakeBody = try #require(
            coreSource.callbackProofSlice(
                from: "    fileprivate func applyCallbackWake(",
                to: "    private func offerValidatedBindingLocked("
            )
        )
        let storedBindingCurrentnessBody = try #require(
            slotRegistrySource.callbackProofSlice(
                from: "    func storedBindingCurrentness(\n",
                to: "    func recordDesiredRegistration("
            )
        )
        let keyedSlotStateBody = try #require(
            slotRegistrySource.callbackProofSlice(
                from: "    func state(\n",
                to: "    func storedBindingCurrentness("
            )
        )
        let genericOfferBody = try #require(
            gatherMailboxSource.callbackProofSlice(
                from: "    fileprivate func offer(\n",
                to: "    private func makeOfferContext("
            )
        )
        let makeOfferContextBody = try #require(
            gatherMailboxSource.callbackProofSlice(
                from: "    private func makeOfferContext(\n",
                to: "    private func attemptOffer("
            )
        )
        let attemptOfferBody = try #require(
            gatherMailboxSource.callbackProofSlice(
                from: "    private func attemptOffer(",
                to: "    fileprivate func bindConsumer()"
            )
        )
        let ordinaryRetainedPath =
            callbackAdmissionBody + captureAndOfferBody + validatedOfferBody
            + applyCallbackWakeBody + storedBindingCurrentnessBody
            + makeOfferContextBody + attemptOfferBody

        // Act / Assert
        #expect(callbackAdmissionBody.callbackProofOccurrenceCount(of: "core.captureAndOffer(") == 1)
        #expect(
            callbackAdmissionBody.callbackProofOccurrenceCount(
                of: "synchronization.afterAuthorityConsumedBeforeMailboxOffer()"
            ) == 1
        )
        #expect(
            callbackAdmissionBody.callbackProofOccurrenceCount(
                of: "synchronization.afterMailboxOfferBeforeWakeApplication()"
            ) == 1
        )
        #expect(callbackAdmissionBody.callbackProofOccurrenceCount(of: "applyWakeAndMap(mailboxResult)") == 1)
        #expect(callbackAdmissionBody.callbackProofOccurrenceCount(of: "lease.withOneShotCallbackAdmission(") == 1)

        #expect(
            captureAndOfferBody.callbackProofOccurrenceCount(
                of: "slotRegistry.storedBindingCurrentness(of: binding)"
            ) == 1
        )
        #expect(captureAndOfferBody.callbackProofOccurrenceCount(of: "switch capture()") == 1)
        #expect(captureAndOfferBody.callbackProofOccurrenceCount(of: "lock.withLockUnchecked") == 1)
        #expect(
            captureAndOfferBody.callbackProofOccurrenceCount(
                of: "offerValidatedBindingLocked(offer, for: binding, state: &state)"
            ) == 1
        )
        #expect(captureAndOfferBody.callbackProofOccurrenceCount(of: "offerLocked(") == 0)

        #expect(
            validatedOfferBody.callbackProofOccurrenceCount(
                of: "slotRegistry.storedBindingCurrentness"
            ) == 0
        )
        #expect(validatedOfferBody.callbackProofOccurrenceCount(of: "gatherMailbox.producerPort.offer(") == 1)
        #expect(validatedOfferBody.callbackProofOccurrenceCount(of: "key: binding.physicalSlotID") == 1)
        #expect(validatedOfferBody.callbackProofOccurrenceCount(of: "slotRegistry.physicalSlotIDs") == 0)
        #expect(validatedOfferBody.callbackProofOccurrenceCount(of: "recoveryRegister.") == 0)

        #expect(
            storedBindingCurrentnessBody.callbackProofOccurrenceCount(
                of: "state(of: binding.physicalSlotID)"
            ) == 1
        )
        #expect(storedBindingCurrentnessBody.callbackProofOccurrenceCount(of: "statesByPhysicalSlotID.") == 0)
        #expect(
            storedBindingCurrentnessBody.callbackProofOccurrenceCount(
                of: "FilesystemObservationSlotCurrentnessClassifier.classify("
            ) == 1
        )
        #expect(
            keyedSlotStateBody.callbackProofOccurrenceCount(
                of: "statesByPhysicalSlotID[physicalSlotID]"
            ) == 1
        )
        #expect(keyedSlotStateBody.callbackProofOccurrenceCount(of: "statesByPhysicalSlotID.") == 0)

        #expect(genericOfferBody.callbackProofOccurrenceCount(of: "makeOfferContext(for: contribution.key)") == 1)
        #expect(genericOfferBody.callbackProofOccurrenceCount(of: "attemptOffer(") == 1)
        #expect(genericOfferBody.callbackProofOccurrenceCount(of: "while true") == 1)
        #expect(genericOfferBody.callbackProofOccurrenceCount(of: "declaredSlotsByKey") == 0)
        #expect(genericOfferBody.callbackProofOccurrenceCount(of: ".keys") == 0)
        #expect(genericOfferBody.callbackProofOccurrenceCount(of: ".values") == 0)

        #expect(makeOfferContextBody.callbackProofOccurrenceCount(of: "declaredSlotsByKey[key]") == 1)
        #expect(attemptOfferBody.callbackProofOccurrenceCount(of: "withAdmissionProtectedState") == 1)
        #expect(attemptOfferBody.callbackProofOccurrenceCount(of: "case .retain(let context)") == 1)
        #expect(attemptOfferBody.callbackProofOccurrenceCount(of: "completeRetainedOffer(") == 2)
        #expect(attemptOfferBody.callbackProofOccurrenceCount(of: "recoveryRegister.") == 0)

        #expect(applyCallbackWakeBody.callbackProofOccurrenceCount(of: "doorbell.ownerPort.apply(wake)") == 1)
        #expect(ordinaryRetainedPath.callbackProofOccurrenceCount(of: "doorbell.ownerPort.apply(") == 1)
        #expect(ordinaryRetainedPath.callbackProofOccurrenceCount(of: "recoveryRegister.") == 0)

        for forbiddenOperation in [
            ".keys", ".values", ".map(", ".filter(", ".reduce(", "Task {", "Task." + "detached",
            "await ", "actorConsumerPort", "@MainActor", "MainActor.run", "EventBus", "RuntimeEnvelope",
            "physicalSlotIDs.map", "Array(statesByPhysicalSlotID", "contiguousPhysicalSlotIDs",
        ] {
            #expect(
                !ordinaryRetainedPath.contains(forbiddenOperation),
                "Accepted callback path must not contain \(forbiddenOperation)"
            )
        }
        for forbiddenLoopPattern in [
            #"(?m)^\s*for\s+[A-Za-z_][A-Za-z0-9_]*\s+in\b"#,
            #"(?m)^\s*while\s+"#,
        ] {
            #expect(
                ordinaryRetainedPath.range(
                    of: forbiddenLoopPattern,
                    options: .regularExpression
                ) == nil,
                "Accepted callback path must not contain a loop matching \(forbiddenLoopPattern)"
            )
        }
    }

    @Test("facade forwards typed operations without owning mutable custody")
    func facadeOwnsNoMutableCustody() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let facadeSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailbox.swift"
            ),
            encoding: .utf8
        )
        let coreSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailboxCore.swift"
            ),
            encoding: .utf8
        )
        let coreOwnedCustodyDeclarations = [
            "private struct State: Sendable",
            "private let slotRegistry: FilesystemObservationSlotRegistry",
            "private let gatherMailbox:",
            "private let recoveryRegister: FixedFilesystemRecoveryEvidenceRegister",
            "private let doorbell = AdmissionDoorbell()",
            "private let lock: OSAllocatedUnfairLock<State>",
        ]
        let facadeForbiddenCustodyOperations = [
            "OSAllocatedUnfairLock",
            "private struct State",
            "slotRegistry",
            "gatherMailbox",
            "recoveryRegister",
            "AdmissionDoorbell(",
            "doorbell.ownerPort",
            "UUIDv7.generate()",
            "GatherProducerPort",
            "AdmissionDoorbellSignalerPort",
            ".producerPort",
            ".signalerPort",
            ".ownerPort",
            ".withLock",
            "Task {",
            "Task." + "detached",
            "MainActor.run",
            "@MainActor",
        ]

        // Act / Assert
        #expect(
            facadeSource.callbackProofOccurrenceCount(
                of: "private let core: FilesystemObservationMailboxCore"
            ) == 1
        )
        #expect(
            facadeSource.callbackProofOccurrenceCount(of: "private let ") == 1,
            "Facade must retain only its core forwarding reference"
        )
        #expect(facadeSource.contains("core.nativeGenerationPorts("))
        #expect(!facadeSource.contains("func callbackAdmissionPort("))
        #expect(!coreSource.contains("func callbackAdmissionPort("))
        #expect(!facadeSource.contains("func offer("))
        #expect(!coreSource.contains("func offer("))
        #expect(
            facadeSource.range(
                of: #"(?m)^\s*private\s+var\s+"#,
                options: .regularExpression
            ) == nil,
            "Facade must not retain private mutable state"
        )
        #expect(
            facadeSource.range(
                of: #"\basync\b"#,
                options: .regularExpression
            ) == nil,
            "Facade operations must remain synchronous rather than creating actor work"
        )
        #expect(
            facadeSource.range(
                of: #"(?m)^\s*(?:fileprivate\s+|private\s+|internal\s+|public\s+)?actor\s+"#,
                options: .regularExpression
            ) == nil,
            "Facade must not declare an actor executor"
        )

        for custodyDeclaration in coreOwnedCustodyDeclarations {
            #expect(
                coreSource.callbackProofOccurrenceCount(of: custodyDeclaration) == 1,
                "Core must own exactly one declaration matching \(custodyDeclaration)"
            )
            #expect(
                !facadeSource.contains(custodyDeclaration),
                "Facade must not duplicate core custody matching \(custodyDeclaration)"
            )
        }
        for forbiddenOperation in facadeForbiddenCustodyOperations {
            #expect(
                !facadeSource.contains(forbiddenOperation),
                "Facade must not contain raw custody operation \(forbiddenOperation)"
            )
        }
    }

    @Test("contribution identity construction is owned by the mailbox core")
    func contributionIdentityConstructionIsCoreOwned() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let filesystemSourceDirectory = projectRoot.appending(
            path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem"
        )
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: filesystemSourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { $0.pathExtension == "swift" }
        let constructionNeedle = "FilesystemObservationContributionIdentity("
        var filesContainingConstruction: Set<String> = []

        // Act
        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            if source.contains(constructionNeedle) {
                filesContainingConstruction.insert(sourceFile.lastPathComponent)
            }
        }

        // Assert
        #expect(filesContainingConstruction == Set(["FilesystemObservationMailboxCore.swift"]))
    }

    @Test("core is the sole raw custody owner across mailbox sidecars")
    func mailboxSidecarsOwnNoMutableCustody() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let filesystemSourceDirectory = projectRoot.appending(
            path: "Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem"
        )
        let mailboxSourceFiles = try FileManager.default.contentsOfDirectory(
            at: filesystemSourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter {
            $0.lastPathComponent.hasPrefix("FilesystemObservationMailbox")
                && $0.pathExtension == "swift"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let coreFilename = "FilesystemObservationMailboxCore.swift"
        let expectedMailboxFilenames = Set([
            "FilesystemObservationMailbox.swift",
            "FilesystemObservationMailboxContracts.swift",
            coreFilename,
            "FilesystemObservationMailboxProjection.swift",
        ])
        let rawCustodyVocabulary = [
            "OSAllocatedUnfairLock",
            "private struct State: Sendable",
            "private let slotRegistry:",
            "private let gatherMailbox:",
            "private let recoveryRegister:",
            "private let doorbell = AdmissionDoorbell()",
            "slotRegistry.",
            "gatherMailbox.",
            "recoveryRegister.",
            "doorbell.ownerPort",
            "UUIDv7.generate()",
        ]
        var owningFilenamesByVocabulary: [String: Set<String>] = [:]
        var coreDeclarationCount = 0
        var coreExtensionCount = 0

        // Act
        for mailboxSourceFile in mailboxSourceFiles {
            let filename = mailboxSourceFile.lastPathComponent
            let source = try String(contentsOf: mailboxSourceFile, encoding: .utf8)
            coreDeclarationCount += source.callbackProofOccurrenceCount(
                of: "final class FilesystemObservationMailboxCore"
            )
            coreExtensionCount += source.callbackProofOccurrenceCount(
                of: "extension FilesystemObservationMailboxCore"
            )
            for custodyVocabulary in rawCustodyVocabulary
            where source.contains(custodyVocabulary) {
                owningFilenamesByVocabulary[custodyVocabulary, default: []].insert(filename)
            }
        }

        // Assert
        #expect(
            Set(mailboxSourceFiles.map(\.lastPathComponent)).isSuperset(
                of: expectedMailboxFilenames
            )
        )
        #expect(coreDeclarationCount == 1)
        #expect(coreExtensionCount == 0)
        for custodyVocabulary in rawCustodyVocabulary {
            #expect(
                owningFilenamesByVocabulary[custodyVocabulary] == Set([coreFilename]),
                "Only the core may contain raw custody vocabulary \(custodyVocabulary)"
            )
        }
    }
}

extension String {
    fileprivate func callbackProofSlice(
        from startMarker: String,
        to endMarker: String
    ) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }

    fileprivate func callbackProofOccurrenceCount(of value: String) -> Int {
        components(separatedBy: value).count - 1
    }
}
