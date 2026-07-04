import type { BridgeDemandIntent } from '../models/bridge-demand-models.js';
import type { BridgeResourceDescriptor } from '../models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../resources/bridge-resource-registry.js';
import { bridgeContentDemandExecutionPolicy } from './bridge-content-demand-policy.js';

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
	readonly eligibleAtMilliseconds: number;
	readonly loadOptions: BridgeResourceExecutorLoadOptions;
	readonly pendingEnteredAtMilliseconds: number;
	readonly resolve: (result: BridgeResourceExecutorResult<TContent>) => void;
	readonly sequence: number;
}

interface DeliveryFailureBackoffFact {
	readonly attemptCount: number;
	readonly retryEligibleAtMilliseconds: number;
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
	let pendingPumpTimer: ReturnType<typeof setTimeout> | null = null;
	const now = props.now ?? defaultNow;
	const deliveryFailureBackoffByInFlightKey = new Map<string, DeliveryFailureBackoffFact>();

	const load = (
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
			return existingLoad.promise;
		}
		const existingPendingLoad = pendingByDedupeKey.get(inFlightKey);
		if (existingPendingLoad !== undefined) {
			let promotedPendingLoad = existingPendingLoad;
			if (compareDemandIntentPriority(intent, existingPendingLoad.intent) < 0) {
				promotedPendingLoad = {
					...existingPendingLoad,
					intent,
					sequence: nextPendingSequence,
				};
				pendingByDedupeKey.set(inFlightKey, promotedPendingLoad);
				nextPendingSequence += 1;
				if (promotedPendingLoad.eligibleAtMilliseconds <= now() && isIntentFresh(intent)) {
					preemptLowerPriorityInFlightLoads({
						byteBudget: promotedPendingLoad.byteBudget,
						intent,
					});
					pumpPendingLoads();
				}
			}
			return promotedPendingLoad.promise;
		}
		const descriptor = props.registry.lookup(intent.descriptorRef);
		if (descriptor === null) {
			return Promise.resolve({ ok: false, reason: 'descriptor_missing' });
		}
		const byteBudget = descriptor.content.expectedBytes ?? descriptor.content.maxBytes;
		if (byteBudget > props.maxInFlightBytes) {
			return Promise.resolve({ ok: false, reason: 'byte_budget_exceeded' });
		}
		if (!isIntentFresh(intent)) {
			return Promise.resolve({ ok: false, reason: 'stale_completion' });
		}
		const abortController = new AbortController();
		const retryEligibleAtMilliseconds = deliveryFailureRetryEligibleAtMilliseconds({
			deliveryFailureBackoffByInFlightKey,
			inFlightKey,
			nowMilliseconds: now(),
		});
		if (retryEligibleAtMilliseconds !== null) {
			return enqueuePendingLoad({
				abortController,
				byteBudget,
				descriptor,
				eligibleAtMilliseconds: retryEligibleAtMilliseconds,
				inFlightKey,
				intent,
				loadOptions: options,
				pendingEnteredAtMilliseconds: now(),
			});
		}
		if (canStartLoad(byteBudget)) {
			const pendingEnteredAtMilliseconds = now();
			return startLoad({
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
			return startLoad({
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
		return enqueuePendingLoad({
			abortController,
			byteBudget,
			descriptor,
			eligibleAtMilliseconds: pendingEnteredAtMilliseconds,
			inFlightKey,
			intent,
			loadOptions: options,
			pendingEnteredAtMilliseconds,
		});
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
		schedulePendingPump();
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
				updateDeliveryFailureBackoff({
					deliveryFailureBackoffByInFlightKey,
					inFlightKey: startProps.inFlightKey,
					nowMilliseconds: completedAtMilliseconds,
					result,
				});
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

	const enqueuePendingLoad = (enqueueProps: {
		readonly abortController: AbortController;
		readonly byteBudget: number;
		readonly descriptor: BridgeResourceDescriptor;
		readonly eligibleAtMilliseconds: number;
		readonly inFlightKey: string;
		readonly intent: BridgeDemandIntent;
		readonly loadOptions: BridgeResourceExecutorLoadOptions;
		readonly pendingEnteredAtMilliseconds: number;
	}): Promise<BridgeResourceExecutorResult<TContent>> => {
		let resolvePending: ((result: BridgeResourceExecutorResult<TContent>) => void) | null = null;
		const promise = new Promise<BridgeResourceExecutorResult<TContent>>((resolve): void => {
			resolvePending = resolve;
		});
		if (resolvePending === null) {
			throw new Error('Pending Bridge resource load was not initialized.');
		}
		pendingByDedupeKey.set(enqueueProps.inFlightKey, {
			intent: enqueueProps.intent,
			descriptor: enqueueProps.descriptor,
			promise,
			abortController: enqueueProps.abortController,
			byteBudget: enqueueProps.byteBudget,
			eligibleAtMilliseconds: enqueueProps.eligibleAtMilliseconds,
			loadOptions: enqueueProps.loadOptions,
			pendingEnteredAtMilliseconds: enqueueProps.pendingEnteredAtMilliseconds,
			resolve: resolvePending,
			sequence: nextPendingSequence,
		});
		queuedBytes += enqueueProps.byteBudget;
		nextPendingSequence += 1;
		props.onLifecycleEvent?.({
			byteBudget: enqueueProps.byteBudget,
			intent: enqueueProps.intent,
			kind: 'queued',
			pendingEnteredAtMilliseconds: enqueueProps.pendingEnteredAtMilliseconds,
			queuedBytesAfter: queuedBytes,
			queuedLoadCountAfter: pendingByDedupeKey.size,
		});
		pumpPendingLoads();
		return promise;
	};

	const pumpPendingLoads = (): void => {
		if (pendingPumpTimer !== null) {
			clearTimeout(pendingPumpTimer);
			pendingPumpTimer = null;
		}
		while (inFlightByDedupeKey.size < props.maxConcurrentLoads) {
			const nextPending = nextStartablePendingLoad({
				nowMilliseconds: now(),
				pendingLoads: pendingByDedupeKey,
				availableBytes: props.maxInFlightBytes - inFlightBytes,
			});
			if (nextPending === null) {
				schedulePendingPump();
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
			if (nextPending.eligibleAtMilliseconds > now()) {
				pendingByDedupeKey.set(inFlightKey, nextPending);
				queuedBytes += nextPending.byteBudget;
				schedulePendingPump();
				return;
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

	const schedulePendingPump = (): void => {
		if (pendingPumpTimer !== null || pendingByDedupeKey.size === 0) {
			return;
		}
		const nextEligibleAtMilliseconds = nextPendingEligibilityMilliseconds({
			pendingLoads: pendingByDedupeKey,
			availableBytes: props.maxInFlightBytes - inFlightBytes,
			nowMilliseconds: now(),
		});
		if (nextEligibleAtMilliseconds === null) {
			return;
		}
		const delayMilliseconds = Math.max(0, nextEligibleAtMilliseconds - now());
		pendingPumpTimer = setTimeout((): void => {
			pendingPumpTimer = null;
			pumpPendingLoads();
		}, delayMilliseconds);
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
	readonly nowMilliseconds: number;
}): PendingResourceLoad<TContent> | null {
	return (
		Array.from(props.pendingLoads.values())
			.filter(
				(pendingLoad: PendingResourceLoad<TContent>): boolean =>
					pendingLoad.byteBudget <= props.availableBytes &&
					pendingLoad.eligibleAtMilliseconds <= props.nowMilliseconds,
			)
			.toSorted(comparePendingResourceLoads)[0] ?? null
	);
}

function nextPendingEligibilityMilliseconds<TContent>(props: {
	readonly pendingLoads: ReadonlyMap<string, PendingResourceLoad<TContent>>;
	readonly availableBytes: number;
	readonly nowMilliseconds: number;
}): number | null {
	let nextEligibleAtMilliseconds: number | null = null;
	for (const pendingLoad of props.pendingLoads.values()) {
		if (pendingLoad.byteBudget > props.availableBytes) {
			continue;
		}
		if (pendingLoad.eligibleAtMilliseconds <= props.nowMilliseconds) {
			return props.nowMilliseconds;
		}
		nextEligibleAtMilliseconds =
			nextEligibleAtMilliseconds === null
				? pendingLoad.eligibleAtMilliseconds
				: Math.min(nextEligibleAtMilliseconds, pendingLoad.eligibleAtMilliseconds);
	}
	return nextEligibleAtMilliseconds;
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

function deliveryFailureRetryEligibleAtMilliseconds(props: {
	readonly deliveryFailureBackoffByInFlightKey: ReadonlyMap<string, DeliveryFailureBackoffFact>;
	readonly inFlightKey: string;
	readonly nowMilliseconds: number;
}): number | null {
	const backoffFact = props.deliveryFailureBackoffByInFlightKey.get(props.inFlightKey);
	if (
		backoffFact === undefined ||
		backoffFact.retryEligibleAtMilliseconds <= props.nowMilliseconds
	) {
		return null;
	}
	return backoffFact.retryEligibleAtMilliseconds;
}

function updateDeliveryFailureBackoff<TContent>(props: {
	readonly deliveryFailureBackoffByInFlightKey: Map<string, DeliveryFailureBackoffFact>;
	readonly inFlightKey: string;
	readonly nowMilliseconds: number;
	readonly result: BridgeResourceExecutorResult<TContent>;
}): void {
	if (props.result.ok) {
		props.deliveryFailureBackoffByInFlightKey.delete(props.inFlightKey);
		return;
	}
	if (props.result.reason !== 'load_failed') {
		return;
	}
	const previousAttemptCount =
		props.deliveryFailureBackoffByInFlightKey.get(props.inFlightKey)?.attemptCount ?? 0;
	const attemptCount = previousAttemptCount + 1;
	props.deliveryFailureBackoffByInFlightKey.set(props.inFlightKey, {
		attemptCount,
		retryEligibleAtMilliseconds:
			props.nowMilliseconds + deliveryFailureBackoffDelayMilliseconds(attemptCount),
	});
}

function deliveryFailureBackoffDelayMilliseconds(attemptCount: number): number {
	const multiplierExponent = Math.max(0, attemptCount - 1);
	const delayMilliseconds =
		bridgeContentDemandExecutionPolicy.deliveryFailureBackoffInitialMilliseconds *
		bridgeContentDemandExecutionPolicy.deliveryFailureBackoffMultiplier ** multiplierExponent;
	return Math.min(
		delayMilliseconds,
		bridgeContentDemandExecutionPolicy.deliveryFailureBackoffMaxMilliseconds,
	);
}

function defaultNow(): number {
	return globalThis.performance?.now() ?? Date.now();
}
