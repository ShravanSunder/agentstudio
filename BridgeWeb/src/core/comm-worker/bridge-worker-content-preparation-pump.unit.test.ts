import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Worker content preparation pump', () => {
	test('large preparation yields to selected facts and resumes without redoing completed slices', () => {
		let clockMs = 0;
		const executionOrder: string[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => clockMs,
		});
		let backgroundProgress = 0;

		pump.enqueue({
			id: 'background-large-file',
			rank: 'background',
			runSlice: () => {
				backgroundProgress += 1;
				executionOrder.push(`background:${backgroundProgress}`);
				clockMs += 3;
				if (backgroundProgress === 1) {
					pump.enqueueOrPromote({
						id: 'selected-click',
						rank: 'selected',
						runSlice: () => {
							executionOrder.push('selected');
							clockMs += 1;
							return { complete: true };
						},
					});
				}
				return { complete: backgroundProgress === 3 };
			},
		});

		const firstRun = pump.runUntilBudget();
		expect(firstRun.completedIds).toEqual(['selected-click']);
		expect(firstRun.yielded).toBe(true);
		expect(executionOrder).toEqual(['background:1', 'selected', 'background:2']);

		const secondRun = pump.runUntilBudget();
		expect(secondRun.completedIds).toEqual(['background-large-file']);
		expect(executionOrder).toEqual(['background:1', 'selected', 'background:2', 'background:3']);
		expect(pump.getPendingWorkIds()).toEqual([]);
	});

	test('promotes an existing work item without duplicating completed preparation', () => {
		let clockMs = 0;
		const executionOrder: string[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 2,
			now: () => clockMs,
		});
		let sharedProgress = 0;
		const sharedWork = {
			id: 'shared-file',
			rank: 'background' as const,
			runSlice: () => {
				sharedProgress += 1;
				executionOrder.push(`shared:${sharedProgress}`);
				clockMs += 1;
				return { complete: sharedProgress === 2 };
			},
		};

		pump.enqueue(sharedWork);
		pump.enqueueOrPromote({
			...sharedWork,
			rank: 'selected',
		});

		expect(pump.getPendingWorkIds()).toEqual(['shared-file']);
		const result = pump.runUntilBudget();

		expect(result.completedIds).toEqual(['shared-file']);
		expect(sharedProgress).toBe(2);
		expect(executionOrder).toEqual(['shared:1', 'shared:2']);
		expect(pump.getPendingWorkIds()).toEqual([]);
	});

	test('records queue wait and handler duration by rank and work kind', () => {
		let clockMs = 0;
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 10,
			now: () => clockMs,
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		pump.enqueue({
			id: 'visible-review-content',
			rank: 'visible',
			telemetry: {
				payloadClass: 'inline',
				sourceEpoch: 7,
				workKind: 'review_content_ready',
			},
			runSlice: () => {
				clockMs += 3;
				return { complete: true };
			},
		});
		clockMs = 5;

		const result = pump.runUntilBudget();

		expect(result.completedIds).toEqual(['visible-review-content']);
		expect(telemetrySamples).toHaveLength(1);
		expect(telemetrySamples[0]).toMatchObject({
			name: 'performance.bridge.worker.task',
			durationMilliseconds: 3,
			stringAttributes: {
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.worker.lane': 'visible',
				'agentstudio.bridge.worker.payload_class': 'inline',
				'agentstudio.bridge.worker.task_kind': 'content_preparation',
				'agentstudio.bridge.worker.work_kind': 'review_content_ready',
			},
			numericAttributes: {
				'agentstudio.bridge.worker.handler_duration_ms': 3,
				'agentstudio.bridge.worker.queue_wait_ms': 5,
				'agentstudio.bridge.worker.source_epoch': 7,
			},
		});
	});

	test('re-stamps queue wait when lower-priority work promotes to selected', () => {
		let clockMs = 0;
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 10,
			now: () => clockMs,
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});
		const sharedWork = {
			id: 'shared-review-content',
			rank: 'background' as const,
			telemetry: {
				payloadClass: 'inline',
				sourceEpoch: 11,
				workKind: 'review_content_ready',
			},
			runSlice: () => {
				clockMs += 2;
				return { complete: true };
			},
		};

		pump.enqueue(sharedWork);
		clockMs = 20;
		pump.enqueueOrPromote({
			...sharedWork,
			rank: 'selected',
		});
		clockMs = 25;

		pump.runUntilBudget();

		expect(telemetrySamples[0]).toMatchObject({
			stringAttributes: {
				'agentstudio.bridge.worker.lane': 'selected',
			},
			numericAttributes: {
				'agentstudio.bridge.worker.queue_wait_ms': 5,
			},
		});
	});
});
