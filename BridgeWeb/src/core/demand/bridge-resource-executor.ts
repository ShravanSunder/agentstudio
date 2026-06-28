import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type { BridgeResourceDescriptor } from '../models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';

export interface BridgeResourceExecutorLoadResourceProps {
	readonly descriptor: BridgeResourceDescriptor;
	readonly intent: BridgeDemandIntent;
	readonly onChunk: (chunk: BridgeResourceExecutorStreamChunk) => void;
	readonly signal: AbortSignal;
}

export interface BridgeResourceExecutorContent<TContent = unknown> {
	readonly authoritative?: boolean;
	readonly content: TContent;
	readonly byteLength: number;
}

export interface BridgeResourceExecutorStreamChunk<TChunk = unknown> {
	readonly byteLength: number;
	readonly chunk: TChunk;
	readonly totalBytesRead: number;
}

export type BridgeResourceExecutorLoadResource<TContent = unknown> = (
	props: BridgeResourceExecutorLoadResourceProps,
) => Promise<BridgeResourceExecutorContent<TContent>>;

export interface BridgeResourceExecutorProps<TContent = unknown> {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly maxConcurrentLoads: number;
	readonly maxInFlightBytes: number;
	readonly maxQueuedLoads: number;
	readonly maxQueuedBytes: number;
	readonly loadResource: BridgeResourceExecutorLoadResource<TContent>;
	readonly isFresh?: (intent: BridgeDemandIntent) => boolean;
	readonly onChunk?: (props: {
		readonly chunk: BridgeResourceExecutorStreamChunk;
		readonly descriptor: BridgeResourceDescriptor;
		readonly intent: BridgeDemandIntent;
	}) => void;
}

export type BridgeResourceExecutorResult<TContent = unknown> =
	| {
			readonly ok: true;
			readonly authoritative: boolean;
			readonly content: TContent;
			readonly byteLength: number;
			readonly descriptor: BridgeResourceDescriptor;
			readonly freshnessKey: string;
	  }
	| {
			readonly ok: false;
			readonly reason:
				| 'descriptor_missing'
				| 'byte_budget_exceeded'
				| 'concurrency_exceeded'
				| 'load_failed'
				| 'stale_completion'
				| 'aborted';
	  };

export interface BridgeResourceExecutor<TContent = unknown> {
	load(intent: BridgeDemandIntent): Promise<BridgeResourceExecutorResult<TContent>>;
	cancelGroup(cancellationGroup: string): number;
	readonly inFlightCount: number;
	readonly inFlightBytes: number;
	readonly maxConcurrentLoads: number;
	readonly maxInFlightBytes: number;
	readonly maxQueuedBytes: number;
	readonly maxQueuedLoads: number;
	readonly queuedLoadCount: number;
	readonly queuedBytes: number;
}

interface InFlightResourceLoad<TContent> {
	readonly promise: Promise<BridgeResourceExecutorResult<TContent>>;
	readonly abortController: AbortController;
	readonly cancellationGroup: string;
	readonly byteBudget: number;
	readonly intent: BridgeDemandIntent;
}

interface PendingResourceLoad<TContent> {
	readonly intent: BridgeDemandIntent;
	readonly descriptor: BridgeResourceDescriptor;
	readonly promise: Promise<BridgeResourceExecutorResult<TContent>>;
	readonly abortController: AbortController;
	readonly byteBudget: number;
	readonly resolve: (result: BridgeResourceExecutorResult<TContent>) => void;
	readonly sequence: number;
}

interface PendingResourceLoadEntry<TContent> {
	readonly inFlightKey: string;
	readonly pendingLoad: PendingResourceLoad<TContent>;
}

const demandLaneOrder = [
	'foreground',
	'active',
	'visible',
	'nearby',
	'speculative',
	'idle',
] as const satisfies readonly BridgeDemandIntent['lane'][];

