import { describe, expect, test } from 'vitest';

import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import {
	controlChanged,
	createHarness,
	deferred,
	flushTaskQueueUntil,
	makeProjectionPages,
	pushSessionCatalog,
} from './test-fixtures/bridge-comm-worker-annotation-projection.test-support.js';

describe('Bridge annotation projection query recovery', () => {
	test('settles two retryable failures once and accepts a fresh metadata invalidation', async () => {
		const pages = await makeProjectionPages(1, 1);
		let queryCount = 0;
		const harness = await createHarness({
			pages,
			queryOverride: (): Promise<unknown> => {
				queryCount += 1;
				return queryCount <= 2
					? Promise.reject(retryableProjectionFailure(queryCount))
					: Promise.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
			},
		});
		try {
			harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 1 });
			harness.controller.ensureSubscription();
			pushSessionCatalog(harness.notifications, 1);
			await harness.controller.waitForIdle();

			expect(harness.querySourceGenerations).toEqual([1, 1]);
			expect(harness.statuses).toEqual(['refreshing', 'refreshing', 'unavailable']);
			expect(harness.failures).toHaveLength(1);

			harness.notifications.push(controlChanged(1));
			await harness.controller.waitForIdle();

			expect(harness.querySourceGenerations).toEqual([1, 1, 1]);
			expect(harness.failures).toHaveLength(1);
			expect(harness.publications).toHaveLength(1);
			expect(harness.publications[0]?.snapshot.sourceGeneration).toBe(1);
			expect(harness.statuses.at(-1)).toBe('ready');
			expect(harness.subscriptionCount()).toBe(1);
		} finally {
			await harness.controller.dispose();
		}
	});

	test('does not publish unavailable from an attempt superseded by deactivate and newer demand', async () => {
		const firstAttempt = deferred<unknown>();
		const pages = await makeProjectionPages(1, 2);
		let queryCount = 0;
		const harness = await createHarness({
			pages,
			queryOverride: (): Promise<unknown> => {
				queryCount += 1;
				return queryCount === 1
					? firstAttempt.promise
					: Promise.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
			},
		});
		try {
			harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 1 });
			harness.controller.ensureSubscription();
			pushSessionCatalog(harness.notifications, 1);
			await flushTaskQueueUntil(() => harness.querySourceGenerations.length === 1);

			harness.controller.setDemand({ active: false, sessionIds: [], sourceGeneration: 1 });
			harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 2 });
			harness.notifications.push(controlChanged(2));
			firstAttempt.resolve(Promise.reject(retryableProjectionFailure(1)));
			await harness.controller.waitForIdle();

			expect(harness.failures).toEqual([]);
			expect(harness.publications).toHaveLength(1);
			expect(harness.publications[0]?.snapshot.sourceGeneration).toBe(2);
			expect(harness.statuses.at(-1)).toBe('ready');
		} finally {
			await harness.controller.dispose();
		}
	});

	test('converges on new source-generation demand after retry exhaustion without manual retry', async () => {
		const pages = await makeProjectionPages(1, 2);
		let queryCount = 0;
		const harness = await createHarness({
			pages,
			queryOverride: (): Promise<unknown> => {
				queryCount += 1;
				return queryCount <= 2
					? Promise.reject(retryableProjectionFailure(queryCount))
					: Promise.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
			},
		});
		try {
			harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 1 });
			harness.controller.ensureSubscription();
			pushSessionCatalog(harness.notifications, 1);
			await harness.controller.waitForIdle();
			expect(harness.failures).toHaveLength(1);

			harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 2 });
			await harness.controller.waitForIdle();

			expect(harness.querySourceGenerations).toEqual([1, 1, 2]);
			expect(harness.failures).toHaveLength(1);
			expect(harness.publications).toHaveLength(1);
			expect(harness.publications[0]?.snapshot.sourceGeneration).toBe(2);
			expect(harness.statuses.at(-1)).toBe('ready');
			expect(harness.subscriptionCount()).toBe(1);
		} finally {
			await harness.controller.dispose();
		}
	});
});

function retryableProjectionFailure(attempt: number): BridgeProductControlRequestError {
	return new BridgeProductControlRequestError({
		code: 'internal',
		message: `Projection query attempt ${attempt} failed.`,
		retryAfterMilliseconds: null,
		retryable: true,
	});
}
