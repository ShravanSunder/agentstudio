import {
	fetchSelectedBridgeWorkerFileViewContentReadyResource,
	isSelectedFileViewContentReadyPreparationCurrent,
	publishSelectedBridgeWorkerFileViewContentReadyFetchResult,
	type BridgeWorkerFileViewContentReadyFetchResult,
	type DispatchSelectedBridgeWorkerFileViewContentReadyProps,
} from './bridge-comm-worker-file-view-runtime.js';
import type {
	BridgeWorkerContentPreparationWork,
	WorkerContentPreparationPump,
} from './bridge-worker-content-preparation-pump.js';

export interface EnqueueSelectedBridgeWorkerFileViewContentReadyPreparationProps extends DispatchSelectedBridgeWorkerFileViewContentReadyProps {
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain?: () => void;
	readonly workId?: string;
}

export interface BridgeWorkerFileViewContentReadyPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
	readonly workId: string;
}

export function enqueueSelectedBridgeWorkerFileViewContentReadyPreparation(
	props: EnqueueSelectedBridgeWorkerFileViewContentReadyPreparationProps,
): BridgeWorkerFileViewContentReadyPreparationTicket {
	const { pump, workId = selectedFileViewContentReadyWorkId(props), ...dispatchProps } = props;
	const completion = createBridgeWorkerFileViewContentReadyPreparationCompletion();
	let fetchStarted = false;
	let fetchResult: BridgeWorkerFileViewContentReadyFetchResult | null = null;
	if (!isSelectedFileViewContentReadyPreparationCurrent(dispatchProps)) {
		completion.resolve();
		return { completion: completion.promise, enqueued: false, workId };
	}

	const work: BridgeWorkerContentPreparationWork = {
		id: workId,
		rank: 'selected',
		telemetry: {
			payloadClass: 'inline',
			sourceEpoch: props.epoch,
			workKind: 'file_view_content_ready',
		},
		runSlice: () => {
			if (!isSelectedFileViewContentReadyPreparationCurrent(dispatchProps)) {
				completion.resolve();
				return { complete: true };
			}
			if (!fetchStarted) {
				fetchStarted = true;
				void fetchSelectedBridgeWorkerFileViewContentReadyResource(dispatchProps)
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
				publishSelectedBridgeWorkerFileViewContentReadyFetchResult({
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

function selectedFileViewContentReadyWorkId(
	props: DispatchSelectedBridgeWorkerFileViewContentReadyProps,
): string {
	return `file-view-content-ready:${props.itemId}:${props.epoch}:${props.sequence}`;
}

function createBridgeWorkerFileViewContentReadyPreparationCompletion(): {
	readonly promise: Promise<void>;
	readonly reject: (reason: unknown) => void;
	readonly resolve: () => void;
} {
	let resolveCompletion: () => void = noopBridgeWorkerFileViewContentReadyPreparationCompletion;
	let rejectCompletion: (reason: unknown) => void =
		noopBridgeWorkerFileViewContentReadyPreparationRejection;
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

function noopBridgeWorkerFileViewContentReadyPreparationCompletion(): void {}

function noopBridgeWorkerFileViewContentReadyPreparationRejection(_reason: unknown): void {}
