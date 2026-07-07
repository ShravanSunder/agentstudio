import {
	type BridgeCommWorkerPort,
	postPreparedBridgeCommWorkerMessage,
} from './bridge-comm-worker-entry.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	type BridgeWorkerContentFetch,
	type BridgeWorkerFetchedReviewContentResource,
	fetchBridgeWorkerReviewContentResource,
} from './bridge-worker-review-content-fetch.js';
import {
	commitBridgeWorkerReviewContentReadySlicePatch,
	prepareBridgeWorkerReviewContentRenderJobEvent,
} from './bridge-worker-review-content-ready.js';
import { prepareBridgeWorkerStructuredMessage } from './bridge-worker-transfer-list.js';

export interface DispatchSelectedBridgeWorkerReviewContentReadyProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly epoch: number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
	readonly itemId: string;
	readonly port: BridgeCommWorkerPort;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
}

export interface DispatchBridgeWorkerReviewContentReadyProps extends DispatchSelectedBridgeWorkerReviewContentReadyProps {
	readonly demandKey: string;
	readonly isDemandCurrent?: () => boolean;
}

export type BridgeWorkerReviewContentReadyFetchResult =
	| {
			readonly status: 'ready';
			readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
			readonly semantics: BridgeWorkerReviewRenderSemantics;
	  }
	| {
			readonly status: 'terminal';
			readonly reason: BridgeWorkerTerminalContentAvailabilityReason;
			readonly state: BridgeWorkerTerminalContentAvailabilityState;
	  }
	| {
			readonly status: 'stale';
	  };

export interface BridgeWorkerReviewContentResourceFetch {
	(
		descriptor: BridgeWorkerReviewContentRequestDescriptor,
	): Promise<BridgeWorkerFetchedReviewContentResource>;
}

export async function dispatchSelectedBridgeWorkerReviewContentReady(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps,
): Promise<void> {
	await dispatchBridgeWorkerReviewContentReady({
		...props,
		demandKey: selectedReviewContentReadyDemandKey(props),
	});
}

export async function dispatchBridgeWorkerReviewContentReady(
	props: DispatchBridgeWorkerReviewContentReadyProps,
): Promise<void> {
	const fetchResult = await fetchBridgeWorkerReviewContentReadyResources(props);
	publishBridgeWorkerReviewContentReadyFetchResult({ ...props, fetchResult });
}

export async function fetchSelectedBridgeWorkerReviewContentReadyResources(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps,
): Promise<BridgeWorkerReviewContentReadyFetchResult> {
	return fetchBridgeWorkerReviewContentReadyResources({
		...props,
		demandKey: selectedReviewContentReadyDemandKey(props),
	});
}

export async function fetchBridgeWorkerReviewContentReadyResources(
	props: DispatchBridgeWorkerReviewContentReadyProps,
): Promise<BridgeWorkerReviewContentReadyFetchResult> {
	if (!isReviewContentReadyDemandCurrent(props)) {
		return { status: 'stale' };
	}
	const semantics = props.renderSemantics.find((candidate) => candidate.itemId === props.itemId);
	if (semantics === undefined) {
		return { reason: 'descriptor_missing', status: 'terminal', state: 'unavailable' };
	}
	let resources: readonly BridgeWorkerFetchedReviewContentResource[];
	try {
		const fetchReviewContentResource =
			props.fetchReviewContentResource ?? createBridgeWorkerReviewContentResourceFetch(props);
		resources = await Promise.all(
			selectReviewContentRequestDescriptorsForSemantics({
				descriptors: props.contentRequestDescriptors,
				semantics,
			}).map(fetchReviewContentResource),
		);
	} catch {
		return { reason: 'load_failed', status: 'terminal', state: 'failed' };
	}
	if (!isReviewContentReadyDemandCurrent(props)) {
		return { status: 'stale' };
	}
	return { status: 'ready', resources, semantics };
}

export function publishSelectedBridgeWorkerReviewContentReadyFetchResult(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps & {
		readonly fetchResult: BridgeWorkerReviewContentReadyFetchResult;
	},
): void {
	publishBridgeWorkerReviewContentReadyFetchResult({
		...props,
		demandKey: selectedReviewContentReadyDemandKey(props),
	});
}

export function publishBridgeWorkerReviewContentReadyFetchResult(
	props: DispatchBridgeWorkerReviewContentReadyProps & {
		readonly fetchResult: BridgeWorkerReviewContentReadyFetchResult;
	},
): void {
	if (props.fetchResult.status === 'stale') {
		return;
	}
	if (props.fetchResult.status === 'terminal') {
		postReviewContentTerminalAvailability({
			...props,
			reason: props.fetchResult.reason,
			state: props.fetchResult.state,
		});
		return;
	}
	if (!isReviewContentReadyDemandCurrent(props)) {
		return;
	}
	const preparedJobEvent = prepareBridgeWorkerReviewContentRenderJobEvent({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		resources: props.fetchResult.resources,
		semantics: props.fetchResult.semantics,
	});
	if (preparedJobEvent === null) {
		postReviewContentTerminalAvailability({
			...props,
			reason: 'descriptor_rejected',
			state: 'unavailable',
		});
		return;
	}

	postPreparedBridgeCommWorkerMessage(props.port, preparedJobEvent);
	const contentReadyCommit = commitBridgeWorkerReviewContentReadySlicePatch({
		epoch: props.epoch,
		preparedJobEvent,
		sequence: props.sequence,
		store: props.store,
	});
	postPreparedBridgeCommWorkerMessage(props.port, contentReadyCommit.preparedMessage);
}

