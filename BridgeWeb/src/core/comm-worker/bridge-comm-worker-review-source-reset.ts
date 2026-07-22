import type {
	BridgeCommWorkerDemandExecutionScheduleRequest,
	BridgeCommWorkerReviewMetadataResetScheduleRequest,
	BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import { isReviewRuntimeSourceExecutableForItem } from './bridge-comm-worker-review-source-diff.js';
import type { WorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

const bridgeCommWorkerReviewSourceResetChunkEntryCount = 64;

export interface EnqueuedBridgeCommWorkerDemandPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
}

interface EnqueueBridgeCommWorkerReviewSourceResetProps {
	readonly createSequence: () => number;
	readonly isCurrentResetEpoch: () => boolean;
	readonly onResetComplete: () => void;
	readonly pump: WorkerContentPreparationPump;
	readonly request: BridgeCommWorkerReviewMetadataResetScheduleRequest;
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
	const completion = createBridgeCommWorkerCompletion();
	const processedContentItemIds = new Set<string>();
	const processedRowIds = new Set<string>();
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
			const runtimeSource = props.request.readReviewRuntimeSource();
			const chunkContentItems = runtimeSource.contentItems
				.filter((metadata) => !processedContentItemIds.has(metadata.itemId))
				.slice(0, bridgeCommWorkerReviewSourceResetChunkEntryCount);
			const chunkRows = runtimeSource.rows
				.filter((row) => !processedRowIds.has(row.id))
				.slice(0, bridgeCommWorkerReviewSourceResetChunkEntryCount);
			for (const metadata of chunkContentItems) processedContentItemIds.add(metadata.itemId);
			for (const row of chunkRows) processedRowIds.add(row.id);
			const chunkAffectedItemIds = chunkContentItems
				.map((metadata) => metadata.itemId)
				.filter((itemId) => affectedItemIds.has(itemId));
			const completeContentItemIds = runtimeSource.contentItems.map((metadata) => metadata.itemId);
			const completeRowIds = runtimeSource.rows.map((row) => row.id);
			const resetComplete =
				completeContentItemIds.every((itemId) => processedContentItemIds.has(itemId)) &&
				completeRowIds.every((rowId) => processedRowIds.has(rowId));
			props.request.store.actions.applyReviewSourceUpdateFact({
				...(resetComplete ? { completeContentItemIds, completeRowIds } : {}),
				contentItems: chunkContentItems,
				epoch: props.request.epoch,
				resetComplete: false,
				rows: chunkRows,
			});
			const selectedId = props.request.store.getState().selectedId;
			const selectedDemand =
				selectedId !== null &&
				chunkAffectedItemIds.includes(selectedId) &&
				isReviewRuntimeSourceExecutableForItem(runtimeSource, selectedId)
					? props.request.store.actions.applySelectedSourceChurnFact({
							itemId: selectedId,
						})
					: null;
			if (
				selectedId !== null &&
				selectedDemand !== null &&
				selectedDemand.selectedDemandEpoch !== null
			) {
				props.scheduleSelectedReviewContentReadyPreparation({
					epoch: selectedDemand.selectedDemandEpoch,
					itemId: selectedId,
					store: props.request.store,
				});
			}
			if (chunkAffectedItemIds.length > 0) {
				props.scheduleDemandExecution({
					affectedItemIds: chunkAffectedItemIds,
					cause: props.request.cause,
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