export function createBridgeResourceExecutor<TContent = unknown>(
	props: BridgeResourceExecutorProps<TContent>,
): BridgeResourceExecutor<TContent> {
	const inFlightByDedupeKey = new Map<string, InFlightResourceLoad<TContent>>();
	const pendingByDedupeKey = new Map<string, PendingResourceLoad<TContent>>();
	let nextPendingSequence = 0;
	let inFlightBytes = 0;
	let queuedBytes = 0;

	const load = async (
		intent: BridgeDemandIntent,
	): Promise<BridgeResourceExecutorResult<TContent>> => {
		const inFlightKey = makeInFlightKey(intent);
		const existingLoad = inFlightByDedupeKey.get(inFlightKey);
		if (existingLoad !== undefined) {
			return await existingLoad.promise;
		}
		const existingPendingLoad = pendingByDedupeKey.get(inFlightKey);
		if (existingPendingLoad !== undefined) {
			if (compareDemandIntentPriority(intent, existingPendingLoad.intent) < 0) {
				pendingByDedupeKey.set(inFlightKey, {
					...existingPendingLoad,
					intent,
					sequence: nextPendingSequence,
				});
				nextPendingSequence += 1;
			}
			return await existingPendingLoad.promise;
		}
		const descriptor = props.registry.lookup(intent.descriptorRef);
		if (descriptor === null) {
			return { ok: false, reason: 'descriptor_missing' };
		}
		const byteBudget = descriptor.content.expectedBytes ?? descriptor.content.maxBytes;
		if (byteBudget > props.maxInFlightBytes) {
			return { ok: false, reason: 'byte_budget_exceeded' };
		}
		if (!isIntentFresh(intent)) {
			return { ok: false, reason: 'stale_completion' };
		}
		const abortController = new AbortController();
		if (canStartLoad(byteBudget)) {
			return await startLoad({ abortController, byteBudget, descriptor, inFlightKey, intent });
		}
		preemptLowerPriorityInFlightLoads({ byteBudget, intent });
		if (canStartLoad(byteBudget)) {
			return await startLoad({ abortController, byteBudget, descriptor, inFlightKey, intent });
		}
		if (!canQueueUnderPressure(intent)) {
			return { ok: false, reason: 'concurrency_exceeded' };
		}
		if (!canQueuePendingLoad(byteBudget)) {
			evictLowerPriorityPendingLoads({ byteBudget, intent });
		}
		if (!canQueuePendingLoad(byteBudget)) {
			return { ok: false, reason: 'concurrency_exceeded' };
		}
		let resolvePending: ((result: BridgeResourceExecutorResult<TContent>) => void) | null = null;
		const promise = new Promise<BridgeResourceExecutorResult<TContent>>((resolve): void => {
			resolvePending = resolve;
		});
		if (resolvePending === null) {
			throw new Error('Pending Bridge resource load was not initialized.');
		}
		pendingByDedupeKey.set(inFlightKey, {
			intent,
			descriptor,
			promise,
			abortController,
			byteBudget,
			resolve: resolvePending,
			sequence: nextPendingSequence,
		});
		queuedBytes += byteBudget;
		nextPendingSequence += 1;
		pumpPendingLoads();
		return await promise;
	};

	const cancelGroup = (cancellationGroup: string): number => {
		let cancelledCount = 0;
		for (const inFlightLoad of inFlightByDedupeKey.values()) {
			if (inFlightLoad.cancellationGroup !== cancellationGroup) {
				continue;
			}
			inFlightLoad.abortController.abort();
			cancelledCount += 1;
		}
		for (const [inFlightKey, pendingLoad] of pendingByDedupeKey) {
			if (pendingLoad.intent.cancellationGroup !== cancellationGroup) {
				continue;
			}
			pendingLoad.abortController.abort();
			pendingByDedupeKey.delete(inFlightKey);
			queuedBytes -= pendingLoad.byteBudget;
			pendingLoad.resolve({ ok: false, reason: 'aborted' });
			cancelledCount += 1;
		}
		return cancelledCount;
	};

	const evictLowerPriorityPendingLoads = (evictProps: {
		readonly byteBudget: number;
		readonly intent: BridgeDemandIntent;
	}): void => {
		while (!canQueuePendingLoad(evictProps.byteBudget)) {
			const evictableEntry = lowestPriorityPendingLoadBelow(evictProps.intent);
			if (evictableEntry === null) {
				return;
			}
			removePendingLoad({
				inFlightKey: evictableEntry.inFlightKey,
				pendingLoad: evictableEntry.pendingLoad,
				reason: 'aborted',
			});
		}
	};

	const lowestPriorityPendingLoadBelow = (
		intent: BridgeDemandIntent,
	): PendingResourceLoadEntry<TContent> | null =>
		Array.from(pendingByDedupeKey.entries())
			.map(
				([inFlightKey, pendingLoad]): PendingResourceLoadEntry<TContent> => ({
					inFlightKey,
					pendingLoad,
				}),
			)
			.filter((entry): boolean => compareDemandIntentPriority(intent, entry.pendingLoad.intent) < 0)
			.toSorted(
				(left, right): number =>
					compareDemandIntentPriority(right.pendingLoad.intent, left.pendingLoad.intent) ||
					right.pendingLoad.sequence - left.pendingLoad.sequence,
			)[0] ?? null;

	const removePendingLoad = (removeProps: {
		readonly inFlightKey: string;
		readonly pendingLoad: PendingResourceLoad<TContent>;
		readonly reason: 'aborted' | 'concurrency_exceeded';
	}): void => {
		removeProps.pendingLoad.abortController.abort();
		pendingByDedupeKey.delete(removeProps.inFlightKey);
		queuedBytes -= removeProps.pendingLoad.byteBudget;
		removeProps.pendingLoad.resolve({ ok: false, reason: removeProps.reason });
	};

	const preemptLowerPriorityInFlightLoads = (preemptProps: {
		readonly byteBudget: number;
		readonly intent: BridgeDemandIntent;
	}): void => {
		let projectedInFlightCount = inFlightByDedupeKey.size;
		let projectedInFlightBytes = inFlightBytes;
		const lowerPriorityLoads = Array.from(inFlightByDedupeKey.values())
			.filter(
				(inFlightLoad: InFlightResourceLoad<TContent>): boolean =>
					!inFlightLoad.abortController.signal.aborted &&
					compareDemandIntentPriority(preemptProps.intent, inFlightLoad.intent) < 0,
			)
			.toSorted(
				(left, right): number =>
					compareDemandIntentPriority(right.intent, left.intent) ||
					right.byteBudget - left.byteBudget,
			);
		for (const inFlightLoad of lowerPriorityLoads) {
			if (
				projectedInFlightCount < props.maxConcurrentLoads &&
				projectedInFlightBytes + preemptProps.byteBudget <= props.maxInFlightBytes
			) {
				return;
			}
			inFlightLoad.abortController.abort();
			projectedInFlightCount -= 1;
			projectedInFlightBytes -= inFlightLoad.byteBudget;
		}
	};

	const canStartLoad = (byteBudget: number): boolean =>
		inFlightByDedupeKey.size < props.maxConcurrentLoads &&
		inFlightBytes + byteBudget <= props.maxInFlightBytes;

	const canQueuePendingLoad = (byteBudget: number): boolean =>
		pendingByDedupeKey.size < props.maxQueuedLoads &&
		queuedBytes + byteBudget <= props.maxQueuedBytes;

	const isIntentFresh = (intent: BridgeDemandIntent): boolean =>
		(props.isFresh ?? (() => true))(intent);

	const startLoad = (startProps: {
		readonly abortController: AbortController;
		readonly byteBudget: number;
		readonly descriptor: BridgeResourceDescriptor;
		readonly inFlightKey: string;
		readonly intent: BridgeDemandIntent;
	}): Promise<BridgeResourceExecutorResult<TContent>> => {
		const promise = runResourceLoad({
			descriptor: startProps.descriptor,
			intent: startProps.intent,
			abortController: startProps.abortController,
			loadResource: props.loadResource,
			isFresh: isIntentFresh,
			onChunk: (chunk): void => {
				props.onChunk?.({
					chunk,
					descriptor: startProps.descriptor,
					intent: startProps.intent,
				});
			},
		}).finally((): void => {
			const activeLoad = inFlightByDedupeKey.get(startProps.inFlightKey);
			if (activeLoad?.promise === promise) {
				inFlightBytes -= activeLoad.byteBudget;
				inFlightByDedupeKey.delete(startProps.inFlightKey);
			}
			pumpPendingLoads();
		});
		inFlightByDedupeKey.set(startProps.inFlightKey, {
			promise,
			abortController: startProps.abortController,
			cancellationGroup: startProps.intent.cancellationGroup,
			byteBudget: startProps.byteBudget,
			intent: startProps.intent,
		});
		inFlightBytes += startProps.byteBudget;
		return promise;
	};

	const pumpPendingLoads = (): void => {
		while (inFlightByDedupeKey.size < props.maxConcurrentLoads) {
			const nextPending = nextStartablePendingLoad({
				pendingLoads: pendingByDedupeKey,
				availableBytes: props.maxInFlightBytes - inFlightBytes,
			});
			if (nextPending === null) {
				return;
			}
			const inFlightKey = makeInFlightKey(nextPending.intent);
			pendingByDedupeKey.delete(inFlightKey);
			queuedBytes -= nextPending.byteBudget;
			if (nextPending.abortController.signal.aborted) {
				nextPending.resolve({ ok: false, reason: 'aborted' });
				continue;
			}
			if (!isIntentFresh(nextPending.intent)) {
				nextPending.resolve({ ok: false, reason: 'stale_completion' });
				continue;
			}
			void startLoad({
				abortController: nextPending.abortController,
				byteBudget: nextPending.byteBudget,
				descriptor: nextPending.descriptor,
				inFlightKey,
				intent: nextPending.intent,
			}).then(nextPending.resolve);
		}
	};

	return {
		load,
		cancelGroup,
		get inFlightCount(): number {
			return inFlightByDedupeKey.size;
		},
		get inFlightBytes(): number {
			return inFlightBytes;
		},
		get maxConcurrentLoads(): number {
			return props.maxConcurrentLoads;
		},
		get maxInFlightBytes(): number {
			return props.maxInFlightBytes;
		},
		get maxQueuedBytes(): number {
			return props.maxQueuedBytes;
		},
		get maxQueuedLoads(): number {
			return props.maxQueuedLoads;
		},
		get queuedLoadCount(): number {
			return pendingByDedupeKey.size;
		},
		get queuedBytes(): number {
			return queuedBytes;
		},
	};
}

