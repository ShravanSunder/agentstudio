import type { BridgeResourceExecutorResult } from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
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
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewItemPresentation } from '../code-view/bridge-code-view-materialization.js';
import type {
	ReviewContentDemandInterest,
	ReviewContentDemandLoadResult,
	ReviewContentDemandPlan,
} from './review-content-demand-types.js';

export function demandPlansForReviewItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly interest: ReviewContentDemandInterest;
	readonly presentation: BridgeCodeViewItemPresentation | null;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
}): readonly ReviewContentDemandPlan[] | null {
	const roleHandles = roleHandlesForReviewItem({
		item: props.item,
		presentation: props.presentation,
	});
	const plans: ReviewContentDemandPlan[] = [];
	let missingDescriptorRefCount = 0;
	for (const roleHandle of roleHandles) {
		const descriptorRef = props.resolveDescriptorRef(roleHandle.handle);
		if (descriptorRef === null) {
			missingDescriptorRefCount += 1;
			continue;
		}
		plans.push({
			handle: roleHandle.handle,
			role: roleHandle.role,
			descriptorRef,
		});
	}
	if (plans.length === 0) {
		return null;
	}
	if (
		missingDescriptorRefCount > 0 &&
		!allowsPartialModifiedContentPlans({
			interest: props.interest,
			plannedRoles: plans.map((plan): BridgeContentRole => plan.role),
			requestedRoles: roleHandles.map((roleHandle): BridgeContentRole => roleHandle.role),
		})
	) {
		return null;
	}
	return plans;
}

export function intentsForReviewContentDemandPlans(props: {
	readonly interest: ReviewContentDemandInterest;
	readonly plans: readonly ReviewContentDemandPlan[];
}): readonly BridgeDemandIntent[] {
	return props.plans.flatMap((plan: ReviewContentDemandPlan): readonly BridgeDemandIntent[] =>
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
}

export function demandKeysForPlan(
	plan: ReviewContentDemandPlan,
	interest: ReviewContentDemandInterest,
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
		dedupeKey: demandKey,
		freshnessKey: descriptorIdentityKey,
		cancellationGroup: demandCancellationGroupForReviewDescriptorRefAndInterest({
			descriptorRef: plan.descriptorRef,
			interest,
		}),
	};
}

