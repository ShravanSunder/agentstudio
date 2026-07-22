import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import { reviewInteractionPerformanceSatisfied } from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	collectReviewWorkerQueueWaitMilliseconds,
	parseNullableNumericAttribute,
	reviewContentStateCanRenderFirstVisibleWindow,
} from './performance-correlation.ts';
import type { WorktreeBridgeTelemetrySampleProof } from './types.ts';
import { makePassingReviewInteractionPerformanceProof } from './unit-test-fixtures.ts';

describe('worktree performance correlation', () => {
	test('treats windowed Review content as a rendered first-visible window', () => {
		expect(reviewContentStateCanRenderFirstVisibleWindow('hydrated')).toBe(true);
		expect(reviewContentStateCanRenderFirstVisibleWindow('windowed')).toBe(true);
		expect(reviewContentStateCanRenderFirstVisibleWindow('loading')).toBe(false);
	});

	test('preserves missing numeric attributes instead of coercing them to zero', () => {
		expect(parseNullableNumericAttribute(null)).toBeNull();
		expect(parseNullableNumericAttribute('')).toBeNull();
		expect(parseNullableNumericAttribute('0')).toBe(0);
		expect(parseNullableNumericAttribute('not-a-number')).toBeNull();
	});

	test('selects Review worker queue waits from their phase-specific status snapshots', () => {
		const selectedPhaseSamples = [
			makeWorkerTaskSample({ command: 'select', lane: 'selected', queueWaitMilliseconds: 7 }),
			makeWorkerTaskSample({ command: 'viewport', lane: 'visible', queueWaitMilliseconds: 97 }),
			makeWorkerTaskSample({
				command: 'select',
				lane: 'selected',
				queueWaitMilliseconds: 13,
				taskKind: 'store_action',
			}),
			makeWorkerTaskSample({ command: 'viewport', lane: 'selected', queueWaitMilliseconds: 17 }),
			makeWorkerTaskSample({ command: 'select', lane: 'selected', queueWaitMilliseconds: null }),
		];
		const visiblePhaseSamples = [
			makeWorkerTaskSample({ command: 'select', lane: 'selected', queueWaitMilliseconds: 89 }),
			makeWorkerTaskSample({ command: 'viewport', lane: 'visible', queueWaitMilliseconds: 11 }),
		];

		expect(
			collectReviewWorkerQueueWaitMilliseconds({
				sampleCount: 100,
				selectedPhaseSamples,
				visiblePhaseSamples,
			}),
		).toEqual({ selected: [7], visible: [11] });
	});

	test('enforces the accepted Review selection and worker queue-wait budgets', () => {
		const passingProof = makePassingReviewInteractionPerformanceProof();
		expect(reviewInteractionPerformanceSatisfied(passingProof)).toBe(true);
		expect(
			reviewInteractionPerformanceSatisfied({
				...passingProof,
				reviewClickPhaseDurations: {
					...passingProof.reviewClickPhaseDurations,
					selectionCommit: {
						...passingProof.reviewClickPhaseDurations.selectionCommit,
						p99Ms: 32,
					},
				},
			}),
		).toBe(false);
		expect(
			reviewInteractionPerformanceSatisfied({
				...passingProof,
				workerQueueWait: {
					...passingProof.workerQueueWait,
					selected: {
						...passingProof.workerQueueWait.selected,
						p95Ms: 16,
					},
				},
			}),
		).toBe(false);
		expect(
			reviewInteractionPerformanceSatisfied({
				...passingProof,
				workerQueueWait: {
					...passingProof.workerQueueWait,
					visible: {
						...passingProof.workerQueueWait.visible,
						p99Ms: 64,
					},
				},
			}),
		).toBe(false);
	});

	test('keeps File tree settlement timing independent from demand telemetry correlation', async () => {
		const scrollPerformanceSource = await readFile(
			new URL('./scroll-performance.ts', import.meta.url),
			'utf8',
		);
		expect(scrollPerformanceSource).not.toContain('data-last-demand-dispatch');
		expect(scrollPerformanceSource).not.toContain('visibleQueueWaitMilliseconds');
		expect(scrollPerformanceSource.indexOf('durationMilliseconds.push')).toBeGreaterThan(
			scrollPerformanceSource.indexOf('stableSignature = nextSignature'),
		);
	});
});

function makeWorkerTaskSample(props: {
	readonly command: string;
	readonly lane: string;
	readonly queueWaitMilliseconds: number | null;
	readonly taskKind?: string;
}): WorktreeBridgeTelemetrySampleProof {
	return {
		durationMilliseconds: 1,
		name: 'performance.bridge.worker.task',
		numericAttributes:
			props.queueWaitMilliseconds === null
				? {}
				: { 'agentstudio.bridge.worker.queue_wait_ms': props.queueWaitMilliseconds },
		phase: 'worker_task',
		result: 'success',
		slice: 'worker_task',
		transport: 'worker',
		viewer: null,
		workerCommand: props.command,
		workerLane: props.lane,
		workerTaskKind: props.taskKind ?? 'message_handler',
	};
}
