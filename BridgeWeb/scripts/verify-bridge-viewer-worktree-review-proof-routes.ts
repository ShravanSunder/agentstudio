import type {
	ReviewContentRouteDeltaProof,
	ReviewDemandTelemetryProof,
	WorktreeFileDemandDispatchTelemetryProof,
	WorktreeFileOpenLoadTelemetryPredicateInput,
	WorktreeFileScrollExtentCanaryPredicateInput,
	WorktreeFileSplitResetReplacementProof,
} from './verify-bridge-viewer-worktree-review-proof-performance.ts';

export interface ReviewContentRoutePressureProof {
	readonly duplicateRouteCount: number;
	readonly duplicatedRouteUrls: readonly string[];
	readonly routeHitContentDescriptorIds: readonly string[];
	readonly routeHitCount: number;
	readonly routeHitItemIds: readonly string[];
	readonly uniqueRouteHitCount: number;
}

export interface ReviewMetadataBeforeContentProof {
	readonly blockedContentHitCount: number;
	readonly metadataHitCount: number;
	readonly selectedContentStateWhileBlocked: string | null;
	readonly selectedDisplayPathWhileBlocked: string | null;
	readonly treeVisibleRowCountWhileBlocked: number;
	readonly treeVisibleWhileBlocked: boolean;
}

export interface BuildReviewContentRouteDeltaProofProps {
	readonly allHitUrls: readonly string[];
	readonly beforeHitCount: number;
	readonly expectedContentDescriptorIds?: readonly string[];
	readonly expectedItemId: string;
}

export function buildReviewContentRouteDeltaProof(
	props: BuildReviewContentRouteDeltaProofProps,
): ReviewContentRouteDeltaProof {
	const preClickHitUrls = props.allHitUrls.slice(0, props.beforeHitCount);
	const postClickHitUrls = props.allHitUrls.slice(props.beforeHitCount);
	const expectedContentDescriptorIds =
		props.expectedContentDescriptorIds === undefined ||
		props.expectedContentDescriptorIds.length === 0
			? [props.expectedItemId]
			: props.expectedContentDescriptorIds;
	const matchingPreClickHitUrls = preClickHitUrls.filter((url: string): boolean =>
		reviewContentRouteHitMatchesAnyDescriptor(url, expectedContentDescriptorIds),
	);
	const matchingPostClickHitUrls = postClickHitUrls.filter((url: string): boolean =>
		reviewContentRouteHitMatchesAnyDescriptor(url, expectedContentDescriptorIds),
	);

	return {
		afterHitCount: props.allHitUrls.length,
		beforeHitCount: props.beforeHitCount,
		contentRouteSatisfiedBy:
			matchingPostClickHitUrls.length > 0
				? 'matching-post-click-route'
				: 'no-matching-post-click-route',
		expectedContentDescriptorIds,
		expectedItemId: props.expectedItemId,
		matchingPreClickHitUrls,
		matchingPostClickHitUrls,
		preClickHitCount: preClickHitUrls.length,
		preClickHitUrls,
		postClickHitCount: postClickHitUrls.length,
		postClickHitUrls,
	};
}

function reviewContentRouteHitMatchesAnyDescriptor(
	routeHitUrl: string,
	expectedContentDescriptorIds: readonly string[],
): boolean {
	const contentHandleId = reviewContentRouteHitHandleId(routeHitUrl);
	return (
		contentHandleId !== null &&
		expectedContentDescriptorIds.some(
			(descriptorId: string): boolean => descriptorId === contentHandleId,
		)
	);
}

function reviewContentRouteHitHandleId(routeHitUrl: string): string | null {
	try {
		const url = new URL(routeHitUrl);
		return decodeURIComponent(url.pathname.split('/').at(-1) ?? '');
	} catch {
		return routeHitUrl.split('/').at(-1) ?? null;
	}
}

export function reviewContentRouteDeltaSatisfied(proof: ReviewContentRouteDeltaProof): boolean {
	return proof.matchingPostClickHitUrls.length > 0;
}

export function reviewMetadataBeforeContentSatisfied(
	proof: ReviewMetadataBeforeContentProof,
): boolean {
	return (
		proof.metadataHitCount > 0 &&
		proof.blockedContentHitCount > 0 &&
		proof.treeVisibleWhileBlocked &&
		proof.treeVisibleRowCountWhileBlocked > 0 &&
		proof.selectedDisplayPathWhileBlocked !== null &&
		proof.selectedDisplayPathWhileBlocked.length > 0 &&
		proof.selectedContentStateWhileBlocked !== 'ready'
	);
}

