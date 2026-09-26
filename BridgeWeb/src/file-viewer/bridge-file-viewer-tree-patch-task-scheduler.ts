export type BridgeFileViewerTreePatchTaskPriority = 'background' | 'visible';

export interface BridgeFileViewerTreePatchTaskScheduler {
	readonly cancel: (key: object) => void;
	readonly schedule: (
		key: object,
		priority: BridgeFileViewerTreePatchTaskPriority,
		runOneTurn: () => boolean,
	) => void;
}

type ScheduledTaskCancellation = () => void;
type ScheduleTask = (callback: () => void) => ScheduledTaskCancellation;

interface ScheduledTreePatchTask {
	readonly key: object;
	readonly priority: BridgeFileViewerTreePatchTaskPriority;
	readonly runOneTurn: () => boolean;
}

const treePatchTaskSchedulerByDocument = new WeakMap<
	Document,
	BridgeFileViewerTreePatchTaskScheduler
>();

export function bridgeFileViewerTreePatchTaskSchedulerForDocument(
	ownerDocument: Document,
): BridgeFileViewerTreePatchTaskScheduler {
	const existingScheduler = treePatchTaskSchedulerByDocument.get(ownerDocument);
	if (existingScheduler !== undefined) return existingScheduler;

	const scheduler = createBridgeFileViewerTreePatchTaskScheduler();
	treePatchTaskSchedulerByDocument.set(ownerDocument, scheduler);
	return scheduler;
}

export function createBridgeFileViewerTreePatchTaskScheduler(
	scheduleTask: ScheduleTask = scheduleMacrotask,
): BridgeFileViewerTreePatchTaskScheduler {
	const visibleTasks = new Map<object, ScheduledTreePatchTask>();
	const backgroundTasks = new Map<object, ScheduledTreePatchTask>();
	let cancelPendingTask: ScheduledTaskCancellation | null = null;
	let isDisposed = false;

	const hasTasks = (): boolean => visibleTasks.size > 0 || backgroundTasks.size > 0;
	const hasTask = (key: object): boolean => visibleTasks.has(key) || backgroundTasks.has(key);

	const storeTask = (task: ScheduledTreePatchTask): void => {
		visibleTasks.delete(task.key);
		backgroundTasks.delete(task.key);
		const destination = task.priority === 'visible' ? visibleTasks : backgroundTasks;
		destination.set(task.key, task);
	};

	const takeNextTask = (): ScheduledTreePatchTask | null => {
		const queue = visibleTasks.size > 0 ? visibleTasks : backgroundTasks;
		const nextEntry = queue.entries().next();
		if (nextEntry.done) return null;
		const [key, task] = nextEntry.value;
		queue.delete(key);
		return task;
	};

	let requestNextTask: () => void;
	requestNextTask = (): void => {
		if (isDisposed || cancelPendingTask !== null || !hasTasks()) return;
		cancelPendingTask = scheduleTask((): void => {
			cancelPendingTask = null;
			if (isDisposed) return;
			const task = takeNextTask();
			if (task === null) return;
			let hasMoreWork = false;
			try {
				hasMoreWork = task.runOneTurn();
			} finally {
				if (hasMoreWork && !isDisposed && !hasTask(task.key)) {
					storeTask(task);
				}
				requestNextTask();
			}
		});
	};

	return {
		cancel(key): void {
			visibleTasks.delete(key);
			backgroundTasks.delete(key);
			if (!hasTasks() && cancelPendingTask !== null) {
				cancelPendingTask();
				cancelPendingTask = null;
			}
		},
		schedule(key, priority, runOneTurn): void {
			if (isDisposed) return;
			storeTask({ key, priority, runOneTurn });
			requestNextTask();
		},
	};
}

function scheduleMacrotask(callback: () => void): ScheduledTaskCancellation {
	const taskId = globalThis.setTimeout(callback, 0);
	return (): void => globalThis.clearTimeout(taskId);
}
