export interface ReviewContentRouteDeltaProof {
	readonly afterHitCount: number;
	readonly beforeHitCount: number;
	readonly contentRouteSatisfiedBy:
		| 'matching-pre-click-route-with-rendered-selection'
		| 'matching-post-click-route';
	readonly expectedItemId: string;
	readonly matchingPreClickHitUrls: readonly string[];
	readonly matchingPostClickHitUrls: readonly string[];
	readonly preClickHitCount: number;
	readonly preClickHitUrls: readonly string[];
	readonly postClickHitCount: number;
	readonly postClickHitUrls: readonly string[];
}

export interface WorktreeFileOpenLoadTelemetryPredicateInput {
	readonly disposition: string | null;
	readonly durationMilliseconds: number | null;
	readonly estimatedBytes: number | null;
	readonly executorInFlightBytesAfter: number | null;
	readonly executorInFlightBytesBefore: number | null;
	readonly executorInFlightCountAfter: number | null;
	readonly executorInFlightCountBefore: number | null;
	readonly executorQueuedBytesAfter: number | null;
	readonly executorQueuedBytesBefore: number | null;
	readonly executorQueuedLoadCountAfter: number | null;
	readonly executorQueuedLoadCountBefore: number | null;
	readonly lane: string | null;
	readonly schedulerQueuedEstimatedBytesAfter: number | null;
	readonly schedulerQueuedEstimatedBytesBefore: number | null;
	readonly schedulerQueuedIntentCountAfter: number | null;
	readonly schedulerQueuedIntentCountBefore: number | null;
}

export interface ReviewDemandTelemetryProof {
	readonly admittedBytes: number | null;
	readonly admittedBytesByLane: Record<string, number> | null;
	readonly byteBudgetSource: string | null;
	readonly configuredExecutorMaxConcurrentLoads: number | null;
	readonly configuredExecutorMaxInFlightBytes: number | null;
	readonly configuredSchedulerMaxQueuedEstimatedBytes: number | null;
	readonly configuredSchedulerMaxQueuedIntentsPerLane: number | null;
	readonly deferredCount: number | null;
	readonly deferredEstimatedBytesByLane: Record<string, number> | null;
	readonly droppedEstimatedBytesByLane: Record<string, number> | null;
	readonly droppedIntentCount: number | null;
	readonly enqueueAcceptedCount: number | null;
	readonly enqueueRejectedCount: number | null;
	readonly executorInFlightCountAfterDispatch: number | null;
	readonly executorInFlightCountAfter: number | null;
	readonly executorInFlightCountBefore: number | null;
	readonly executorQueuedLoadCountAfter: number | null;
	readonly failedCount: number | null;
	readonly foregroundIntentCount: number | null;
	readonly interest: string | null;
	readonly laneUpgradeCount: number | null;
	readonly loadedCount: number | null;
	readonly maxExecutorInFlightCount: number | null;
	readonly maxExecutorQueuedLoadCount: number | null;
	readonly maxSchedulerQueuedIntentCount: number | null;
	readonly schedulerQueuedIntentCountAfterEnqueue: number | null;
	readonly schedulerQueuedIntentCountAfter: number | null;
	readonly schedulerQueuedIntentCountBefore: number | null;
	readonly staleDropCount: number | null;
	readonly visibleIntentCount: number | null;
}

export interface ReviewContentRoutePressureProof {
	readonly duplicateRouteCount: number;
	readonly duplicatedRouteUrls: readonly string[];
	readonly routeHitCount: number;
	readonly uniqueRouteHitCount: number;
}

export interface BuildReviewContentRouteDeltaProofProps {
	readonly allHitUrls: readonly string[];
	readonly beforeHitCount: number;
	readonly expectedItemId: string;
}

export function buildReviewContentRouteDeltaProof(
	props: BuildReviewContentRouteDeltaProofProps,
): ReviewContentRouteDeltaProof {
	const preClickHitUrls = props.allHitUrls.slice(0, props.beforeHitCount);
	const postClickHitUrls = props.allHitUrls.slice(props.beforeHitCount);
	const matchingPreClickHitUrls = preClickHitUrls.filter((url: string): boolean =>
		url.includes(props.expectedItemId),
	);
	const matchingPostClickHitUrls = postClickHitUrls.filter((url: string): boolean =>
		url.includes(props.expectedItemId),
	);

	return {
		afterHitCount: props.allHitUrls.length,
		beforeHitCount: props.beforeHitCount,
		contentRouteSatisfiedBy:
			matchingPostClickHitUrls.length > 0
				? 'matching-post-click-route'
				: 'matching-pre-click-route-with-rendered-selection',
		expectedItemId: props.expectedItemId,
		matchingPreClickHitUrls,
		matchingPostClickHitUrls,
		preClickHitCount: preClickHitUrls.length,
		preClickHitUrls,
		postClickHitCount: postClickHitUrls.length,
		postClickHitUrls,
	};
}

