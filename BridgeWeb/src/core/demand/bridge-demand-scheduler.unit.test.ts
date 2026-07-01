import { describe, expect, test } from 'vitest';

import type { BridgeDemandIntent, BridgeDemandLane } from '../models/bridge-demand-models.js';
import { createBridgeDemandScheduler } from './bridge-demand-scheduler.js';

describe('bridge demand scheduler', () => {
	test('orders generic lanes ahead of lower urgency work and preserves lane ordering keys', () => {
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 1024,
		});

		scheduler.enqueue({
			intent: makeIntent({ lane: 'visible', dedupeKey: 'visible-1', orderingKey: '003' }),
		});
		scheduler.enqueue({
			intent: makeIntent({ lane: 'foreground', dedupeKey: 'foreground-2', orderingKey: '002' }),
		});
		scheduler.enqueue({
			intent: makeIntent({ lane: 'foreground', dedupeKey: 'foreground-1', orderingKey: '001' }),
		});
		scheduler.enqueue({
			intent: makeIntent({ lane: 'active', dedupeKey: 'active-1', orderingKey: '001' }),
		});

		expect(drainScheduler(scheduler)).toEqual([
			'foreground:001',
			'foreground:002',
			'active:001',
			'visible:003',
		]);
	});

	test('dedupes queued work by dedupe key and replaces stale freshness', () => {
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 1024,
		});

		const firstResult = scheduler.enqueue({
			intent: makeIntent({
				dedupeKey: 'review:item-1',
				freshnessKey: 'review:item-1:rev-1',
				orderingKey: '002',
			}),
		});
		const replacementResult = scheduler.enqueue({
			intent: makeIntent({
				dedupeKey: 'review:item-1',
				freshnessKey: 'review:item-1:rev-2',
				orderingKey: '001',
			}),
		});

		expect(firstResult).toEqual({ ok: true, status: 'queued' });
		expect(replacementResult).toEqual({ ok: true, status: 'replaced' });
		expect(scheduler.dequeueNext()?.freshnessKey).toBe('review:item-1:rev-2');
		expect(scheduler.dequeueNext()).toBeNull();
	});

	test('caps queues and admits foreground by dropping lower-priority work first', () => {
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 2,
			maxQueuedEstimatedBytes: 100,
		});

		expect(
			scheduler.enqueue({
				intent: makeIntent({ lane: 'speculative', dedupeKey: 'spec-1' }),
				estimatedBytes: 60,
			}),
		).toEqual({ ok: true, status: 'queued' });
		expect(
			scheduler.enqueue({
				intent: makeIntent({ lane: 'idle', dedupeKey: 'idle-1' }),
				estimatedBytes: 20,
			}),
		).toEqual({ ok: true, status: 'queued' });
		expect(
			scheduler.enqueue({
				intent: makeIntent({ lane: 'foreground', dedupeKey: 'fg-1' }),
				estimatedBytes: 40,
			}),
		).toEqual({ ok: true, status: 'queued', droppedLowerPriorityCount: 1 });

		expect(drainScheduler(scheduler)).toEqual(['foreground:001', 'speculative:001']);
	});

	test('drops queued work by cancellation group on source reset', () => {
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 1024,
		});

		scheduler.enqueue({
			intent: makeIntent({ dedupeKey: 'review:item-1', cancellationGroup: 'review:package-1' }),
		});
		scheduler.enqueue({
			intent: makeIntent({ dedupeKey: 'review:item-2', cancellationGroup: 'review:package-1' }),
		});
		scheduler.enqueue({
			intent: makeIntent({ dedupeKey: 'review:item-3', cancellationGroup: 'review:package-2' }),
		});

		expect(scheduler.cancelGroup('review:package-1')).toBe(2);
		expect(drainScheduler(scheduler)).toEqual(['foreground:001']);
	});

	test('emits queue wait lifecycle timing when work dequeues', () => {
		let nowMilliseconds = 1_000;
		const lifecycleEvents: unknown[] = [];
		const scheduler = createBridgeDemandScheduler({
			maxQueuedIntentsPerLane: 8,
			maxQueuedEstimatedBytes: 1024,
			now: () => nowMilliseconds,
			onLifecycleEvent: (event): void => {
				lifecycleEvents.push(event);
			},
		});
		const intent = makeIntent({ lane: 'visible', dedupeKey: 'visible-1' });

		expect(scheduler.enqueue({ intent, estimatedBytes: 128 })).toEqual({
			ok: true,
			status: 'queued',
		});
		nowMilliseconds = 1_024;
		expect(scheduler.dequeueNext()).toEqual(intent);

		expect(lifecycleEvents).toEqual([
			{
				estimatedBytes: 128,
				intent,
				kind: 'enqueued',
				lane: 'visible',
				queueDepthAfter: 1,
				queuedAtMilliseconds: 1_000,
				queuedEstimatedBytesAfter: 128,
				status: 'queued',
			},
			{
				dequeuedAtMilliseconds: 1_024,
				estimatedBytes: 128,
				intent,
				kind: 'dequeued',
				lane: 'visible',
				queueDepthAfter: 0,
				queueWaitMilliseconds: 24,
				queuedAtMilliseconds: 1_000,
				queuedEstimatedBytesAfter: 0,
			},
		]);
	});
});

function drainScheduler(
	scheduler: ReturnType<typeof createBridgeDemandScheduler>,
): readonly string[] {
	const drained: string[] = [];
	let nextIntent: BridgeDemandIntent | null = scheduler.dequeueNext();
	while (nextIntent !== null) {
		drained.push(`${nextIntent.lane}:${nextIntent.orderingKey}`);
		nextIntent = scheduler.dequeueNext();
	}
	return drained;
}

interface MakeIntentProps {
	readonly cancellationGroup?: string;
	readonly dedupeKey?: string;
	readonly freshnessKey?: string;
	readonly lane?: BridgeDemandLane;
	readonly orderingKey?: string;
}

function makeIntent(props: MakeIntentProps = {}): BridgeDemandIntent {
	const lane = props.lane ?? 'foreground';
	const dedupeKey = props.dedupeKey ?? `${lane}:descriptor`;
	return {
		descriptorRef: {
			descriptorId: dedupeKey,
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: {
				paneId: 'pane-1',
				protocol: 'review',
				sourceId: 'source-1',
				packageId: 'package-1',
				generation: 1,
				revision: 1,
			},
		},
		lane,
		orderingKey: props.orderingKey ?? '001',
		dedupeKey,
		freshnessKey: props.freshnessKey ?? `${dedupeKey}:fresh`,
		cancellationGroup: props.cancellationGroup ?? 'review:package-1',
	};
}
