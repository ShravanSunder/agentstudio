import type { BridgeResourceExecutorResult } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeDemandIntent } from '../../core/models/bridge-demand-models.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import type { BridgeContentRole } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { recordBridgeViewerContentFetchTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	allowsPartialReviewContentDemandResult,
	assertNever,
	demandCancellationGroupForReviewDescriptorRef,
	demandCancellationGroupsForReviewDescriptorRef,
	demandFreshnessKeyForReviewDescriptorRef,
	demandPlansForReviewItem,
	estimatedBytesForDemandIntent,
	intentsForReviewContentDemandPlans,
	isTerminalDemandResourceFailure,
	loadResultForFailedResource,
	resultForPlans,
} from './review-content-demand-policy.js';
import { newReviewContentDemandTelemetryBuilder } from './review-content-demand-telemetry.js';
import type {
	LoadReviewItemContentResourcesThroughDemandProps,
	LoadedReviewContentDemandResult,
	LoadedReviewContentDemandSettledResult,
	ReviewContentDemandLoadResult,
	ReviewContentDemandPlan,
} from './review-content-demand-types.js';

export type {
	LoadReviewItemContentResourcesThroughDemandProps,
	ReviewContentDemandInterest,
	ReviewContentDemandLoadResult,
	ReviewContentDemandTelemetry,
} from './review-content-demand-types.js';

export {
	demandCancellationGroupForReviewDescriptorRef,
	demandCancellationGroupsForReviewDescriptorRef,
	demandFreshnessKeyForReviewDescriptorRef,
};

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
		interest: props.interest,
		presentation: props.presentation ?? null,
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
	const intents = intentsForReviewContentDemandPlans({
		interest: props.interest,
		plans,
	});
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
	const executableIntents = dequeueDemandPlansForExecution({
		plans,
		dequeueNextMatching: props.scheduler.dequeueNextMatching.bind(props.scheduler),
	});
	try {
		const settledLoadedResults: LoadedReviewContentDemandSettledResult[] = [];
		const allowsPartialRoleResults = allowsPartialReviewContentDemandResult({
			interest: props.interest,
			plans,
		});
		const loadedResults = executableIntents.map(async (executableIntent) => {
			try {
				const resourceResult = await loadDemandResourceWithTelemetry({
					intent: executableIntent.intent,
					role: executableIntent.plan.role,
					interest: props.interest,
					executor: props.executor,
					signal: demandAbortController.signal,
					traceContext: props.traceContext ?? null,
					telemetryRecorder: props.telemetryRecorder,
				});
				if (!allowsPartialRoleResults && isTerminalDemandResourceFailure(resourceResult)) {
					abortDemandLoads();
				}
				const loadedResult = {
					role: executableIntent.plan.role,
					intent: executableIntent.intent,
					estimatedBytes: estimatedBytesForDemandIntent({
						intent: executableIntent.intent,
						interest: props.interest,
						plans,
					}),
					result: resourceResult,
				};
				settledLoadedResults.push({ status: 'fulfilled', value: loadedResult });
				return loadedResult;
			} catch (error: unknown) {
				settledLoadedResults.push({ status: 'rejected' });
				throw error;
			}
		});
		telemetryBuilder.recordAfterDispatch();
		const result = allowsPartialRoleResults
			? await loadAllDemandResources({
					allowsPartialRoleResults,
					plans,
					loadedResults,
					signal: demandAbortController.signal,
				})
			: await Promise.race([
					loadAllDemandResources({
						allowsPartialRoleResults,
						plans,
						loadedResults,
						signal: demandAbortController.signal,
					}),
					failFastOnFirstDemandResourceFailure({
						loadedResults,
						abortSiblingLoads: abortDemandLoads,
					}),
				]);
		if (!allowsPartialRoleResults && result.status === 'failed') {
			abortDemandLoads();
		}
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

function dequeueDemandPlansForExecution(props: {
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly dequeueNextMatching: (
		predicate: (intent: BridgeDemandIntent) => boolean,
	) => BridgeDemandIntent | null;
}): {
	readonly intent: BridgeDemandIntent;
	readonly plan: ReviewContentDemandPlan;
}[] {
	const executableIntents: {
		readonly intent: BridgeDemandIntent;
		readonly plan: ReviewContentDemandPlan;
	}[] = [];
	let nextIntent = props.dequeueNextMatching((intent): boolean =>
		props.plans.some(
			(plan: ReviewContentDemandPlan): boolean =>
				plan.descriptorRef.descriptorId === intent.descriptorRef.descriptorId,
		),
	);
	while (nextIntent !== null) {
		const matchingPlan = props.plans.find(
			(plan: ReviewContentDemandPlan): boolean =>
				plan.descriptorRef.descriptorId === nextIntent?.descriptorRef.descriptorId,
		);
		if (matchingPlan !== undefined) {
			executableIntents.push({ intent: nextIntent, plan: matchingPlan });
		}
		nextIntent = props.dequeueNextMatching((intent): boolean =>
			props.plans.some(
				(plan: ReviewContentDemandPlan): boolean =>
					plan.descriptorRef.descriptorId === intent.descriptorRef.descriptorId,
			),
		);
	}
	return executableIntents;
}

async function loadAllDemandResources(props: {
	readonly allowsPartialRoleResults: boolean;
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResults: readonly Promise<LoadedReviewContentDemandResult>[];
	readonly signal: AbortSignal | undefined;
}): Promise<ReviewContentDemandLoadResult> {
	const loadedResourcesByRole = new Map<
		BridgeContentRole,
		BridgeResourceExecutorResult<BridgeTextResourceStreamResult>
	>();
	const loadedResults = await Promise.all(props.loadedResults);
	for (const loadedResult of loadedResults) {
		loadedResourcesByRole.set(loadedResult.role, loadedResult.result);
	}
	const result = resultForPlans({
		allowsPartialRoleResults: props.allowsPartialRoleResults,
		plans: props.plans,
		loadedResourcesByRole,
	});
	if (result.status === 'failed') {
		return result;
	}
	if (props.signal?.aborted === true) {
		return { status: 'deferred', reason: 'aborted' };
	}
	return result;
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
	readonly interest: LoadReviewItemContentResourcesThroughDemandProps['interest'];
	readonly executor: LoadReviewItemContentResourcesThroughDemandProps['executor'];
	readonly signal: AbortSignal | undefined;
	readonly traceContext: LoadReviewItemContentResourcesThroughDemandProps['traceContext'];
	readonly telemetryRecorder: LoadReviewItemContentResourcesThroughDemandProps['telemetryRecorder'];
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
				traceContext: props.traceContext ?? null,
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
