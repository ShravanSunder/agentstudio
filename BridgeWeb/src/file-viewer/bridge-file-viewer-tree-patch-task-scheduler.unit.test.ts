import { describe, expect, test } from 'vitest';

import { createBridgeFileViewerTreePatchTaskScheduler } from './bridge-file-viewer-tree-patch-task-scheduler.js';

describe('Bridge File viewer tree patch task scheduler', () => {
	test('runs visible pane work before queued background work', () => {
		const taskPoster = createRecordingTaskPoster();
		const scheduler = createBridgeFileViewerTreePatchTaskScheduler(taskPoster.postTask);
		const executionOrder: string[] = [];

		scheduler.schedule({}, 'background', (): boolean => {
			executionOrder.push('background');
			return false;
		});
		scheduler.schedule({}, 'visible', (): boolean => {
			executionOrder.push('visible');
			return false;
		});

		taskPoster.runNext();
		taskPoster.runNext();

		expect(executionOrder).toEqual(['visible', 'background']);
	});

	test('coalesces pending work by tree identity and yields after each bounded turn', () => {
		const taskPoster = createRecordingTaskPoster();
		const scheduler = createBridgeFileViewerTreePatchTaskScheduler(taskPoster.postTask);
		const treeIdentity = {};
		const executionOrder: string[] = [];
		let currentTurn = 0;

		scheduler.schedule(treeIdentity, 'background', (): boolean => {
			executionOrder.push('superseded');
			return false;
		});
		scheduler.schedule(treeIdentity, 'visible', (): boolean => {
			currentTurn += 1;
			executionOrder.push(`turn-${String(currentTurn)}`);
			return currentTurn < 3;
		});

		taskPoster.runNext();
		expect(executionOrder).toEqual(['turn-1']);
		taskPoster.runNext();
		expect(executionOrder).toEqual(['turn-1', 'turn-2']);
		taskPoster.runNext();

		expect(executionOrder).toEqual(['turn-1', 'turn-2', 'turn-3']);
		expect(taskPoster.pendingCount).toBe(0);
	});

	test('cancels queued work when its tree runtime is disposed', () => {
		const taskPoster = createRecordingTaskPoster();
		const scheduler = createBridgeFileViewerTreePatchTaskScheduler(taskPoster.postTask);
		const treeIdentity = {};
		let didRun = false;

		scheduler.schedule(treeIdentity, 'visible', (): boolean => {
			didRun = true;
			return false;
		});
		scheduler.cancel(treeIdentity);
		taskPoster.runNext();

		expect(didRun).toBe(false);
		expect(taskPoster.pendingCount).toBe(0);
	});
});

interface RecordingTaskPoster {
	readonly pendingCount: number;
	readonly postTask: (callback: () => void) => () => void;
	readonly runNext: () => void;
}

function createRecordingTaskPoster(): RecordingTaskPoster {
	const pendingTasks: Array<{ cancelled: boolean; callback: () => void }> = [];
	return {
		get pendingCount(): number {
			return pendingTasks.filter((task): boolean => !task.cancelled).length;
		},
		postTask(callback): () => void {
			const task = { callback, cancelled: false };
			pendingTasks.push(task);
			return (): void => {
				task.cancelled = true;
			};
		},
		runNext(): void {
			const task = pendingTasks.shift();
			if (task === undefined) throw new Error('No pending task to run.');
			if (!task.cancelled) task.callback();
		},
	};
}
