import {
	fetchSelectedBridgeWorkerReviewContentReadyResources,
	isSelectedReviewContentReadyPreparationCurrent,
	publishSelectedBridgeWorkerReviewContentReadyFetchResult,
	type BridgeWorkerReviewContentReadyFetchResult,
	type DispatchSelectedBridgeWorkerReviewContentReadyProps,
} from './bridge-comm-worker-review-runtime.js';
import type {
	BridgeWorkerContentPreparationWork,
	WorkerContentPreparationPump,
} from './bridge-worker-content-preparation-pump.js';

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
	const { pump, workId = selectedReviewContentReadyWorkId(props), ...dispatchProps } = props;
	const completion = createBridgeWorkerReviewContentReadyPreparationCompletion();
	let fetchStarted = false;
	let fetchResult: BridgeWorkerReviewContentReadyFetchResult | null = null;
	if (!isSelectedReviewContentReadyPreparationCurrent(dispatchProps)) {
		completion.resolve();
		return { completion: completion.promise, enqueued: false, workId };
	}

	const work: BridgeWorkerContentPreparationWork = {
		id: workId,
		rank: 'selected',
		runSlice: () => {
			if (!isSelectedReviewContentReadyPreparationCurrent(dispatchProps)) {
				completion.resolve();
				return { complete: true };
			}
			if (!fetchStarted) {
				fetchStarted = true;
				void fetchSelectedBridgeWorkerReviewContentReadyResources(dispatchProps)
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
				publishSelectedBridgeWorkerReviewContentReadyFetchResult({
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
