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
	readonly executorInFlightMilliseconds: number | null;
	readonly executorPendingWaitMilliseconds: number | null;
	readonly executorQueuedBytesAfter: number | null;
	readonly executorQueuedBytesBefore: number | null;
	readonly executorQueuedLoadCountAfter: number | null;
	readonly executorQueuedLoadCountBefore: number | null;
	readonly lane: string | null;
	readonly resourceBodyRegistryCommitMilliseconds: number | null;
	readonly resourceFetchResponseWaitMilliseconds: number | null;
	readonly resourceFirstChunkWaitMilliseconds: number | null;
	readonly resourceStreamReadMilliseconds: number | null;
	readonly schedulerQueueWaitMilliseconds: number | null;
	readonly schedulerQueuedEstimatedBytesAfter: number | null;
	readonly schedulerQueuedEstimatedBytesBefore: number | null;
	readonly schedulerQueuedIntentCountAfter: number | null;
	readonly schedulerQueuedIntentCountBefore: number | null;
}

export interface WorktreeInteractionDurationSummary {
	readonly failureCount: number;
	readonly maxMs: number | null;
	readonly medianMs: number | null;
	readonly minMs: number | null;
	readonly p95Ms: number | null;
	readonly p99Ms: number | null;
	readonly sampleCount: number;
}

export interface WorktreeInteractionPerformanceProof {
	readonly blankTreeWindowCount: number;
	readonly browserOrNativeRuntime: 'vite' | 'native';
	readonly clickPhaseDurations: WorktreeFileClickPhaseDurationSummaries;
	readonly clickToFirstVisibleContentWindow: WorktreeInteractionDurationSummary;
	readonly commitSha: string;
	readonly demandQueueWait: WorktreeDemandQueueWaitProof;
	readonly foregroundContentLoadTiming: WorktreeForegroundContentLoadTimingProof;
	readonly fileClickFailureDetails?: readonly WorktreeInteractionFailureDetail[];
	readonly fileClickSlowSampleDetails?: readonly WorktreeInteractionSlowSampleDetail[];
	readonly fileClickSampleCount: number;
	readonly runMarker: string;
	readonly scrollToVisibleRows: WorktreeInteractionDurationSummary;
	readonly startupLoadTiming: WorktreeStartupLoadTimingProof;
	readonly treeScrollSettleFrameCount: WorktreeInteractionDurationSummary;
	readonly treeScrollSampleCount: number;
	readonly workerMode: 'on' | 'off';
	readonly wrongVisibleRowCount: number;
}

export interface ReviewInteractionPerformanceProof {
	readonly browserOrNativeRuntime: 'vite' | 'native';
	readonly codeViewBlankWindowCount: number;
	readonly codeViewHeightChangeCount: number;
	readonly codeViewItemCountAfter: number;
	readonly codeViewScrollSampleCount: number;
	readonly codeViewScrollToStableWindow: WorktreeInteractionDurationSummary;
	readonly commitSha: string;
	readonly reviewClickReadinessBreakdown: ReviewClickReadinessBreakdownSummaries;
	readonly reviewClickPhaseDurations: ReviewClickPhaseDurationSummaries;
	readonly reviewClickFailureDetails?: readonly WorktreeInteractionFailureDetail[];
	readonly reviewClickSlowSampleDetails?: readonly WorktreeInteractionSlowSampleDetail[];
	readonly reviewClickSampleCount: number;
	readonly reviewClickToSelectedReady: WorktreeInteractionDurationSummary;
	readonly reviewDevContentResponseTiming: ReviewDevContentResponseTimingProof;
	readonly reviewStartupLoadTiming: ReviewStartupLoadTimingProof;
	readonly reviewTreeBlankWindowCount: number;
	readonly reviewTreeScrollSettleFrameCount: WorktreeInteractionDurationSummary;
	readonly reviewTreeScrollSampleCount: number;
	readonly reviewTreeScrollToVisibleRows: WorktreeInteractionDurationSummary;
	readonly reviewTreeWrongVisibleRowCount: number;
	readonly runMarker: string;
	readonly workerMode: 'on' | 'off';
	readonly codeViewScrollSettleFrameCount: WorktreeInteractionDurationSummary;
}

