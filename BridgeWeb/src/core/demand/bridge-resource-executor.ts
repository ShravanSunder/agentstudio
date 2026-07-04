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
	readonly classifyLoadFailure?: (error: unknown) => BridgeResourceExecutorLoadFailureKind | null;
	readonly isFresh?: (intent: BridgeDemandIntent) => boolean;
	readonly now?: () => number;
	readonly onLifecycleEvent?: (event: BridgeResourceExecutorLifecycleEvent) => void;
	readonly onChunk?: (props: {
		readonly chunk: BridgeResourceExecutorStreamChunk;
		readonly descriptor: BridgeResourceDescriptor;
		readonly intent: BridgeDemandIntent;
	}) => void;
}

export interface BridgeResourceExecutorLoadOptions {
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
			readonly loadFailureKind?: BridgeResourceExecutorLoadFailureKind;
	  };

export type BridgeResourceExecutorLoadFailureKind =
	| 'http_error'
	| 'missing_body'
	| 'byte_limit_exceeded'
	| 'integrity_mismatch'
	| 'chunk_manifest_unsupported';

export interface BridgeResourceExecutor<TContent = unknown> {
	load(
		intent: BridgeDemandIntent,
		options?: BridgeResourceExecutorLoadOptions,
	): Promise<BridgeResourceExecutorResult<TContent>>;
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

export type BridgeResourceExecutorLifecycleResult =
	| 'success'
	| 'descriptor_missing'
	| 'byte_budget_exceeded'
	| 'concurrency_exceeded'
	| 'load_failed'
	| 'stale_completion'
	| 'aborted';

export type BridgeResourceExecutorLifecycleEvent =
	| {
			readonly byteBudget: number;
			readonly intent: BridgeDemandIntent;
			readonly kind: 'queued';
			readonly pendingEnteredAtMilliseconds: number;
			readonly queuedBytesAfter: number;
			readonly queuedLoadCountAfter: number;
	  }
	| {
			readonly byteBudget: number;
			readonly inFlightBytesAfter: number;
			readonly inFlightCountAfter: number;
			readonly intent: BridgeDemandIntent;
			readonly kind: 'started';
			readonly pendingEnteredAtMilliseconds: number;
			readonly pendingWaitMilliseconds: number;
			readonly startedAtMilliseconds: number;
	  }
	| {
			readonly completedAtMilliseconds: number;
			readonly inFlightMilliseconds: number;
			readonly intent: BridgeDemandIntent;
			readonly kind: 'completed';
			readonly result: BridgeResourceExecutorLifecycleResult;
			readonly startedAtMilliseconds: number;
	  };

interface InFlightResourceLoad<TContent> {
	readonly promise: Promise<BridgeResourceExecutorResult<TContent>>;
	readonly abortController: AbortController;
	readonly cancellationGroups: Set<string>;
	readonly byteBudget: number;
	intent: BridgeDemandIntent;
}

interface PendingResourceLoad<TContent> {
	readonly intent: BridgeDemandIntent;
	readonly descriptor: BridgeResourceDescriptor;
	readonly promise: Promise<BridgeResourceExecutorResult<TContent>>;
	readonly abortController: AbortController;
	readonly byteBudget: number;
	readonly loadOptions: BridgeResourceExecutorLoadOptions;
	readonly pendingEnteredAtMilliseconds: number;
	readonly resolve: (result: BridgeResourceExecutorResult<TContent>) => void;
	readonly sequence: number;
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
	const now = props.now ?? defaultNow;

