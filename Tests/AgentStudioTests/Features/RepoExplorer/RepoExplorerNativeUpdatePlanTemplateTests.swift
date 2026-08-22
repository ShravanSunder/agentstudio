import Foundation
import Testing

@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@Suite("Repo Explorer native update plan templates")
struct RepoExplorerNativeUpdatePlanTemplateTests {
    @Test("forward and reverse templates instantiate ordinary plans with identity-only changes")
    func forwardAndReverseTemplatesInstantiateOrdinaryPlans() throws {
        let source = nativePlanContent(nativePlanSnapshot(["A", "B", "C"]))
        let target = nativePlanContent(nativePlanSnapshot(["C", "D", "A"], changedTitles: ["A"]))
        let templates = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ).get()
        let baseline = nativePlanBaseline(
            snapshot: try #require(source.contentSnapshot),
            revision: 41,
            lifetime: nativePlanLifetime(7),
            demandEpoch: 19,
            visibleGeneration: 80
        )

        let firstCandidate = try templates.forward.instantiate(
            baseline: baseline,
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 91),
            requestGeneration: 81,
            visibleGeneration: 81
        ).get()
        let secondCandidate = try templates.forward.instantiate(
            baseline: RepoExplorerMaterializationBaseline(
                lifetimeID: nativePlanLifetime(8),
                demandEpoch: 20,
                revision: 99,
                visibleGeneration: 100,
                presentation: source
            ),
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 92),
            requestGeneration: 101,
            visibleGeneration: 101
        ).get()

        #expect(firstCandidate.id.rawValue == 91)
        #expect(firstCandidate.lifetimeID == nativePlanLifetime(7))
        #expect(firstCandidate.demandEpoch == 19)
        #expect(firstCandidate.expectedRevision == 41)
        #expect(firstCandidate.proposedRevision == 42)
        #expect(firstCandidate.presentation == target)
        #expect(secondCandidate.expectedRevision == 99)
        #expect(secondCandidate.proposedRevision == 100)
        #expect(
            firstCandidate.nativeUpdatePlan.tableUpdatePlan()
                == secondCandidate.nativeUpdatePlan.tableUpdatePlan()
        )

        let reverseBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: firstCandidate.lifetimeID,
            demandEpoch: firstCandidate.demandEpoch,
            revision: firstCandidate.proposedRevision,
            visibleGeneration: firstCandidate.visibleGeneration,
            presentation: firstCandidate.presentation
        )
        let reverseCandidate = try templates.reverse.instantiate(
            baseline: reverseBaseline,
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 93),
            requestGeneration: 82,
            visibleGeneration: 82
        ).get()
        #expect(reverseCandidate.presentation == source)
        #expect(reverseCandidate.expectedRevision == 42)
        #expect(reverseCandidate.proposedRevision == 43)

        let forwardTablePlan = try #require(firstCandidate.nativeUpdatePlan.tableUpdatePlan())
        guard case .membership(let forwardMembership) = forwardTablePlan else {
            Issue.record("Expected forward membership plan")
            return
        }
        #expect(
            forwardMembership.anchorFallbacks.entries == [
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "B"),
                    targetRowID: .group(groupID: "C")
                )
            ]
        )

        let reverseTablePlan = try #require(reverseCandidate.nativeUpdatePlan.tableUpdatePlan())
        guard case .membership(let reverseMembership) = reverseTablePlan else {
            Issue.record("Expected reverse membership plan")
            return
        }
        #expect(
            reverseMembership.anchorFallbacks.entries == [
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "D"),
                    targetRowID: .group(groupID: "A")
                )
            ]
        )
    }

    @Test("instantiation rejects stale kind count fingerprint and revision overflow")
    func instantiationRejectsStaleBaselines() throws {
        let sourceSnapshot = nativePlanSnapshot(["A", "B"])
        let source = nativePlanContent(sourceSnapshot)
        let target = nativePlanContent(nativePlanSnapshot(["B", "C"]))
        let template = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ).get().forward
        let validBaseline = nativePlanBaseline(snapshot: sourceSnapshot, revision: 4)

        #expect(
            template.instantiate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 4),
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
                requestGeneration: 11,
                visibleGeneration: 11
            ) == .failure(.baselinePresentationKindMismatch)
        )
        #expect(
            template.instantiate(
                baseline: nativePlanBaseline(snapshot: nativePlanSnapshot(["A"]), revision: 4),
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
                requestGeneration: 11,
                visibleGeneration: 11
            ) == .failure(.baselineCountMismatch)
        )
        let mismatchedFingerprint = RepoExplorerMaterializationBaseline(
            lifetimeID: validBaseline.lifetimeID,
            demandEpoch: validBaseline.demandEpoch,
            revision: validBaseline.revision,
            visibleGeneration: validBaseline.visibleGeneration,
            presentation: .content(
                snapshot: sourceSnapshot,
                fingerprint: RepoExplorerMaterializationFingerprint(rawValue: 999)
            )
        )
        #expect(
            template.instantiate(
                baseline: mismatchedFingerprint,
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
                requestGeneration: 11,
                visibleGeneration: 11
            ) == .failure(.baselineFingerprintMismatch)
        )
        #expect(
            template.instantiate(
                baseline: nativePlanBaseline(snapshot: sourceSnapshot, revision: .max),
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
                requestGeneration: 11,
                visibleGeneration: 11
            ) == .failure(.revisionOverflow)
        )
    }

    @Test("template pair is Sendable and alternates monotonically through R")
    func templatesAreSendableAndAlternateRevision() throws {
        requireSendable(RepoExplorerNativeUpdatePlanTemplatePair.self)
        let source = nativePlanContent(nativePlanSnapshot(["A", "B"]))
        let target = nativePlanContent(nativePlanSnapshot(["B", "A", "C"]))
        let templates = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ).get()
        var baseline = RepoExplorerMaterializationBaseline(
            lifetimeID: nativePlanLifetime(),
            demandEpoch: 7,
            revision: 0,
            visibleGeneration: 0,
            presentation: source
        )

        for step in 1...20 {
            let template = step.isMultiple(of: 2) ? templates.reverse : templates.forward
            let candidate = try template.instantiate(
                baseline: baseline,
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: UInt64(step)),
                requestGeneration: UInt64(step),
                visibleGeneration: UInt64(step)
            ).get()
            #expect(candidate.expectedRevision == UInt64(step - 1))
            #expect(candidate.proposedRevision == UInt64(step))
            baseline = RepoExplorerMaterializationBaseline(
                lifetimeID: candidate.lifetimeID,
                demandEpoch: candidate.demandEpoch,
                revision: candidate.proposedRevision,
                visibleGeneration: candidate.visibleGeneration,
                presentation: candidate.presentation
            )
        }
    }

    @Test("instantiation is identity-only and template construction stays private")
    func instantiationSourceContractIsConstantWork() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerNativeUpdatePlanTemplate.swift"
            ),
            encoding: .utf8
        )
        let instantiateSource = try #require(
            source.components(separatedBy: "    func instantiate(").dropFirst().first?
                .components(separatedBy: "\n}\n\nextension RepoExplorerProjectionWorker").first
        )

        #expect(source.contains("fileprivate init("))
        #expect(!source.contains("public "))
        #expect(!source.contains("package "))
        #expect(!instantiateSource.contains("validating("))
        #expect(!instantiateSource.contains(".make("))
        #expect(!instantiateSource.contains(".map"))
        #expect(!instantiateSource.contains(".sorted"))
        #expect(!instantiateSource.contains("Dictionary"))
        #expect(!instantiateSource.contains("rows"))
    }
}

private func requireSendable<T: Sendable>(_: T.Type) {}
