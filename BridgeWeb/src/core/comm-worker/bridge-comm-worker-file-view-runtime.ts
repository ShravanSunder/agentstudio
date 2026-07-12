import {
	type BridgeCommWorkerPort,
	postPreparedBridgeCommWorkerMessage,
} from './bridge-comm-worker-entry.js';
import type { BridgeCommWorkerFileViewContentRequest } from './bridge-comm-worker-file-metadata-projection.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import {
	isBridgeWorkerFileViewContentMetadata,
	type BridgeWorkerContentAvailabilityPatchPayload,
	type BridgeWorkerFileViewContentMetadata,
} from './bridge-worker-contracts.js';
import {
	type BridgeWorkerFetchedFileViewContentResource,
	fetchBridgeWorkerFileViewContentResource,
	type BridgeWorkerFileViewContentOpen,
} from './bridge-worker-file-view-content-fetch.js';
import {
	bridgeWorkerFileRenderPatchesFromSlicePatchEvent,
	commitBridgeWorkerFileViewContentReadyRenderPatch,
	prepareBridgeWorkerFileRenderPatchEvent,
	prepareBridgeWorkerFileViewContentRenderJobEvent,
} from './bridge-worker-file-view-content-ready.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';

export interface DispatchSelectedBridgeWorkerFileViewContentReadyProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentRequests?: readonly BridgeCommWorkerFileViewContentRequest[];
	readonly contentRequestsByItemId?: ReadonlyMap<string, BridgeCommWorkerFileViewContentRequest>;
	readonly epoch: number;
	readonly itemId: string;
	readonly isPreparationCurrent?: () => boolean;
	readonly openContent: BridgeWorkerFileViewContentOpen;
	readonly port: BridgeCommWorkerPort;
	readonly sequence: number;
	readonly signal?: AbortSignal;
	readonly store: BridgeCommWorkerStore;
	readonly workerDerivationEpoch: number;
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
	const contentRequest =
		props.contentRequestsByItemId?.get(props.itemId) ??
		props.contentRequests?.find((candidate) => candidate.itemId === props.itemId) ??
		null;
	if (contentRequest === null) {
		return { reason: 'descriptor_missing', status: 'terminal', state: 'unavailable' };
	}
	let resource: BridgeWorkerFetchedFileViewContentResource;
	try {
		resource = await fetchBridgeWorkerFileViewContentResource({
			contentRequest,
			openContent: props.openContent,
			...(props.signal === undefined ? {} : { signal: props.signal }),
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
		publicationSequence: props.sequence,
		resource: props.fetchResult.resource,
		workerDerivationEpoch: props.workerDerivationEpoch,
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
	const contentReadyCommit = commitBridgeWorkerFileViewContentReadyRenderPatch({
		preparedJobEvent,
		publicationSequence: props.sequence,
		store: props.store,
		workerDerivationEpoch: props.workerDerivationEpoch,
	});
	postPreparedBridgeCommWorkerMessage(props.port, contentReadyCommit.preparedMessage);
}

export function isSelectedFileViewContentReadyPreparationCurrent(
	props: Pick<
		DispatchSelectedBridgeWorkerFileViewContentReadyProps,
		'epoch' | 'isPreparationCurrent' | 'itemId' | 'store'
	>,
): boolean {
	const state = props.store.getState();
	return (
		state.selectedId === props.itemId &&
		state.demandByKey.get(props.itemId) === `selected:${props.epoch}` &&
		(props.isPreparationCurrent?.() ?? true)
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
		epoch: props.workerDerivationEpoch,
		sequence: props.sequence,
	});
	postPreparedBridgeCommWorkerMessage(
		props.port,
		prepareBridgeWorkerFileRenderPatchEvent({
			patches: bridgeWorkerFileRenderPatchesFromSlicePatchEvent(slicePatchEvent),
			publicationSequence: props.sequence,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
	);
}

function selectedFileViewContentMetadata(
	props: Pick<DispatchSelectedBridgeWorkerFileViewContentReadyProps, 'itemId' | 'store'>,
): BridgeWorkerFileViewContentMetadata | null {
	const metadata = props.store.getState().contentMetadataByItemId.get(props.itemId) ?? null;
	return isBridgeWorkerFileViewContentMetadata(metadata) ? metadata : null;
}