export function buildReviewContentRoutePressureProof(
	routeHitUrls: readonly string[],
): ReviewContentRoutePressureProof {
	const hitCountByUrl = new Map<string, number>();
	const routeHitContentDescriptorIds = new Set<string>();
	const routeHitItemIds = new Set<string>();
	for (const routeHitUrl of routeHitUrls) {
		hitCountByUrl.set(routeHitUrl, (hitCountByUrl.get(routeHitUrl) ?? 0) + 1);
		const contentDescriptorId = reviewContentRouteHitHandleId(routeHitUrl);
		if (contentDescriptorId !== null) {
			routeHitContentDescriptorIds.add(contentDescriptorId);
		}
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
		routeHitContentDescriptorIds: Array.from(routeHitContentDescriptorIds).toSorted(),
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
	readonly expectedVisibleContentDescriptorIds?: readonly string[] | null;
	readonly expectedVisibleItemId?: string | null;
	readonly routePressureProof: ReviewContentRoutePressureProof;
	readonly selectedDemandTelemetryProof: ReviewDemandTelemetryProof;
	readonly visibleDemandTelemetryProof: ReviewDemandTelemetryProof;
}): boolean {
	const expectedContentDescriptorIds = props.expectedVisibleContentDescriptorIds ?? [];
	return (
		props.routePressureProof.routeHitCount > 0 &&
		props.routePressureProof.duplicateRouteCount === 0 &&
		props.routePressureProof.uniqueRouteHitCount === props.routePressureProof.routeHitCount &&
		(expectedContentDescriptorIds.length > 0
			? expectedContentDescriptorIds.some((descriptorId: string): boolean =>
					props.routePressureProof.routeHitContentDescriptorIds.includes(descriptorId),
				)
			: props.expectedVisibleItemId === undefined ||
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
		proof.executorInFlightCountAfter !== null &&
		proof.executorInFlightCountAfter >= 0 &&
		proof.executorInFlightBytesAfter !== null &&
		proof.executorInFlightBytesAfter >= 0 &&
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
		proof.executorInFlightMilliseconds !== null &&
		proof.executorInFlightMilliseconds >= 0 &&
		proof.executorPendingWaitMilliseconds !== null &&
		proof.executorPendingWaitMilliseconds >= 0 &&
		proof.resourceBodyRegistryCommitMilliseconds !== null &&
		proof.resourceBodyRegistryCommitMilliseconds >= 0 &&
		proof.resourceFetchResponseWaitMilliseconds !== null &&
		proof.resourceFetchResponseWaitMilliseconds >= 0 &&
		proof.resourceFirstChunkWaitMilliseconds !== null &&
		proof.resourceFirstChunkWaitMilliseconds >= 0 &&
		proof.resourceStreamReadMilliseconds !== null &&
		proof.resourceStreamReadMilliseconds >= 0 &&
		proof.executorQueuedLoadCountBefore !== null &&
		proof.executorQueuedLoadCountBefore >= 0 &&
		proof.executorQueuedBytesBefore !== null &&
		proof.executorQueuedBytesBefore >= 0 &&
		proof.schedulerQueueWaitMilliseconds !== null &&
		proof.schedulerQueueWaitMilliseconds >= 0
	);
}

export function worktreeFileSplitResetReplacementSatisfied(
	proof: WorktreeFileSplitResetReplacementProof,
): boolean {
	return (
		proof.proofPath.length > 0 &&
		proof.oldContentHandle !== proof.replacementContentHandle &&
		proof.replacementContentHash !== null &&
		proof.replacementSourceCursor.length > 0 &&
		proof.initialContentStillVisibleWhileStale &&
		proof.staleMessageVisible &&
		proof.selectedContentStateAfterReset === 'stale' &&
		proof.refreshDisabledAtFirstStale &&
		proof.refreshEnabledAfterReplacement &&
		proof.foreignContentRouteHitCount === 0 &&
		proof.oldContentRouteHitCount === 0 &&
		proof.preDispatchContentRouteHitCount === 0 &&
		proof.postReplacementContentRouteHitCount <= 1 &&
		proof.postRefreshContentRouteHitCount === 1 &&
		proof.replacementContentRouteHitCount === 1 &&
		proof.refreshedContentVisible &&
		proof.devReloadRequest === 'force-split-reset' &&
		proof.devReloadStatus === 'delivered' &&
		proof.devReloadSourceCursor === proof.replacementSourceCursor &&
		proof.devReloadFrameCount === proof.devReloadFrameKinds.length &&
		proof.devReloadFrameCount === proof.devReloadFrameSequences.length &&
		proof.devReloadFrameCount === proof.devReloadFrameGenerations.length &&
		proof.devReloadFrameCount === proof.devReloadFrameStreamIds.length &&
		proof.devReloadFrameKinds[0] === 'worktree.reset' &&
		proof.devReloadFrameKinds[1] === 'worktree.snapshot' &&
		numberListIsStrictlyIncreasing(proof.devReloadFrameSequences) &&
		numberListUsesOneSafeInteger(proof.devReloadFrameGenerations) &&
		stringListUsesOneValue(proof.devReloadFrameStreamIds)
	);
}

export function worktreeFileScrollExtentCanarySatisfied(
	canary: WorktreeFileScrollExtentCanaryPredicateInput,
): boolean {
	return (
		canary.treeDeclaredTotalSizePixels !== null &&
		canary.treeDeclaredTotalSizePixels > 0 &&
		canary.treeDeclaredTotalSizeSource === 'providerFacts' &&
		Math.abs(canary.treeScrollHeightAfterReady - canary.treeDeclaredTotalSizePixels) <= 1 &&
		canary.contentDeclaredTotalSizePixelsAfterSelection !== null &&
		canary.contentDeclaredTotalSizePixelsAfterReady !== null &&
		canary.contentDeclaredTotalSizePixelsAfterSelection ===
			canary.contentDeclaredTotalSizePixelsAfterReady &&
		Math.abs(canary.treeHeightDeltaPixels) <= 1 &&
		canary.treeScrollTopBeforeSelection > 0 &&
		canary.treeScrollTopAfterReady > 0 &&
		Math.abs(canary.contentHeightDeltaPixels) <= 1 &&
		canary.contentScrollTopAfterSelection > 0 &&
		canary.stableAnchorPass &&
		canary.exactSizeTolerancePass
	);
}

function numberListIsStrictlyIncreasing(values: readonly number[]): boolean {
	for (let index = 1; index < values.length; index += 1) {
		const currentValue = values[index];
		const previousValue = values[index - 1];
		if (
			currentValue === undefined ||
			previousValue === undefined ||
			!Number.isSafeInteger(currentValue) ||
			!Number.isSafeInteger(previousValue) ||
			currentValue <= previousValue
		) {
			return false;
		}
	}
	return values.length > 0;
}

function numberListUsesOneSafeInteger(values: readonly number[]): boolean {
	if (values.length === 0) {
		return false;
	}
	const expectedValue = values[0];
	return (
		expectedValue !== undefined &&
		Number.isSafeInteger(expectedValue) &&
		values.every((value: number): boolean => value === expectedValue)
	);
}

function stringListUsesOneValue(values: readonly string[]): boolean {
	if (values.length === 0) {
		return false;
	}
	const expectedValue = values[0];
	return (
		expectedValue !== undefined &&
		expectedValue.length > 0 &&
		values.every((value: string): boolean => value === expectedValue)
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
		(proof.firstDisposition === 'visible-preloaded' || proof.firstDisposition === 'cache-hit') &&
		proof.schedulerQueuedIntentCountAfter === 0 &&
		proof.schedulerQueuedEstimatedBytesAfter === 0 &&
		proof.executorInFlightCountAfter === 0 &&
		proof.executorInFlightBytesAfter === 0 &&
		proof.executorQueuedLoadCountAfter === 0 &&
		proof.executorQueuedBytesAfter === 0 &&
		proof.firstExecutorInFlightMilliseconds !== null &&
		proof.firstExecutorInFlightMilliseconds >= 0 &&
		proof.firstExecutorPendingWaitMilliseconds !== null &&
		proof.firstExecutorPendingWaitMilliseconds >= 0 &&
		proof.firstSchedulerQueueWaitMilliseconds !== null &&
		proof.firstSchedulerQueueWaitMilliseconds >= 0
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
		proof.firstDisposition === 'visible-preloaded' ||
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
		proof.durationMilliseconds !== null &&
		proof.durationMilliseconds >= 0 &&
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
		proof.executorInFlightCountAfter !== null &&
		proof.executorInFlightCountAfter <= proof.configuredExecutorMaxConcurrentLoads
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
		proof.durationMilliseconds !== null &&
		proof.durationMilliseconds >= 0 &&
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
