import type { BridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import type {
	BridgeResourceExecutor,
	BridgeResourceExecutorResult,
} from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
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
	readonly executor: BridgeResourceExecutor<string>;
	readonly signal?: AbortSignal;
	readonly traceContext?: BridgeTraceContext | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
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

interface ReviewContentDemandPlan {
	readonly handle: BridgeContentHandle;
	readonly role: BridgeContentRole;
	readonly descriptorRef: BridgeDescriptorRef;
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
	for (const intent of intents) {
		const enqueueResult = props.scheduler.enqueue({
			intent,
			estimatedBytes: 0,
		});
		if (!enqueueResult.ok) {
			for (const acceptedIntent of intents.slice(0, intents.indexOf(intent))) {
				props.scheduler.cancelGroup(acceptedIntent.cancellationGroup);
			}
			return { status: 'deferred', reason: 'concurrency_exceeded' };
		}
	}
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
		const loadedResults = executableIntents.map(async (executableIntent) => ({
			role: executableIntent.plan.role,
			result: await loadDemandResourceWithTelemetry({
				intent: executableIntent.intent,
				role: executableIntent.plan.role,
				interest: props.interest,
				executor: props.executor,
				signal: demandAbortController.signal,
				traceContext: props.traceContext ?? null,
				telemetryRecorder: props.telemetryRecorder,
			}),
		}));
		return await Promise.race([
			loadAllDemandResources({ plans, loadedResults, signal: demandAbortController.signal }),
			failFastOnFirstDemandResourceFailure({
				loadedResults,
				abortSiblingLoads: abortDemandLoads,
			}),
		]);
	} finally {
		props.signal?.removeEventListener('abort', abortDemandLoads);
	}
}

interface LoadedReviewContentDemandResult {
	readonly role: BridgeContentRole;
	readonly result: BridgeResourceExecutorResult<string>;
}

async function loadAllDemandResources(props: {
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResults: readonly Promise<LoadedReviewContentDemandResult>[];
	readonly signal: AbortSignal | undefined;
}): Promise<ReviewContentDemandLoadResult> {
	const loadedResourcesByRole = new Map<BridgeContentRole, BridgeResourceExecutorResult<string>>();
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
	readonly executor: BridgeResourceExecutor<string>;
	readonly signal: AbortSignal | undefined;
	readonly traceContext: BridgeTraceContext | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
}): Promise<BridgeResourceExecutorResult<string>> {
	const start = performance.now();
	let loadResult: BridgeResourceExecutorResult<string> | null = null;
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

function telemetryResultForExecutorResult(result: BridgeResourceExecutorResult<string> | null): {
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
		BridgeResourceExecutorResult<string>
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
		resources[plan.role] = {
			handle: plan.handle,
			text: result.body,
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
		BridgeResourceExecutorResult<string>
	>;
}): BridgeResourceExecutorResult<string> | null {
	for (const plan of props.plans) {
		const result = props.loadedResourcesByRole.get(plan.role);
		if (result !== undefined && !result.ok && isTerminalDemandResourceFailure(result)) {
			return result;
		}
	}
	return null;
}

function loadResultForFailedResource(
	result: BridgeResourceExecutorResult<string>,
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

function isTerminalDemandResourceFailure(result: BridgeResourceExecutorResult<string>): boolean {
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
