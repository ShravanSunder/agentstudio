import type { BridgeDemandIntent, BridgeDemandLane } from '../models/bridge-demand-models.js';

export interface BridgeDemandSchedulerProps {
	readonly maxQueuedIntentsPerLane: number;
	readonly maxQueuedEstimatedBytes: number;
	readonly now?: () => number;
	readonly onLifecycleEvent?: (event: BridgeDemandSchedulerLifecycleEvent) => void;
}

export interface BridgeDemandSchedulerEnqueueProps {
	readonly intent: BridgeDemandIntent;
	readonly estimatedBytes?: number;
}

export type BridgeDemandSchedulerEnqueueResult =
	| {
			readonly ok: true;
			readonly status: 'queued' | 'replaced';
			readonly droppedLowerPriorityCount?: number;
	  }
	| {
			readonly ok: false;
			readonly reason: 'lane_queue_full' | 'queued_byte_limit_exceeded';
	  };

export type BridgeDemandSchedulerLifecycleEvent =
	| {
			readonly estimatedBytes: number;
			readonly intent: BridgeDemandIntent;
			readonly kind: 'enqueued';
			readonly lane: BridgeDemandLane;
			readonly queueDepthAfter: number;
			readonly queuedAtMilliseconds: number;
			readonly queuedEstimatedBytesAfter: number;
			readonly status: 'queued' | 'replaced';
	  }
	| {
			readonly dequeuedAtMilliseconds: number;
			readonly estimatedBytes: number;
			readonly intent: BridgeDemandIntent;
			readonly kind: 'dequeued';
			readonly lane: BridgeDemandLane;
			readonly queueDepthAfter: number;
			readonly queueWaitMilliseconds: number;
			readonly queuedAtMilliseconds: number;
			readonly queuedEstimatedBytesAfter: number;
	  };

export interface BridgeDemandScheduler {
	enqueue(props: BridgeDemandSchedulerEnqueueProps): BridgeDemandSchedulerEnqueueResult;
	dequeueNext(): BridgeDemandIntent | null;
	dequeueNextMatching(
		predicate: (intent: BridgeDemandIntent) => boolean,
	): BridgeDemandIntent | null;
	cancelGroup(cancellationGroup: string): number;
	readonly maxQueuedEstimatedBytes: number;
	readonly maxQueuedIntentsPerLane: number;
	readonly queuedIntentCount: number;
	readonly queuedEstimatedBytes: number;
}

interface QueuedDemandIntent {
	readonly intent: BridgeDemandIntent;
	readonly estimatedBytes: number;
	readonly queuedAtMilliseconds: number;
	readonly sequence: number;
}

const demandLaneOrder = [
	'foreground',
	'active',
	'visible',
	'nearby',
	'speculative',
	'idle',
] as const satisfies readonly BridgeDemandLane[];

