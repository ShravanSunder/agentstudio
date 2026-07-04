import type {
	BridgeResourceExecutor,
	BridgeResourceExecutorResult,
} from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
	BridgeDemandLane,
} from '../../core/models/bridge-demand-models.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import { assertNever } from './review-content-demand-policy.js';
import type {
	LoadedReviewContentDemandSettledResult,
	ReviewContentDemandInterest,
	ReviewContentDemandLoadResult,
	ReviewContentDemandResultReason,
	ReviewContentDemandTelemetry,
} from './review-content-demand-types.js';

export interface ReviewContentDemandTelemetryBuilder {
	recordAfterDispatch(): void;
	recordCompletion(props: {
		readonly result: ReviewContentDemandLoadResult;
		readonly loadedResults: readonly LoadedReviewContentDemandSettledResult[];
	}): void;
	build(): ReviewContentDemandTelemetry;
}

export function newReviewContentDemandTelemetryBuilder(props: {
	readonly itemId: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly interest: ReviewContentDemandInterest;
	readonly intents: readonly BridgeDemandIntent[];
	readonly executor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
}): ReviewContentDemandTelemetryBuilder {
	const laneCounts = countDemandIntentsByLane(props.intents);
	const executorInFlightCountBefore = props.executor.inFlightCount;
	const executorInFlightBytesBefore = props.executor.inFlightBytes;
	const executorQueuedLoadCountBefore = props.executor.queuedLoadCount;
	const executorQueuedBytesBefore = props.executor.queuedBytes;
	let executorInFlightCountAfterDispatch = executorInFlightCountBefore;
	let executorInFlightBytesAfterDispatch = executorInFlightBytesBefore;
	let executorQueuedLoadCountAfterDispatch = executorQueuedLoadCountBefore;
	let executorQueuedBytesAfterDispatch = executorQueuedBytesBefore;
	let executorInFlightCountAfter = executorInFlightCountBefore;
	let executorInFlightBytesAfter = executorInFlightBytesBefore;
	let executorQueuedLoadCountAfter = executorQueuedLoadCountBefore;
	let executorQueuedBytesAfter = executorQueuedBytesBefore;
	let loadedCount = 0;
	let deferredCount = 0;
	let failedCount = 0;
	let admittedBytes = 0;
	const droppedIntentCount = 0;
	const laneUpgradeCount = 0;
	let resultReason: ReviewContentDemandResultReason | undefined;
	let resultStatus: ReviewContentDemandLoadResult['status'] | undefined;
	let resultLoadFailureKind: ReviewContentDemandTelemetry['resultLoadFailureKind'] | undefined;
	let staleDropCount = 0;
	const admittedBytesByLane = emptyDemandLaneByteCounts();
	const deferredEstimatedBytesByLane = emptyDemandLaneByteCounts();
	const droppedEstimatedBytesByLane = emptyDemandLaneByteCounts();
	const startedAtMilliseconds = performance.now();

	const recordAfterDispatch = (): void => {
		executorInFlightCountAfterDispatch = props.executor.inFlightCount;
		executorInFlightBytesAfterDispatch = props.executor.inFlightBytes;
		executorQueuedLoadCountAfterDispatch = props.executor.queuedLoadCount;
		executorQueuedBytesAfterDispatch = props.executor.queuedBytes;
	};

	const recordCompletion = (completionProps: {
		readonly result: ReviewContentDemandLoadResult;
		readonly loadedResults: readonly LoadedReviewContentDemandSettledResult[];
	}): void => {
		resultStatus = completionProps.result.status;
		resultReason =
			completionProps.result.status === 'ready' ? undefined : completionProps.result.reason;
		for (const loadedResult of completionProps.loadedResults) {
			if (loadedResult.status === 'rejected') {
				failedCount += 1;
				continue;
			}
			if (loadedResult.value.result.ok) {
				if (!loadedResult.value.result.authoritative) {
					deferredCount += 1;
					staleDropCount += 1;
					deferredEstimatedBytesByLane[loadedResult.value.intent.lane] +=
						loadedResult.value.estimatedBytes;
					continue;
				}
				loadedCount += 1;
				admittedBytes += loadedResult.value.result.byteLength;
				admittedBytesByLane[loadedResult.value.intent.lane] += loadedResult.value.result.byteLength;
				continue;
			}
			if (isDeferredExecutorResult(loadedResult.value.result)) {
				deferredCount += 1;
				deferredEstimatedBytesByLane[loadedResult.value.intent.lane] +=
					loadedResult.value.estimatedBytes;
				if (loadedResult.value.result.reason === 'stale_completion') {
					staleDropCount += 1;
				}
				continue;
			}
			if (
				loadedResult.value.result.reason === 'load_failed' &&
				loadedResult.value.result.loadFailureKind !== undefined
			) {
				resultLoadFailureKind ??= loadedResult.value.result.loadFailureKind;
			}
			failedCount += 1;
		}
		if (completionProps.result.status === 'deferred' && deferredCount === 0) {
			deferredCount = Math.max(1, props.intents.length - loadedCount - failedCount);
		}
		if (completionProps.result.status === 'failed' && failedCount === 0) {
			failedCount = Math.max(1, props.intents.length - loadedCount - deferredCount);
		}
		executorInFlightCountAfter = props.executor.inFlightCount;
		executorInFlightBytesAfter = props.executor.inFlightBytes;
		executorQueuedLoadCountAfter = props.executor.queuedLoadCount;
		executorQueuedBytesAfter = props.executor.queuedBytes;
	};

	return {
		recordAfterDispatch,
		recordCompletion,
		build(): ReviewContentDemandTelemetry {
			return {
				itemId: props.itemId,
				packageId: props.packageId,
				reviewGeneration: props.reviewGeneration,
				revision: props.revision,
				interest: props.interest,
				...(resultReason === undefined ? {} : { resultReason }),
				...(resultStatus === undefined ? {} : { resultStatus }),
				...(resultLoadFailureKind === undefined ? {} : { resultLoadFailureKind }),
				byteBudgetSource: 'review-content-demand',
				durationMilliseconds: Math.max(0, performance.now() - startedAtMilliseconds),
				configuredExecutorMaxConcurrentLoads: props.executor.maxConcurrentLoads,
				configuredExecutorMaxInFlightBytes: props.executor.maxInFlightBytes,
				intentCount: props.intents.length,
				foregroundIntentCount: laneCounts.foreground,
				activeIntentCount: laneCounts.active,
				visibleIntentCount: laneCounts.visible,
				nearbyIntentCount: laneCounts.nearby,
				speculativeIntentCount: laneCounts.speculative,
				idleIntentCount: laneCounts.idle,
				executorInFlightCountBefore,
				executorInFlightCountAfterDispatch,
				executorInFlightCountAfter,
				executorInFlightBytesBefore,
				executorInFlightBytesAfterDispatch,
				executorInFlightBytesAfter,
				executorQueuedLoadCountBefore,
				executorQueuedLoadCountAfterDispatch,
				executorQueuedLoadCountAfter,
				executorQueuedBytesBefore,
				executorQueuedBytesAfterDispatch,
				executorQueuedBytesAfter,
				laneUpgradeCount,
				maxExecutorInFlightCount: Math.max(
					executorInFlightCountBefore,
					executorInFlightCountAfterDispatch,
					executorInFlightCountAfter,
				),
				maxExecutorQueuedLoadCount: Math.max(
					executorQueuedLoadCountBefore,
					executorQueuedLoadCountAfterDispatch,
					executorQueuedLoadCountAfter,
				),
				admittedBytes,
				admittedBytesByLane,
				deferredCount,
				deferredEstimatedBytesByLane,
				droppedEstimatedBytesByLane,
				droppedIntentCount,
				failedCount,
				loadedCount,
				staleDropCount,
			};
		},
	};
}

function countDemandIntentsByLane(
	intents: readonly BridgeDemandIntent[],
): Record<BridgeDemandLane, number> {
	const counts: Record<BridgeDemandLane, number> = {
		foreground: 0,
		active: 0,
		visible: 0,
		nearby: 0,
		speculative: 0,
		idle: 0,
	};
	for (const intent of intents) {
		counts[intent.lane] += 1;
	}
	return counts;
}

function emptyDemandLaneByteCounts(): Record<BridgeDemandLane, number> {
	return {
		foreground: 0,
		active: 0,
		visible: 0,
		nearby: 0,
		speculative: 0,
		idle: 0,
	};
}

function isDeferredExecutorResult(
	result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>,
): boolean {
	if (result.ok) {
		return false;
	}
	switch (result.reason) {
		case 'aborted':
		case 'concurrency_exceeded':
		case 'stale_completion':
			return true;
		case 'byte_budget_exceeded':
		case 'descriptor_missing':
		case 'load_failed':
			return false;
	}
	return assertNever(result.reason);
}
