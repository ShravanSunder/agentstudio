import { describe, expect, test } from 'vitest';

import {
	planBridgeCommWorkerDemandExecution,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-executor.js';

describe('Bridge comm worker demand executor', () => {
	test('applies pacing and backoff without becoming membership truth', () => {
		const membership: readonly BridgeCommWorkerDemandMember[] = [
			{ itemId: 'visible-backoff', role: 'visible' },
			{ itemId: 'selected-now', role: 'selected', selectedDemandEpoch: 9 },
			{ itemId: 'visible-capacity', role: 'visible' },
		];

		const plan = planBridgeCommWorkerDemandExecution({
			backoffByItemId: new Map([
				[
					'visible-backoff',
					{
						attemptCount: 2,
						retryEligibleAtMilliseconds: 1_500,
					},
				],
			]),
			inFlightItemIds: new Set(),
			maxStartCount: 1,
			membership,
			nowMilliseconds: 1_000,
		});

		expect(plan.startItemIds).toEqual(['selected-now']);
		expect(plan.deferredItems).toEqual([
			{
				itemId: 'visible-backoff',
				reason: 'backoff',
				retryEligibleAtMilliseconds: 1_500,
			},
			{
				itemId: 'visible-capacity',
				reason: 'pacing',
				retryEligibleAtMilliseconds: null,
			},
		]);
		expect(membership.map((member) => member.itemId)).toEqual([
			'visible-backoff',
			'selected-now',
			'visible-capacity',
		]);
	});

	test('preserves reconciler order for equal-rank visible members', () => {
		const plan = planBridgeCommWorkerDemandExecution({
			backoffByItemId: new Map(),
			inFlightItemIds: new Set(),
			maxStartCount: 3,
			membership: [
				{ itemId: 'visible-c', role: 'visible' },
				{ itemId: 'visible-a', role: 'visible' },
				{ itemId: 'visible-b', role: 'visible' },
			],
			nowMilliseconds: 1_000,
		});

		expect(plan.startItemIds).toEqual(['visible-c', 'visible-a', 'visible-b']);
	});
});
