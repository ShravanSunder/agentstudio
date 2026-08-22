import Foundation

enum RepoExplorerNativeUpdatePlanTemplateSealError: Error, Equatable {
    case forwardValidation(RepoExplorerNativeUpdatePlan.ValidationError)
    case reverseValidation(RepoExplorerNativeUpdatePlan.ValidationError)
    case equalTransition
}

enum RepoExplorerNativeTemplateInstantiationError: Error, Equatable {
    case baselinePresentationKindMismatch
    case baselineCountMismatch
    case baselineFingerprintMismatch
    case invalidCandidateIdentity
    case invalidGeneration
    case revisionOverflow
}

struct RepoExplorerNativeUpdatePlanTemplatePair: Sendable {
    let forward: RepoExplorerNativeUpdatePlanTemplate
    let reverse: RepoExplorerNativeUpdatePlanTemplate

    private init(
        forward: RepoExplorerNativeUpdatePlanTemplate,
        reverse: RepoExplorerNativeUpdatePlanTemplate
    ) {
        self.forward = forward
        self.reverse = reverse
    }

    fileprivate static func sealing(
        source: RepoExplorerMaterializationPresentation,
        target: RepoExplorerMaterializationPresentation
    ) -> Result<Self, RepoExplorerNativeUpdatePlanTemplateSealError> {
        let prototypeLifetime = RepoExplorerMaterializationHostLifetimeID(
            rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        )
        let sourceBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: prototypeLifetime,
            demandEpoch: 0,
            revision: 0,
            visibleGeneration: 0,
            presentation: source
        )
        let targetBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: prototypeLifetime,
            demandEpoch: 0,
            revision: 0,
            visibleGeneration: 0,
            presentation: target
        )

        let forwardPlan: RepoExplorerNativeUpdatePlan
        switch RepoExplorerNativeUpdatePlan.validating(
            baseline: sourceBaseline,
            candidate: target,
            requestGeneration: 1
        ) {
        case .success(let plan): forwardPlan = plan
        case .failure(let error): return .failure(.forwardValidation(error))
        }
        let reversePlan: RepoExplorerNativeUpdatePlan
        switch RepoExplorerNativeUpdatePlan.validating(
            baseline: targetBaseline,
            candidate: source,
            requestGeneration: 1
        ) {
        case .success(let plan): reversePlan = plan
        case .failure(let error): return .failure(.reverseValidation(error))
        }
        guard let forwardPayload = forwardPlan.sealedChangedTemplatePayload(),
            let reversePayload = reversePlan.sealedChangedTemplatePayload()
        else {
            return .failure(.equalTransition)
        }

        return .success(
            Self(
                forward: RepoExplorerNativeUpdatePlanTemplate(
                    source: source,
                    target: target,
                    payload: forwardPayload
                ),
                reverse: RepoExplorerNativeUpdatePlanTemplate(
                    source: target,
                    target: source,
                    payload: reversePayload
                )
            )
        )
    }
}

struct RepoExplorerNativeUpdatePlanTemplate: Sendable {
    private enum PresentationKind: Sendable {
        case rowless
        case content

        init(_ presentation: RepoExplorerMaterializationPresentation) {
            switch presentation {
            case .rowless: self = .rowless
            case .content: self = .content
            }
        }
    }

    private let sourceKind: PresentationKind
    private let sourceCount: Int
    private let sourceFingerprint: RepoExplorerMaterializationFingerprint
    private let target: RepoExplorerMaterializationPresentation
    private let payload: RepoExplorerNativeChangedPlanTemplatePayload

    fileprivate init(
        source: RepoExplorerMaterializationPresentation,
        target: RepoExplorerMaterializationPresentation,
        payload: RepoExplorerNativeChangedPlanTemplatePayload
    ) {
        sourceKind = PresentationKind(source)
        sourceCount = source.rowCount
        sourceFingerprint = source.fingerprint
        self.target = target
        self.payload = payload
    }

    func instantiate(
        baseline: RepoExplorerMaterializationBaseline,
        candidateID: RepoExplorerMaterializationCandidateID,
        requestGeneration: UInt64,
        visibleGeneration: UInt64
    ) -> Result<
        RepoExplorerMaterializationCandidate,
        RepoExplorerNativeTemplateInstantiationError
    > {
        guard sourceKind == PresentationKind(baseline.presentation) else {
            return .failure(.baselinePresentationKindMismatch)
        }
        guard baseline.rowCount == sourceCount else {
            return .failure(.baselineCountMismatch)
        }
        guard baseline.fingerprint == sourceFingerprint else {
            return .failure(.baselineFingerprintMismatch)
        }
        guard candidateID.rawValue > 0 else {
            return .failure(.invalidCandidateIdentity)
        }
        guard requestGeneration == visibleGeneration,
            visibleGeneration > baseline.visibleGeneration
        else {
            return .failure(.invalidGeneration)
        }

        let plan: RepoExplorerNativeUpdatePlan
        switch RepoExplorerNativeUpdatePlan.instantiating(
            payload: payload,
            baseline: baseline,
            requestGeneration: requestGeneration
        ) {
        case .success(let instantiatedPlan):
            plan = instantiatedPlan
        case .failure(.revisionOverflow):
            return .failure(.revisionOverflow)
        case .failure:
            preconditionFailure("A sealed changed template can fail only on revision overflow")
        }
        let proposedRevision = baseline.revision &+ 1
        return .success(
            RepoExplorerMaterializationCandidate(
                id: candidateID,
                lifetimeID: baseline.lifetimeID,
                demandEpoch: baseline.demandEpoch,
                requestGeneration: requestGeneration,
                visibleGeneration: visibleGeneration,
                expectedRevision: baseline.revision,
                proposedRevision: proposedRevision,
                presentation: target,
                nativeUpdatePlan: plan
            )
        )
    }
}

extension RepoExplorerProjectionWorker {
    static func sealNativeUpdatePlanTemplates(
        source: RepoExplorerMaterializationPresentation,
        target: RepoExplorerMaterializationPresentation
    ) -> Result<RepoExplorerNativeUpdatePlanTemplatePair, RepoExplorerNativeUpdatePlanTemplateSealError> {
        RepoExplorerNativeUpdatePlanTemplatePair.sealing(source: source, target: target)
    }
}