async function runResourceLoad<TContent>(props: {
	readonly descriptor: BridgeResourceDescriptor;
	readonly intent: BridgeDemandIntent;
	readonly abortController: AbortController;
	readonly loadResource: BridgeResourceExecutorLoadResource<TContent>;
	readonly isFresh: (intent: BridgeDemandIntent) => boolean;
	readonly onChunk: (chunk: BridgeResourceExecutorStreamChunk) => void;
}): Promise<BridgeResourceExecutorResult<TContent>> {
	if (props.abortController.signal.aborted) {
		return { ok: false, reason: 'aborted' };
	}
	let contentResult: BridgeResourceExecutorContent<TContent>;
	try {
		contentResult = await raceResourceLoadAgainstAbort({
			load: props.loadResource({
				descriptor: props.descriptor,
				intent: props.intent,
				onChunk: props.onChunk,
				signal: props.abortController.signal,
			}),
			signal: props.abortController.signal,
		});
	} catch {
		return props.abortController.signal.aborted
			? { ok: false, reason: 'aborted' }
			: { ok: false, reason: 'load_failed' };
	}
	if (props.abortController.signal.aborted) {
		return { ok: false, reason: 'aborted' };
	}
	if (!props.isFresh(props.intent)) {
		return { ok: false, reason: 'stale_completion' };
	}
	return {
		ok: true,
		authoritative: contentResult.authoritative ?? true,
		content: contentResult.content,
		byteLength: contentResult.byteLength,
		descriptor: props.descriptor,
		freshnessKey: props.intent.freshnessKey,
	};
}

