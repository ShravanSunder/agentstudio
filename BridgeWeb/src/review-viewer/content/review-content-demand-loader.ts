import type { BridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import type {
	BridgeResourceExecutor,
	BridgeResourceExecutorResult,
} from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
	BridgeDemandLane,
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import { mapReviewDemandStimulusToIntents } from '../../features/review/demand/review-demand-policy.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { recordBridgeViewerContentFetchTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';

export interface LoadReviewItemContentResourcesThroughDemandProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly itemId: string;
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative';
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly signal?: AbortSignal;
	readonly traceContext?: BridgeTraceContext | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly onDemandTelemetry?: (sample: ReviewContentDemandTelemetry) => void;
}

export type ReviewContentDemandInterest =
	LoadReviewItemContentResourcesThroughDemandProps['interest'];

export type ReviewContentDemandLoadResult =
	| {
			readonly status: 'ready';
			readonly resources: BridgeCodeViewContentResources;
	  }
	| {
			readonly status: 'deferred';
			readonly reason: 'aborted' | 'concurrency_exceeded' | 'stale_completion';
	  }
	| {
			readonly status: 'failed';
			readonly reason: 'byte_budget_exceeded' | 'descriptor_missing' | 'load_failed';
	  };

export interface ReviewContentDemandTelemetry {
	readonly itemId: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly interest: ReviewContentDemandInterest;
	readonly byteBudgetSource: 'review-content-demand';
	readonly configuredExecutorMaxConcurrentLoads: number;
	readonly configuredExecutorMaxInFlightBytes: number;
	readonly configuredSchedulerMaxQueuedEstimatedBytes: number;
	readonly configuredSchedulerMaxQueuedIntentsPerLane: number;
	readonly intentCount: number;
	readonly foregroundIntentCount: number;
	readonly activeIntentCount: number;
	readonly visibleIntentCount: number;
	readonly nearbyIntentCount: number;
	readonly speculativeIntentCount: number;
	readonly idleIntentCount: number;
	readonly enqueueAcceptedCount: number;
	readonly enqueueRejectedCount: number;
	readonly schedulerQueuedIntentCountBefore: number;
	readonly schedulerQueuedIntentCountAfterEnqueue: number;
	readonly schedulerQueuedIntentCountAfter: number;
	readonly schedulerQueuedEstimatedBytesBefore: number;
	readonly schedulerQueuedEstimatedBytesAfterEnqueue: number;
	readonly schedulerQueuedEstimatedBytesAfter: number;
	readonly executorInFlightCountBefore: number;
	readonly executorInFlightCountAfterDispatch: number;
	readonly executorInFlightCountAfter: number;
	readonly executorInFlightBytesBefore: number;
	readonly executorInFlightBytesAfterDispatch: number;
	readonly executorInFlightBytesAfter: number;
	readonly executorQueuedLoadCountBefore: number;
	readonly executorQueuedLoadCountAfterDispatch: number;
	readonly executorQueuedLoadCountAfter: number;
	readonly executorQueuedBytesBefore: number;
	readonly executorQueuedBytesAfterDispatch: number;
	readonly executorQueuedBytesAfter: number;
	readonly laneUpgradeCount: number;
	readonly maxSchedulerQueuedIntentCount: number;
	readonly maxExecutorInFlightCount: number;
	readonly maxExecutorQueuedLoadCount: number;
	readonly admittedBytes: number;
	readonly admittedBytesByLane: Record<BridgeDemandLane, number>;
	readonly deferredCount: number;
	readonly deferredEstimatedBytesByLane: Record<BridgeDemandLane, number>;
	readonly droppedEstimatedBytesByLane: Record<BridgeDemandLane, number>;
	readonly droppedIntentCount: number;
	readonly failedCount: number;
	readonly loadedCount: number;
	readonly staleDropCount: number;
}

interface ReviewContentDemandPlan {
	readonly handle: BridgeContentHandle;
	readonly role: BridgeContentRole;
	readonly descriptorRef: BridgeDescriptorRef;
}

