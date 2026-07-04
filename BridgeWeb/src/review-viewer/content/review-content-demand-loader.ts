import type { BridgeResourceExecutorResult } from '../../core/demand/bridge-resource-executor.js';
import type { BridgeDemandIntent } from '../../core/models/bridge-demand-models.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type { BridgeContentRole } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import {
	recordBridgeReviewContentDemandTelemetry,
	recordBridgeViewerContentFetchTelemetry,
} from '../telemetry/bridge-review-viewer-telemetry.js';
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
import type { BridgeReviewContentRegistry } from './review-content-registry.js';

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
	const planPartition =
		props.contentRegistry === undefined
			? null
			: partitionDemandPlansByCache({
					contentRegistry: props.contentRegistry,
					plans,
				});
	const demandPlans = planPartition?.missingPlans ?? plans;
	// A full registry hit is a pure cache read: no executor traffic and no
	// executor traffic, and no demand telemetry sample because nothing was
	// demanded from the transport.
	if (demandPlans.length === 0) {
		return {
			status: 'ready',
			resources: planPartition?.cachedResources ?? {},
		};
	}
	const allowsPartialRoleResults = allowsPartialReviewContentDemandResult({
		interest: props.interest,
		plans,
	});
	const demandAbortController = new AbortController();
	const abortDemandLoads = (): void => {
		demandAbortController.abort();
	};
	props.signal?.addEventListener('abort', abortDemandLoads, { once: true });
	const intents = intentsForReviewContentDemandPlans({
		interest: props.interest,
		plans: demandPlans,
	});
	const telemetryBuilder = newReviewContentDemandTelemetryBuilder({
		itemId: props.itemId,
		packageId: props.reviewPackage.packageId,
		reviewGeneration: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		interest: props.interest,
		intents,
		executor: props.executor,
	});
	const executableIntents = intents.map((intent) => {
		const matchingPlan = demandPlans.find(
			(plan: ReviewContentDemandPlan): boolean =>
				plan.descriptorRef.descriptorId === intent.descriptorRef.descriptorId,
		);
		if (matchingPlan === undefined) {
			throw new Error(`Missing demand plan for descriptor ${intent.descriptorRef.descriptorId}`);
		}
		return { intent, plan: matchingPlan };
	});
	try {
		const settledLoadedResults: LoadedReviewContentDemandSettledResult[] = [];
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
						plans: demandPlans,
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
					plans: demandPlans,
					loadedResults,
					signal: demandAbortController.signal,
				})
			: await Promise.race([
					loadAllDemandResources({
						allowsPartialRoleResults,
						plans: demandPlans,
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
		const mergedResult = resultWithCachedResources({
			allowsPartialRoleResults,
			cachedResources: planPartition?.cachedResources ?? {},
			result,
		});
		if (mergedResult.status === 'ready' && props.contentRegistry !== undefined) {
			storeContentResourcesInRegistry({
				contentRegistry: props.contentRegistry,
				resources: mergedResult.resources,
			});
		}
		telemetryBuilder.recordCompletion({
			result: mergedResult,
			loadedResults: settledLoadedResults,
		});
		const demandTelemetry = telemetryBuilder.build();
		props.onDemandTelemetry?.(demandTelemetry);
		if (props.telemetryRecorder !== undefined) {
			recordBridgeReviewContentDemandTelemetry({
				telemetryRecorder: props.telemetryRecorder,
				traceContext: props.traceContext ?? null,
				telemetry: demandTelemetry,
			});
		}
		return mergedResult;
	} finally {
		props.signal?.removeEventListener('abort', abortDemandLoads);
	}
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

function partitionDemandPlansByCache(props: {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly plans: readonly ReviewContentDemandPlan[];
}): {
	readonly cachedResources: BridgeCodeViewContentResources;
	readonly missingPlans: readonly ReviewContentDemandPlan[];
} {
	const resources: { -readonly [Role in BridgeContentRole]?: BridgeContentResource } = {};
	const missingPlans: ReviewContentDemandPlan[] = [];
	for (const plan of props.plans) {
		const cachedResource = props.contentRegistry.peekResource(plan.handle);
		if (cachedResource === null) {
			missingPlans.push(plan);
			continue;
		}
		resources[plan.role] = cachedResource;
	}
	return {
		cachedResources: resources,
		missingPlans,
	};
}

function resultWithCachedResources(props: {
	readonly allowsPartialRoleResults: boolean;
	readonly cachedResources: BridgeCodeViewContentResources;
	readonly result: ReviewContentDemandLoadResult;
}): ReviewContentDemandLoadResult {
	if (props.result.status === 'ready') {
		return {
			status: 'ready',
			resources: {
				...props.cachedResources,
				...props.result.resources,
			},
		};
	}
	if (props.allowsPartialRoleResults && contentResourcesHaveAnyRole(props.cachedResources)) {
		return {
			status: 'ready',
			resources: props.cachedResources,
		};
	}
	return props.result;
}

function contentResourcesHaveAnyRole(resources: BridgeCodeViewContentResources): boolean {
	return (
		resources.base !== undefined ||
		resources.head !== undefined ||
		resources.diff !== undefined ||
		resources.file !== undefined
	);
}

function storeContentResourcesInRegistry(props: {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly resources: BridgeCodeViewContentResources;
}): void {
	const roleResources = [
		props.resources.base,
		props.resources.head,
		props.resources.diff,
		props.resources.file,
	];
	for (const resource of roleResources) {
		if (resource !== undefined) {
			props.contentRegistry.storeResource({ resource });
		}
	}
}
