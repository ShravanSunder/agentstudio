import type { FileContents } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { demandRankForContentRole } from '../../../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentDemandRole } from '../../../core/models/bridge-demand-models.js';
import type { BridgeContentResource } from '../../../foundation/content/content-resource-loader.js';
import { makeBridgeReviewItem } from '../../../foundation/review-package/bridge-review-package-test-support.js';
import { materializeBridgeCodeViewItem } from '../../code-view/bridge-code-view-materialization.js';
import {
	bridgePierreDemandRankForWorkerTask,
	installBridgePierreWorkerPoolRankScheduler,
	sortBridgePierreWorkerPoolQueuedTasksForDemandRank,
} from './bridge-pierre-worker-pool.js';

describe('Bridge Pierre worker pool demand rank', () => {
	test('dequeues selected materialized CodeView file ahead of saturated viewport work', () => {
		const queuedTasks: BridgePierreWorkerPoolTestTask[] = [];
		const workerPool = {
			queuedTasks,
			enqueueRenderTask(task: BridgePierreWorkerPoolTestTask): void {
				queuedTasks.push(task);
			},
		};
		installBridgePierreWorkerPoolRankScheduler(
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- rank scheduling only reflects enqueueRenderTask and queuedTasks from this focused fake.
			workerPool as unknown as Parameters<typeof installBridgePierreWorkerPoolRankScheduler>[0],
		);

		workerPool.enqueueRenderTask(
			makeWorkerTask({
				id: 1,
				file: materializedCodeViewFileForWorkerTask({
					contentDemandRole: 'visible',
					itemId: 'visible-a',
					path: 'Sources/App/VisibleA.swift',
				}),
			}),
		);
		workerPool.enqueueRenderTask(
			makeWorkerTask({
				id: 2,
				file: materializedCodeViewFileForWorkerTask({
					contentDemandRole: 'visible',
					itemId: 'visible-b',
					path: 'Sources/App/VisibleB.swift',
				}),
			}),
		);
		workerPool.enqueueRenderTask(
			makeWorkerTask({
				id: 3,
				file: materializedCodeViewFileForWorkerTask({
					contentDemandRole: 'visible',
					itemId: 'visible-c',
					path: 'Sources/App/VisibleC.swift',
				}),
			}),
		);

		workerPool.enqueueRenderTask(
			makeWorkerTask({
				id: 4,
				file: materializedCodeViewFileForWorkerTask({
					contentDemandRole: 'selected',
					itemId: 'selected',
					path: 'Sources/App/Selected.swift',
				}),
			}),
		);

		expect(queuedTasks[0]?.request.file.name).toBe('Sources/App/Selected.swift');
	});

	test('dequeues selected-rank highlight work before lower-rank work when the pool is saturated', () => {
		const queuedTasks = [
			makeWorkerTask({
				id: 4,
				file: makeRankedFile({ name: 'visible-queued-a.ts', demandRank: 1 }),
			}),
			makeWorkerTask({
				id: 5,
				file: makeRankedFile({ name: 'visible-queued-b.ts', demandRank: 1 }),
			}),
			makeWorkerTask({
				id: 6,
				file: makeRankedFile({ name: 'background-queued.ts', demandRank: 4 }),
			}),
			makeWorkerTask({
				id: 7,
				file: makeRankedFile({ name: 'selected-queued.ts', demandRank: 0 }),
			}),
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
		const unrankedTask = makeWorkerTask({
			id: 1,
			file: makeRankedFile({ name: 'unranked.ts' }),
		});
		const selectedTask = makeWorkerTask({
			id: 2,
			file: makeRankedFile({ name: 'selected.ts', demandRank: 0 }),
		});
		const visibleTask = makeWorkerTask({
			id: 3,
			file: makeRankedFile({ name: 'visible.ts', demandRank: 1 }),
		});
		const queuedTasks = [unrankedTask, visibleTask, selectedTask];

		sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);

		expect(queuedTasks).toEqual([selectedTask, visibleTask, unrankedTask]);
		expect(bridgePierreDemandRankForWorkerTask(selectedTask)).toBe(0);
		expect(bridgePierreDemandRankForWorkerTask(unrankedTask)).toBe(Number.MAX_SAFE_INTEGER);
	});

	test('dequeues every CodeView demand tier in selected-first rank order', () => {
		const selectedTask = makeWorkerTask({
			id: 5,
			file: makeRankedFile({
				name: 'selected.ts',
				demandRank: demandRankForContentRole('selected'),
			}),
		});
		const visibleTask = makeWorkerTask({
			id: 4,
			file: makeRankedFile({
				name: 'visible.ts',
				demandRank: demandRankForContentRole('visible'),
			}),
		});
		const nearbyTask = makeWorkerTask({
			id: 3,
			file: makeRankedFile({
				name: 'nearby.ts',
				demandRank: demandRankForContentRole('nearby'),
			}),
		});
		const speculativeTask = makeWorkerTask({
			id: 2,
			file: makeRankedFile({
				name: 'speculative.ts',
				demandRank: demandRankForContentRole('speculative'),
			}),
		});
		const backgroundTask = makeWorkerTask({
			id: 1,
			file: makeRankedFile({
				name: 'background.ts',
				demandRank: demandRankForContentRole('background'),
			}),
		});
		const queuedTasks = [backgroundTask, speculativeTask, nearbyTask, visibleTask, selectedTask];

		sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);

		expect(queuedTasks).toEqual([
			selectedTask,
			visibleTask,
			nearbyTask,
			speculativeTask,
			backgroundTask,
		]);
	});
});

interface BridgePierreWorkerPoolTestTask {
	readonly id: number;
	readonly request: {
		readonly file: FileContents & { readonly bridgeDemandRank?: number };
		readonly type: 'file';
	};
}

function makeWorkerTask(props: {
	readonly id: number;
	readonly file: FileContents & { readonly bridgeDemandRank?: number };
}): BridgePierreWorkerPoolTestTask {
	return {
		id: props.id,
		request: {
			type: 'file',
			file: props.file,
		},
	};
}

function makeRankedFile(props: {
	readonly name: string;
	readonly demandRank?: number;
}): FileContents & { readonly bridgeDemandRank?: number } {
	return {
		name: props.name,
		contents: 'let value = 1\n',
		cacheKey: props.name,
		...(props.demandRank === undefined ? {} : { bridgeDemandRank: props.demandRank }),
	};
}

function materializedCodeViewFileForWorkerTask(props: {
	readonly contentDemandRole: BridgeContentDemandRole;
	readonly itemId: string;
	readonly path: string;
}): FileContents & { readonly bridgeDemandRank?: number } {
	const item = makeBridgeReviewItem({ itemId: props.itemId, path: props.path });
	const headHandle = item.contentRoles.head;
	if (headHandle === null || headHandle === undefined) {
		throw new Error(`expected fixture head content handle for ${props.itemId}`);
	}
	const materializedItem = materializeBridgeCodeViewItem({
		contentDemandRole: props.contentDemandRole,
		item,
		presentation: { kind: 'file', version: 'head' },
		resources: {
			head: makeContentResource(headHandle, `let ${props.itemId.replaceAll('-', '')} = 1\n`),
		},
	});
	if (materializedItem?.type !== 'file') {
		throw new Error(`expected file materialization for ${props.itemId}`);
	}
	return materializedItem.file;
}

function makeContentResource(
	handle: BridgeContentResource['handle'],
	text: string,
): BridgeContentResource {
	return { handle, readText: (): string => text };
}