export function reviewContentRouteDeltaSatisfied(proof: ReviewContentRouteDeltaProof): boolean {
	return proof.matchingPostClickHitUrls.length > 0 || proof.matchingPreClickHitUrls.length > 0;
}

export function buildReviewContentRoutePressureProof(
	routeHitUrls: readonly string[],
): ReviewContentRoutePressureProof {
	const hitCountByUrl = new Map<string, number>();
	for (const routeHitUrl of routeHitUrls) {
		hitCountByUrl.set(routeHitUrl, (hitCountByUrl.get(routeHitUrl) ?? 0) + 1);
	}
	const duplicatedRouteUrls = Array.from(hitCountByUrl.entries())
		.filter(([, hitCount]): boolean => hitCount > 1)
		.map(([routeHitUrl]): string => routeHitUrl)
		.toSorted();
	const duplicateRouteCount = Array.from(hitCountByUrl.values()).reduce(
		(count, hitCount): number => count + Math.max(0, hitCount - 1),
		0,
	);
	return {
		duplicateRouteCount,
		duplicatedRouteUrls,
		routeHitCount: routeHitUrls.length,
		uniqueRouteHitCount: hitCountByUrl.size,
	};
}

export function reviewRoutePressureSatisfied(props: {
	readonly routePressureProof: ReviewContentRoutePressureProof;
	readonly selectedDemandTelemetryProof: ReviewDemandTelemetryProof;
	readonly visibleDemandTelemetryProof: ReviewDemandTelemetryProof;
}): boolean {
	return (
		props.routePressureProof.routeHitCount > 0 &&
		props.routePressureProof.duplicateRouteCount === 0 &&
		props.routePressureProof.uniqueRouteHitCount === props.routePressureProof.routeHitCount &&
		reviewSelectedDemandTelemetrySatisfied(props.selectedDemandTelemetryProof) &&
		reviewVisibleDemandTelemetryAttributed(props.visibleDemandTelemetryProof)
	);
}

export function worktreeFileOpenLoadTelemetrySatisfied(
	proof: WorktreeFileOpenLoadTelemetryPredicateInput,
): boolean {
	return (
		(proof.disposition === 'cold-loaded' || proof.disposition === 'cache-hit') &&
		proof.lane === 'foreground' &&
		proof.durationMilliseconds !== null &&
		proof.durationMilliseconds >= 0 &&
		proof.estimatedBytes !== null &&
		proof.estimatedBytes > 0 &&
		proof.schedulerQueuedIntentCountAfter === 0 &&
		proof.schedulerQueuedEstimatedBytesAfter === 0 &&
		proof.executorInFlightCountAfter === 0 &&
		proof.executorInFlightBytesAfter === 0 &&
		proof.executorQueuedLoadCountAfter === 0 &&
		proof.executorQueuedBytesAfter === 0 &&
		proof.schedulerQueuedIntentCountBefore !== null &&
		proof.schedulerQueuedIntentCountBefore >= 0 &&
		proof.schedulerQueuedEstimatedBytesBefore !== null &&
		proof.schedulerQueuedEstimatedBytesBefore >= 0 &&
		proof.executorInFlightCountBefore !== null &&
		proof.executorInFlightCountBefore >= 0 &&
		proof.executorInFlightBytesBefore !== null &&
		proof.executorInFlightBytesBefore >= 0 &&
		proof.executorQueuedLoadCountBefore !== null &&
		proof.executorQueuedLoadCountBefore >= 0 &&
		proof.executorQueuedBytesBefore !== null &&
		proof.executorQueuedBytesBefore >= 0
	);
}