export interface WorktreeFileClickPhaseDurationSummaries {
	readonly firstVisibleAfterReady: WorktreeInteractionDurationSummary;
	readonly openReadyAfterSelection: WorktreeInteractionDurationSummary;
	readonly selectionCommit: WorktreeInteractionDurationSummary;
}

export interface ReviewClickPhaseDurationSummaries {
	readonly firstVisibleAfterReady: WorktreeInteractionDurationSummary;
	readonly readyAfterSelection: WorktreeInteractionDurationSummary;
	readonly selectionCommit: WorktreeInteractionDurationSummary;
}

export interface ReviewClickReadinessBreakdownSummaries {
	readonly codeViewMaterializedAfterContentReady: WorktreeInteractionDurationSummary;
	readonly contentReadyAfterSelectedPath: WorktreeInteractionDurationSummary;
	readonly selectedDemandDuration: WorktreeInteractionDurationSummary;
	readonly selectedPathState: WorktreeInteractionDurationSummary;
	readonly treeSelectionVisible: WorktreeInteractionDurationSummary;
	readonly visibleContentRenderedAfterMaterialization: WorktreeInteractionDurationSummary;
}

export interface ReviewDevContentResponseTimingProof {
	readonly getProvider: WorktreeInteractionDurationSummary;
	readonly providerLoad: WorktreeInteractionDurationSummary;
	readonly responseTotal: WorktreeInteractionDurationSummary;
}

export interface WorktreeDemandQueueWaitProof {
	readonly foreground: WorktreeInteractionDurationSummary;
	readonly visible: WorktreeInteractionDurationSummary;
}

export interface WorktreeForegroundContentLoadTimingProof {
	readonly executorInFlight: WorktreeInteractionDurationSummary;
	readonly executorPendingWait: WorktreeInteractionDurationSummary;
	readonly resourceBodyRegistryCommit: WorktreeInteractionDurationSummary;
	readonly resourceFetchResponseWait: WorktreeInteractionDurationSummary;
	readonly resourceFirstChunkWait: WorktreeInteractionDurationSummary;
	readonly resourceStreamRead: WorktreeInteractionDurationSummary;
}

export interface WorktreeStartupLoadTimingProof {
	readonly pageLoadToContentReady: WorktreeInteractionDurationSummary;
	readonly pageLoadToFirstVisibleContentWindow: WorktreeInteractionDurationSummary;
	readonly pageLoadToSelectedPath: WorktreeInteractionDurationSummary;
}

export interface ReviewStartupLoadTimingProof {
	readonly metadataApplyDuration: WorktreeInteractionDurationSummary;
	readonly pageLoadToMetadata: WorktreeInteractionDurationSummary;
	readonly pageLoadToReviewReady: WorktreeInteractionDurationSummary;
	readonly pageLoadToSelectedContentReady: WorktreeInteractionDurationSummary;
	readonly reviewReadyDuration: WorktreeInteractionDurationSummary;
	readonly selectedContentReadyDuration: WorktreeInteractionDurationSummary;
}

export interface WorktreeInteractionFailureDetail {
	readonly message: string;
	readonly path: string;
}

export interface WorktreeInteractionSlowSampleDetail {
	readonly appSelectionCommitMilliseconds?: number | null;
	readonly codeViewMaterializedMilliseconds?: number | null;
	readonly clickDispatchMilliseconds?: number | null;
	readonly durationMilliseconds: number;
	readonly expectedBytes: number | null;
	readonly lineCount: number | null;
	readonly path: string;
	readonly preClickMilliseconds?: number | null;
	readonly readyMilliseconds: number | null;
	readonly selectedMilliseconds: number | null;
	readonly selectedDemandDurationMilliseconds?: number | null;
	readonly selectedMaterializationMilliseconds?: number | null;
	readonly treeSelectionVisibleMilliseconds?: number | null;
	readonly visibleContentRenderedMilliseconds?: number | null;
}

