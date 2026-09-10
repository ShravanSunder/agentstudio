import { describe, expect, test } from 'vitest';

import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import {
	controlChanged,
	createHarness,
	createNotificationQueue,
	deferred,
	flushMicrotasks,
	flushTaskQueue,
	flushTaskQueueUntil,
	makeProjectionPages,
	pushSessionCatalog,
	sessionChanged,
	sessionId,
	uuidv7,
} from './test-fixtures/bridge-comm-worker-annotation-projection.test-support.js';
const reviewPublicationIdentity = {
	packageId: 'package-annotations-1',
	publicationId: uuidv7(41),
	reviewGeneration: 7,
	revision: 3,
	sourceIdentity: 'source-annotations-1',
} as const;

describe('Bridge comm worker annotation projection query controller', () => {
	test('returns the exact Review identity captured by the query attempt', async () => {
		const harness = await createHarness({
			pages: await makeProjectionPages(1, 7, undefined, 'review'),
			surface: 'review',
		});
		harness.controller.setDemand({
			active: true,
			reviewPublicationIdentity,
			sessionIds: [sessionId],
			sourceGeneration: 7,
		});
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 7);

		await harness.controller.waitForIdle();

		expect(harness.publications).toHaveLength(2);
		expect(harness.publications).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ reviewPublicationIdentity, surface: 'review' }),
			]),
		);
	});

	test('records inactive invalidations and fetches only after activation', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 7) });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 7);
		await flushMicrotasks();
		expect(harness.querySourceGenerations).toEqual([]);

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 7 });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([7, 7]);
		expect(harness.statuses).toEqual(['refreshing', 'ready', 'refreshing', 'ready']);
		expect(harness.publications).toHaveLength(2);
		expect(harness.publications.at(-1)?.snapshot.threads[0]?.messages).toHaveLength(1);
		const lifecyclePhases = harness.telemetrySamples.map(
			(sample) =>
				`${sample.stringAttributes['agentstudio.bridge.phase']}:${sample.stringAttributes['agentstudio.bridge.result']}`,
		);
		expect(
			lifecyclePhases.filter((phase) => phase === 'annotation_invalidation_received:success'),
		).toHaveLength(3);
		expect(
			lifecyclePhases.filter((phase) => phase === 'projection_query_terminal:success'),
		).toHaveLength(2);
		expect(
			harness.telemetrySamples.every(
				(sample) => sample.stringAttributes['agentstudio.bridge.operation.id'] === 'a'.repeat(64),
			),
		).toBe(true);
		expect([
			...new Set(
				harness.telemetrySamples
					.filter(
						(sample) =>
							sample.stringAttributes['agentstudio.bridge.phase'] !==
							'annotation_invalidation_received',
					)
					.map((sample) => sample.numericAttributes['agentstudio.bridge.stage.attempt']),
			),
		]).toEqual([0, 1]);
	});

	test('requeries when demanded sessions change on the same active source generation', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 100);
		await harness.controller.waitForIdle();

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
	});

	test('finishes the empty-demand control read before retained demand loads rich content', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		harness.controller.ensureSubscription();

		pushSessionCatalog(harness.notifications, 8);
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
		expect(harness.publications.map((publication) => publication.contentSessionIds)).toEqual([
			[],
			[sessionId],
		]);
	});

	test('records an undemanded session change without fetching rich content', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 8);
		await harness.controller.waitForIdle();
		harness.querySessionIds.length = 0;

		harness.notifications.push(sessionChanged(9, 2));
		await harness.controller.waitForIdle();
		expect(harness.querySessionIds).toEqual([]);

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();
		expect(harness.querySessionIds).toEqual([[sessionId]]);
		expect(harness.publications.at(-1)?.contentSessionIds).toEqual([sessionId]);
	});

	test('suppresses equal session revisions and queries demanded content only for a newer revision', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 8);
		await harness.controller.waitForIdle();
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();
		harness.querySessionIds.length = 0;

		harness.notifications.push(sessionChanged(9, 1));
		harness.notifications.push(sessionChanged(10, 2));
		harness.notifications.push(sessionChanged(11, 2));
		await flushMicrotasks();
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[sessionId]]);
	});

	test('control changes query summaries with empty rich demand even while a session is demanded', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 8);
		await harness.controller.waitForIdle();
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();
		harness.querySessionIds.length = 0;

		harness.notifications.push(controlChanged(9));
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
		expect(harness.publications.at(-2)?.contentSessionIds).toEqual([]);
		expect(harness.publications.at(-1)?.contentSessionIds).toEqual([sessionId]);
	});

	test('requeries after same-generation demand is deactivated and reactivated', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 9) });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 9 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 9);
		await harness.controller.waitForIdle();

		harness.controller.setDemand({ active: false, sessionIds: [sessionId], sourceGeneration: 9 });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 9 });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([9, 9, 9]);
		expect(harness.statuses).toEqual([
			'refreshing',
			'ready',
			'refreshing',
			'ready',
			'refreshing',
			'ready',
		]);
	});

	test('keeps convergence live when notification precedes the current source generation', async () => {
		const pages12 = await makeProjectionPages(1, 12);
		const harness = await createHarness({
			pages: pages12,
			queryOverride: (request) =>
				request.sourceGeneration === 10
					? Promise.resolve({ currentSourceGeneration: 12, kind: 'source_stale' })
					: Promise.resolve({ descriptor: pages12[0]?.descriptor, kind: 'content' }),
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 10 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 12);
		await harness.controller.waitForIdle();

		expect(harness.statuses).toEqual(['refreshing']);
		expect(harness.publications).toEqual([]);
		expect(harness.sourceAuthorityStalePublications).toEqual([
			{ currentSourceGeneration: 12, requestedSourceGeneration: 10, surface: 'file' },
		]);

		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 12 });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([10, 12]);
		expect(
			harness.publications.map((publication) => publication.snapshot.sourceGeneration),
		).toEqual([12]);
	});

	test('settles stale-await unavailable when its presentation source producer dies', async () => {
		const harness = await createHarness({
			pages: await makeProjectionPages(1, 18),
			queryOverride: (): Promise<unknown> =>
				Promise.resolve({ currentSourceGeneration: 18, kind: 'source_stale' }),
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 17 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 18);
		await harness.controller.waitForIdle();
		harness.controller.sourceUnavailable(new Error('File metadata producer ended.'));
		expect(harness.statuses).toEqual(['refreshing', 'unavailable']);
	});

	test('retries one typed retryable projection failure before publishing unavailable', async () => {
		const pages = await makeProjectionPages(1, 16);
		let queryAttemptCount = 0;
		const harness = await createHarness({
			pages,
			queryOverride: (): Promise<unknown> => {
				queryAttemptCount += 1;
				return queryAttemptCount === 1
					? Promise.reject(
							new BridgeProductControlRequestError({
								code: 'internal',
								message: 'Projection capacity is temporarily unavailable.',
								retryAfterMilliseconds: null,
								retryable: true,
							}),
						)
					: Promise.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
			},
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 16 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 16);

		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([16, 16]);
		expect(harness.failures).toEqual([]);
		expect(harness.statuses).toEqual(['refreshing', 'refreshing', 'ready']);
	});

	test('reopens one failed active notification subscription and bootstraps current truth', async () => {
		const firstNotifications = createNotificationQueue('file');
		const replacementNotifications = createNotificationQueue('file');
		const harness = await createHarness({
			notificationQueues: [firstNotifications, replacementNotifications],
			pages: await makeProjectionPages(1, 17),
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 17 });
		harness.controller.ensureSubscription();

		firstNotifications.close();
		await flushTaskQueueUntil(() => harness.subscriptionCount() === 2);
		pushSessionCatalog(replacementNotifications, 17);
		await flushTaskQueue();
		await harness.controller.waitForIdle();

		expect(harness.subscriptionCount()).toBe(2);
		expect(harness.statuses).toEqual(['unavailable', 'refreshing', 'ready']);
	});

	test('retires failed subscription authority, fences its in-flight query, and reopens from a lower catalog revision', async () => {
		const firstNotifications = createNotificationQueue('file');
		const replacementNotifications = createNotificationQueue('file');
		const firstQuery = deferred<unknown>();
		const pages = await makeProjectionPages(1, 17);
		const observedSignals: AbortSignal[] = [];
		let queryCount = 0;
		const harness = await createHarness({
			notificationQueues: [firstNotifications, replacementNotifications],
			pages,
			queryOverride: (_request, signal) => {
				observedSignals.push(signal);
				queryCount += 1;
				return queryCount === 1
					? firstQuery.promise
					: Promise.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
			},
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 17 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(firstNotifications, 20);
		await flushTaskQueueUntil(() => harness.querySourceGenerations.length === 1);

		firstNotifications.close();
		await flushTaskQueueUntil(() => harness.subscriptionCount() === 2);

		expect(observedSignals[0]?.aborted).toBe(true);
		expect(harness.catalogAuthorityRetirements).toEqual([true]);
		firstQuery.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
		await flushTaskQueue();
		expect(harness.publications).toEqual([]);
		expect(harness.querySourceGenerations).toEqual([17]);

		pushSessionCatalog(replacementNotifications, 1);
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([17, 17]);
		expect(harness.publications).toHaveLength(1);
		expect(harness.statuses).toEqual(['refreshing', 'unavailable', 'refreshing', 'ready']);
	});

	test('explicit retry reopens after two pre-bootstrap notification failures', async () => {
		const firstNotifications = createNotificationQueue('file');
		const replacementNotifications = createNotificationQueue('file');
		const retryNotifications = createNotificationQueue('file');
		const harness = await createHarness({
			notificationQueues: [firstNotifications, replacementNotifications, retryNotifications],
			pages: await makeProjectionPages(1, 19),
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 19 });
		harness.controller.ensureSubscription();

		firstNotifications.close();
		await flushTaskQueueUntil(() => harness.subscriptionCount() === 2);
		replacementNotifications.close();
		await harness.controller.waitForIdle();
		harness.controller.retry();
		await flushTaskQueueUntil(() => harness.subscriptionCount() === 3);
		pushSessionCatalog(retryNotifications, 19);
		await flushTaskQueue();
		await harness.controller.waitForIdle();

		expect(harness.subscriptionCount()).toBe(3);
		expect(harness.statuses.at(-1)).toBe('ready');
	});

	test('coalesces invalidations 11 through 15 while 10 is blocked and fences stale completion', async () => {
		const firstQuery = deferred<unknown>();
		const pages10 = await makeProjectionPages(1, 10);
		const observedSignals: AbortSignal[] = [];
		let queryCount = 0;
		const harness = await createHarness({
			pages: pages10,
			queryOverride: (_request, signal) => {
				observedSignals.push(signal);
				return ++queryCount === 1
					? firstQuery.promise
					: Promise.resolve({ descriptor: pages10[0]?.descriptor, kind: 'content' });
			},
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 10 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 10);
		await flushTaskQueueUntil(() => harness.querySourceGenerations.length === 1);
		for (let sourceGeneration = 11; sourceGeneration <= 15; sourceGeneration += 1) {
			harness.notifications.push(controlChanged(sourceGeneration));
		}
		await flushTaskQueueUntil(() => harness.querySourceGenerations.length === 2);
		expect(harness.querySourceGenerations).toEqual([10, 10]);
		expect(observedSignals[0]?.aborted).toBe(true);
		firstQuery.resolve({ descriptor: pages10[0]?.descriptor, kind: 'content' });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([10, 10]);
		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.sourceGeneration).toBe(10);
	});

	test('installs a projection larger than 2 MiB only after ordered pages validate', async () => {
		const pages = await makeProjectionPages(132, 20, 2 * 1024 * 1024);
		expect(pages).toHaveLength(2);
		expect(pages.reduce((sum, page) => sum + page.bytes.byteLength, 0)).toBeGreaterThan(
			2 * 1024 * 1024,
		);
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 20 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 20);
		await harness.controller.waitForIdle();

		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.expectedMessageCount).toBe(132);
		expect(harness.publications[0]?.snapshot.threads[0]?.messages).toHaveLength(132);
	});

	test('installs three or more ordered pages atomically', async () => {
		const pages = await makeProjectionPages(180, 21, 100_000);
		expect(pages.length).toBeGreaterThanOrEqual(3);
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 21 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 21);
		await harness.controller.waitForIdle();

		expect(harness.failures).toEqual([]);
		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.expectedMessageCount).toBe(180);
	});

	test('rejects a page chain beyond the maximum logical page count', async () => {
		const pages = await makeProjectionPages(129, 22, 1);
		expect(pages.length).toBeGreaterThan(128);
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 22 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 22);
		await harness.controller.waitForIdle();

		expect(harness.publications).toEqual([]);
		expect(harness.failures).toHaveLength(1);
	});

	test('rejects a mixed snapshot identity and publishes no partial projection', async () => {
		const pages = await makeProjectionPages(2, 30, 1_200);
		expect(pages.length).toBeGreaterThanOrEqual(2);
		const secondPage = pages[1];
		if (secondPage === undefined) throw new Error('Expected a second projection page.');
		secondPage.descriptor = {
			...secondPage.descriptor,
			page: { ...secondPage.descriptor.page, snapshotId: uuidv7(999) },
		};
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 30 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 30);
		await harness.controller.waitForIdle();

		expect(harness.publications).toEqual([]);
		expect(harness.failures).toHaveLength(1);
	});

	test('retains the publication boundary when content fails or is partial', async () => {
		const pages = await makeProjectionPages(1, 40);
		const harness = await createHarness({ pages, terminalKind: 'error' });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 40 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 40);
		await harness.controller.waitForIdle();

		expect(harness.publications).toEqual([]);
		expect(harness.failures).toHaveLength(1);
	});

	test('disposal aborts the in-flight query and prevents a late publish', async () => {
		const pendingQuery = deferred<unknown>();
		const pages = await makeProjectionPages(1, 50);
		const observedSignals: AbortSignal[] = [];
		const harness = await createHarness({
			pages,
			queryOverride: (_request, signal) => {
				observedSignals.push(signal);
				return pendingQuery.promise;
			},
		});
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 50 });
		harness.controller.ensureSubscription();
		pushSessionCatalog(harness.notifications, 50);
		await flushTaskQueue();
		const disposal = harness.controller.dispose();
		expect(observedSignals[0]?.aborted).toBe(true);
		pendingQuery.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
		await disposal;

		expect(harness.publications).toEqual([]);
	});
});
