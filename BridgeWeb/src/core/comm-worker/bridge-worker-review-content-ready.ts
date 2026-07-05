import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerPierreRenderJobEvent,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import { prepareBridgeWorkerReviewPierreRenderJobEvent } from './bridge-worker-review-pierre-job-planner.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export interface PrepareBridgeWorkerReviewContentReadyEventsProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}

export interface CommitBridgeWorkerReviewContentReadySlicePatchProps {
	readonly epoch: number;
	readonly preparedJobEvent: PreparedBridgeWorkerStructuredMessage<BridgeWorkerPierreRenderJobEvent>;
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeWorkerReviewContentReadySlicePatchCommit {
	readonly touchedKeys: readonly string[];
	readonly preparedMessage: BridgeWorkerPreparedServerToMainMessage;
}

export type BridgeWorkerPreparedServerToMainMessage =
	PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>;

export function prepareBridgeWorkerReviewContentRenderJobEvent(
	props: PrepareBridgeWorkerReviewContentReadyEventsProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerPierreRenderJobEvent> | null {
	return prepareBridgeWorkerReviewPierreRenderJobEvent({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		resources: props.resources,
		semantics: props.semantics,
	});
}

export function commitBridgeWorkerReviewContentReadySlicePatch(
	props: CommitBridgeWorkerReviewContentReadySlicePatchProps,
): BridgeWorkerReviewContentReadySlicePatchCommit {
	const contentReadyResult = props.store.actions.applyContentReady({
		itemId: props.preparedJobEvent.message.job.itemId,
		contentCacheKey: props.preparedJobEvent.message.job.contentCacheKey,
	});
	const slicePatchEvent = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.epoch,
		sequence: props.sequence,
	});

	return {
		touchedKeys: contentReadyResult.touchedKeys,
		preparedMessage: prepareBridgeWorkerStructuredMessage({
			message: assertBridgeWorkerSlicePatchEvent(slicePatchEvent),
			declaredFields: [],
		}),
	};
}

function assertBridgeWorkerSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): BridgeWorkerServerToMainMessage {
	if (event === null) {
		throw new Error('Bridge worker content-ready commit produced no slice patch event.');
	}
	return event;
}
