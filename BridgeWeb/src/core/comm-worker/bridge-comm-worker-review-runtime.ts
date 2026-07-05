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
	readonly itemId: string;
	readonly port: BridgeCommWorkerPort;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
}

export async function dispatchSelectedBridgeWorkerReviewContentReady(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps,
): Promise<void> {
	if (!isSelectedReviewContentReadyPreparationCurrent(props)) {
		return;
	}
	const semantics = props.renderSemantics.find((candidate) => candidate.itemId === props.itemId);
	if (semantics === undefined) {
		postSelectedReviewContentTerminalAvailability({ ...props, state: 'unavailable' });
		return;
	}
	let resources: readonly BridgeWorkerFetchedReviewContentResource[];
	try {
		resources = await Promise.all(
			selectReviewContentRequestDescriptorsForSemantics({
				descriptors: props.contentRequestDescriptors,
				semantics,
			}).map((descriptor) =>
				fetchBridgeWorkerReviewContentResource({
					descriptor,
					...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				}),
			),
		);
	} catch {
		postSelectedReviewContentTerminalAvailability({ ...props, state: 'failed' });
		return;
	}
	if (!isSelectedReviewContentReadyPreparationCurrent(props)) {
		return;
	}
	const preparedJobEvent = prepareBridgeWorkerReviewContentRenderJobEvent({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		resources,
		semantics,
	});
	if (preparedJobEvent === null) {
		postSelectedReviewContentTerminalAvailability({ ...props, state: 'unavailable' });
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

type BridgeWorkerReviewContentRole = BridgeWorkerReviewContentRequestDescriptor['role'];
type BridgeWorkerReviewContentRoleGroup = readonly BridgeWorkerReviewContentRole[];

function postSelectedReviewContentTerminalAvailability(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps & {
		readonly state: BridgeWorkerTerminalContentAvailabilityState;
	},
): void {
	if (!isSelectedReviewContentReadyPreparationCurrent(props)) {
		return;
	}
	props.store.actions.applyContentTerminalAvailability({
		itemId: props.itemId,
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
	const state = props.store.getState();
	return (
		state.selectedId === props.itemId &&
		state.demandByKey.get(props.itemId) === `selected:${props.epoch}`
	);
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