type BridgeWorkerTerminalContentAvailabilityState = Extract<
	BridgeWorkerContentAvailabilityPatchPayload['state'],
	'failed' | 'unavailable'
>;
type BridgeWorkerTerminalContentAvailabilityReason = NonNullable<
	BridgeWorkerContentAvailabilityPatchPayload['reason']
>;

type BridgeWorkerReviewContentRole = BridgeWorkerReviewContentRequestDescriptor['role'];
type BridgeWorkerReviewContentRoleGroup = readonly BridgeWorkerReviewContentRole[];

function postReviewContentTerminalAvailability(
	props: DispatchBridgeWorkerReviewContentReadyProps & {
		readonly reason: BridgeWorkerTerminalContentAvailabilityReason;
		readonly state: BridgeWorkerTerminalContentAvailabilityState;
	},
): void {
	if (!isReviewContentReadyDemandCurrent(props)) {
		return;
	}
	props.store.actions.applyContentTerminalAvailability({
		itemId: props.itemId,
		reason: props.reason,
		sourceEpoch: props.epoch,
		state: props.state,
	});
	const slicePatchEvent = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.epoch,
		sequence: props.sequence,
	});
	postPreparedBridgeCommWorkerMessage(
		props.port,
		prepareBridgeWorkerStructuredMessage({
			message: assertBridgeWorkerSlicePatchEvent(slicePatchEvent),
			declaredFields: [],
		}),
	);
}

export function isSelectedReviewContentReadyPreparationCurrent(
	props: Pick<DispatchSelectedBridgeWorkerReviewContentReadyProps, 'epoch' | 'itemId' | 'store'>,
): boolean {
	return isReviewContentReadyDemandCurrent({
		...props,
		demandKey: selectedReviewContentReadyDemandKey(props),
	});
}

export function isReviewContentReadyDemandCurrent(
	props: Pick<
		DispatchBridgeWorkerReviewContentReadyProps,
		'demandKey' | 'isDemandCurrent' | 'itemId' | 'store'
	>,
): boolean {
	const state = props.store.getState();
	return (
		state.demandByKey.get(props.itemId) === props.demandKey && (props.isDemandCurrent?.() ?? true)
	);
}

export function canRenderBridgeWorkerReviewContentForSemantics(props: {
	readonly descriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): boolean {
	return selectReviewContentRequestDescriptorsForSemantics(props).length > 0;
}

function selectedReviewContentReadyDemandKey(
	props: Pick<DispatchSelectedBridgeWorkerReviewContentReadyProps, 'epoch'>,
): string {
	return `selected:${props.epoch}`;
}

function createBridgeWorkerReviewContentResourceFetch(
	props: Pick<DispatchBridgeWorkerReviewContentReadyProps, 'fetchContent'>,
): BridgeWorkerReviewContentResourceFetch {
	return (descriptor: BridgeWorkerReviewContentRequestDescriptor) =>
		fetchBridgeWorkerReviewContentResource({
			descriptor,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		});
}

function assertBridgeWorkerSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): BridgeWorkerServerToMainMessage {
	if (event === null) {
		throw new Error('Bridge worker terminal content availability produced no slice patch event.');
	}
	return event;
}

function selectReviewContentRequestDescriptorsForSemantics(props: {
	readonly descriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	const descriptorsByRole = new Map(
		props.descriptors
			.filter((descriptor) => descriptor.itemId === props.semantics.itemId)
			.map((descriptor) => [descriptor.role, descriptor] as const),
	);
	if (requiresTwoSidedDiffDescriptors(props.semantics)) {
		const baseDescriptor = descriptorsByRole.get('base') ?? null;
		const headDescriptor = descriptorsByRole.get('head') ?? null;
		return baseDescriptor === null || headDescriptor === null
			? []
			: [baseDescriptor, headDescriptor];
	}
	return contentRoleGroupsForSemantics(props.semantics).flatMap((roleGroup) => {
		const descriptor = firstDescriptorForRoleGroup(descriptorsByRole, roleGroup);
		return descriptor === null ? [] : [descriptor];
	});
}

function requiresTwoSidedDiffDescriptors(semantics: BridgeWorkerReviewRenderSemantics): boolean {
	switch (semantics.changeKind) {
		case 'modified':
		case 'renamed':
		case 'copied':
			return semantics.itemKind === 'diff';
		case 'added':
		case 'deleted':
			return false;
	}
	const exhaustiveChangeKind: never = semantics.changeKind;
	void exhaustiveChangeKind;
	throw new Error('Unhandled Bridge worker review change kind.');
}

function firstDescriptorForRoleGroup(
	descriptorsByRole: ReadonlyMap<
		BridgeWorkerReviewContentRole,
		BridgeWorkerReviewContentRequestDescriptor
	>,
	roleGroup: BridgeWorkerReviewContentRoleGroup,
): BridgeWorkerReviewContentRequestDescriptor | null {
	for (const role of roleGroup) {
		const descriptor = descriptorsByRole.get(role);
		if (descriptor !== undefined) {
			return descriptor;
		}
	}
	return null;
}

function contentRoleGroupsForSemantics(
	semantics: BridgeWorkerReviewRenderSemantics,
): readonly BridgeWorkerReviewContentRoleGroup[] {
	switch (semantics.changeKind) {
		case 'added':
			return [['head', 'file']];
		case 'deleted':
			return [['base', 'diff']];
		case 'modified':
		case 'renamed':
		case 'copied':
			return semantics.itemKind === 'diff'
				? [['base'], ['head']]
				: [['head', 'file', 'diff', 'base']];
	}
	const exhaustiveChangeKind: never = semantics.changeKind;
	void exhaustiveChangeKind;
	throw new Error('Unhandled Bridge worker review change kind.');
}