export function reviewSelectedDemandTelemetrySatisfied(proof: ReviewDemandTelemetryProof): boolean {
	return (
		proof.interest === 'selected' &&
		proof.foregroundIntentCount !== null &&
		proof.foregroundIntentCount > 0 &&
		proof.visibleIntentCount === 0 &&
		proof.loadedCount !== null &&
		proof.loadedCount > 0 &&
		proof.deferredCount === 0 &&
		proof.failedCount === 0 &&
		proof.admittedBytes !== null &&
		proof.admittedBytes > 0 &&
		proof.admittedBytesByLane !== null &&
		(proof.admittedBytesByLane['foreground'] ?? 0) > 0 &&
		proof.byteBudgetSource === 'review-content-demand' &&
		proof.configuredExecutorMaxConcurrentLoads !== null &&
		proof.configuredExecutorMaxConcurrentLoads > 0 &&
		proof.configuredExecutorMaxInFlightBytes !== null &&
		proof.configuredExecutorMaxInFlightBytes > 0 &&
		proof.configuredSchedulerMaxQueuedEstimatedBytes !== null &&
		proof.configuredSchedulerMaxQueuedEstimatedBytes >= 0 &&
		proof.configuredSchedulerMaxQueuedIntentsPerLane !== null &&
		proof.configuredSchedulerMaxQueuedIntentsPerLane > 0 &&
		proof.deferredEstimatedBytesByLane !== null &&
		proof.droppedEstimatedBytesByLane !== null &&
		proof.droppedIntentCount === 0 &&
		proof.enqueueAcceptedCount !== null &&
		proof.enqueueAcceptedCount > 0 &&
		proof.enqueueRejectedCount === 0 &&
		proof.executorInFlightCountAfterDispatch !== null &&
		proof.executorInFlightCountAfterDispatch <= proof.configuredExecutorMaxConcurrentLoads &&
		proof.executorInFlightCountBefore !== null &&
		proof.executorInFlightCountBefore >= 0 &&
		proof.executorQueuedLoadCountAfter === 0 &&
		proof.laneUpgradeCount === 0 &&
		proof.maxExecutorInFlightCount !== null &&
		proof.maxExecutorInFlightCount > 0 &&
		proof.maxExecutorInFlightCount <= proof.configuredExecutorMaxConcurrentLoads &&
		proof.maxExecutorQueuedLoadCount !== null &&
		proof.maxExecutorQueuedLoadCount >= 0 &&
		proof.maxSchedulerQueuedIntentCount !== null &&
		proof.maxSchedulerQueuedIntentCount > 0 &&
		proof.schedulerQueuedIntentCountAfterEnqueue !== null &&
		proof.schedulerQueuedIntentCountAfterEnqueue >= 0 &&
		proof.schedulerQueuedIntentCountAfter === 0 &&
		proof.schedulerQueuedIntentCountBefore !== null &&
		proof.schedulerQueuedIntentCountBefore >= 0 &&
		proof.staleDropCount === 0 &&
		proof.executorInFlightCountAfter === 0
	);
}

export function reviewVisibleDemandTelemetryAttributed(proof: ReviewDemandTelemetryProof): boolean {
	const admittedVisibleBytes = proof.admittedBytesByLane?.['visible'] ?? null;
	const deferredVisibleBytes = proof.deferredEstimatedBytesByLane?.['visible'] ?? null;
	const droppedVisibleBytes = proof.droppedEstimatedBytesByLane?.['visible'] ?? null;
	return (
		proof.interest === 'visible' &&
		proof.visibleIntentCount !== null &&
		proof.visibleIntentCount > 0 &&
		proof.foregroundIntentCount === 0 &&
		proof.byteBudgetSource === 'review-content-demand' &&
		proof.configuredExecutorMaxConcurrentLoads !== null &&
		proof.configuredExecutorMaxConcurrentLoads > 0 &&
		proof.configuredExecutorMaxInFlightBytes !== null &&
		proof.configuredExecutorMaxInFlightBytes > 0 &&
		proof.configuredSchedulerMaxQueuedEstimatedBytes !== null &&
		proof.configuredSchedulerMaxQueuedEstimatedBytes >= 0 &&
		proof.configuredSchedulerMaxQueuedIntentsPerLane !== null &&
		proof.configuredSchedulerMaxQueuedIntentsPerLane > 0 &&
		proof.admittedBytesByLane !== null &&
		proof.deferredEstimatedBytesByLane !== null &&
		proof.droppedEstimatedBytesByLane !== null &&
		admittedVisibleBytes !== null &&
		deferredVisibleBytes !== null &&
		droppedVisibleBytes !== null &&
		proof.enqueueAcceptedCount !== null &&
		proof.enqueueAcceptedCount >= 0 &&
		proof.enqueueRejectedCount !== null &&
		proof.enqueueRejectedCount >= 0 &&
		proof.droppedIntentCount !== null &&
		proof.droppedIntentCount >= 0 &&
		proof.failedCount !== null &&
		proof.failedCount >= 0 &&
		proof.loadedCount !== null &&
		proof.loadedCount >= 0 &&
		proof.deferredCount !== null &&
		proof.deferredCount >= 0 &&
		proof.executorInFlightCountAfterDispatch !== null &&
		proof.executorInFlightCountAfterDispatch <= proof.configuredExecutorMaxConcurrentLoads &&
		proof.maxExecutorInFlightCount !== null &&
		proof.maxExecutorInFlightCount <= proof.configuredExecutorMaxConcurrentLoads &&
		proof.maxExecutorQueuedLoadCount !== null &&
		proof.maxExecutorQueuedLoadCount >= 0 &&
		proof.maxSchedulerQueuedIntentCount !== null &&
		proof.maxSchedulerQueuedIntentCount >= 0 &&
		proof.schedulerQueuedIntentCountAfterEnqueue !== null &&
		proof.schedulerQueuedIntentCountAfterEnqueue >= 0 &&
		proof.schedulerQueuedIntentCountAfter !== null &&
		proof.schedulerQueuedIntentCountAfter >= 0 &&
		proof.schedulerQueuedIntentCountBefore !== null &&
		proof.schedulerQueuedIntentCountBefore >= 0 &&
		proof.staleDropCount !== null &&
		proof.staleDropCount >= 0
	);
}

