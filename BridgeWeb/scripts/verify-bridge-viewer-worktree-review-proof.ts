export interface ReviewContentRouteDeltaProof {
	readonly afterHitCount: number;
	readonly beforeHitCount: number;
	readonly contentRouteSatisfiedBy: 'matching-post-click-route' | 'no-matching-post-click-route';
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

export interface WorktreeFileDemandDispatchTelemetryProof {
	readonly expectedVisibleFileCount: number | null;
	readonly failedCount: number | null;
	readonly failedCountByLane: Record<string, number> | null;
	readonly failedCountByReason: Record<string, number> | null;
	readonly firstDedupeKey: string | null;
	readonly firstDisposition: string | null;
	readonly firstFreshnessKey: string | null;
	readonly firstLane: string | null;
	readonly intentCount: number | null;
	readonly loadedCount: number | null;
	readonly executorInFlightBytesAfter: number | null;
	readonly executorInFlightCountAfter: number | null;
	readonly executorQueuedBytesAfter: number | null;
	readonly executorQueuedLoadCountAfter: number | null;
	readonly schedulerQueuedEstimatedBytesAfter: number | null;
	readonly schedulerQueuedIntentCountAfter: number | null;
	readonly recentlyUpdatedOpenFilePathAfter: string | null;
	readonly recentlyUpdatedOpenFilePathBefore: string | null;
	readonly status: string | null;
	readonly stimulusCount: number | null;
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
	readonly itemId: string | null;
	readonly packageId: string | null;
	readonly packageReviewGeneration: number | null;
	readonly packageRevision: number | null;
	readonly currentPackageId: string | null;
	readonly currentPackageReviewGeneration: number | null;
	readonly currentPackageRevision: number | null;
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
	readonly routeHitItemIds: readonly string[];
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
				: 'no-matching-post-click-route',
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
	return proof.matchingPostClickHitUrls.length > 0;
}

export function buildReviewContentRoutePressureProof(
	routeHitUrls: readonly string[],
): ReviewContentRoutePressureProof {
	const hitCountByUrl = new Map<string, number>();
	const routeHitItemIds = new Set<string>();
	for (const routeHitUrl of routeHitUrls) {
		hitCountByUrl.set(routeHitUrl, (hitCountByUrl.get(routeHitUrl) ?? 0) + 1);
		const itemId = reviewContentRouteHitItemId(routeHitUrl);
		if (itemId !== null) {
			routeHitItemIds.add(itemId);
		}
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
		routeHitItemIds: Array.from(routeHitItemIds).toSorted(),
		uniqueRouteHitCount: hitCountByUrl.size,
	};
}

function reviewContentRouteHitItemId(routeHitUrl: string): string | null {
	let contentHandleId: string;
	try {
		const url = new URL(routeHitUrl);
		contentHandleId = decodeURIComponent(url.pathname.split('/').at(-1) ?? '');
	} catch {
		contentHandleId = routeHitUrl.split('/').at(-1) ?? '';
	}
	for (const roleSuffix of ['-base', '-head', '-diff', '-file'] as const) {
		if (contentHandleId.endsWith(roleSuffix)) {
			return contentHandleId.slice(0, -roleSuffix.length);
		}
	}
	return null;
}

export function reviewRoutePressureSatisfied(props: {
	readonly expectedVisibleItemId?: string | null;
	readonly routePressureProof: ReviewContentRoutePressureProof;
	readonly selectedDemandTelemetryProof: ReviewDemandTelemetryProof;
	readonly visibleDemandTelemetryProof: ReviewDemandTelemetryProof;
}): boolean {
	return (
		props.routePressureProof.routeHitCount > 0 &&
		props.routePressureProof.duplicateRouteCount === 0 &&
		props.routePressureProof.uniqueRouteHitCount === props.routePressureProof.routeHitCount &&
		(props.expectedVisibleItemId === undefined ||
			props.expectedVisibleItemId === null ||
			props.routePressureProof.routeHitItemIds.includes(props.expectedVisibleItemId)) &&
		reviewSelectedDemandTelemetrySatisfied(props.selectedDemandTelemetryProof) &&
		reviewVisibleDemandTelemetryAttributed(props.visibleDemandTelemetryProof, {
			expectedItemId: props.expectedVisibleItemId ?? null,
		})
	);
}

export function worktreeFileOpenLoadTelemetrySatisfied(
	proof: WorktreeFileOpenLoadTelemetryPredicateInput,
): boolean {
	const validOpenDisposition =
		proof.disposition === 'cold-loaded' ||
		proof.disposition === 'visible-preloaded' ||
		proof.disposition === 'nearby-preloaded' ||
		proof.disposition === 'speculative-preloaded';
	return (
		validOpenDisposition &&
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

export function worktreeFileVisibleDemandTelemetrySatisfied(
	proof: WorktreeFileDemandDispatchTelemetryProof,
): boolean {
	const failedCount = proof.failedCount;
	return (
		proof.status === 'settled' &&
		proof.stimulusCount !== null &&
		proof.stimulusCount > 0 &&
		proof.intentCount !== null &&
		proof.intentCount > 0 &&
		proof.expectedVisibleFileCount !== null &&
		proof.expectedVisibleFileCount === proof.intentCount &&
		proof.loadedCount !== null &&
		proof.loadedCount === proof.intentCount &&
		failedCount !== null &&
		failedCount === 0 &&
		worktreeFileDemandDispatchFailuresAccounted({
			failedCount,
			failedCountByLane: proof.failedCountByLane,
			failedCountByReason: proof.failedCountByReason,
		}) &&
		proof.firstLane === 'visible' &&
		proof.firstDisposition === 'visible-preloaded' &&
		proof.schedulerQueuedIntentCountAfter === 0 &&
		proof.schedulerQueuedEstimatedBytesAfter === 0 &&
		proof.executorInFlightCountAfter === 0 &&
		proof.executorInFlightBytesAfter === 0 &&
		proof.executorQueuedLoadCountAfter === 0 &&
		proof.executorQueuedBytesAfter === 0
	);
}

export function worktreeFileRecentlyUpdatedDemandTelemetrySatisfied(
	proof: WorktreeFileDemandDispatchTelemetryProof,
): boolean {
	const failedCount = proof.failedCount;
	const validLane = proof.firstLane === 'nearby' || proof.firstLane === 'speculative';
	const validDisposition =
		proof.firstDisposition === 'nearby-preloaded' ||
		proof.firstDisposition === 'speculative-preloaded' ||
		proof.firstDisposition === 'cache-hit';
	return (
		proof.status === 'settled' &&
		proof.stimulusCount === 1 &&
		proof.intentCount === 1 &&
		proof.loadedCount === 1 &&
		failedCount === 0 &&
		proof.recentlyUpdatedOpenFilePathAfter === proof.recentlyUpdatedOpenFilePathBefore &&
		worktreeFileDemandDispatchFailuresAccounted({
			failedCount,
			failedCountByLane: proof.failedCountByLane,
			failedCountByReason: proof.failedCountByReason,
		}) &&
		validLane &&
		validDisposition &&
		proof.firstDedupeKey !== null &&
		proof.firstDedupeKey.length > 0 &&
		proof.firstFreshnessKey !== null &&
		proof.firstFreshnessKey.length > 0 &&
		proof.schedulerQueuedIntentCountAfter === 0 &&
		proof.schedulerQueuedEstimatedBytesAfter === 0 &&
		proof.executorInFlightCountAfter === 0 &&
		proof.executorInFlightBytesAfter === 0 &&
		proof.executorQueuedLoadCountAfter === 0 &&
		proof.executorQueuedBytesAfter === 0
	);
}

function reviewDemandTelemetryMatchesCurrentPackage(proof: ReviewDemandTelemetryProof): boolean {
	return (
		proof.packageId !== null &&
		proof.packageId.length > 0 &&
		proof.currentPackageId === proof.packageId &&
		proof.packageReviewGeneration !== null &&
		proof.currentPackageReviewGeneration === proof.packageReviewGeneration &&
		proof.packageRevision !== null &&
		proof.currentPackageRevision === proof.packageRevision
	);
}

function worktreeFileDemandDispatchFailuresAccounted(props: {
	readonly failedCount: number;
	readonly failedCountByLane: Record<string, number> | null;
	readonly failedCountByReason: Record<string, number> | null;
}): boolean {
	if (props.failedCount === 0) {
		return true;
	}
	return (
		props.failedCountByLane !== null &&
		props.failedCountByReason !== null &&
		recordNumberSum(props.failedCountByLane) === props.failedCount &&
		recordNumberSum(props.failedCountByReason) === props.failedCount &&
		(props.failedCountByLane['visible'] ?? 0) === props.failedCount
	);
}

function recordNumberSum(record: Record<string, number>): number {
	let sum = 0;
	for (const value of Object.values(record)) {
		if (!Number.isFinite(value) || value < 0) {
			return -1;
		}
		sum += value;
	}
	return sum;
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
		reviewDemandTelemetryMatchesCurrentPackage(proof) &&
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

export function reviewVisibleDemandTelemetryAttributed(
	proof: ReviewDemandTelemetryProof,
	options: { readonly expectedItemId?: string | null } = {},
): boolean {
	const admittedVisibleBytes = proof.admittedBytesByLane?.['visible'] ?? null;
	const deferredVisibleBytes = proof.deferredEstimatedBytesByLane?.['visible'] ?? null;
	const droppedVisibleBytes = proof.droppedEstimatedBytesByLane?.['visible'] ?? null;
	const expectedItemId = options.expectedItemId ?? null;
	return (
		proof.interest === 'visible' &&
		proof.itemId !== null &&
		proof.itemId.length > 0 &&
		(expectedItemId === null || proof.itemId === expectedItemId) &&
		reviewDemandTelemetryMatchesCurrentPackage(proof) &&
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

export interface ReviewStartupTelemetrySampleProof {
	readonly durationMilliseconds: number | null;
	readonly name: string;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly phase: string | null;
	readonly result: string | null;
	readonly slice: string | null;
	readonly transport: string | null;
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

export function reviewStartupTelemetrySatisfied(
	samples: readonly ReviewStartupTelemetrySampleProof[],
): boolean {
	const samplesByName = new Map(samples.map((sample) => [sample.name, sample]));
	return expectedReviewStartupTelemetrySampleNames.every((name): boolean => {
		const sample = samplesByName.get(name);
		return sample !== undefined && sample.result === 'success';
	});
}

const expectedReviewStartupTelemetrySampleNames = [
	'performance.bridge.web.review_package_body_load',
	'performance.bridge.web.review_package_first_chunk',
	'performance.bridge.web.review_package_parse',
	'performance.bridge.web.review_snapshot_apply',
	'performance.bridge.web.projection_total',
	'performance.bridge.web.selected_content_ready',
	'performance.bridge.web.review_ready',
] as const satisfies readonly string[];
