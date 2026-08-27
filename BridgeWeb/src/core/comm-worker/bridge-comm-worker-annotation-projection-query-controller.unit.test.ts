import { createHash } from 'node:crypto';

import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	BridgeCommWorkerAnnotationProjectionQueryController,
	type BridgeCommWorkerAnnotationProjectionPublication,
	type BridgeCommWorkerAnnotationProjectionTransport,
} from './bridge-comm-worker-annotation-projection-query-controller.js';
import type { BridgeProductMetadataDataFrame } from './bridge-product-metadata-application-protocol.js';
import {
	bridgeProductFileAnnotationMetadataApplicationProtocol,
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeProductContentStream,
	BridgeProductMetadataApplicationSubscription,
} from './bridge-product-transport-contract.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';
import type {
	BridgeProductAnnotationProjectionContentDescriptor,
	BridgeProductAnnotationProjectionQueryRequest,
} from './bridge-product-worktree-annotation-projection-query-contracts.js';

const worktreeId = 'worktree-annotations-1';
const sessionId = uuidv7(1);
const threadId = uuidv7(2);

describe('Bridge comm worker annotation projection query controller', () => {
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
		harness.notifications.push(controlChanged(12));
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
		harness.notifications.push(controlChanged(18));
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
		harness.notifications.push(controlChanged(16));

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
		replacementNotifications.push(controlChanged(17));
		await harness.controller.waitForIdle();

		expect(harness.subscriptionCount()).toBe(2);
		expect(harness.statuses).toEqual(['unavailable', 'refreshing', 'ready']);
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
		retryNotifications.push(controlChanged(19));
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
		harness.notifications.push(controlChanged(10));
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
		harness.notifications.push(controlChanged(20));
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
		harness.notifications.push(controlChanged(21));
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
		harness.notifications.push(controlChanged(22));
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
		harness.notifications.push(controlChanged(30));
		await harness.controller.waitForIdle();

		expect(harness.publications).toEqual([]);
		expect(harness.failures).toHaveLength(1);
	});

	test('retains the publication boundary when content fails or is partial', async () => {
		const pages = await makeProjectionPages(1, 40);
		const harness = await createHarness({ pages, terminalKind: 'error' });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 40 });
		harness.controller.ensureSubscription();
		harness.notifications.push(controlChanged(40));
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
		harness.notifications.push(controlChanged(50));
		await flushTaskQueue();
		const disposal = harness.controller.dispose();
		expect(observedSignals[0]?.aborted).toBe(true);
		pendingQuery.resolve({ descriptor: pages[0]?.descriptor, kind: 'content' });
		await disposal;

		expect(harness.publications).toEqual([]);
	});
});

interface MutableProjectionPage {
	descriptor: BridgeProductAnnotationProjectionContentDescriptor;
	readonly bytes: Uint8Array<ArrayBuffer>;
}

interface TestNotificationQueue {
	readonly close: () => void;
	readonly push: (event: BridgeProductWorktreeAnnotationEvent) => void;
	readonly subscription: AnnotationMetadataSubscription;
}

type AnnotationMetadataProtocol =
	| typeof bridgeProductFileAnnotationMetadataApplicationProtocol
	| typeof bridgeProductReviewAnnotationMetadataApplicationProtocol;
type AnnotationMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<AnnotationMetadataProtocol>;
type AnnotationMetadataFrame = BridgeProductMetadataDataFrame<BridgeProductWorktreeAnnotationEvent>;

interface AnnotationProjectionTestHarness {
	readonly controller: BridgeCommWorkerAnnotationProjectionQueryController;
	readonly failures: unknown[];
	readonly notifications: TestNotificationQueue;
	readonly publications: Array<{
		readonly contentSessionIds: readonly string[];
		readonly snapshot: Extract<
			BridgeCommWorkerAnnotationProjectionPublication['state'],
			{ readonly kind: 'ready' }
		>['snapshot'];
		readonly surface: BridgeCommWorkerAnnotationProjectionPublication['surface'];
	}>;
	readonly querySourceGenerations: number[];
	readonly querySessionIds: string[][];
	readonly sourceAuthorityStalePublications: Array<{
		readonly currentSourceGeneration: number;
		readonly requestedSourceGeneration: number;
		readonly surface: 'file' | 'review';
	}>;
	readonly statuses: Array<BridgeCommWorkerAnnotationProjectionPublication['state']['kind']>;
	readonly subscriptionCount: () => number;
	readonly telemetrySamples: BridgeTelemetrySample[];
}