	const load = async (
		intent: BridgeDemandIntent,
		options: BridgeResourceExecutorLoadOptions = {},
	): Promise<BridgeResourceExecutorResult<TContent>> => {
		const inFlightKey = makeInFlightKey(intent);
		const existingLoad = inFlightByDedupeKey.get(inFlightKey);
		if (existingLoad !== undefined) {
			existingLoad.cancellationGroups.add(intent.cancellationGroup);
			if (compareDemandIntentPriority(intent, existingLoad.intent) < 0) {
				existingLoad.intent = intent;
			}
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
			const pendingEnteredAtMilliseconds = now();
			return await startLoad({
				abortController,
				byteBudget,
				descriptor,
				inFlightKey,
				intent,
				loadOptions: options,
				pendingEnteredAtMilliseconds,
			});
		}
		preemptLowerPriorityInFlightLoads({ byteBudget, intent });
		if (canStartLoad(byteBudget)) {
			const pendingEnteredAtMilliseconds = now();
			return await startLoad({
				abortController,
				byteBudget,
				descriptor,
				inFlightKey,
				intent,
				loadOptions: options,
				pendingEnteredAtMilliseconds,
			});
		}
		const pendingEnteredAtMilliseconds = now();
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
			loadOptions: options,
			pendingEnteredAtMilliseconds,
			resolve: resolvePending,
			sequence: nextPendingSequence,
		});
		queuedBytes += byteBudget;
		nextPendingSequence += 1;
		props.onLifecycleEvent?.({
			byteBudget,
			intent,
			kind: 'queued',
			pendingEnteredAtMilliseconds,
			queuedBytesAfter: queuedBytes,
			queuedLoadCountAfter: pendingByDedupeKey.size,
		});
		pumpPendingLoads();
		return await promise;
	};

	const cancelGroup = (cancellationGroup: string): number => {
		let cancelledCount = 0;
		for (const inFlightLoad of inFlightByDedupeKey.values()) {
			if (!inFlightLoad.cancellationGroups.has(cancellationGroup)) {
				continue;
			}
			inFlightLoad.cancellationGroups.delete(cancellationGroup);
			if (inFlightLoad.cancellationGroups.size === 0) {
				inFlightLoad.abortController.abort();
			}
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

	const preemptLowerPriorityInFlightLoads = (preemptProps: {
		readonly byteBudget: number;
		readonly intent: BridgeDemandIntent;
	}): void => {
		let projectedInFlightCount = inFlightByDedupeKey.size;
		let projectedInFlightBytes = inFlightBytes;
		const lowerPriorityLoads = Array.from(inFlightByDedupeKey.entries())
			.filter(
				([, inFlightLoad]): boolean =>
					!inFlightLoad.abortController.signal.aborted &&
					compareDemandIntentPriority(preemptProps.intent, inFlightLoad.intent) < 0,
			)
			.toSorted(([, left], [, right]): number => {
				const priorityComparison = compareDemandIntentPriority(right.intent, left.intent);
				return priorityComparison === 0 ? right.byteBudget - left.byteBudget : priorityComparison;
			});
		for (const [inFlightKey, inFlightLoad] of lowerPriorityLoads) {
			if (
				projectedInFlightCount < props.maxConcurrentLoads &&
				projectedInFlightBytes + preemptProps.byteBudget <= props.maxInFlightBytes
			) {
				return;
			}
			inFlightLoad.abortController.abort();
			if (inFlightByDedupeKey.get(inFlightKey) === inFlightLoad) {
				inFlightByDedupeKey.delete(inFlightKey);
				inFlightBytes -= inFlightLoad.byteBudget;
			}
			projectedInFlightCount -= 1;
			projectedInFlightBytes -= inFlightLoad.byteBudget;
		}
	};

	const canStartLoad = (byteBudget: number): boolean =>
		inFlightByDedupeKey.size < props.maxConcurrentLoads &&
		inFlightBytes + byteBudget <= props.maxInFlightBytes;

	const isIntentFresh = (intent: BridgeDemandIntent): boolean =>
		(props.isFresh ?? (() => true))(intent);

	const startLoad = (startProps: {
		readonly abortController: AbortController;
		readonly byteBudget: number;
		readonly descriptor: BridgeResourceDescriptor;
		readonly inFlightKey: string;
		readonly intent: BridgeDemandIntent;
		readonly loadOptions: BridgeResourceExecutorLoadOptions;
		readonly pendingEnteredAtMilliseconds: number;
	}): Promise<BridgeResourceExecutorResult<TContent>> => {
		const startedAtMilliseconds = now();
		const promise = runResourceLoad({
			descriptor: startProps.descriptor,
			intent: startProps.intent,
			abortController: startProps.abortController,
			loadResource: props.loadResource,
			classifyLoadFailure: props.classifyLoadFailure,
			isFresh: isIntentFresh,
			onChunk: (chunk): void => {
				const chunkProps = {
					chunk,
					descriptor: startProps.descriptor,
					intent: startProps.intent,
				} as const;
				props.onChunk?.(chunkProps);
				startProps.loadOptions.onChunk?.(chunkProps);
			},
		})
			.then((result): BridgeResourceExecutorResult<TContent> => {
				const completedAtMilliseconds = now();
				props.onLifecycleEvent?.({
					completedAtMilliseconds,
					inFlightMilliseconds: Math.max(0, completedAtMilliseconds - startedAtMilliseconds),
					intent: startProps.intent,
					kind: 'completed',
					result: executorLifecycleResult(result),
					startedAtMilliseconds,
				});
				return result;
			})
			.finally((): void => {
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
			cancellationGroups: new Set([startProps.intent.cancellationGroup]),
			byteBudget: startProps.byteBudget,
			intent: startProps.intent,
		});
		inFlightBytes += startProps.byteBudget;
		props.onLifecycleEvent?.({
			byteBudget: startProps.byteBudget,
			inFlightBytesAfter: inFlightBytes,
			inFlightCountAfter: inFlightByDedupeKey.size,
			intent: startProps.intent,
			kind: 'started',
			pendingEnteredAtMilliseconds: startProps.pendingEnteredAtMilliseconds,
			pendingWaitMilliseconds: Math.max(
				0,
				startedAtMilliseconds - startProps.pendingEnteredAtMilliseconds,
			),
			startedAtMilliseconds,
		});
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
				loadOptions: nextPending.loadOptions,
				pendingEnteredAtMilliseconds: nextPending.pendingEnteredAtMilliseconds,
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
	readonly classifyLoadFailure:
		| ((error: unknown) => BridgeResourceExecutorLoadFailureKind | null)
		| undefined;
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
	} catch (error: unknown) {
		if (props.abortController.signal.aborted || isAbortLikeResourceLoadError(error)) {
			return { ok: false, reason: 'aborted' };
		}
		const loadFailureKind = props.classifyLoadFailure?.(error) ?? null;
		return loadFailureKind === null
			? { ok: false, reason: 'load_failed' }
			: { ok: false, reason: 'load_failed', loadFailureKind };
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

function isAbortLikeResourceLoadError(error: unknown): boolean {
	if (error instanceof DOMException && error.name === 'AbortError') {
		return true;
	}
	if (error instanceof Error) {
		return error.name === 'AbortError' || error.message.toLowerCase().includes('aborted');
	}
	return false;
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
	const leftDemandRank = left.demandRank ?? Number.MAX_SAFE_INTEGER;
	const rightDemandRank = right.demandRank ?? Number.MAX_SAFE_INTEGER;
	const demandRankComparison = leftDemandRank - rightDemandRank;
	if (demandRankComparison !== 0) {
		return demandRankComparison;
	}
	const laneComparison = demandLaneOrder.indexOf(left.lane) - demandLaneOrder.indexOf(right.lane);
	if (laneComparison !== 0) {
		return laneComparison;
	}
	return left.orderingKey.localeCompare(right.orderingKey);
}

function executorLifecycleResult<TContent>(
	result: BridgeResourceExecutorResult<TContent>,
): BridgeResourceExecutorLifecycleResult {
	return result.ok ? 'success' : result.reason;
}

function defaultNow(): number {
	return globalThis.performance?.now() ?? Date.now();
}
