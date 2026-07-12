import type {
	BridgeCommWorkerDemandExecutionScheduleRequest,
	BridgeCommWorkerReviewSourceUpdateScheduleRequest,
	BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { WorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

const bridgeCommWorkerReviewSourceResetChunkItemCount = 64;

export interface EnqueuedBridgeCommWorkerDemandPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
}

interface EnqueueBridgeCommWorkerReviewSourceResetProps {
	readonly createSequence: () => number;
	readonly isCurrentResetEpoch: () => boolean;
	readonly onResetComplete: () => void;
	readonly pump: WorkerContentPreparationPump;
	readonly request: BridgeCommWorkerReviewSourceUpdateScheduleRequest;
	readonly requestPreparationDrain: () => void;
	readonly scheduleDemandExecution: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => boolean;
	readonly scheduleSelectedReviewContentReadyPreparation: (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	) => void;
}

export function enqueueBridgeCommWorkerReviewSourceReset(
	props: EnqueueBridgeCommWorkerReviewSourceResetProps,
): EnqueuedBridgeCommWorkerDemandPreparationTicket {
	let processedItemCount = 0;
	const completion = createBridgeCommWorkerCompletion();
	const orderedItemIds = props.request.nextReviewRuntimeSource.rows.map((row) => row.id);
	const affectedItemIds = new Set(props.request.affectedItemIds);
	const work = {
		id: `review-source-reset:${props.request.epoch}`,
		rank: 'background' as const,
		telemetry: {
			payloadClass: 'source_reset',
			sourceEpoch: props.request.epoch,
			workKind: 'review_source_reset',
		},
		runSlice: (): { readonly complete: boolean; readonly continuation?: 'external' } => {
			if (!props.isCurrentResetEpoch()) {
				completion.resolve();
				return { complete: true };
			}
			processedItemCount = Math.min(
				processedItemCount + bridgeCommWorkerReviewSourceResetChunkItemCount,
				orderedItemIds.length,
			);
			const previousProcessedItemCount = Math.max(
				0,
				processedItemCount - bridgeCommWorkerReviewSourceResetChunkItemCount,
			);
			const chunkItemIds = new Set(
				orderedItemIds.slice(previousProcessedItemCount, processedItemCount),
			);
			const chunkAffectedItemIds = [...chunkItemIds].filter((itemId) =>
				affectedItemIds.has(itemId),
			);
			const resetComplete = processedItemCount >= orderedItemIds.length;
			const sourceUpdateResult = props.request.store.actions.applyReviewSourceUpdateFact({
				contentItems: props.request.nextReviewRuntimeSource.contentItems.filter((metadata) =>
					chunkItemIds.has(metadata.itemId),
				),
				epoch: props.request.epoch,
				...(resetComplete ? { completeItemIds: orderedItemIds } : {}),
				resetComplete: false,
				rows: props.request.nextReviewRuntimeSource.rows.filter((row) => chunkItemIds.has(row.id)),
			});
			const selectedId = props.request.store.getState().selectedId;
			const selectedSourceChurnResult =
				selectedId !== null && chunkAffectedItemIds.includes(selectedId)
					? props.request.store.actions.applySelectedSourceChurnFact({
							epoch: props.request.epoch,
							itemId: selectedId,
						})
					: null;
			if (
				selectedId !== null &&
				(sourceUpdateResult.touchedKeys.includes(`demand:${selectedId}`) ||
					selectedSourceChurnResult?.touchedKeys.includes(`demand:${selectedId}`) === true)
			) {
				props.scheduleSelectedReviewContentReadyPreparation({
					epoch: props.request.epoch,
					itemId: selectedId,
					store: props.request.store,
				});
			}
			if (chunkAffectedItemIds.length > 0) {
				props.scheduleDemandExecution({
					affectedItemIds: chunkAffectedItemIds,
					cause: 'reviewSourceUpdate',
					epoch: props.request.epoch,
					forceExecutionItemIds: chunkAffectedItemIds,
					store: props.request.store,
				});
			}
			if (!resetComplete) {
				scheduleBridgeCommWorkerTaskBoundary(() => {
					props.pump.enqueueOrPromote(work);
					props.requestPreparationDrain();
				});
				return { complete: false, continuation: 'external' };
			}
			props.onResetComplete();
			completion.resolve();
			return { complete: true };
		},
	};
	props.pump.enqueueOrPromote(work);
	return { completion: completion.promise, enqueued: true };
}

function scheduleBridgeCommWorkerTaskBoundary(callback: () => void): void {
	setTimeout(callback, 0);
}

function createBridgeCommWorkerCompletion(): {
	readonly promise: Promise<void>;
	readonly reject: (reason: unknown) => void;
	readonly resolve: () => void;
} {
	let resolveCompletion: () => void = noopBridgeCommWorkerCompletionResolve;
	let rejectCompletion: (reason: unknown) => void = noopBridgeCommWorkerCompletionReject;
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

function noopBridgeCommWorkerCompletionResolve(): void {}

function noopBridgeCommWorkerCompletionReject(_reason: unknown): void {}
