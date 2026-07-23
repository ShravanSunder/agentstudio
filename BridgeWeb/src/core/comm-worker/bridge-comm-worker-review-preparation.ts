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
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';

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
	cancel(
		settlement?: Extract<
			BridgeWorkerReviewContentReadyPreparationSettlement,
			'invalidated' | 'teardown'
		>,
	): void;
	readonly completion: Promise<BridgeWorkerReviewContentReadyPreparationSettlement>;
	readonly enqueued: boolean;
	pause(): void;
	resume(): void;
	updateDemand(props: {
		readonly bridgeDemandRank: BridgeWorkerDemandRank;
		readonly budget: BridgeWorkerPierreRenderBudget;
		readonly preparationRank: BridgeWorkerContentPreparationRank;
	}): void;
	readonly workId: string;
}

export type BridgeWorkerReviewContentReadyPreparationSettlement =
	| 'invalidated'
	| 'resident'
	| 'retryWait'
	| 'teardown'
	| 'terminal';

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
	return JSON.stringify(
		canonicalReviewPreparationIdentityValue([
			'selected-review-preparation-v1',
			props.epoch,
			props.workerDerivationEpoch,
			...reviewItemPreparationIdentityParts(props),
		]),
	);
}

export function reviewItemPreparationIdentity(props: {
	readonly itemId: string;
	readonly source: BridgeCommWorkerReviewRuntimeSource;
}): string {
	return JSON.stringify(
		canonicalReviewPreparationIdentityValue([
			'review-item-preparation-v1',
			...reviewItemPreparationIdentityParts(props),
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
	let currentBridgeDemandRank = dispatchProps.bridgeDemandRank;
	let currentBudget = dispatchProps.budget;
	let currentPreparationRank = props.preparationRank;
	let fetchStarted = false;
	let fetchResult: BridgeWorkerReviewContentReadyFetchResult | null = null;
	let publication: BridgeWorkerReviewContentReadyPublication | null = null;
	let lifecycle: BridgeWorkerReviewContentReadyPreparationLifecycle = 'active';
	const resolveCompletion = (
		settlement: BridgeWorkerReviewContentReadyPreparationSettlement,
	): void => {
		if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
		lifecycle = 'settled';
		completion.resolve(settlement);
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
		resolveCompletion('invalidated');
		return {
			cancel: noopBridgeWorkerReviewContentReadyPreparationControl,
			completion: completion.promise,
			enqueued: false,
			pause: noopBridgeWorkerReviewContentReadyPreparationControl,
			resume: noopBridgeWorkerReviewContentReadyPreparationControl,
			updateDemand: noopBridgeWorkerReviewContentReadyPreparationUpdate,
			workId,
		};
	}

	const work: BridgeWorkerContentPreparationWork = {
		id: workId,
		get rank(): BridgeWorkerContentPreparationRank {
			return currentPreparationRank;
		},
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
					resolveCompletion('invalidated');
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
						bridgeDemandRank: currentBridgeDemandRank,
						budget: currentBudget,
						fetchResult,
					});
					return { complete: false };
				}
				const publicationResult = publication.runNextStage();
				if (!publicationResult.complete) return { complete: false };
				resolveCompletion(settlementForBridgeWorkerReviewFetchResult(fetchResult));
			} catch (error) {
				rejectCompletion(error);
			}
			return { complete: true };
		},
	};
	pump.enqueueOrPromote(work);

	return {
		cancel: (settlement = 'teardown'): void => {
			if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
			lifecycle = 'cancelled';
			fetchResult = null;
			publication = null;
			pump.cancel(workId);
			completion.resolve(settlement);
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
		updateDemand: (demand): void => {
			if (lifecycle === 'settled' || lifecycle === 'cancelled') return;
			currentBridgeDemandRank = demand.bridgeDemandRank;
			currentBudget = demand.budget;
			currentPreparationRank = demand.preparationRank;
			if (lifecycle === 'active') pump.enqueueOrPromote(work);
		},
		workId,
	};
}

function settlementForBridgeWorkerReviewFetchResult(
	fetchResult: BridgeWorkerReviewContentReadyFetchResult,
): BridgeWorkerReviewContentReadyPreparationSettlement {
	switch (fetchResult.status) {
		case 'ready':
			return 'resident';
		case 'retryWait':
			return 'retryWait';
		case 'stale':
			return 'invalidated';
		case 'terminal':
			return 'terminal';
	}
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
	readonly promise: Promise<BridgeWorkerReviewContentReadyPreparationSettlement>;
	readonly reject: (reason: unknown) => void;
	readonly resolve: (settlement: BridgeWorkerReviewContentReadyPreparationSettlement) => void;
} {
	let resolveCompletion: (settlement: BridgeWorkerReviewContentReadyPreparationSettlement) => void =
		noopBridgeWorkerReviewContentReadyPreparationSettlement;
	let rejectCompletion: (reason: unknown) => void =
		noopBridgeWorkerReviewContentReadyPreparationRejection;
	const promise = new Promise<BridgeWorkerReviewContentReadyPreparationSettlement>(
		(resolve, reject) => {
			resolveCompletion = resolve;
			rejectCompletion = reject;
		},
	);
	return {
		promise,
		reject: rejectCompletion,
		resolve: resolveCompletion,
	};
}

function noopBridgeWorkerReviewContentReadyPreparationSettlement(
	_settlement: BridgeWorkerReviewContentReadyPreparationSettlement,
): void {}

function noopBridgeWorkerReviewContentReadyPreparationRejection(_reason: unknown): void {}

function noopBridgeWorkerReviewContentReadyPreparationControl(): void {}

function noopBridgeWorkerReviewContentReadyPreparationUpdate(): void {}

function reviewItemPreparationIdentityParts(props: {
	readonly itemId: string;
	readonly source: BridgeCommWorkerReviewRuntimeSource;
}): readonly unknown[] {
	const contentMetadata =
		props.source.contentItems.find((metadata) => metadata.itemId === props.itemId) ?? null;
	const contentRequestDescriptors = props.source.contentRequestDescriptors.filter(
		(descriptor) => descriptor.itemId === props.itemId,
	);
	const renderSemantics =
		props.source.renderSemantics.find((semantics) => semantics.itemId === props.itemId) ?? null;
	return [props.itemId, contentMetadata, contentRequestDescriptors, renderSemantics];
}

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