export function estimatedBytesForDemandIntent(props: {
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
): string {
	return demandCancellationGroupForReviewDescriptorRefAndInterest({
		descriptorRef,
		interest: 'selected',
	});
}

export function demandCancellationGroupsForReviewDescriptorRef(
	descriptorRef: BridgeDescriptorRef,
): readonly string[] {
	return reviewContentDemandInterests.map((interest): string =>
		demandCancellationGroupForReviewDescriptorRefAndInterest({
			descriptorRef,
			interest,
		}),
	);
}

export function resultForPlans(props: {
	readonly allowsPartialRoleResults: boolean;
	readonly plans: readonly ReviewContentDemandPlan[];
	readonly loadedResourcesByRole: ReadonlyMap<
		BridgeContentRole,
		BridgeResourceExecutorResult<BridgeTextResourceStreamResult>
	>;
}): ReviewContentDemandLoadResult {
	if (!props.allowsPartialRoleResults) {
		const terminalFailure = firstTerminalFailureForPlans(props);
		if (terminalFailure !== null) {
			return loadResultForFailedResource(terminalFailure);
		}
	}
	const resources: Record<BridgeContentRole, BridgeContentResource | undefined> = {
		base: undefined,
		head: undefined,
		diff: undefined,
		file: undefined,
	};
	let failedResult: BridgeResourceExecutorResult<BridgeTextResourceStreamResult> | null = null;
	let deferredResult: BridgeResourceExecutorResult<BridgeTextResourceStreamResult> | null = null;
	for (const plan of props.plans) {
		const result = props.loadedResourcesByRole.get(plan.role);
		if (result?.ok !== true) {
			const failedResourceResult = result ?? { ok: false, reason: 'descriptor_missing' };
			if (!props.allowsPartialRoleResults) {
				return loadResultForFailedResource(failedResourceResult);
			}
			if (isTerminalDemandResourceFailure(failedResourceResult)) {
				failedResult ??= failedResourceResult;
			} else {
				deferredResult ??= failedResourceResult;
			}
			continue;
		}
		if (!result.authoritative) {
			if (!props.allowsPartialRoleResults) {
				return { status: 'deferred', reason: 'stale_completion' };
			}
			deferredResult ??= { ok: false, reason: 'stale_completion' };
			continue;
		}
		resources[plan.role] = {
			authoritative: result.authoritative,
			byteLength: result.byteLength,
			handle: plan.handle,
			readText: (): string => result.content.readText(),
		};
	}
	if (
		resources.base === undefined &&
		resources.head === undefined &&
		resources.diff === undefined &&
		resources.file === undefined
	) {
		return loadResultForFailedResource(
			failedResult ?? deferredResult ?? { ok: false, reason: 'descriptor_missing' },
		);
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

export function allowsPartialReviewContentDemandResult(props: {
	readonly interest: ReviewContentDemandInterest;
	readonly plans: readonly ReviewContentDemandPlan[];
}): boolean {
	if (props.plans.length !== 2) {
		return false;
	}
	const roles = new Set(props.plans.map((plan): BridgeContentRole => plan.role));
	return roles.has('base') && roles.has('head');
}

export function loadResultForFailedResource(
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

export function isTerminalDemandResourceFailure(
	result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>,
): boolean {
	return (
		!result.ok &&
		(result.reason === 'byte_budget_exceeded' ||
			result.reason === 'descriptor_missing' ||
			result.reason === 'load_failed')
	);
}

export function assertNever(value: never): never {
	throw new Error(`Unhandled review content demand result: ${JSON.stringify(value)}`);
}

function allowsPartialModifiedContentPlans(props: {
	readonly interest: ReviewContentDemandInterest;
	readonly plannedRoles: readonly BridgeContentRole[];
	readonly requestedRoles: readonly BridgeContentRole[];
}): boolean {
	const requestedRoles = new Set(props.requestedRoles);
	if (requestedRoles.size !== 2 || !requestedRoles.has('base') || !requestedRoles.has('head')) {
		return false;
	}
	return props.plannedRoles.every(
		(plannedRole): boolean => plannedRole === 'base' || plannedRole === 'head',
	);
}

function roleHandlesForReviewItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation: BridgeCodeViewItemPresentation | null;
}): readonly { readonly role: BridgeContentRole; readonly handle: BridgeContentHandle }[] {
	if (props.presentation?.kind === 'file') {
		const presentationHandle = preferredContentHandleForFilePresentation({
			item: props.item,
			version: props.presentation.version,
		});
		return presentationHandle === null ? [] : [presentationHandle];
	}
	const baseHandle = props.item.contentRoles.base ?? null;
	const headHandle = props.item.contentRoles.head ?? null;
	if (props.item.itemKind === 'diff' && baseHandle !== null && headHandle !== null) {
		return [
			{ role: 'base', handle: baseHandle },
			{ role: 'head', handle: headHandle },
		];
	}
	const diffHandle = props.item.contentRoles.diff ?? null;
	if (props.item.itemKind === 'diff' && diffHandle !== null) {
		return [{ role: 'diff', handle: diffHandle }];
	}
	const preferredHandle = preferredContentHandle(props.item);
	return preferredHandle === null ? [] : [preferredHandle];
}

function preferredContentHandleForFilePresentation(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly version: 'base' | 'current' | 'head';
}): { readonly role: BridgeContentRole; readonly handle: BridgeContentHandle } | null {
	switch (props.version) {
		case 'base': {
			const baseHandle = props.item.contentRoles.base ?? null;
			return baseHandle === null ? null : { role: 'base', handle: baseHandle };
		}
		case 'head': {
			const headHandle = props.item.contentRoles.head ?? null;
			if (headHandle !== null) {
				return { role: 'head', handle: headHandle };
			}
			const fileHandle = props.item.contentRoles.file ?? null;
			return fileHandle === null ? null : { role: 'file', handle: fileHandle };
		}
		case 'current':
			return preferredContentHandle(props.item);
	}
	return assertNever(props.version);
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
	interest: ReviewContentDemandInterest,
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
	if (interest === 'background') {
		return { kind: 'reviewDescriptorInvalidated', descriptorRef: plan.descriptorRef };
	}
	return { kind: 'reviewDescriptorInvalidated', descriptorRef: plan.descriptorRef };
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

const reviewContentDemandInterests: readonly ReviewContentDemandInterest[] = [
	'selected',
	'visible',
	'nearby',
	'speculative',
	'background',
];

function demandCancellationGroupForReviewDescriptorRefAndInterest(props: {
	readonly descriptorRef: BridgeDescriptorRef;
	readonly interest: ReviewContentDemandInterest;
}): string {
	return `${demandFreshnessKeyForReviewDescriptorRef(props.descriptorRef)}:${props.interest}`;
}
