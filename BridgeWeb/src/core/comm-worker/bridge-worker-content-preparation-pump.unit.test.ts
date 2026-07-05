import { describe, expect, test } from 'vitest';

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
});