async function createHarness(props: {
	readonly notificationQueues?: readonly TestNotificationQueue[];
	readonly pages: readonly MutableProjectionPage[];
	readonly queryOverride?: (
		request: BridgeProductAnnotationProjectionQueryRequest,
		signal: AbortSignal,
	) => Promise<unknown>;
	readonly terminalKind?: 'complete' | 'error';
}): Promise<AnnotationProjectionTestHarness> {
	const notifications = createNotificationQueue('file');
	const notificationQueues = props.notificationQueues ?? [notifications];
	let observedSubscriptionCount = 0;
	const publications: AnnotationProjectionTestHarness['publications'] = [];
	const failures: unknown[] = [];
	const statuses: AnnotationProjectionTestHarness['statuses'] = [];
	const querySourceGenerations: number[] = [];
	const querySessionIds: string[][] = [];
	const sourceAuthorityStalePublications: AnnotationProjectionTestHarness['sourceAuthorityStalePublications'] =
		[];
	const telemetrySamples: BridgeTelemetrySample[] = [];
	const pageByCursor = new Map<string | null, MutableProjectionPage>();
	for (const page of props.pages) {
		const cursor =
			page.descriptor.page.pageOrdinal === 0 ? null : `cursor-${page.descriptor.page.pageOrdinal}`;
		pageByCursor.set(cursor, page);
	}
	const transport: BridgeCommWorkerAnnotationProjectionTransport = {
		callProjection: async (_surface, request, signal): Promise<unknown> => {
			querySourceGenerations.push(request.sourceGeneration);
			querySessionIds.push([...request.sessionIds]);
			if (props.queryOverride !== undefined) return await props.queryOverride(request, signal);
			return { descriptor: pageByCursor.get(request.cursor)?.descriptor, kind: 'content' };
		},
		openContent: (descriptor): BridgeProductContentStream<'annotation.projection'> => {
			const page = props.pages.find(
				(candidate) => candidate.descriptor.descriptorId === descriptor.descriptorId,
			);
			if (page === undefined) throw new Error('Unknown annotation projection descriptor.');
			return makeContentStream(page, props.terminalKind ?? 'complete');
		},
		subscribe: () => {
			const subscription = notificationQueues[observedSubscriptionCount]?.subscription;
			observedSubscriptionCount += 1;
			if (subscription === undefined) throw new Error('Unexpected annotation subscription reopen.');
			return subscription;
		},
	};
	const controller = new BridgeCommWorkerAnnotationProjectionQueryController({
		onCatalog: (): void => {},
		onConvergence: ({ state, surface }): void => {
			statuses.push(state.kind);
			if (state.kind === 'ready') {
				publications.push({
					contentSessionIds: state.contentSessionIds,
					snapshot: state.snapshot,
					surface,
				});
			} else if (state.kind === 'unavailable') failures.push(state.error);
		},
		onSourceAuthorityStale: (publication): void => {
			sourceAuthorityStalePublications.push(publication);
		},
		surface: 'file',
		telemetryClient: {
			record: (sample): void => {
				telemetrySamples.push(sample);
			},
		},
		transport,
	});
	return {
		controller,
		failures,
		notifications,
		publications,
		querySourceGenerations,
		querySessionIds,
		sourceAuthorityStalePublications,
		statuses,
		subscriptionCount: (): number => observedSubscriptionCount,
		telemetrySamples,
	};
}

function createNotificationQueue(surface: 'file' | 'review'): TestNotificationQueue {
	const pending: Array<IteratorResult<AnnotationMetadataFrame>> = [];
	const waiters: Array<(result: IteratorResult<AnnotationMetadataFrame>) => void> = [];
	const events: AsyncIterable<AnnotationMetadataFrame> = {
		[Symbol.asyncIterator]: () => ({
			next: async (): Promise<IteratorResult<AnnotationMetadataFrame>> => {
				const result = pending.shift();
				if (result !== undefined) return result;
				return await new Promise((resolve) => waiters.push(resolve));
			},
		}),
	};
	const base = {
		cancel: vi.fn(async (): Promise<void> => {
			for (const resolve of waiters.splice(0)) resolve({ done: true, value: undefined });
		}),
		events,
		update: vi.fn(async (): Promise<void> => {}),
	};
	const subscription: AnnotationMetadataSubscription =
		surface === 'file'
			? {
					...base,
					subscriptionId: 'file-annotation-notifications',
					subscriptionKind: 'file.annotations',
				}
			: {
					...base,
					subscriptionId: 'review-annotation-notifications',
					subscriptionKind: 'review.annotations',
				};
	return {
		close: (): void => {
			for (const resolve of waiters.splice(0)) resolve({ done: true, value: undefined });
			pending.push({ done: true, value: undefined });
		},
		push: (event: BridgeProductWorktreeAnnotationEvent): void => {
			const frame = annotationMetadataFrame(event, subscription);
			const resolve = waiters.shift();
			if (resolve === undefined) pending.push({ done: false, value: frame });
			else resolve({ done: false, value: frame });
		},
		subscription,
	};
}

