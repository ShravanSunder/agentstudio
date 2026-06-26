import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type { BridgeResourceDescriptor } from '../models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';

export interface BridgeResourceExecutorLoadResourceProps {
	readonly descriptor: BridgeResourceDescriptor;
	readonly intent: BridgeDemandIntent;
	readonly signal: AbortSignal;
}

export interface BridgeResourceExecutorBody<TBody = unknown> {
	readonly body: TBody;
	readonly byteLength: number;
}

export type BridgeResourceExecutorLoadResource<TBody = unknown> = (
	props: BridgeResourceExecutorLoadResourceProps,
) => Promise<BridgeResourceExecutorBody<TBody>>;

export interface BridgeResourceExecutorProps<TBody = unknown> {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly maxConcurrentLoads: number;
	readonly maxInFlightBytes: number;
	readonly maxQueuedLoads: number;
	readonly maxQueuedBytes: number;
	readonly loadResource: BridgeResourceExecutorLoadResource<TBody>;
	readonly isFresh?: (intent: BridgeDemandIntent) => boolean;
}

export type BridgeResourceExecutorResult<TBody = unknown> =
	| {
			readonly ok: true;
			readonly body: TBody;
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

export interface BridgeResourceExecutor<TBody = unknown> {
	load(intent: BridgeDemandIntent): Promise<BridgeResourceExecutorResult<TBody>>;
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

interface InFlightResourceLoad<TBody> {
	readonly promise: Promise<BridgeResourceExecutorResult<TBody>>;
	readonly abortController: AbortController;
	readonly cancellationGroup: string;
	readonly byteBudget: number;
	readonly intent: BridgeDemandIntent;
}

interface PendingResourceLoad<TBody> {
	readonly intent: BridgeDemandIntent;
	readonly descriptor: BridgeResourceDescriptor;
	readonly promise: Promise<BridgeResourceExecutorResult<TBody>>;
	readonly abortController: AbortController;
	readonly byteBudget: number;
	readonly resolve: (result: BridgeResourceExecutorResult<TBody>) => void;
	readonly sequence: number;
}

interface PendingResourceLoadEntry<TBody> {
	readonly inFlightKey: string;
	readonly pendingLoad: PendingResourceLoad<TBody>;
}

const demandLaneOrder = [
	'foreground',
	'active',
	'visible',
	'nearby',
	'speculative',
	'idle',
] as const satisfies readonly BridgeDemandIntent['lane'][];

export function createBridgeResourceExecutor<TBody = unknown>(
	props: BridgeResourceExecutorProps<TBody>,
): BridgeResourceExecutor<TBody> {
	const inFlightByDedupeKey = new Map<string, InFlightResourceLoad<TBody>>();
	const pendingByDedupeKey = new Map<string, PendingResourceLoad<TBody>>();
	let nextPendingSequence = 0;
	let inFlightBytes = 0;
	let queuedBytes = 0;

	const load = async (intent: BridgeDemandIntent): Promise<BridgeResourceExecutorResult<TBody>> => {
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
		let resolvePending: ((result: BridgeResourceExecutorResult<TBody>) => void) | null = null;
		const promise = new Promise<BridgeResourceExecutorResult<TBody>>((resolve): void => {
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
	): PendingResourceLoadEntry<TBody> | null =>
		Array.from(pendingByDedupeKey.entries())
			.map(
				([inFlightKey, pendingLoad]): PendingResourceLoadEntry<TBody> => ({
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
		readonly pendingLoad: PendingResourceLoad<TBody>;
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
				(inFlightLoad: InFlightResourceLoad<TBody>): boolean =>
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
	}): Promise<BridgeResourceExecutorResult<TBody>> => {
		const promise = runResourceLoad({
			descriptor: startProps.descriptor,
			intent: startProps.intent,
			abortController: startProps.abortController,
			loadResource: props.loadResource,
			isFresh: isIntentFresh,
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

async function runResourceLoad<TBody>(props: {
	readonly descriptor: BridgeResourceDescriptor;
	readonly intent: BridgeDemandIntent;
	readonly abortController: AbortController;
	readonly loadResource: BridgeResourceExecutorLoadResource<TBody>;
	readonly isFresh: (intent: BridgeDemandIntent) => boolean;
}): Promise<BridgeResourceExecutorResult<TBody>> {
	if (props.abortController.signal.aborted) {
		return { ok: false, reason: 'aborted' };
	}
	let loadedBody: BridgeResourceExecutorBody<TBody>;
	try {
		loadedBody = await raceResourceLoadAgainstAbort({
			load: props.loadResource({
				descriptor: props.descriptor,
				intent: props.intent,
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
		body: loadedBody.body,
		byteLength: loadedBody.byteLength,
		descriptor: props.descriptor,
		freshnessKey: props.intent.freshnessKey,
	};
}

function raceResourceLoadAgainstAbort<TBody>(props: {
	readonly load: Promise<BridgeResourceExecutorBody<TBody>>;
	readonly signal: AbortSignal;
}): Promise<BridgeResourceExecutorBody<TBody>> {
	if (props.signal.aborted) {
		return Promise.reject(new DOMException('Bridge resource load aborted', 'AbortError'));
	}
	return new Promise<BridgeResourceExecutorBody<TBody>>((resolve, reject): void => {
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

function nextStartablePendingLoad<TBody>(props: {
	readonly pendingLoads: ReadonlyMap<string, PendingResourceLoad<TBody>>;
	readonly availableBytes: number;
}): PendingResourceLoad<TBody> | null {
	return (
		Array.from(props.pendingLoads.values())
			.filter(
				(pendingLoad: PendingResourceLoad<TBody>): boolean =>
					pendingLoad.byteBudget <= props.availableBytes,
			)
			.toSorted(comparePendingResourceLoads)[0] ?? null
	);
}

function comparePendingResourceLoads<TBody>(
	left: PendingResourceLoad<TBody>,
	right: PendingResourceLoad<TBody>,
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
