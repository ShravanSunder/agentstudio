import type { BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-types.js';
import type { BridgeReviewProjectionInputItem } from '../review-viewer/models/review-projection-models.js';

export function makeReviewProjectionInputItem(props: {
	readonly itemId: string;
	readonly path: string;
}): BridgeReviewProjectionInputItem {
	return {
		itemId: props.itemId,
		basePath: props.path,
		headPath: props.path,
		changeKind: 'modified',
		fileClass: 'source',
		language: 'swift',
		extension: 'swift',
		isHiddenByDefault: false,
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
		contentRoles: ['base', 'head'],
		contentDescriptorIdsByRole: {
			base: `handle-${props.itemId}-base`,
			head: `handle-${props.itemId}-head`,
		},
		mimeTypes: ['text/x-swift'],
		provenance: emptyReviewProjectionItemProvenance(),
	};
}

function emptyReviewProjectionItemProvenance(): BridgeReviewProjectionInputItem['provenance'] {
	return {
		agentSessionIds: [],
		promptIds: [],
		operationIds: [],
	};
}

export interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

export function createDeferred<TValue>(): Deferred<TValue> {
	let resolveDeferred: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolveDeferred = resolve;
	});
	if (resolveDeferred === null) {
		throw new Error('Deferred test value did not initialize');
	}
	return {
		promise,
		resolve: resolveDeferred,
	};
}

export async function flushMicrotasks(count: number): Promise<void> {
	let flushPromise = Promise.resolve();
	for (let index = 0; index < count; index += 1) {
		flushPromise = flushPromise.then((): void => {});
	}
	await flushPromise;
}

export async function flushMicrotasksUntil(
	predicate: () => boolean,
	maxFlushCount: number,
): Promise<void> {
	if (predicate() || maxFlushCount <= 0) {
		return;
	}
	await flushMicrotasks(1);
	await flushMicrotasksUntil(predicate, maxFlushCount - 1);
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

export function makeNoopTelemetryRecorder(): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => false,
		record: (): void => {},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		flush: (): boolean => true,
	};
}

export function makeSelectedReviewContentDemandTelemetry(
	props: Pick<
		ReviewContentDemandTelemetry,
		'itemId' | 'packageId' | 'reviewGeneration' | 'revision' | 'resultStatus' | 'resultReason'
	>,
): ReviewContentDemandTelemetry {
	return {
		...props,
		interest: 'selected',
		byteBudgetSource: 'review-content-demand',
		durationMilliseconds: 4,
		configuredExecutorMaxConcurrentLoads: 2,
		configuredExecutorMaxInFlightBytes: 10,
		intentCount: 0,
		foregroundIntentCount: 0,
		activeIntentCount: 0,
		visibleIntentCount: 0,
		nearbyIntentCount: 0,
		speculativeIntentCount: 0,
		idleIntentCount: 0,
		executorInFlightCountBefore: 0,
		executorInFlightCountAfterDispatch: 0,
		executorInFlightCountAfter: 0,
		executorInFlightBytesBefore: 0,
		executorInFlightBytesAfterDispatch: 0,
		executorInFlightBytesAfter: 0,
		executorQueuedLoadCountBefore: 0,
		executorQueuedLoadCountAfterDispatch: 0,
		executorQueuedLoadCountAfter: 0,
		executorQueuedBytesBefore: 0,
		executorQueuedBytesAfterDispatch: 0,
		executorQueuedBytesAfter: 0,
		laneUpgradeCount: 0,
		maxExecutorInFlightCount: 0,
		maxExecutorQueuedLoadCount: 0,
		admittedBytes: 0,
		admittedBytesByLane: emptyDemandLaneByteCounts(),
		deferredCount: 0,
		deferredEstimatedBytesByLane: emptyDemandLaneByteCounts(),
		droppedEstimatedBytesByLane: emptyDemandLaneByteCounts(),
		droppedIntentCount: 0,
		failedCount: props.resultStatus === 'failed' ? 1 : 0,
		loadedCount: props.resultStatus === 'ready' ? 1 : 0,
		staleDropCount: 0,
	};
}
