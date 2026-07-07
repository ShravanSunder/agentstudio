import {
	type BridgeCommWorkerPort,
	postPreparedBridgeCommWorkerMessage,
} from './bridge-comm-worker-entry.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerContentMetadata,
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import {
	type BridgeWorkerFetchedFileViewContentResource,
	fetchBridgeWorkerFileViewContentResource,
} from './bridge-worker-file-view-content-fetch.js';
import {
	commitBridgeWorkerFileViewContentReadySlicePatch,
	prepareBridgeWorkerFileViewContentRenderJobEvent,
} from './bridge-worker-file-view-content-ready.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerContentFetch } from './bridge-worker-review-content-fetch.js';
import { prepareBridgeWorkerStructuredMessage } from './bridge-worker-transfer-list.js';

export interface DispatchSelectedBridgeWorkerFileViewContentReadyProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly epoch: number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly itemId: string;
	readonly port: BridgeCommWorkerPort;
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
}

export type BridgeWorkerFileViewContentReadyFetchResult =
	| {
			readonly status: 'ready';
			readonly metadata: BridgeWorkerFileViewContentMetadata;
			readonly resource: BridgeWorkerFetchedFileViewContentResource;
	  }
	| {
			readonly status: 'terminal';
			readonly reason: BridgeWorkerTerminalContentAvailabilityReason;
			readonly state: BridgeWorkerTerminalContentAvailabilityState;
	  }
	| {
			readonly status: 'stale';
	  };

type BridgeWorkerTerminalContentAvailabilityState = Extract<
	BridgeWorkerContentAvailabilityPatchPayload['state'],
	'failed' | 'unavailable'
>;
type BridgeWorkerTerminalContentAvailabilityReason = NonNullable<
	BridgeWorkerContentAvailabilityPatchPayload['reason']
>;

export async function dispatchSelectedBridgeWorkerFileViewContentReady(
	props: DispatchSelectedBridgeWorkerFileViewContentReadyProps,
): Promise<void> {
	const fetchResult = await fetchSelectedBridgeWorkerFileViewContentReadyResource(props);
	publishSelectedBridgeWorkerFileViewContentReadyFetchResult({ ...props, fetchResult });
}

export async function fetchSelectedBridgeWorkerFileViewContentReadyResource(
	props: DispatchSelectedBridgeWorkerFileViewContentReadyProps,
): Promise<BridgeWorkerFileViewContentReadyFetchResult> {
	if (!isSelectedFileViewContentReadyPreparationCurrent(props)) {
		return { status: 'stale' };
	}
	const metadata = selectedFileViewContentMetadata(props);
	if (metadata === null) {
		return { reason: 'content_unavailable', status: 'terminal', state: 'unavailable' };
	}
	const descriptor =
		props.contentRequestDescriptors.find((candidate) => candidate.itemId === props.itemId) ?? null;
	if (descriptor === null) {
		return { reason: 'descriptor_missing', status: 'terminal', state: 'unavailable' };
	}
	let resource: BridgeWorkerFetchedFileViewContentResource;
	try {
		resource = await fetchBridgeWorkerFileViewContentResource({
			descriptor,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		});
	} catch {
		return { reason: 'load_failed', status: 'terminal', state: 'failed' };
	}
	if (!isSelectedFileViewContentReadyPreparationCurrent(props)) {
		return { status: 'stale' };
	}
	return { status: 'ready', metadata, resource };
}

export function publishSelectedBridgeWorkerFileViewContentReadyFetchResult(
	props: DispatchSelectedBridgeWorkerFileViewContentReadyProps & {
		readonly fetchResult: BridgeWorkerFileViewContentReadyFetchResult;
	},
): void {
	if (props.fetchResult.status === 'stale') {
		return;
	}
	if (props.fetchResult.status === 'terminal') {
		postSelectedFileViewContentTerminalAvailability({
			...props,
			reason: props.fetchResult.reason,
			state: props.fetchResult.state,
		});
		return;
	}
	if (!isSelectedFileViewContentReadyPreparationCurrent(props)) {
		return;
	}
	const preparedJobEvent = prepareBridgeWorkerFileViewContentRenderJobEvent({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		metadata: props.fetchResult.metadata,
		resource: props.fetchResult.resource,
	});
	if (preparedJobEvent === null) {
		postSelectedFileViewContentTerminalAvailability({
			...props,
			reason: 'descriptor_rejected',
			state: 'unavailable',
		});
		return;
	}

	postPreparedBridgeCommWorkerMessage(props.port, preparedJobEvent);
	const contentReadyCommit = commitBridgeWorkerFileViewContentReadySlicePatch({
		epoch: props.epoch,
		preparedJobEvent,
		sequence: props.sequence,
		store: props.store,
	});
	postPreparedBridgeCommWorkerMessage(props.port, contentReadyCommit.preparedMessage);
}

export function isSelectedFileViewContentReadyPreparationCurrent(
	props: Pick<DispatchSelectedBridgeWorkerFileViewContentReadyProps, 'epoch' | 'itemId' | 'store'>,
): boolean {
	const state = props.store.getState();
	return (
		state.selectedId === props.itemId &&
		state.demandByKey.get(props.itemId) === `selected:${props.epoch}`
	);
}

function postSelectedFileViewContentTerminalAvailability(
	props: DispatchSelectedBridgeWorkerFileViewContentReadyProps & {
		readonly reason: BridgeWorkerTerminalContentAvailabilityReason;
		readonly state: BridgeWorkerTerminalContentAvailabilityState;
	},
): void {
	if (!isSelectedFileViewContentReadyPreparationCurrent(props)) {
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

function selectedFileViewContentMetadata(
	props: Pick<DispatchSelectedBridgeWorkerFileViewContentReadyProps, 'itemId' | 'store'>,
): BridgeWorkerFileViewContentMetadata | null {
	const metadata = props.store.getState().contentMetadataByItemId.get(props.itemId) ?? null;
	return isBridgeWorkerFileViewContentMetadata(metadata) ? metadata : null;
}

function isBridgeWorkerFileViewContentMetadata(
	metadata: BridgeWorkerContentMetadata | null,
): metadata is BridgeWorkerFileViewContentMetadata {
	return metadata !== null && 'contentHandle' in metadata;
}

function assertBridgeWorkerSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): BridgeWorkerServerToMainMessage {
	if (event === null) {
		throw new Error('Bridge worker File View terminal availability produced no slice patch event.');
	}
	return event;
}
