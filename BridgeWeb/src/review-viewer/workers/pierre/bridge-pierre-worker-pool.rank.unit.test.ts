import type { FileContents } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { demandRankForContentRole } from '../../../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentDemandRole } from '../../../core/models/bridge-demand-models.js';
import { materializeBridgeCodeViewLoadingItem } from '../../code-view/bridge-code-view-materialization.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanelSelector } from '../../code-view/bridge-code-view-worker-prepared-items.js';
import { makeBridgeViewerProjectionFixture } from '../../test-support/review-viewer-fixtures.js';
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

	test('reads demand rank from real Pierre diff requests', () => {
		const diffTask = makeDiffWorkerTask({
			demandRank: 0,
			highlightKey: 'diff:review-item:1',
			id: 8,
		});

		expect(bridgePierreDemandRankForWorkerTask(diffTask)).toBe(0);
	});

	test('orders equal-rank queued work by stable request id', () => {
		const laterTask = makeWorkerTask({
			id: 12,
			file: makeRankedFile({ name: 'later.ts', demandRank: 1 }),
		});
		const earlierTask = makeWorkerTask({
			id: 9,
			file: makeRankedFile({ name: 'earlier.ts', demandRank: 1 }),
		});
		const queuedTasks = [laterTask, earlierTask];

		sortBridgePierreWorkerPoolQueuedTasksForDemandRank(queuedTasks);

		expect(queuedTasks).toEqual([earlierTask, laterTask]);
	});

	test('promotes an existing same-highlight-key queued task in place', () => {
		const selectedPresentationItem = selectedDiffPresentationFromOneVisiblePublication();
		const selectedPresentationDiff = selectedPresentationItem.fileDiff;
		const existingTask = makeDiffWorkerTask({
			demandRank: 1,
			highlightKey: `diff:${selectedPresentationDiff.cacheKey}:1`,
			id: 4,
		});
		const backgroundTask = makeWorkerTask({
			id: 3,
			file: makeRankedFile({ name: 'background.ts', demandRank: 4 }),
		});
		const queuedTasks: BridgePierreWorkerPoolTestQueuedTask[] = [backgroundTask, existingTask];
		let highlightCallCount = 0;
		const workerPool = {
			queuedTasks,
			enqueueRenderTask(task: BridgePierreWorkerPoolTestQueuedTask): void {
				queuedTasks.push(task);
			},
			getDiffHighlightKey(diff: { readonly cacheKey?: string }): string {
				return `diff:${diff.cacheKey}:1`;
			},
			highlightDiffAST(
				_instance: unknown,
				_diff: {
					readonly bridgeDemandRank?: number | undefined;
					readonly cacheKey?: string | undefined;
				},
			): void {
				highlightCallCount += 1;
			},
		};
		installBridgePierreWorkerPoolRankScheduler(
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- focused fake reflects Pierre's queuedTasks and highlightDiffAST early-return seam.
			workerPool as unknown as Parameters<typeof installBridgePierreWorkerPoolRankScheduler>[0],
		);

		workerPool.highlightDiffAST({}, selectedPresentationDiff);

		expect(queuedTasks).toHaveLength(2);
		expect(
			queuedTasks.filter(
				(task): boolean =>
					'highlightKey' in task && task.highlightKey === existingTask.highlightKey,
			),
		).toHaveLength(1);
		expect(queuedTasks[0]).toBe(existingTask);
		expect(bridgePierreDemandRankForWorkerTask(existingTask)).toBe(0);
		expect(highlightCallCount).toBe(1);
	});

	test('leaves already-running same-highlight-key work untouched', () => {
		const activeTask = makeDiffWorkerTask({
			demandRank: 1,
			highlightKey: 'diff:active-review-item:1',
			id: 2,
		});
		const queuedTask = makeWorkerTask({
			id: 3,
			file: makeRankedFile({ name: 'background.ts', demandRank: 4 }),
		});
		const queuedTasks: BridgePierreWorkerPoolTestQueuedTask[] = [queuedTask];
		const workerPool = {
			activeTaskById: new Map([[activeTask.id, activeTask]]),
			queuedTasks,
			enqueueRenderTask(task: BridgePierreWorkerPoolTestQueuedTask): void {
				queuedTasks.push(task);
			},
			getDiffHighlightKey(diff: { readonly cacheKey?: string }): string {
				return `diff:${diff.cacheKey}:1`;
			},
			highlightDiffAST(_instance: unknown, _diff: ReturnType<typeof makeRankedDiff>): void {},
		};
		installBridgePierreWorkerPoolRankScheduler(
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- focused fake proves the scheduler never inspects Pierre's activeTaskById map.
			workerPool as unknown as Parameters<typeof installBridgePierreWorkerPoolRankScheduler>[0],
		);

		workerPool.highlightDiffAST({}, { ...makeRankedDiff(0), cacheKey: 'active-review-item' });

		expect(workerPool.activeTaskById.get(activeTask.id)).toBe(activeTask);
		expect(bridgePierreDemandRankForWorkerTask(activeTask)).toBe(1);
		expect(queuedTasks).toEqual([queuedTask]);
	});
});

