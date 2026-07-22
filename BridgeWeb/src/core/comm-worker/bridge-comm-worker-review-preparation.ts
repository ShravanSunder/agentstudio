import {
	createBridgeWorkerReviewContentReadyPublication,
	fetchBridgeWorkerReviewContentReadyResources,
	isReviewContentReadyDemandCurrent,
	type BridgeWorkerReviewContentReadyFetchResult,
	type BridgeWorkerReviewContentReadyPublication,
	type DispatchBridgeWorkerReviewContentReadyProps,
	type DispatchSelectedBridgeWorkerReviewContentReadyProps,
} from './bridge-comm-worker-review-runtime.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
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
	cancel(): void;
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
	pause(): void;
	resume(): void;
	readonly workId: string;
}

type BridgeWorkerReviewContentReadyPreparationLifecycle =
	| 'active'
	| 'paused'
	| 'cancelled'
	| 'settled';

export function selectedReviewPreparationIdentity(props: {
	readonly epoch: number;
	readonly itemId: string;
	readonly source: BridgeCommWorkerReviewRuntimeSource;
	readonly workerDerivationEpoch: number;
}): string {
	const selectedContentMetadata =
		props.source.contentItems.find((metadata) => metadata.itemId === props.itemId) ?? null;
	const selectedContentRequestDescriptors = props.source.contentRequestDescriptors.filter(
		(descriptor) => descriptor.itemId === props.itemId,
	);
	const selectedRenderSemantics =
		props.source.renderSemantics.find((semantics) => semantics.itemId === props.itemId) ?? null;
	return JSON.stringify(
		canonicalReviewPreparationIdentityValue([
			'selected-review-preparation-v1',
			props.epoch,
			props.workerDerivationEpoch,
			props.itemId,
			selectedContentMetadata,
			selectedContentRequestDescriptors,
			selectedRenderSemantics,
		]),
	);
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
	let publication: BridgeWorkerReviewContentReadyPublication | null = null;
	let lifecycle: BridgeWorkerReviewContentReadyPreparationLifecycle = 'active';
	const resolveCompletion = (): void => {
		if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
		lifecycle = 'settled';
		completion.resolve();
	};
	const rejectCompletion = (reason: unknown): void => {
		if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
		lifecycle = 'settled';
		completion.reject(reason);
	};
	if (!isReviewContentReadyDemandCurrent(dispatchProps)) {
		recordBridgeWorkerReviewPreparationSelectedContentDrop({
			...dispatchProps,
			dropReason: 'stale_before_fetch',
		});
		resolveCompletion();
		return {
			cancel: noopBridgeWorkerReviewContentReadyPreparationControl,
			completion: completion.promise,
			enqueued: false,
			pause: noopBridgeWorkerReviewContentReadyPreparationControl,
			resume: noopBridgeWorkerReviewContentReadyPreparationControl,
			workId,
		};
	}

	const work: BridgeWorkerContentPreparationWork = {
		id: workId,
		rank: props.preparationRank,
		telemetry: {
			payloadClass: 'inline',
			sourceEpoch: props.epoch,
			workKind: 'review_content_ready',
		},
		runSlice: (context) => {
			if (lifecycle === 'cancelled' || lifecycle === 'settled') {
				return { complete: true };
			}
			if (lifecycle === 'paused') {
				return { complete: false, continuation: 'external' };
			}
			if (!fetchStarted) {
				if (!isReviewContentReadyDemandCurrent(dispatchProps)) {
					recordBridgeWorkerReviewPreparationSelectedContentDrop({
						...dispatchProps,
						dropReason: 'stale_before_fetch',
					});
					resolveCompletion();
					return { complete: true };
				}
				fetchStarted = true;
				void fetchBridgeWorkerReviewContentReadyResources(dispatchProps)
					.then((result) => {
						if (lifecycle === 'cancelled' || lifecycle === 'settled') return;
						fetchResult = result;
						if (lifecycle === 'paused') return;
						pump.enqueueOrPromote(work);
						props.requestPreparationDrain?.();
					})
					.catch(rejectCompletion);
				return { complete: false, continuation: 'external' };
			}
			if (fetchResult === null) {
				return { complete: false, continuation: 'external' };
			}
			try {
				if (context.shouldYield()) return { complete: false };
				if (publication === null) {
					publication = createBridgeWorkerReviewContentReadyPublication({
						...dispatchProps,
						fetchResult,
					});
					return { complete: false };
				}
				const publicationResult = publication.runNextStage();
				if (!publicationResult.complete) return { complete: false };
				resolveCompletion();
			} catch (error) {
				rejectCompletion(error);
			}
			return { complete: true };
		},
	};
	pump.enqueueOrPromote(work);

	return {
		cancel: (): void => {
			if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
			lifecycle = 'cancelled';
			fetchResult = null;
			publication = null;
			pump.cancel(workId);
			completion.resolve();
		},
		completion: completion.promise,
		enqueued: true,
		pause: (): void => {
			if (lifecycle !== 'active') return;
			lifecycle = 'paused';
			pump.cancel(workId);
		},
		resume: (): void => {
			if (lifecycle !== 'paused') return;
			lifecycle = 'active';
			if (fetchStarted && fetchResult === null) return;
			pump.enqueueOrPromote(work);
			props.requestPreparationDrain?.();
		},
		workId,
	};
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

function noopBridgeWorkerReviewContentReadyPreparationControl(): void {}

function canonicalReviewPreparationIdentityValue(value: unknown): unknown {
	if (Array.isArray(value)) {
		return value.map(canonicalReviewPreparationIdentityValue);
	}
	if (value === null || typeof value !== 'object') {
		return value;
	}
	return Object.fromEntries(
		Object.entries(value)
			.toSorted(([leftKey], [rightKey]) => (leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0))
			.map(([key, nestedValue]) => [key, canonicalReviewPreparationIdentityValue(nestedValue)]),
	);
}
