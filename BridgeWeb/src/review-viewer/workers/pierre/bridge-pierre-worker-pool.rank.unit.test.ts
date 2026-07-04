import { describe, expect, test } from 'vitest';

import {
	bridgePierreDemandRankForWorkerTask,
	sortBridgePierreWorkerPoolQueuedTasksForDemandRank,
} from './bridge-pierre-worker-pool.js';

describe('Bridge Pierre worker pool demand rank', () => {
	test('dequeues selected-rank highlight work before lower-rank work when the pool is saturated', () => {
		const queuedTasks = [
			makeWorkerTask({ id: 4, name: 'visible-queued-a.ts', demandRank: 1 }),
			makeWorkerTask({ id: 5, name: 'visible-queued-b.ts', demandRank: 1 }),
			makeWorkerTask({ id: 6, name: 'background-queued.ts', demandRank: 4 }),
			makeWorkerTask({ id: 7, name: 'selected-queued.ts', demandRank: 0 }),
		];

		sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);

		expect(queuedTasks.map((task) => task.request.file.name)).toEqual([
			'selected-queued.ts',
			'visible-queued-a.ts',
			'visible-queued-b.ts',
			'background-queued.ts',
		]);
	});

	test('treats unranked worker work as lower priority than ranked demand', () => {
		const unrankedTask = makeWorkerTask({ id: 1, name: 'unranked.ts' });
		const selectedTask = makeWorkerTask({ id: 2, name: 'selected.ts', demandRank: 0 });
		const visibleTask = makeWorkerTask({ id: 3, name: 'visible.ts', demandRank: 1 });
		const queuedTasks = [unrankedTask, visibleTask, selectedTask];

		sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);

		expect(queuedTasks).toEqual([selectedTask, visibleTask, unrankedTask]);
		expect(bridgePierreDemandRankForWorkerTask(selectedTask)).toBe(0);
		expect(bridgePierreDemandRankForWorkerTask(unrankedTask)).toBe(Number.MAX_SAFE_INTEGER);
	});
});

function makeWorkerTask(props: {
	readonly id: number;
	readonly name: string;
	readonly demandRank?: number;
}): {
	readonly id: number;
	readonly request: {
		readonly file: {
			readonly bridgeDemandRank?: number;
			readonly cacheKey: string;
			readonly contents: string;
			readonly name: string;
		};
		readonly type: 'file';
	};
} {
	return {
		id: props.id,
		request: {
			type: 'file',
			file: {
				name: props.name,
				contents: 'let value = 1\n',
				cacheKey: props.name,
				...(props.demandRank === undefined ? {} : { bridgeDemandRank: props.demandRank }),
			},
		},
	};
}
