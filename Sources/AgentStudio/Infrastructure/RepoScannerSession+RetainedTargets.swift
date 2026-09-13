import Foundation

extension RepoScannerTraversalSession {
    func removeRetainedTargetExaminedByTraversal(
        _ entry: PendingEnumerationEntry,
        isSymbolicLink: Bool,
        state: inout TraversalState
    ) {
        guard entry.depth <= state.maxDepth,
            !isSymbolicLink,
            !state.remainingRetainedPathKeys.isEmpty
        else { return }
        state.remainingRetainedPathKeys.remove(
            retainedTargetKey(for: entry, rootURL: state.rootURL)
        )
    }

    func retainedTargetKey(
        for entry: PendingEnumerationEntry,
        rootURL: URL
    ) -> String {
        entry.url.pathComponents.suffix(entry.depth).reduce(rootURL) { partialPath, component in
            partialPath.appending(path: component)
        }.standardizedFileURL.path
    }

    func inspectNextRetainedTarget(
        at nextIndex: Int,
        traversalLease: TraversalLease,
        usage: inout MutableQuantumUsage,
        serviceClock: ContinuousClock,
        serviceStartedAt: ContinuousClock.Instant
    ) -> QuantumDisposition? {
        guard !traversalLease.state.remainingRetainedPathKeys.isEmpty else {
            traversalLease.state.position = .exhausted
            return .exhausted
        }
        guard nextIndex < traversalLease.state.retainedCheckoutPaths.count else {
            traversalLease.state.position = .exhausted
            return .exhausted
        }

        let retainedCheckoutPath = traversalLease.state.retainedCheckoutPaths[nextIndex]
        let followingPosition = TraversalPosition.retainedTargets(nextIndex: nextIndex + 1)
        let retainedPathKey = retainedCheckoutPath.standardizedFileURL.path
        guard traversalLease.state.remainingRetainedPathKeys.contains(retainedPathKey) else {
            usage.enumeratedItemCount += 1
            traversalLease.state.position = followingPosition
            return nil
        }
        if shouldSuspendBeforeConsumingPath(retainedCheckoutPath, usage: usage) {
            traversalLease.state.position = .retainedTargets(nextIndex: nextIndex)
            return .suspended
        }
        traversalLease.state.remainingRetainedPathKeys.remove(retainedPathKey)
        guard
            consumeEnumeratedItem(
                retainedCheckoutPath,
                state: &traversalLease.state,
                usage: &usage
            )
        else {
            return .exhausted
        }

        let resolvedRetainedCheckoutPath = retainedCheckoutPath.resolvingSymlinksInPath()
        guard
            resolvedRetainedCheckoutPath.pathComponents.starts(
                with: traversalLease.state.rootURL.pathComponents
            )
        else {
            traversalLease.state.validationFailureCount += 1
            if recordFailure(
                .gitRepositoryDiscoveryFailed(
                    candidatePath: retainedCheckoutPath,
                    reason: .candidateAdmissionRejected(.outsideRegisteredRoot)
                ),
                state: &traversalLease.state,
                usage: &usage
            ) {
                return .exhausted
            }
            traversalLease.state.position = followingPosition
            return nil
        }

        let retainedTargetValues: URLResourceValues
        do {
            retainedTargetValues = try retainedCheckoutPath.resourceValues(
                forKeys: [.isDirectoryKey]
            )
        } catch let error as CocoaError where Self.isMissingFileError(error) {
            traversalLease.state.position = followingPosition
            return nil
        } catch {
            traversalLease.state.entryMetadataFailureCount += 1
            if recordFailure(
                .entryMetadataReadFailed(
                    entryPath: retainedCheckoutPath,
                    detail: String(describing: error)
                ),
                state: &traversalLease.state,
                usage: &usage
            ) {
                return .exhausted
            }
            traversalLease.state.position = followingPosition
            return nil
        }
        guard retainedTargetValues.isDirectory == true else {
            traversalLease.state.position = followingPosition
            return nil
        }

        traversalLease.state.directoryVisitCount += 1
        return inspectRetainedTargetGitMarker(
            at: retainedCheckoutPath,
            nextIndex: nextIndex,
            traversalLease: traversalLease,
            usage: &usage,
            serviceClock: serviceClock,
            serviceStartedAt: serviceStartedAt
        )
    }

    private func inspectRetainedTargetGitMarker(
        at retainedCheckoutPath: URL,
        nextIndex: Int,
        traversalLease: TraversalLease,
        usage: inout MutableQuantumUsage,
        serviceClock: ContinuousClock,
        serviceStartedAt: ContinuousClock.Instant
    ) -> QuantumDisposition? {
        let followingPosition = TraversalPosition.retainedTargets(nextIndex: nextIndex + 1)
        switch inspectGitMarker(at: retainedCheckoutPath) {
        case .candidate:
            traversalLease.state.gitCandidateCount += 1
            let continuation = PostValidationContinuation.retainedTargets(
                nextIndex: nextIndex + 1
            )
            if shouldSuspendBeforeValidation(
                usage: usage,
                serviceClock: serviceClock,
                serviceStartedAt: serviceStartedAt
            ) {
                traversalLease.state.position = .pendingValidation(
                    retainedCheckoutPath,
                    continuation: continuation
                )
                return .suspended
            }
            return requestValidation(
                retainedCheckoutPath,
                continuation: continuation,
                traversalLease: traversalLease,
                usage: &usage
            )
        case .notCandidate:
            traversalLease.state.position = followingPosition
            return nil
        case .failed(let detail):
            traversalLease.state.entryMetadataFailureCount += 1
            if recordFailure(
                .gitMarkerInspectionFailed(
                    candidatePath: retainedCheckoutPath,
                    detail: detail
                ),
                state: &traversalLease.state,
                usage: &usage
            ) {
                return .exhausted
            }
            traversalLease.state.position = followingPosition
            return nil
        }
    }
}