interface ReviewContentDemandTelemetryBuilder {
	recordAcceptedEnqueue(props: { readonly droppedLowerPriorityCount: number }): void;
	recordRejectedEnqueue(intent: BridgeDemandIntent, estimatedBytes: number): void;
	recordAfterEnqueue(): void;
	recordAfterDispatch(): void;
	recordCompletion(props: {
		readonly result: ReviewContentDemandLoadResult;
		readonly loadedResults: readonly LoadedReviewContentDemandSettledResult[];
	}): void;
	build(): ReviewContentDemandTelemetry;
}

type LoadedReviewContentDemandSettledResult =
	| {
			readonly status: 'fulfilled';
			readonly value: LoadedReviewContentDemandResult;
	  }
	| {
			readonly status: 'rejected';
	  };

function newReviewContentDemandTelemetryBuilder(props: {
	readonly itemId: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly interest: ReviewContentDemandInterest;
	readonly intents: readonly BridgeDemandIntent[];
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
}): ReviewContentDemandTelemetryBuilder {
	const laneCounts = countDemandIntentsByLane(props.intents);
	const schedulerQueuedIntentCountBefore = props.scheduler.queuedIntentCount;
	const schedulerQueuedEstimatedBytesBefore = props.scheduler.queuedEstimatedBytes;
	const executorInFlightCountBefore = props.executor.inFlightCount;
	const executorInFlightBytesBefore = props.executor.inFlightBytes;
	const executorQueuedLoadCountBefore = props.executor.queuedLoadCount;
	const executorQueuedBytesBefore = props.executor.queuedBytes;
	let enqueueAcceptedCount = 0;
	let enqueueRejectedCount = 0;
	let schedulerQueuedIntentCountAfterEnqueue = schedulerQueuedIntentCountBefore;
	let schedulerQueuedEstimatedBytesAfterEnqueue = schedulerQueuedEstimatedBytesBefore;
	let executorInFlightCountAfterDispatch = executorInFlightCountBefore;
	let executorInFlightBytesAfterDispatch = executorInFlightBytesBefore;
	let executorQueuedLoadCountAfterDispatch = executorQueuedLoadCountBefore;
	let executorQueuedBytesAfterDispatch = executorQueuedBytesBefore;
	let schedulerQueuedIntentCountAfter = schedulerQueuedIntentCountBefore;
	let schedulerQueuedEstimatedBytesAfter = schedulerQueuedEstimatedBytesBefore;
	let executorInFlightCountAfter = executorInFlightCountBefore;
	let executorInFlightBytesAfter = executorInFlightBytesBefore;
	let executorQueuedLoadCountAfter = executorQueuedLoadCountBefore;
	let executorQueuedBytesAfter = executorQueuedBytesBefore;
	let loadedCount = 0;
	let deferredCount = 0;
	let failedCount = 0;
	let admittedBytes = 0;
	let droppedIntentCount = 0;
	const laneUpgradeCount = 0;
	let staleDropCount = 0;
	const admittedBytesByLane = emptyDemandLaneByteCounts();
	const deferredEstimatedBytesByLane = emptyDemandLaneByteCounts();
	const droppedEstimatedBytesByLane = emptyDemandLaneByteCounts();

	const recordAfterEnqueue = (): void => {
		schedulerQueuedIntentCountAfterEnqueue = props.scheduler.queuedIntentCount;
		schedulerQueuedEstimatedBytesAfterEnqueue = props.scheduler.queuedEstimatedBytes;
	};

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
			failedCount += 1;
		}
		if (completionProps.result.status === 'deferred' && deferredCount === 0) {
			deferredCount = Math.max(1, props.intents.length - loadedCount - failedCount);
		}
		if (completionProps.result.status === 'failed' && failedCount === 0) {
			failedCount = Math.max(1, props.intents.length - loadedCount - deferredCount);
		}
		schedulerQueuedIntentCountAfter = props.scheduler.queuedIntentCount;
		schedulerQueuedEstimatedBytesAfter = props.scheduler.queuedEstimatedBytes;
		executorInFlightCountAfter = props.executor.inFlightCount;
		executorInFlightBytesAfter = props.executor.inFlightBytes;
		executorQueuedLoadCountAfter = props.executor.queuedLoadCount;
		executorQueuedBytesAfter = props.executor.queuedBytes;
	};

	return {
		recordAcceptedEnqueue(acceptedProps: { readonly droppedLowerPriorityCount: number }): void {
			enqueueAcceptedCount += 1;
			droppedIntentCount += acceptedProps.droppedLowerPriorityCount;
		},
		recordRejectedEnqueue(intent: BridgeDemandIntent, estimatedBytes: number): void {
			enqueueRejectedCount += 1;
			droppedIntentCount += 1;
			droppedEstimatedBytesByLane[intent.lane] += estimatedBytes;
		},
		recordAfterEnqueue,
		recordAfterDispatch,
		recordCompletion,
		build(): ReviewContentDemandTelemetry {
			return {
				itemId: props.itemId,
				packageId: props.packageId,
				reviewGeneration: props.reviewGeneration,
				revision: props.revision,
				interest: props.interest,
				byteBudgetSource: 'review-content-demand',
				configuredExecutorMaxConcurrentLoads: props.executor.maxConcurrentLoads,
				configuredExecutorMaxInFlightBytes: props.executor.maxInFlightBytes,
				configuredSchedulerMaxQueuedEstimatedBytes: props.scheduler.maxQueuedEstimatedBytes,
				configuredSchedulerMaxQueuedIntentsPerLane: props.scheduler.maxQueuedIntentsPerLane,
				intentCount: props.intents.length,
				foregroundIntentCount: laneCounts.foreground,
				activeIntentCount: laneCounts.active,
				visibleIntentCount: laneCounts.visible,
				nearbyIntentCount: laneCounts.nearby,
				speculativeIntentCount: laneCounts.speculative,
				idleIntentCount: laneCounts.idle,
				enqueueAcceptedCount,
				enqueueRejectedCount,
				schedulerQueuedIntentCountBefore,
				schedulerQueuedIntentCountAfterEnqueue,
				schedulerQueuedIntentCountAfter,
				schedulerQueuedEstimatedBytesBefore,
				schedulerQueuedEstimatedBytesAfterEnqueue,
				schedulerQueuedEstimatedBytesAfter,
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
				maxSchedulerQueuedIntentCount: Math.max(
					schedulerQueuedIntentCountBefore,
					schedulerQueuedIntentCountAfterEnqueue,
					schedulerQueuedIntentCountAfter,
				),
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

export async function loadReviewItemContentResourcesThroughDemand(
	props: LoadReviewItemContentResourcesThroughDemandProps,
): Promise<BridgeCodeViewContentResources | null> {
	const result = await loadReviewItemContentResourcesThroughDemandResult(props);
	return result.status === 'ready' ? result.resources : null;
}

export async function loadReviewItemContentResourcesThroughDemandResult(
	props: LoadReviewItemContentResourcesThroughDemandProps,
): Promise<ReviewContentDemandLoadResult> {
	const item = props.reviewPackage.itemsById[props.itemId];
	if (item === undefined) {
		return { status: 'failed', reason: 'descriptor_missing' };
	}
	const plans = demandPlansForReviewItem({
		item,
		resolveDescriptorRef: props.resolveDescriptorRef,
	});
	if (plans === null) {
		return { status: 'failed', reason: 'descriptor_missing' };
	}
	if (props.signal?.aborted) {
		return { status: 'deferred', reason: 'aborted' };
	}
	const demandAbortController = new AbortController();
	const abortDemandLoads = (): void => {
		demandAbortController.abort();
	};
	props.signal?.addEventListener('abort', abortDemandLoads, { once: true });
	const intents = plans.flatMap((plan: ReviewContentDemandPlan): readonly BridgeDemandIntent[] =>
		mapReviewDemandStimulusToIntents({
			stimulus: stimulusForPlan(plan, props.interest),
			readContext: {
				getDescriptorState: (): BridgeDescriptorDemandState => ({
					kind: 'valid',
					freshnessKey: demandFreshnessKeyForReviewDescriptorRef(plan.descriptorRef),
					needsBodyOrWindow: true,
				}),
				getViewInterest: (): BridgeViewInterest => ({ kind: props.interest }),
				buildDemandKeys: () => demandKeysForPlan(plan, props.interest),
			},
		}),
	);
	const telemetryBuilder = newReviewContentDemandTelemetryBuilder({
		itemId: props.itemId,
		packageId: props.reviewPackage.packageId,
		reviewGeneration: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		interest: props.interest,
		intents,
		scheduler: props.scheduler,
		executor: props.executor,
	});
	for (const intent of intents) {
		const estimatedBytes = estimatedBytesForDemandIntent({
			intent,
			interest: props.interest,
			plans,
		});
		const enqueueResult = props.scheduler.enqueue({
			intent,
			estimatedBytes,
		});
		if (!enqueueResult.ok) {
			telemetryBuilder.recordRejectedEnqueue(intent, estimatedBytes);
			for (const acceptedIntent of intents.slice(0, intents.indexOf(intent))) {
				props.scheduler.cancelGroup(acceptedIntent.cancellationGroup);
			}
			const result: ReviewContentDemandLoadResult =
				enqueueResult.reason === 'queued_byte_limit_exceeded'
					? { status: 'failed', reason: 'byte_budget_exceeded' }
					: { status: 'deferred', reason: 'concurrency_exceeded' };
			telemetryBuilder.recordCompletion({
				result,
				loadedResults: [],
			});
			props.onDemandTelemetry?.(telemetryBuilder.build());
			return result;
		}
		telemetryBuilder.recordAcceptedEnqueue({
			droppedLowerPriorityCount: enqueueResult.droppedLowerPriorityCount ?? 0,
		});
	}
	telemetryBuilder.recordAfterEnqueue();
	const executableIntents: {
		readonly intent: BridgeDemandIntent;
		readonly plan: ReviewContentDemandPlan;
	}[] = [];
	let nextIntent = props.scheduler.dequeueNextMatching((intent): boolean =>
		plans.some(
			(plan: ReviewContentDemandPlan): boolean =>
				plan.descriptorRef.descriptorId === intent.descriptorRef.descriptorId,
		),
	);
	while (nextIntent !== null) {
		const matchingPlan = plans.find(
			(plan: ReviewContentDemandPlan): boolean =>
				plan.descriptorRef.descriptorId === nextIntent?.descriptorRef.descriptorId,
		);
		if (matchingPlan !== undefined) {
			executableIntents.push({ intent: nextIntent, plan: matchingPlan });
		}
		nextIntent = props.scheduler.dequeueNextMatching((intent): boolean =>
			plans.some(
				(plan: ReviewContentDemandPlan): boolean =>
					plan.descriptorRef.descriptorId === intent.descriptorRef.descriptorId,
			),
		);
	}
	try {
		const settledLoadedResults: LoadedReviewContentDemandSettledResult[] = [];
		const loadedResults = executableIntents.map(async (executableIntent) => {
			try {
				const loadedResult = {
					role: executableIntent.plan.role,
					intent: executableIntent.intent,
					estimatedBytes: estimatedBytesForDemandIntent({
						intent: executableIntent.intent,
						interest: props.interest,
						plans,
					}),
					result: await loadDemandResourceWithTelemetry({
						intent: executableIntent.intent,
						role: executableIntent.plan.role,
						interest: props.interest,
						executor: props.executor,
						signal: demandAbortController.signal,
						traceContext: props.traceContext ?? null,
						telemetryRecorder: props.telemetryRecorder,
					}),
				};
				settledLoadedResults.push({ status: 'fulfilled', value: loadedResult });
				return loadedResult;
			} catch (error: unknown) {
				settledLoadedResults.push({ status: 'rejected' });
				throw error;
			}
		});
		telemetryBuilder.recordAfterDispatch();
		const result = await Promise.race([
			loadAllDemandResources({ plans, loadedResults, signal: demandAbortController.signal }),
			failFastOnFirstDemandResourceFailure({
				loadedResults,
				abortSiblingLoads: abortDemandLoads,
			}),
		]);
		telemetryBuilder.recordCompletion({
			result,
			loadedResults: settledLoadedResults,
		});
		props.onDemandTelemetry?.(telemetryBuilder.build());
		return result;
	} finally {
		props.signal?.removeEventListener('abort', abortDemandLoads);
	}
}

interface LoadedReviewContentDemandResult {
	readonly estimatedBytes: number;
	readonly intent: BridgeDemandIntent;
	readonly role: BridgeContentRole;
	readonly result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>;
}

async function loadAllDemandResources(props: {
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResults: readonly Promise<LoadedReviewContentDemandResult>[];
	readonly signal: AbortSignal | undefined;
}): Promise<ReviewContentDemandLoadResult> {
	const loadedResourcesByRole = new Map<
		BridgeContentRole,
		BridgeResourceExecutorResult<BridgeTextResourceStreamResult>
	>();
	const loadedResults = await Promise.all(props.loadedResults);
	if (props.signal?.aborted === true) {
		return { status: 'deferred', reason: 'aborted' };
	}
	for (const loadedResult of loadedResults) {
		loadedResourcesByRole.set(loadedResult.role, loadedResult.result);
	}
	return resultForPlans({ plans: props.plans, loadedResourcesByRole });
}

async function failFastOnFirstDemandResourceFailure(props: {
	readonly loadedResults: readonly Promise<LoadedReviewContentDemandResult>[];
	readonly abortSiblingLoads: () => void;
}): Promise<ReviewContentDemandLoadResult> {
	return await new Promise<ReviewContentDemandLoadResult>((resolve): void => {
		for (const loadedResult of props.loadedResults) {
			void loadedResult.then((result): void => {
				if (!result.result.ok && isTerminalDemandResourceFailure(result.result)) {
					resolve(loadResultForFailedResource(result.result));
					props.abortSiblingLoads();
				}
			});
		}
	});
}

async function loadDemandResourceWithTelemetry(props: {
	readonly intent: BridgeDemandIntent;
	readonly role: BridgeContentRole;
	readonly interest: ReviewContentDemandInterest;
	readonly executor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly signal: AbortSignal | undefined;
	readonly traceContext: BridgeTraceContext | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
}): Promise<BridgeResourceExecutorResult<BridgeTextResourceStreamResult>> {
	const start = performance.now();
	let loadResult: BridgeResourceExecutorResult<BridgeTextResourceStreamResult> | null = null;
	const cancelDemandGroup = (): void => {
		props.executor.cancelGroup(props.intent.cancellationGroup);
	};
	try {
		if (props.signal?.aborted === true) {
			cancelDemandGroup();
			loadResult = { ok: false, reason: 'aborted' };
			return loadResult;
		}
		props.signal?.addEventListener('abort', cancelDemandGroup, { once: true });
		loadResult = await props.executor.load(props.intent);
		return loadResult;
	} finally {
		props.signal?.removeEventListener('abort', cancelDemandGroup);
		if (props.telemetryRecorder !== undefined) {
			const telemetryResult = telemetryResultForExecutorResult(loadResult);
			recordBridgeViewerContentFetchTelemetry({
				telemetryRecorder: props.telemetryRecorder,
				traceContext: props.traceContext,
				contentRole: props.role,
				durationMilliseconds: Math.max(0, performance.now() - start),
				interest: props.interest,
				result: telemetryResult.result,
				resultReason: telemetryResult.resultReason,
			});
		}
	}
}

function telemetryResultForExecutorResult(
	result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult> | null,
): {
	readonly result: 'success' | 'deferred' | 'failed';
	readonly resultReason: string | null;
} {
	if (result === null) {
		return { result: 'failed', resultReason: 'load_threw' };
	}
	if (result.ok) {
		return { result: 'success', resultReason: null };
	}
	switch (result.reason) {
		case 'aborted':
		case 'concurrency_exceeded':
		case 'stale_completion':
			return { result: 'deferred', resultReason: result.reason };
		case 'byte_budget_exceeded':
		case 'descriptor_missing':
		case 'load_failed':
			return { result: 'failed', resultReason: result.reason };
	}
	return assertNever(result.reason);
}

function demandPlansForReviewItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
}): readonly ReviewContentDemandPlan[] | null {
	const roleHandles = roleHandlesForReviewItem(props.item);
	const plans: ReviewContentDemandPlan[] = [];
	for (const roleHandle of roleHandles) {
		const descriptorRef = props.resolveDescriptorRef(roleHandle.handle);
		if (descriptorRef === null) {
			return null;
		}
		plans.push({
			handle: roleHandle.handle,
			role: roleHandle.role,
			descriptorRef,
		});
	}
	return plans.length === 0 ? null : plans;
}

function roleHandlesForReviewItem(
	item: BridgeReviewItemDescriptor,
): readonly { readonly role: BridgeContentRole; readonly handle: BridgeContentHandle }[] {
	const baseHandle = item.contentRoles.base ?? null;
	const headHandle = item.contentRoles.head ?? null;
	if (item.itemKind === 'diff' && baseHandle !== null && headHandle !== null) {
		return [
			{ role: 'base', handle: baseHandle },
			{ role: 'head', handle: headHandle },
		];
	}
	const diffHandle = item.contentRoles.diff ?? null;
	if (item.itemKind === 'diff' && diffHandle !== null) {
		return [{ role: 'diff', handle: diffHandle }];
	}
	const preferredHandle = preferredContentHandle(item);
	return preferredHandle === null ? [] : [preferredHandle];
}

function preferredContentHandle(
	item: BridgeReviewItemDescriptor,
): { readonly role: BridgeContentRole; readonly handle: BridgeContentHandle } | null {
	const headHandle = item.contentRoles.head ?? null;
	if (headHandle !== null) {
		return { role: 'head', handle: headHandle };
	}
	const fileHandle = item.contentRoles.file ?? null;
	if (fileHandle !== null) {
		return { role: 'file', handle: fileHandle };
	}
	const diffHandle = item.contentRoles.diff ?? null;
	if (diffHandle !== null) {
		return { role: 'diff', handle: diffHandle };
	}
	const baseHandle = item.contentRoles.base ?? null;
	return baseHandle === null ? null : { role: 'base', handle: baseHandle };
}

function stimulusForPlan(
	plan: ReviewContentDemandPlan,
	interest: LoadReviewItemContentResourcesThroughDemandProps['interest'],
): Parameters<typeof mapReviewDemandStimulusToIntents>[0]['stimulus'] {
	if (interest === 'selected') {
		return { kind: 'reviewItemSelected', descriptorRef: plan.descriptorRef };
	}
	if (interest === 'visible') {
		return { kind: 'reviewViewportChanged', descriptorRefs: [plan.descriptorRef] };
	}
	if (interest === 'speculative') {
		return { kind: 'reviewHoverChanged', descriptorRef: plan.descriptorRef };
	}
	return { kind: 'reviewDescriptorInvalidated', descriptorRef: plan.descriptorRef };
}

function demandKeysForPlan(
	plan: ReviewContentDemandPlan,
	interest: LoadReviewItemContentResourcesThroughDemandProps['interest'],
): {
	readonly orderingKey: string;
	readonly dedupeKey: string;
	readonly freshnessKey: string;
	readonly cancellationGroup: string;
} {
	const descriptorIdentityKey = demandFreshnessKeyForReviewDescriptorRef(plan.descriptorRef);
	const contentRoleKey = `${plan.handle.itemId}:${plan.role}`;
	const demandKey = `${descriptorIdentityKey}:${contentRoleKey}`;
	return {
		orderingKey: demandKey,
		dedupeKey: `${interest}:${demandKey}`,
		freshnessKey: descriptorIdentityKey,
		cancellationGroup: demandCancellationGroupForReviewDescriptorRef(plan.descriptorRef, interest),
	};
}

function estimatedBytesForDemandIntent(props: {
	readonly intent: BridgeDemandIntent;
	readonly interest: ReviewContentDemandInterest;
	readonly plans: readonly ReviewContentDemandPlan[];
}): number {
	if (props.interest === 'selected') {
		return 0;
	}
	const matchingPlan = props.plans.find(
		(plan: ReviewContentDemandPlan): boolean =>
			plan.descriptorRef.descriptorId === props.intent.descriptorRef.descriptorId,
	);
	return matchingPlan?.handle.sizeBytes ?? 0;
}

export function demandFreshnessKeyForReviewDescriptorRef(
	descriptorRef: BridgeDescriptorRef,
): string {
	return [
		descriptorRef.expectedIdentity.paneId,
		descriptorRef.expectedIdentity.protocol,
		descriptorRef.expectedIdentity.sourceId ?? 'no-source',
		descriptorRef.expectedIdentity.packageId ?? 'no-package',
		String(descriptorRef.expectedIdentity.generation ?? 0),
		String(descriptorRef.expectedIdentity.revision ?? 0),
		descriptorRef.expectedIdentity.streamId ?? 'no-stream',
		descriptorRef.expectedIdentity.cursor ?? 'no-cursor',
		descriptorRef.descriptorId,
	].join(':');
}

export function demandCancellationGroupForReviewDescriptorRef(
	descriptorRef: BridgeDescriptorRef,
	interest: ReviewContentDemandInterest,
): string {
	return `${demandFreshnessKeyForReviewDescriptorRef(descriptorRef)}:${interest}`;
}

export function demandCancellationGroupsForReviewDescriptorRef(
	descriptorRef: BridgeDescriptorRef,
): readonly string[] {
	return reviewContentDemandInterests.map((interest): string =>
		demandCancellationGroupForReviewDescriptorRef(descriptorRef, interest),
	);
}

const reviewContentDemandInterests = [
	'selected',
	'visible',
	'nearby',
	'speculative',
] as const satisfies readonly ReviewContentDemandInterest[];

function resultForPlans(props: {
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResourcesByRole: ReadonlyMap<
		BridgeContentRole,
		BridgeResourceExecutorResult<BridgeTextResourceStreamResult>
	>;
}): ReviewContentDemandLoadResult {
	const terminalFailure = firstTerminalFailureForPlans(props);
	if (terminalFailure !== null) {
		return loadResultForFailedResource(terminalFailure);
	}
	const resources: Record<BridgeContentRole, BridgeContentResource | undefined> = {
		base: undefined,
		head: undefined,
		diff: undefined,
		file: undefined,
	};
	for (const plan of props.plans) {
		const result = props.loadedResourcesByRole.get(plan.role);
		if (result?.ok !== true) {
			return loadResultForFailedResource(result ?? { ok: false, reason: 'descriptor_missing' });
		}
		if (!result.authoritative) {
			return { status: 'deferred', reason: 'stale_completion' };
		}
		resources[plan.role] = {
			authoritative: result.authoritative,
			byteLength: result.byteLength,
			handle: plan.handle,
			readText: (): string => result.content.readText(),
		};
	}
	return {
		status: 'ready',
		resources: {
			...(resources.base === undefined ? {} : { base: resources.base }),
			...(resources.head === undefined ? {} : { head: resources.head }),
			...(resources.diff === undefined ? {} : { diff: resources.diff }),
			...(resources.file === undefined ? {} : { file: resources.file }),
		},
	};
}

function firstTerminalFailureForPlans(props: {
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResourcesByRole: ReadonlyMap<
		BridgeContentRole,
		BridgeResourceExecutorResult<BridgeTextResourceStreamResult>
	>;
}): BridgeResourceExecutorResult<BridgeTextResourceStreamResult> | null {
	for (const plan of props.plans) {
		const result = props.loadedResourcesByRole.get(plan.role);
		if (result !== undefined && !result.ok && isTerminalDemandResourceFailure(result)) {
			return result;
		}
	}
	return null;
}

function loadResultForFailedResource(
	result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>,
): ReviewContentDemandLoadResult {
	if (result.ok) {
		return { status: 'ready', resources: {} };
	}
	switch (result.reason) {
		case 'aborted':
		case 'concurrency_exceeded':
		case 'stale_completion':
			return { status: 'deferred', reason: result.reason };
		case 'byte_budget_exceeded':
		case 'descriptor_missing':
		case 'load_failed':
			return { status: 'failed', reason: result.reason };
	}
	return { status: 'failed', reason: 'load_failed' };
}

function isTerminalDemandResourceFailure(
	result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>,
): boolean {
	return (
		!result.ok &&
		(result.reason === 'byte_budget_exceeded' ||
			result.reason === 'descriptor_missing' ||
			result.reason === 'load_failed')
	);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled review content demand result: ${JSON.stringify(value)}`);
}
