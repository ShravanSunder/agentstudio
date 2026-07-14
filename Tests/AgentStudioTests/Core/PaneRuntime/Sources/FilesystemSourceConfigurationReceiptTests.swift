import Foundation
import Testing

@testable import AgentStudio

@Suite("Filesystem source configuration receipt")
struct FilesystemSourceConfigurationReceiptTests {
    @Test("source kind is derived from the registration source identity")
    func sourceKindIsDerivedFromRegistration() {
        let configuration = makeConfiguration(
            sourceID: makeSourceID(kind: .registeredWorktreeContent)
        )

        #expect(configuration.sourceKind == .registeredWorktreeContent)
        #expect(configuration.sourceID == configuration.registration.sourceID)
    }

    @Test("installed configuration awaiting continuity repair is exact and non-current")
    func installedAwaitingContinuityRepairIsExactAndNonCurrent() throws {
        let repairingSourceID = makeSourceID()
        let installedSourceID = makeSourceID()
        let repairingConfiguration = makeConfiguration(sourceID: repairingSourceID)
        let handoffIdentity = FilesystemContinuityRepairHandoffIdentity(value: UUIDv7.generate())

        let receipt = try FilesystemSourceConfigurationReceipt(
            acceptedTopologyRevision: 43,
            requestedSourceIDs: [repairingSourceID, installedSourceID],
            dispositions: [
                repairingSourceID: .installedAwaitingContinuityRepair(
                    desiredConfiguration: repairingConfiguration,
                    handoffIdentity: handoffIdentity
                ),
                installedSourceID: .installed(makeConfiguration(sourceID: installedSourceID)),
            ]
        )

        #expect(handoffIdentity.isUUIDv7)
        #expect(
            receipt.currentness == .nonCurrent(retrySources: [repairingSourceID])
        )
    }

    @Test("installed awaiting repair rejects a configuration for another source")
    func installedAwaitingContinuityRepairRejectsForeignSource() {
        let requestedSourceID = makeSourceID()
        let foreignSourceID = makeSourceID()

        #expect(throws: FilesystemConfigurationReceiptError.self) {
            try FilesystemSourceConfigurationReceipt(
                acceptedTopologyRevision: 44,
                requestedSourceIDs: [requestedSourceID],
                dispositions: [
                    requestedSourceID: .installedAwaitingContinuityRepair(
                        desiredConfiguration: makeConfiguration(sourceID: foreignSourceID),
                        handoffIdentity: FilesystemContinuityRepairHandoffIdentity(
                            value: UUIDv7.generate()
                        )
                    )
                ]
            )
        }
    }

    @Test("cross-kind change is represented by independent source-keyed entries")
    func crossKindChangeUsesRemovalAndInstallEntries() throws {
        let oldSourceID = makeSourceID(kind: .watchedParentMembership)
        let newSourceID = makeSourceID(kind: .registeredWorktreeContent)

        let receipt = try FilesystemSourceConfigurationReceipt(
            acceptedTopologyRevision: 45,
            requestedSourceIDs: [oldSourceID, newSourceID],
            dispositions: [
                oldSourceID: .removalComplete,
                newSourceID: .installed(makeConfiguration(sourceID: newSourceID)),
            ]
        )

        #expect(receipt.dispositions.count == 2)
        #expect(receipt.currentness == .current)
    }

    @Test("receipt rejects missing and unexpected source dispositions together")
    func receiptRejectsNonTotalDispositionCoverage() {
        let requestedSourceID = makeSourceID()
        let unexpectedSourceID = makeSourceID()
        let unexpectedConfiguration = makeConfiguration(sourceID: unexpectedSourceID)

        #expect(throws: FilesystemConfigurationReceiptError.self) {
            try FilesystemSourceConfigurationReceipt(
                acceptedTopologyRevision: 42,
                requestedSourceIDs: [requestedSourceID],
                dispositions: [unexpectedSourceID: .installed(unexpectedConfiguration)]
            )
        }

        do {
            _ = try FilesystemSourceConfigurationReceipt(
                acceptedTopologyRevision: 42,
                requestedSourceIDs: [requestedSourceID],
                dispositions: [unexpectedSourceID: .installed(unexpectedConfiguration)]
            )
            Issue.record("Expected non-total disposition coverage to be rejected")
        } catch let error as FilesystemConfigurationReceiptError {
            #expect(
                error
                    == .dispositionCoverageMismatch(
                        missing: [requestedSourceID],
                        unexpected: [unexpectedSourceID]
                    )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("receipt rejects a disposition whose configuration belongs to another source")
    func receiptRejectsDispositionSourceMismatch() {
        let requestedSourceID = makeSourceID()
        let foreignSourceID = makeSourceID()
        let foreignConfiguration = makeConfiguration(sourceID: foreignSourceID)

        #expect(throws: FilesystemConfigurationReceiptError.self) {
            try FilesystemSourceConfigurationReceipt(
                acceptedTopologyRevision: 7,
                requestedSourceIDs: [requestedSourceID],
                dispositions: [requestedSourceID: .unchanged(foreignConfiguration)]
            )
        }

        do {
            _ = try FilesystemSourceConfigurationReceipt(
                acceptedTopologyRevision: 7,
                requestedSourceIDs: [requestedSourceID],
                dispositions: [requestedSourceID: .unchanged(foreignConfiguration)]
            )
            Issue.record("Expected foreign disposition configuration to be rejected")
        } catch let error as FilesystemConfigurationReceiptError {
            #expect(
                error
                    == .dispositionSourceMismatches([
                        FilesystemConfigurationSourceMismatch(
                            receiptSourceID: requestedSourceID,
                            dispositionSourceID: foreignSourceID
                        )
                    ])
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("currentness retry set derives only from non-current dispositions")
    func currentnessDerivesOnlyFromClosedDispositions() throws {
        let installedSourceID = makeSourceID()
        let unchangedSourceID = makeSourceID()
        let removedSourceID = makeSourceID()
        let deferredRetainingSourceID = makeSourceID()
        let deferredNonCurrentSourceID = makeSourceID()
        let failedRetainingSourceID = makeSourceID()
        let failedNonCurrentSourceID = makeSourceID()

        let requestedSourceIDs: Set<FilesystemSourceID> = [
            installedSourceID,
            unchangedSourceID,
            removedSourceID,
            deferredRetainingSourceID,
            deferredNonCurrentSourceID,
            failedRetainingSourceID,
            failedNonCurrentSourceID,
        ]
        let dispositions: [FilesystemSourceID: FilesystemSourceConfigurationDisposition] = [
            installedSourceID: .installed(makeConfiguration(sourceID: installedSourceID)),
            unchangedSourceID: .unchanged(makeConfiguration(sourceID: unchangedSourceID)),
            removedSourceID: .removalComplete,
            deferredRetainingSourceID: .deferred(
                .retainingCurrent(
                    existingConfiguration: makeConfiguration(
                        sourceID: deferredRetainingSourceID,
                        registrationGeneration: 1
                    ),
                    desiredConfiguration: makeConfiguration(
                        sourceID: deferredRetainingSourceID,
                        registrationGeneration: 2
                    ),
                    reason: .replacementSlotCapacity
                )
            ),
            deferredNonCurrentSourceID: .deferred(
                .nonCurrent(
                    desiredConfiguration: makeConfiguration(
                        sourceID: deferredNonCurrentSourceID
                    ),
                    reason: .predecessorRetirement
                )
            ),
            failedRetainingSourceID: .failed(
                .retainingCurrent(
                    existingConfiguration: makeConfiguration(
                        sourceID: failedRetainingSourceID,
                        registrationGeneration: 1
                    ),
                    desiredConfiguration: makeConfiguration(
                        sourceID: failedRetainingSourceID,
                        registrationGeneration: 2
                    ),
                    stage: .create
                )
            ),
            failedNonCurrentSourceID: .failed(
                .nonCurrent(
                    desiredConfiguration: makeConfiguration(sourceID: failedNonCurrentSourceID),
                    stage: .start
                )
            ),
        ]

        let receipt = try FilesystemSourceConfigurationReceipt(
            acceptedTopologyRevision: 91,
            requestedSourceIDs: requestedSourceIDs,
            dispositions: dispositions
        )

        #expect(
            receipt.currentness
                == .nonCurrent(
                    retrySources: [deferredNonCurrentSourceID, failedNonCurrentSourceID]
                )
        )
    }

    @Test("receipt with no non-current disposition derives current")
    func receiptWithoutNonCurrentDispositionDerivesCurrent() throws {
        let installedSourceID = makeSourceID()
        let removedSourceID = makeSourceID()

        let receipt = try FilesystemSourceConfigurationReceipt(
            acceptedTopologyRevision: 12,
            requestedSourceIDs: [installedSourceID, removedSourceID],
            dispositions: [
                installedSourceID: .installed(makeConfiguration(sourceID: installedSourceID)),
                removedSourceID: .removalComplete,
            ]
        )

        #expect(receipt.currentness == .current)
    }

    private func makeConfiguration(
        sourceID: FilesystemSourceID,
        registrationGeneration: UInt64 = 1
    ) -> FilesystemObservationSourceConfiguration {
        FilesystemObservationSourceConfiguration(
            registration: FSEventRegistrationToken(
                sourceID: sourceID,
                registrationGeneration: registrationGeneration,
                rootGeneration: registrationGeneration
            ),
            canonicalResolvedRootIdentity: FilesystemCanonicalResolvedRootIdentity(
                path: "/tmp/\(sourceID.rootID.uuidString)"
            ),
            authorizationScopeIdentity: FilesystemAuthorizationScopeIdentity(
                value: sourceID.rootID
            ),
            eventCoverage: .recursiveFileEvents
        )
    }

    private func makeSourceID(
        kind: FilesystemSourceKind = .watchedParentMembership
    ) -> FilesystemSourceID {
        FilesystemSourceID(kind: kind, rootID: UUID())
    }
}