async function makeProjectionPages(
	messageCount: number,
	sourceGeneration: number,
	maximumPageBytes = 2 * 1024 * 1024,
): Promise<MutableProjectionPage[]> {
	const records: Uint8Array<ArrayBuffer>[] = [];
	const header = {
		header: {
			expectedMessageCount: messageCount,
			expectedSessionCount: 1,
			expectedThreadCount: 1,
			projectionRevision: sourceGeneration,
			recoveryStatus: 'available',
			sessions: [
				{
					completedAtUnixMilliseconds: null,
					createdAtUnixMilliseconds: 1,
					eligibleMessageCount: messageCount,
					eligibleWithoutInlinePlacementCount: 0,
					lifecycle: 'living',
					semanticRevision: sourceGeneration,
					sessionId,
					sourceRelationship: 'applicable',
					updatedAtUnixMilliseconds: 2,
				},
			],
			sourceGeneration,
			worktreeId,
		},
		kind: 'header',
	};
	records.push(encodeRecord(header));
	for (let ordinal = 0; ordinal < messageCount; ordinal += 1) {
		records.push(
			encodeRecord({
				kind: 'message',
				message: {
					context: {
						diffSide: 'additions',
						endLine: 12,
						path: 'Sources/App.swift',
						placement: 'exact',
						resolution: 'open',
						scope: 'located',
						sourceIdentity: 'source-1',
						sourceRole: 'file',
						startLine: 10,
						threadId,
					},
					message: {
						attentionState: 'not_applicable',
						authorKind: 'human',
						createdAtUnixMilliseconds: ordinal + 3,
						draft: null,
						handled: false,
						messageId: uuidv7(ordinal + 100),
						messageRevision: 1,
						ordinal,
						savedBody: messageCount > 100 ? 'x'.repeat(16_000) : `message-${ordinal}`,
						savedRevision: 1,
						sessionId,
						sessionRevision: sourceGeneration,
						status: 'locked',
						threadId,
						threadRevision: 1,
					},
				},
			}),
		);
	}
	const pageRecords: Uint8Array<ArrayBuffer>[][] = [[]];
	let currentPageBytes = 0;
	for (const record of records) {
		if (currentPageBytes > 0 && currentPageBytes + record.byteLength > maximumPageBytes) {
			pageRecords.push([]);
			currentPageBytes = 0;
		}
		pageRecords.at(-1)?.push(record);
		currentPageBytes += record.byteLength;
	}
	const pages = pageRecords.map((page) => concatenate(page));
	const aggregateSha256 = createHash('sha256').update(concatenate(pages)).digest('hex');
	return pages.map((bytes, pageOrdinal) => ({
		bytes,
		descriptor: {
			contentKind: 'annotation.projection',
			descriptorId: `projection-${sourceGeneration}-${pageOrdinal}`,
			maximumBytes: bytes.byteLength,
			page: {
				aggregateSha256,
				expectedMessageCount: messageCount,
				expectedPageCount: pages.length,
				expectedSessionCount: 1,
				expectedThreadCount: 1,
				isLastPage: pageOrdinal === pages.length - 1,
				nextCursor: pageOrdinal === pages.length - 1 ? null : `cursor-${pageOrdinal + 1}`,
				operationCorrelationId: 'a'.repeat(64),
				pageOrdinal,
				projectionRevision: sourceGeneration,
				snapshotId: uuidv7(sourceGeneration + 10_000),
				sourceGeneration,
			},
			surface: 'file',
		},
	}));
}