type BridgePierreWorkerPoolTestQueuedTask =
	| BridgePierreWorkerPoolTestTask
	| BridgePierreWorkerPoolTestDiffTask;

interface BridgePierreWorkerPoolTestTask {
	readonly id: number;
	readonly request: {
		readonly file: FileContents & { readonly bridgeDemandRank?: number };
		readonly type: 'file';
	};
}

interface BridgePierreWorkerPoolTestDiffTask {
	readonly highlightKey: string;
	readonly id: number;
	readonly request: {
		readonly diff: ReturnType<typeof makeRankedDiff>;
		readonly type: 'diff';
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

function makeDiffWorkerTask(props: {
	readonly demandRank: number;
	readonly highlightKey: string;
	readonly id: number;
}): BridgePierreWorkerPoolTestDiffTask {
	return {
		highlightKey: props.highlightKey,
		id: props.id,
		request: {
			type: 'diff',
			diff: makeRankedDiff(props.demandRank),
		},
	};
}

function makeRankedDiff(demandRank: number): {
	readonly bridgeDemandRank: number;
	readonly cacheKey: string;
} {
	return {
		bridgeDemandRank: demandRank,
		cacheKey: 'review-item',
	};
}

function selectedDiffPresentationFromOneVisiblePublication(): Extract<
	BridgeMainCodeViewItem,
	{ readonly type: 'diff' }
> {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const selectedDescriptor = reviewPackage.itemsById['source-high'];
	if (selectedDescriptor === undefined) {
		throw new Error('Expected selected Review fixture descriptor.');
	}
	const materializedItem = materializeBridgeCodeViewLoadingItem(selectedDescriptor);
	if (materializedItem.type !== 'diff') {
		throw new Error('Expected selected Review fixture to materialize a diff.');
	}
	const storedVisibleItem: BridgeMainCodeViewItem = {
		...materializedItem,
		bridgeMetadata: { ...materializedItem.bridgeMetadata, contentState: 'hydrated' },
		fileDiff: { ...materializedItem.fileDiff, bridgeDemandRank: 1 },
	};
	const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();
	const selectedPresentationItem = selector({
		reviewPackage,
		selectedCodeViewItem: storedVisibleItem,
		selectedItemId: selectedDescriptor.itemId,
		selectedItemPresentation: null,
		sourceKey: 'single-worker-publication',
		visibleCodeViewItems: [storedVisibleItem],
	}).find((item): boolean => item.id === selectedDescriptor.itemId);
	if (selectedPresentationItem?.type !== 'diff') {
		throw new Error('Expected selected Review presentation to remain a diff.');
	}
	expect(storedVisibleItem.fileDiff.bridgeDemandRank).toBe(1);
	expect(selectedPresentationItem.fileDiff.bridgeDemandRank).toBe(0);
	expect(selectedPresentationItem.fileDiff.cacheKey).toBe(storedVisibleItem.fileDiff.cacheKey);
	return selectedPresentationItem;
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
	return makeRankedFile({
		name: props.path,
		demandRank: demandRankForContentRole(props.contentDemandRole),
	});
}