export interface WorktreeFileDemandDispatchTelemetryProof {
	readonly expectedVisibleFileCount: number | null;
	readonly failedCount: number | null;
	readonly failedCountByLane: Record<string, number> | null;
	readonly failedCountByReason: Record<string, number> | null;
	readonly firstDedupeKey: string | null;
	readonly firstDisposition: string | null;
	readonly firstExecutorInFlightMilliseconds: number | null;
	readonly firstExecutorPendingWaitMilliseconds: number | null;
	readonly firstFreshnessKey: string | null;
	readonly firstLane: string | null;
	readonly firstSchedulerQueueWaitMilliseconds: number | null;
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

export interface WorktreeFileSplitResetReplacementProof {
	readonly devReloadFrameCount: number;
	readonly devReloadFrameGenerations: readonly number[];
	readonly devReloadFrameKinds: readonly string[];
	readonly devReloadFrameSequences: readonly number[];
	readonly devReloadFrameStreamIds: readonly string[];
	readonly devReloadRequest: string | null;
	readonly devReloadSourceCursor: string | null;
	readonly devReloadStatus: string | null;
	readonly foreignContentRouteHitCount: number;
	readonly foreignContentRouteHitUrls: readonly string[];
	readonly initialContentStillVisibleWhileStale: boolean;
	readonly oldContentHandle: string;
	readonly oldContentRouteHitCount: number;
	readonly postRefreshContentRouteHitCount: number;
	readonly postReplacementContentRouteHitCount: number;
	readonly preDispatchContentRouteHitCount: number;
	readonly proofPath: string;
	readonly refreshDisabledAtFirstStale: boolean;
	readonly refreshEnabledAfterReplacement: boolean;
	readonly refreshedContentVisible: boolean;
	readonly replacementContentHandle: string;
	readonly replacementContentHash: string | null;
	readonly replacementContentRouteHitCount: number;
	readonly replacementSourceCursor: string;
	readonly selectedContentStateAfterReset: string | null;
	readonly staleMessageVisible: boolean;
}

export interface WorktreeFileScrollExtentCanaryPredicateInput {
	readonly contentDeclaredTotalSizePixelsAfterReady: number | null;
	readonly contentDeclaredTotalSizePixelsAfterSelection: number | null;
	readonly contentHeightDeltaPixels: number;
	readonly contentScrollTopAfterReady: number;
	readonly contentScrollTopAfterSelection: number;
	readonly exactSizeTolerancePass: boolean;
	readonly stableAnchorPass: boolean;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeDeclaredTotalSizeSource: string | null;
	readonly treeHeightDeltaPixels: number;
	readonly treeScrollHeightAfterReady: number;
	readonly treeScrollTopAfterReady: number;
	readonly treeScrollTopBeforeSelection: number;
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
	readonly durationMilliseconds: number | null;
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

export function summarizeInteractionSamples(
	durationMillisecondsSamples: readonly number[],
): WorktreeInteractionDurationSummary {
	const validSamples = durationMillisecondsSamples
		.filter(
			(durationMilliseconds: number): boolean =>
				Number.isFinite(durationMilliseconds) && durationMilliseconds >= 0,
		)
		.toSorted((left: number, right: number): number => left - right);
	const failureCount = durationMillisecondsSamples.length - validSamples.length;
	if (validSamples.length === 0) {
		return {
			failureCount,
			maxMs: null,
			medianMs: null,
			minMs: null,
			p95Ms: null,
			p99Ms: null,
			sampleCount: 0,
		};
	}
	return {
		failureCount,
		maxMs: validSamples.at(-1) ?? null,
		medianMs: medianOfSortedSamples(validSamples),
		minMs: validSamples[0] ?? null,
		p95Ms: nearestRankPercentile(validSamples, 0.95),
		p99Ms: nearestRankPercentile(validSamples, 0.99),
		sampleCount: validSamples.length,
	};
}

export function worktreeInteractionPerformanceSatisfied(
	proof: WorktreeInteractionPerformanceProof,
): boolean {
	return (
		proof.runMarker.length > 0 &&
		proof.commitSha.length > 0 &&
		proof.fileClickSampleCount >= minimumInteractionPerformanceSampleCount &&
		proof.treeScrollSampleCount >= minimumInteractionPerformanceSampleCount &&
		clickPhaseDurationSummariesSatisfied(proof.clickPhaseDurations, proof.fileClickSampleCount) &&
		demandQueueWaitSatisfied(proof.demandQueueWait) &&
		foregroundContentLoadTimingSatisfied(
			proof.foregroundContentLoadTiming,
			proof.fileClickSampleCount,
		) &&
		worktreeStartupLoadTimingSatisfied(proof) &&
		proof.clickToFirstVisibleContentWindow.sampleCount === proof.fileClickSampleCount &&
		proof.scrollToVisibleRows.sampleCount === proof.treeScrollSampleCount &&
		interactionDurationSummarySatisfied(
			proof.treeScrollSettleFrameCount,
			proof.treeScrollSampleCount,
		) &&
		proof.clickToFirstVisibleContentWindow.failureCount === 0 &&
		proof.scrollToVisibleRows.failureCount === 0 &&
		proof.clickToFirstVisibleContentWindow.p95Ms !== null &&
		proof.clickToFirstVisibleContentWindow.p95Ms < 100 &&
		proof.clickToFirstVisibleContentWindow.p99Ms !== null &&
		proof.clickToFirstVisibleContentWindow.p99Ms < 200 &&
		proof.scrollToVisibleRows.p95Ms !== null &&
		proof.scrollToVisibleRows.p95Ms < 100 &&
		proof.scrollToVisibleRows.p99Ms !== null &&
		proof.scrollToVisibleRows.p99Ms < 200 &&
		proof.blankTreeWindowCount === 0 &&
		proof.wrongVisibleRowCount === 0
	);
}

export function reviewInteractionPerformanceSatisfied(
	proof: ReviewInteractionPerformanceProof,
): boolean {
	return (
		proof.runMarker.length > 0 &&
		proof.commitSha.length > 0 &&
		proof.reviewClickSampleCount >= minimumInteractionPerformanceSampleCount &&
		proof.reviewTreeScrollSampleCount >= minimumInteractionPerformanceSampleCount &&
		reviewClickReadinessBreakdownSatisfied(
			proof.reviewClickReadinessBreakdown,
			proof.reviewClickSampleCount,
		) &&
		reviewClickPhaseDurationSummariesSatisfied(
			proof.reviewClickPhaseDurations,
			proof.reviewClickSampleCount,
		) &&
		reviewStartupLoadTimingSatisfied(proof) &&
		proof.reviewClickToSelectedReady.sampleCount === proof.reviewClickSampleCount &&
		proof.reviewTreeScrollToVisibleRows.sampleCount === proof.reviewTreeScrollSampleCount &&
		interactionDurationSummarySatisfied(
			proof.reviewTreeScrollSettleFrameCount,
			proof.reviewTreeScrollSampleCount,
		) &&
		proof.reviewClickToSelectedReady.failureCount === 0 &&
		proof.reviewTreeScrollToVisibleRows.failureCount === 0 &&
		proof.reviewClickToSelectedReady.p95Ms !== null &&
		proof.reviewClickToSelectedReady.p95Ms < 100 &&
		proof.reviewClickToSelectedReady.p99Ms !== null &&
		proof.reviewClickToSelectedReady.p99Ms < 200 &&
		proof.reviewTreeScrollToVisibleRows.p95Ms !== null &&
		proof.reviewTreeScrollToVisibleRows.p95Ms < 100 &&
		proof.reviewTreeScrollToVisibleRows.p99Ms !== null &&
		proof.reviewTreeScrollToVisibleRows.p99Ms < 200 &&
		proof.codeViewScrollSampleCount >= minimumInteractionPerformanceSampleCount &&
		proof.codeViewScrollToStableWindow.sampleCount === proof.codeViewScrollSampleCount &&
		interactionDurationSummarySatisfied(
			proof.codeViewScrollSettleFrameCount,
			proof.codeViewScrollSampleCount,
		) &&
		proof.codeViewScrollToStableWindow.failureCount === 0 &&
		proof.codeViewScrollToStableWindow.p95Ms !== null &&
		proof.codeViewScrollToStableWindow.p95Ms < 100 &&
		proof.codeViewScrollToStableWindow.p99Ms !== null &&
		proof.codeViewScrollToStableWindow.p99Ms < 200 &&
		proof.reviewTreeBlankWindowCount === 0 &&
		proof.reviewTreeWrongVisibleRowCount === 0 &&
		proof.codeViewBlankWindowCount === 0 &&
		proof.codeViewItemCountAfter > 0 &&
		proof.codeViewHeightChangeCount >= 0
	);
}

export function worktreeStartupLoadTimingSatisfied(
	proof: Partial<Pick<WorktreeInteractionPerformanceProof, 'startupLoadTiming'>>,
): boolean {
	return (
		proof.startupLoadTiming !== undefined &&
		interactionDurationSummarySatisfied(proof.startupLoadTiming.pageLoadToSelectedPath, 1) &&
		interactionDurationSummarySatisfied(proof.startupLoadTiming.pageLoadToContentReady, 1) &&
		interactionDurationSummarySatisfied(
			proof.startupLoadTiming.pageLoadToFirstVisibleContentWindow,
			1,
		)
	);
}

export function reviewStartupLoadTimingSatisfied(
	proof: Partial<Pick<ReviewInteractionPerformanceProof, 'reviewStartupLoadTiming'>>,
): boolean {
	return (
		proof.reviewStartupLoadTiming !== undefined &&
		interactionDurationSummarySatisfied(proof.reviewStartupLoadTiming.pageLoadToMetadata, 1) &&
		interactionDurationSummarySatisfied(
			proof.reviewStartupLoadTiming.pageLoadToSelectedContentReady,
			1,
		) &&
		interactionDurationSummarySatisfied(proof.reviewStartupLoadTiming.pageLoadToReviewReady, 1) &&
		interactionDurationSummarySatisfied(proof.reviewStartupLoadTiming.metadataApplyDuration, 1) &&
		interactionDurationSummarySatisfied(
			proof.reviewStartupLoadTiming.selectedContentReadyDuration,
			1,
		) &&
		interactionDurationSummarySatisfied(proof.reviewStartupLoadTiming.reviewReadyDuration, 1)
	);
}

const minimumInteractionPerformanceSampleCount = 100;

function reviewClickReadinessBreakdownSatisfied(
	breakdown: ReviewClickReadinessBreakdownSummaries | undefined,
	reviewClickSampleCount: number,
): boolean {
	return (
		breakdown !== undefined &&
		interactionDurationSummarySatisfied(breakdown.treeSelectionVisible, reviewClickSampleCount) &&
		interactionDurationSummarySatisfied(breakdown.selectedPathState, reviewClickSampleCount) &&
		interactionDurationSummarySatisfied(
			breakdown.contentReadyAfterSelectedPath,
			reviewClickSampleCount,
		) &&
		interactionDurationSummarySatisfied(breakdown.selectedDemandDuration, reviewClickSampleCount) &&
		interactionDurationSummarySatisfied(
			breakdown.codeViewMaterializedAfterContentReady,
			reviewClickSampleCount,
		) &&
		interactionDurationSummarySatisfied(
			breakdown.visibleContentRenderedAfterMaterialization,
			reviewClickSampleCount,
		)
	);
}

function reviewClickPhaseDurationSummariesSatisfied(
	summaries: ReviewClickPhaseDurationSummaries | undefined,
	reviewClickSampleCount: number,
): boolean {
	return (
		summaries !== undefined &&
		interactionDurationSummarySatisfied(summaries.selectionCommit, reviewClickSampleCount) &&
		interactionDurationSummarySatisfied(summaries.readyAfterSelection, reviewClickSampleCount) &&
		interactionDurationSummarySatisfied(summaries.firstVisibleAfterReady, reviewClickSampleCount)
	);
}

function clickPhaseDurationSummariesSatisfied(
	summaries: WorktreeFileClickPhaseDurationSummaries | undefined,
	fileClickSampleCount: number,
): boolean {
	return (
		summaries !== undefined &&
		interactionDurationSummarySatisfied(summaries.selectionCommit, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(summaries.openReadyAfterSelection, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(summaries.firstVisibleAfterReady, fileClickSampleCount)
	);
}

function demandQueueWaitSatisfied(queueWait: WorktreeDemandQueueWaitProof | undefined): boolean {
	return (
		queueWait !== undefined &&
		interactionDurationSummarySatisfied(
			queueWait.foreground,
			minimumInteractionPerformanceSampleCount,
		) &&
		queueWait.foreground.p95Ms !== null &&
		queueWait.foreground.p95Ms < 32 &&
		queueWait.foreground.p99Ms !== null &&
		queueWait.foreground.p99Ms < 64 &&
		interactionDurationSummarySatisfied(
			queueWait.visible,
			minimumInteractionPerformanceSampleCount,
		) &&
		queueWait.visible.p95Ms !== null &&
		queueWait.visible.p95Ms < 64 &&
		queueWait.visible.p99Ms !== null &&
		queueWait.visible.p99Ms < 100
	);
}

function foregroundContentLoadTimingSatisfied(
	timing: WorktreeForegroundContentLoadTimingProof | undefined,
	fileClickSampleCount: number,
): boolean {
	return (
		timing !== undefined &&
		interactionDurationSummarySatisfied(timing.executorPendingWait, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(timing.executorInFlight, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(timing.resourceBodyRegistryCommit, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(timing.resourceFetchResponseWait, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(timing.resourceFirstChunkWait, fileClickSampleCount) &&
		interactionDurationSummarySatisfied(timing.resourceStreamRead, fileClickSampleCount)
	);
}

function interactionDurationSummarySatisfied(
	summary: WorktreeInteractionDurationSummary | undefined,
	expectedSampleCount: number,
): boolean {
	return (
		summary !== undefined &&
		summary.sampleCount === expectedSampleCount &&
		summary.failureCount === 0 &&
		summary.minMs !== null &&
		summary.medianMs !== null &&
		summary.maxMs !== null &&
		summary.p95Ms !== null &&
		summary.p99Ms !== null
	);
}

function medianOfSortedSamples(samples: readonly number[]): number | null {
	if (samples.length === 0) {
		return null;
	}
	const middleIndex = Math.floor(samples.length / 2);
	if (samples.length % 2 === 1) {
		return samples[middleIndex] ?? null;
	}
	const left = samples[middleIndex - 1];
	const right = samples[middleIndex];
	return left === undefined || right === undefined ? null : (left + right) / 2;
}

function nearestRankPercentile(samples: readonly number[], percentile: number): number | null {
	if (samples.length === 0) {
		return null;
	}
	const percentileIndex = Math.max(0, Math.ceil(samples.length * percentile) - 1);
	return samples[Math.min(percentileIndex, samples.length - 1)] ?? null;
}
