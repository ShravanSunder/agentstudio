import {
	fetchBridgeWorkerReviewContentReadyResources,
	isReviewContentReadyDemandCurrent,
	publishBridgeWorkerReviewContentReadyFetchResult,
	type BridgeWorkerReviewContentReadyFetchResult,
	type DispatchBridgeWorkerReviewContentReadyProps,
	type DispatchSelectedBridgeWorkerReviewContentReadyProps,
} from './bridge-comm-worker-review-runtime.js';
import { recordBridgeCommWorkerSelectedContentDroppedTelemetry } from './bridge-comm-worker-telemetry.js';
import type {
	BridgeWorkerContentPreparationRank,
	BridgeWorkerContentPreparationWork,
	WorkerContentPreparationPump,
} from './bridge-worker-content-preparation-pump.js';

export interface EnqueueBridgeWorkerReviewContentReadyPreparationProps extends DispatchBridgeWorkerReviewContentReadyProps {
	readonly preparationRank: BridgeWorkerContentPreparationRank;
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain?: () => void;
	readonly workId?: string;
}

export interface EnqueueSelectedBridgeWorkerReviewContentReadyPreparationProps extends DispatchSelectedBridgeWorkerReviewContentReadyProps {
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain?: () => void;
	readonly workId?: string;
}

export interface BridgeWorkerReviewContentReadyPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
	readonly workId: string;
}

export function enqueueSelectedBridgeWorkerReviewContentReadyPreparation(
	props: EnqueueSelectedBridgeWorkerReviewContentReadyPreparationProps,
): BridgeWorkerReviewContentReadyPreparationTicket {
	return enqueueBridgeWorkerReviewContentReadyPreparation({
		...props,
		demandKey: `selected:${props.epoch}`,
		preparationRank: 'selected',
		recordSelectedContentDrops: true,
		workId: props.workId ?? selectedReviewContentReadyWorkId(props),
	});
}

export function enqueueBridgeWorkerReviewContentReadyPreparation(
	props: EnqueueBridgeWorkerReviewContentReadyPreparationProps,
): BridgeWorkerReviewContentReadyPreparationTicket {
	const { pump, workId = reviewContentReadyWorkId(props), ...dispatchProps } = props;
	const completion = createBridgeWorkerReviewContentReadyPreparationCompletion();
	let fetchStarted = false;
	let fetchResult: BridgeWorkerReviewContentReadyFetchResult | null = null;
	if (!isReviewContentReadyDemandCurrent(dispatchProps)) {
		recordBridgeWorkerReviewPreparationSelectedContentDrop({
			...dispatchProps,
			dropReason: 'stale_before_fetch',
		});
		completion.resolve();
		return { completion: completion.promise, enqueued: false, workId };
	}

	const work: BridgeWorkerContentPreparationWork = {
		id: workId,
		rank: props.preparationRank,
		telemetry: {
			payloadClass: 'inline',
			sourceEpoch: props.epoch,
			workKind: 'review_content_ready',
		},
		runSlice: () => {
			if (!fetchStarted) {
				if (!isReviewContentReadyDemandCurrent(dispatchProps)) {
					recordBridgeWorkerReviewPreparationSelectedContentDrop({
						...dispatchProps,
						dropReason: 'stale_before_fetch',
					});
					completion.resolve();
					return { complete: true };
				}
				fetchStarted = true;
				void fetchBridgeWorkerReviewContentReadyResources(dispatchProps)
					.then((result) => {
						fetchResult = result;
						pump.enqueueOrPromote(work);
						props.requestPreparationDrain?.();
					})
					.catch(completion.reject);
				return { complete: false, continuation: 'external' };
			}
			if (fetchResult === null) {
				return { complete: false, continuation: 'external' };
			}
			try {
				publishBridgeWorkerReviewContentReadyFetchResult({
					...dispatchProps,
					fetchResult,
				});
				completion.resolve();
			} catch (error) {
				completion.reject(error);
			}
			return { complete: true };
		},
	};
	pump.enqueueOrPromote(work);

	return { completion: completion.promise, enqueued: true, workId };
}

function recordBridgeWorkerReviewPreparationSelectedContentDrop(
	props: DispatchBridgeWorkerReviewContentReadyProps & {
		readonly dropReason: 'stale_before_fetch';
	},
): void {
	if (props.recordSelectedContentDrops !== true) {
		return;
	}
	recordBridgeCommWorkerSelectedContentDroppedTelemetry({
		dropReason: props.dropReason,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	});
}

function reviewContentReadyWorkId(
	props: Pick<
		DispatchBridgeWorkerReviewContentReadyProps,
		'demandKey' | 'epoch' | 'itemId' | 'sequence'
	>,
): string {
	return `review-content-ready:${props.itemId}:${props.demandKey}:${props.sequence}`;
}

function selectedReviewContentReadyWorkId(
	props: DispatchSelectedBridgeWorkerReviewContentReadyProps,
): string {
	return `review-content-ready:${props.itemId}:${props.epoch}:${props.sequence}`;
}

function createBridgeWorkerReviewContentReadyPreparationCompletion(): {
	readonly promise: Promise<void>;
	readonly reject: (reason: unknown) => void;
	readonly resolve: () => void;
} {
	let resolveCompletion: () => void = noopBridgeWorkerReviewContentReadyPreparationCompletion;
	let rejectCompletion: (reason: unknown) => void =
		noopBridgeWorkerReviewContentReadyPreparationRejection;
	const promise = new Promise<void>((resolve, reject) => {
		resolveCompletion = resolve;
		rejectCompletion = reject;
	});
	return {
		promise,
		reject: rejectCompletion,
		resolve: resolveCompletion,
	};
}

function noopBridgeWorkerReviewContentReadyPreparationCompletion(): void {}

function noopBridgeWorkerReviewContentReadyPreparationRejection(_reason: unknown): void {}
