import { describe, expect, test } from 'vitest';

import type { BridgeWorkerAnnotationProjectionSnapshot } from '../core/comm-worker/bridge-comm-worker-annotation-projection-decoder.js';
import { WorktreeAnnotationProjectionStore } from './worktree-annotation-projection-store.js';

describe('WorktreeAnnotationProjectionStore read convergence', () => {
	test('starts unknown until the first complete projection installs', () => {
		const store = new WorktreeAnnotationProjectionStore();

		expect(store.getSnapshot()).toMatchObject({
			readStatus: { kind: 'unknown' },
			revision: null,
			sessions: [],
			threads: [],
			worktreeId: null,
		});
	});

	test('retains the last complete projection while refreshing and unavailable', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const complete = snapshot(4, 7);
		store.apply(complete, 'a'.repeat(64));

		store.markRefreshing();
		expect(store.getSnapshot()).toMatchObject({
			readStatus: { kind: 'refreshing' },
			revision: 4,
			threads: complete.threads,
		});

		store.markUnavailable(true);

		expect(store.getSnapshot()).toMatchObject({
			readStatus: { kind: 'unavailable', retryable: true },
			revision: 4,
			threads: complete.threads,
		});

		store.apply(snapshot(5, 8), 'a'.repeat(64));
		expect(store.getSnapshot().readStatus).toEqual({ kind: 'ready' });
		expect(store.getSnapshot().revision).toBe(5);
	});
});

function snapshot(
	projectionRevision: number,
	sourceGeneration: number,
): BridgeWorkerAnnotationProjectionSnapshot {
	return {
		expectedMessageCount: 0,
		expectedSessionCount: 0,
		expectedThreadCount: 0,
		projectionRevision,
		recoveryStatus: 'available',
		sessions: [],
		sourceGeneration,
		threads: [],
		worktreeId: 'worktree-1',
	};
}