export function createBridgeDemandScheduler(
	props: BridgeDemandSchedulerProps,
): BridgeDemandScheduler {
	const queuedIntentsByLane = new Map<BridgeDemandLane, QueuedDemandIntent[]>(
		demandLaneOrder.map((lane): readonly [BridgeDemandLane, QueuedDemandIntent[]] => [lane, []]),
	);
	let nextSequence = 0;
	let queuedEstimatedBytes = 0;
	const now = props.now ?? defaultNow;

	const removeQueuedIntent = (queuedIntent: QueuedDemandIntent): void => {
		const laneQueue = queuedIntentsByLane.get(queuedIntent.intent.lane);
		if (laneQueue === undefined) {
			return;
		}
		const queuedIndex = laneQueue.indexOf(queuedIntent);
		if (queuedIndex >= 0) {
			laneQueue.splice(queuedIndex, 1);
			queuedEstimatedBytes -= queuedIntent.estimatedBytes;
		}
	};

	const findByDedupeKey = (dedupeKey: string): QueuedDemandIntent | null => {
		for (const laneQueue of queuedIntentsByLane.values()) {
			const queuedIntent = laneQueue.find(
				(candidate: QueuedDemandIntent): boolean => candidate.intent.dedupeKey === dedupeKey,
			);
			if (queuedIntent !== undefined) {
				return queuedIntent;
			}
		}
		return null;
	};

	const countQueuedIntents = (): number => {
		let count = 0;
		for (const laneQueue of queuedIntentsByLane.values()) {
			count += laneQueue.length;
		}
		return count;
	};

	const enqueue = (
		enqueueProps: BridgeDemandSchedulerEnqueueProps,
	): BridgeDemandSchedulerEnqueueResult => {
		const estimatedBytes = enqueueProps.estimatedBytes ?? 0;
		const existingIntent = findByDedupeKey(enqueueProps.intent.dedupeKey);
		const replacedExistingIntent = existingIntent !== null;
		if (existingIntent !== null) {
			removeQueuedIntent(existingIntent);
		}
		let droppedLowerPriorityCount = 0;
		while (queuedEstimatedBytes + estimatedBytes > props.maxQueuedEstimatedBytes) {
			const droppedIntent = dropLowestPriorityIntentBelow(enqueueProps.intent.lane);
			if (droppedIntent === null) {
				if (replacedExistingIntent) {
					insertQueuedIntent(existingIntent);
				}
				return { ok: false, reason: 'queued_byte_limit_exceeded' };
			}
			droppedLowerPriorityCount += 1;
		}
		const laneQueue = queuedIntentsByLane.get(enqueueProps.intent.lane);
		if (laneQueue === undefined || laneQueue.length >= props.maxQueuedIntentsPerLane) {
			if (replacedExistingIntent) {
				insertQueuedIntent(existingIntent);
			}
			return { ok: false, reason: 'lane_queue_full' };
		}
		const queuedAtMilliseconds = now();
		const status = replacedExistingIntent ? 'replaced' : 'queued';
		insertQueuedIntent({
			intent: enqueueProps.intent,
			estimatedBytes,
			queuedAtMilliseconds,
			sequence: nextSequence,
		});
		nextSequence += 1;
		props.onLifecycleEvent?.({
			estimatedBytes,
			intent: enqueueProps.intent,
			kind: 'enqueued',
			lane: enqueueProps.intent.lane,
			queueDepthAfter: countQueuedIntents(),
			queuedAtMilliseconds,
			queuedEstimatedBytesAfter: queuedEstimatedBytes,
			status,
		});
		return {
			ok: true,
			status,
			...(droppedLowerPriorityCount === 0 ? {} : { droppedLowerPriorityCount }),
		};
	};

	const insertQueuedIntent = (queuedIntent: QueuedDemandIntent): void => {
		const laneQueue = queuedIntentsByLane.get(queuedIntent.intent.lane);
		if (laneQueue === undefined) {
			return;
		}
		laneQueue.push(queuedIntent);
		laneQueue.sort(compareQueuedDemandIntents);
		queuedEstimatedBytes += queuedIntent.estimatedBytes;
	};

	const dropLowestPriorityIntentBelow = (lane: BridgeDemandLane): QueuedDemandIntent | null => {
		const lanePriority = demandLaneOrder.indexOf(lane);
		for (let laneIndex = demandLaneOrder.length - 1; laneIndex > lanePriority; laneIndex -= 1) {
			const candidateLane = demandLaneOrder[laneIndex];
			if (candidateLane === undefined) {
				continue;
			}
			const laneQueue = queuedIntentsByLane.get(candidateLane);
			const queuedIntent = laneQueue?.shift() ?? null;
			if (queuedIntent !== null) {
				queuedEstimatedBytes -= queuedIntent.estimatedBytes;
				return queuedIntent;
			}
		}
		return null;
	};

	const dequeueNext = (): BridgeDemandIntent | null => {
		for (const lane of demandLaneOrder) {
			const laneQueue = queuedIntentsByLane.get(lane);
			const queuedIntent = laneQueue?.shift() ?? null;
			if (queuedIntent !== null) {
				return dequeueQueuedIntent(queuedIntent);
			}
		}
		return null;
	};

	const dequeueNextMatching = (
		predicate: (intent: BridgeDemandIntent) => boolean,
	): BridgeDemandIntent | null => {
		for (const lane of demandLaneOrder) {
			const laneQueue = queuedIntentsByLane.get(lane);
			if (laneQueue === undefined) {
				continue;
			}
			const queuedIndex = laneQueue.findIndex((queuedIntent): boolean =>
				predicate(queuedIntent.intent),
			);
			if (queuedIndex < 0) {
				continue;
			}
			const queuedIntent = laneQueue[queuedIndex];
			if (queuedIntent === undefined) {
				continue;
			}
			laneQueue.splice(queuedIndex, 1);
			return dequeueQueuedIntent(queuedIntent);
		}
		return null;
	};

	const dequeueQueuedIntent = (queuedIntent: QueuedDemandIntent): BridgeDemandIntent => {
		queuedEstimatedBytes -= queuedIntent.estimatedBytes;
		const dequeuedAtMilliseconds = now();
		props.onLifecycleEvent?.({
			dequeuedAtMilliseconds,
			estimatedBytes: queuedIntent.estimatedBytes,
			intent: queuedIntent.intent,
			kind: 'dequeued',
			lane: queuedIntent.intent.lane,
			queueDepthAfter: countQueuedIntents(),
			queueWaitMilliseconds: Math.max(
				0,
				dequeuedAtMilliseconds - queuedIntent.queuedAtMilliseconds,
			),
			queuedAtMilliseconds: queuedIntent.queuedAtMilliseconds,
			queuedEstimatedBytesAfter: queuedEstimatedBytes,
		});
		return queuedIntent.intent;
	};

	const cancelGroup = (cancellationGroup: string): number => {
		let cancelledCount = 0;
		for (const laneQueue of queuedIntentsByLane.values()) {
			for (let index = laneQueue.length - 1; index >= 0; index -= 1) {
				const queuedIntent = laneQueue[index];
				if (queuedIntent?.intent.cancellationGroup !== cancellationGroup) {
					continue;
				}
				laneQueue.splice(index, 1);
				queuedEstimatedBytes -= queuedIntent.estimatedBytes;
				cancelledCount += 1;
			}
		}
		return cancelledCount;
	};

	return {
		enqueue,
		dequeueNext,
		dequeueNextMatching,
		cancelGroup,
		get maxQueuedEstimatedBytes(): number {
			return props.maxQueuedEstimatedBytes;
		},
		get maxQueuedIntentsPerLane(): number {
			return props.maxQueuedIntentsPerLane;
		},
		get queuedIntentCount(): number {
			return countQueuedIntents();
		},
		get queuedEstimatedBytes(): number {
			return queuedEstimatedBytes;
		},
	};
}

function compareQueuedDemandIntents(left: QueuedDemandIntent, right: QueuedDemandIntent): number {
	const orderingComparison = left.intent.orderingKey.localeCompare(right.intent.orderingKey);
	return orderingComparison === 0 ? left.sequence - right.sequence : orderingComparison;
}

function defaultNow(): number {
	return globalThis.performance?.now() ?? Date.now();
}