export function normalizeReviewTreeSearchQuery(path: string): string {
	return path.toLowerCase();
}

export interface ReviewRenderedSelectionSnapshot {
	readonly codeViewOverflow: string | null;
	readonly selectedHeaderPresent: boolean;
	readonly selectedItemId: string | null;
	readonly selectedMaterializedFileLineCount: number;
	readonly selectedMaterializedItemType: string | null;
	readonly visibleText: string;
}

export interface ReviewCollapseControlProof {
	readonly ariaExpanded: string | null;
	readonly fontSize: string | null;
	readonly height: number;
	readonly itemId: string | null;
	readonly primitiveSlot: string | null;
	readonly present: boolean;
}

export interface ReviewCollapseControlCandidate {
	readonly proof: ReviewCollapseControlProof;
	readonly visible: boolean;
}

export interface ReviewRouteCollapseControlArtifact {
	readonly reviewCollapseControlProof?: ReviewCollapseControlProof;
}

export interface ReviewRenderedSelectionExpectation {
	readonly expectedCodeViewOverflow: 'wrap';
	readonly expectedItemId: string;
	readonly expectedMaterializedItemType: 'diff' | 'file';
	readonly expectedVisibleText: string;
}

export function emptyReviewCollapseControlProof(): ReviewCollapseControlProof {
	return {
		ariaExpanded: null,
		fontSize: null,
		height: 0,
		itemId: null,
		present: false,
		primitiveSlot: null,
	};
}

export function reviewRenderedSelectionSatisfied(props: {
	readonly expectation: ReviewRenderedSelectionExpectation;
	readonly snapshot: ReviewRenderedSelectionSnapshot;
}): boolean {
	return (
		props.snapshot.codeViewOverflow === props.expectation.expectedCodeViewOverflow &&
		props.snapshot.selectedItemId === props.expectation.expectedItemId &&
		props.snapshot.selectedHeaderPresent &&
		props.snapshot.selectedMaterializedItemType ===
			props.expectation.expectedMaterializedItemType &&
		props.snapshot.visibleText.includes(props.expectation.expectedVisibleText)
	);
}

export function reviewCollapseControlSatisfied(props: {
	readonly expectedItemId: string;
	readonly proof: ReviewCollapseControlProof;
}): boolean {
	return (
		props.proof.present &&
		props.proof.itemId === props.expectedItemId &&
		props.proof.primitiveSlot === 'button' &&
		Math.abs(props.proof.height - 24) <= 1 &&
		(props.proof.ariaExpanded === 'true' || props.proof.ariaExpanded === 'false')
	);
}

export function selectVisibleReviewCollapseControlProof(props: {
	readonly candidates: readonly ReviewCollapseControlCandidate[];
	readonly expectedItemId: string;
}): ReviewCollapseControlProof {
	return (
		props.candidates.find(
			(candidate: ReviewCollapseControlCandidate): boolean =>
				candidate.visible && candidate.proof.itemId === props.expectedItemId,
		)?.proof ?? emptyReviewCollapseControlProof()
	);
}

export function reviewRouteCollapseControlArtifactSatisfied(props: {
	readonly expectedItemId: string;
	readonly routeProof: ReviewRouteCollapseControlArtifact;
}): boolean {
	return (
		props.routeProof.reviewCollapseControlProof !== undefined &&
		reviewCollapseControlSatisfied({
			expectedItemId: props.expectedItemId,
			proof: props.routeProof.reviewCollapseControlProof,
		})
	);
}
