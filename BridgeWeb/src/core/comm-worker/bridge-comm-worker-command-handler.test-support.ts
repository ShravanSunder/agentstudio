import type { BridgeCommWorkerDemandExecutionScheduleRequest } from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerFileViewContentMetadata } from './bridge-worker-contracts.js';

export interface ScheduledSelectedReviewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

export interface ScheduledSelectedFileViewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

export type ScheduledDemandExecution = Pick<
	BridgeCommWorkerDemandExecutionScheduleRequest,
	'affectedItemIds' | 'cause' | 'epoch'
>;

export function pushScheduledSelectedReviewPreparation(
	target: ScheduledSelectedReviewPreparation[],
): (preparation: ScheduledSelectedReviewPreparation) => void {
	return (preparation: ScheduledSelectedReviewPreparation): void => {
		target.push(preparation);
	};
}

export function ignoreScheduledSelectedReviewPreparation(
	_preparation: ScheduledSelectedReviewPreparation,
): void {}

export function pushScheduledSelectedFileViewPreparation(
	target: ScheduledSelectedFileViewPreparation[],
): (preparation: ScheduledSelectedFileViewPreparation) => void {
	return (preparation: ScheduledSelectedFileViewPreparation): void => {
		target.push(preparation);
	};
}

export function ignoreScheduledSelectedFileViewPreparation(
	_preparation: ScheduledSelectedFileViewPreparation,
): void {}

export function pushScheduledDemandExecution(
	target: ScheduledDemandExecution[],
): (request: BridgeCommWorkerDemandExecutionScheduleRequest) => void {
	return (request: BridgeCommWorkerDemandExecutionScheduleRequest): void => {
		target.push({
			...(request.affectedItemIds === undefined
				? {}
				: { affectedItemIds: request.affectedItemIds }),
			cause: request.cause,
			epoch: request.epoch,
		});
	};
}

export function createSequenceFrom(sequences: readonly number[]): () => number {
	let index = 0;
	return (): number => {
		const sequence = sequences[index];
		if (sequence === undefined) {
			throw new Error('test sequence exhausted');
		}
		index += 1;
		return sequence;
	};
}

export function makeWorkerFileViewContentMetadata(
	itemId: string,
): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `file-view:sha256:${itemId}`,
		sizeBytes: 128,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount: 128,
		payloadLineCount: 7,
		totalLineCount: 7,
		truncationKind: 'none',
		isBinary: false,
		canFetchContent: true,
	};
}