function raceResourceLoadAgainstAbort<TContent>(props: {
	readonly load: Promise<BridgeResourceExecutorContent<TContent>>;
	readonly signal: AbortSignal;
}): Promise<BridgeResourceExecutorContent<TContent>> {
	if (props.signal.aborted) {
		return Promise.reject(new DOMException('Bridge resource load aborted', 'AbortError'));
	}
	return new Promise<BridgeResourceExecutorContent<TContent>>((resolve, reject): void => {
		const rejectAbort = (): void => {
			reject(new DOMException('Bridge resource load aborted', 'AbortError'));
		};
		props.signal.addEventListener('abort', rejectAbort, { once: true });
		void props.load.then(
			(value): void => {
				props.signal.removeEventListener('abort', rejectAbort);
				resolve(value);
			},
			(error: unknown): void => {
				props.signal.removeEventListener('abort', rejectAbort);
				reject(error);
			},
		);
	});
}

function makeInFlightKey(intent: BridgeDemandIntent): string {
	return `${intent.dedupeKey}\u0000${intent.freshnessKey}`;
}

function nextStartablePendingLoad<TContent>(props: {
	readonly pendingLoads: ReadonlyMap<string, PendingResourceLoad<TContent>>;
	readonly availableBytes: number;
}): PendingResourceLoad<TContent> | null {
	return (
		Array.from(props.pendingLoads.values())
			.filter(
				(pendingLoad: PendingResourceLoad<TContent>): boolean =>
					pendingLoad.byteBudget <= props.availableBytes,
			)
			.toSorted(comparePendingResourceLoads)[0] ?? null
	);
}

function comparePendingResourceLoads<TContent>(
	left: PendingResourceLoad<TContent>,
	right: PendingResourceLoad<TContent>,
): number {
	const intentPriorityComparison = compareDemandIntentPriority(left.intent, right.intent);
	if (intentPriorityComparison !== 0) {
		return intentPriorityComparison;
	}
	return left.sequence - right.sequence;
}

function compareDemandIntentPriority(left: BridgeDemandIntent, right: BridgeDemandIntent): number {
	const laneComparison = demandLaneOrder.indexOf(left.lane) - demandLaneOrder.indexOf(right.lane);
	if (laneComparison !== 0) {
		return laneComparison;
	}
	return left.orderingKey.localeCompare(right.orderingKey);
}

function canQueueUnderPressure(intent: BridgeDemandIntent): boolean {
	return intent.lane === 'foreground' || intent.lane === 'active';
}