function makeContentStream(
	page: MutableProjectionPage,
	terminalKind: 'complete' | 'error',
): BridgeProductContentStream<'annotation.projection'> {
	return {
		contentKind: 'annotation.projection',
		contentRequestId: `request-${page.descriptor.descriptorId}`,
		frames: { async *[Symbol.asyncIterator]() {} },
		terminal:
			terminalKind === 'complete'
				? Promise.resolve({
						bytes: page.bytes.buffer,
						contentKind: 'annotation.projection',
						descriptorId: page.descriptor.descriptorId,
						endOfSource: true,
						kind: 'complete',
						observedByteLength: page.bytes.byteLength,
						observedSha256: createHash('sha256').update(page.bytes).digest('hex'),
					})
				: Promise.resolve({
						code: 'internal',
						contentKind: 'annotation.projection',
						descriptorId: page.descriptor.descriptorId,
						kind: 'error',
						retryable: true,
						safeMessage: 'projection unavailable',
					}),
	};
}

function encodeRecord(record: unknown): Uint8Array<ArrayBuffer> {
	return new TextEncoder().encode(`${JSON.stringify(record)}\n`);
}

function concatenate(chunks: readonly Uint8Array<ArrayBuffer>[]): Uint8Array<ArrayBuffer> {
	const result = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0));
	let offset = 0;
	for (const chunk of chunks) {
		result.set(chunk, offset);
		offset += chunk.byteLength;
	}
	return result;
}

function controlChanged(sourceGeneration: number): BridgeProductWorktreeAnnotationEvent {
	return {
		authority: {
			applicationSourceGeneration: sourceGeneration,
			worktreeId,
		},
		kind: 'annotation.controlChanged',
		reason: 'discovery',
	};
}

function sessionChanged(
	sourceGeneration: number,
	semanticRevision: number,
): BridgeProductWorktreeAnnotationEvent {
	return {
		authority: {
			applicationSourceGeneration: sourceGeneration,
			worktreeId,
		},
		kind: 'annotation.sessionChanged',
		semanticRevision,
		sessionId,
	};
}

function pushSessionCatalog(notifications: TestNotificationQueue, sourceGeneration: number): void {
	const transferId = `catalog-transfer-${sourceGeneration}`;
	const authority = {
		applicationSourceGeneration: sourceGeneration,
		worktreeId,
	} as const;
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			expectedEntryCount: 1,
			kind: 'catalog.begin',
			transferId,
		},
	});
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			entries: [{ kind: 'session', semanticRevision: 1, sessionId }],
			kind: 'catalog.window',
			transferId,
			windowOrdinal: 0,
		},
	});
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			entryCount: 1,
			kind: 'catalog.commit',
			transferId,
			windowCount: 1,
		},
	});
}

function annotationMetadataFrame(
	event: BridgeProductWorktreeAnnotationEvent,
	subscription: AnnotationMetadataSubscription,
): AnnotationMetadataFrame {
	return {
		data: event,
		metadataStreamId: 'annotation-metadata-stream',
		operationCorrelationId: 'a'.repeat(64),
		sourceGeneration: event.authority.applicationSourceGeneration,
		streamSequence: 1,
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
		subscriptionSequence: 1,
		workerDerivationEpoch: 1,
	};
}

function uuidv7(value: number): string {
	return `00000000-0000-7000-8000-${value.toString().padStart(12, '0')}`;
}

function deferred<TResult>(): {
	readonly promise: Promise<TResult>;
	readonly resolve: (value: TResult) => void;
} {
	let resolvePromise!: (value: TResult) => void;
	const promise = new Promise<TResult>((resolve): void => {
		resolvePromise = resolve;
	});
	return { promise, resolve: resolvePromise };
}

async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
}

async function flushTaskQueue(): Promise<void> {
	await new Promise<void>((resolve): void => {
		const channel = new MessageChannel();
		channel.port1.onmessage = (): void => {
			channel.port1.close();
			channel.port2.close();
			resolve();
		};
		channel.port2.postMessage(null);
	});
}

async function flushTaskQueueUntil(predicate: () => boolean): Promise<void> {
	for (let turn = 0; turn < 10; turn += 1) {
		if (predicate()) return;
		// eslint-disable-next-line no-await-in-loop -- Each turn waits for the exact queued task boundary.
		await flushTaskQueue();
	}
	throw new Error('Expected queued annotation projection work to reach its boundary.');
}
