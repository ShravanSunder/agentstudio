import { createHash } from 'node:crypto';

import { describe, expect, test, vi } from 'vitest';

import {
	BridgeCommWorkerAnnotationProjectionQueryController,
	type BridgeCommWorkerAnnotationProjectionPublication,
	type BridgeCommWorkerAnnotationProjectionTransport,
} from './bridge-comm-worker-annotation-projection-query-controller.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeProductContentStream,
	BridgeProductSubscription,
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
		harness.notifications.push(snapshotRequired(7));
		await flushMicrotasks();
		expect(harness.querySourceGenerations).toEqual([]);

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 7 });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([7]);
		expect(harness.statuses).toEqual(['refreshing', 'ready']);
		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.threads[0]?.messages).toHaveLength(1);
	});

	test('requeries when demanded sessions change on the same active source generation', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		harness.notifications.push(snapshotRequired(100));
		await harness.controller.waitForIdle();

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
	});

	test('requeries after same-generation demand is deactivated and reactivated', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 9) });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 9 });
		harness.controller.ensureSubscription();
		harness.notifications.push(snapshotRequired(9));
		await harness.controller.waitForIdle();

		harness.controller.setDemand({ active: false, sessionIds: [sessionId], sourceGeneration: 9 });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 9 });
		await harness.controller.waitForIdle();

		expect(harness.querySourceGenerations).toEqual([9, 9]);
		expect(harness.statuses).toEqual(['refreshing', 'ready', 'refreshing', 'ready']);
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
		harness.notifications.push(snapshotRequired(12));
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
		harness.notifications.push(snapshotRequired(18));
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
		harness.notifications.push(snapshotRequired(16));

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
		replacementNotifications.push(snapshotRequired(17));
		await harness.controller.waitForIdle();

		expect(harness.subscriptionCount()).toBe(2);
		expect(harness.statuses).toEqual(['unavailable', 'refreshing', 'ready']);
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
		harness.notifications.push(snapshotRequired(10));
		await flushTaskQueueUntil(() => harness.querySourceGenerations.length === 1);
		for (let sourceGeneration = 11; sourceGeneration <= 15; sourceGeneration += 1) {
			harness.notifications.push(snapshotRequired(sourceGeneration));
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
		harness.notifications.push(snapshotRequired(20));
		await harness.controller.waitForIdle();

		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.expectedMessageCount).toBe(132);
		expect(harness.publications[0]?.snapshot.threads[0]?.messages).toHaveLength(132);
	});

	test('installs three or more ordered pages atomically', async () => {
		const pages = await makeProjectionPages(180, 21, 900);
		expect(pages.length).toBeGreaterThanOrEqual(3);
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 21 });
		harness.controller.ensureSubscription();
		harness.notifications.push(snapshotRequired(21));
		await harness.controller.waitForIdle();

		expect(harness.failures).toEqual([]);
		expect(harness.publications).toHaveLength(1);
		expect(harness.publications[0]?.snapshot.expectedMessageCount).toBe(180);
	});

	test('rejects a mixed snapshot identity and publishes no partial projection', async () => {
		const pages = await makeProjectionPages(2, 30, 1_200);
		expect(pages).toHaveLength(2);
		const secondPage = pages[1];
		if (secondPage === undefined) throw new Error('Expected a second projection page.');
		secondPage.descriptor = {
			...secondPage.descriptor,
			page: { ...secondPage.descriptor.page, snapshotId: uuidv7(999) },
		};
		const harness = await createHarness({ pages });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 30 });
		harness.controller.ensureSubscription();
		harness.notifications.push(snapshotRequired(30));
		await harness.controller.waitForIdle();

		expect(harness.publications).toEqual([]);
		expect(harness.failures).toHaveLength(1);
	});

	test('retains the publication boundary when content fails or is partial', async () => {
		const pages = await makeProjectionPages(1, 40);
		const harness = await createHarness({ pages, terminalKind: 'error' });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 40 });
		harness.controller.ensureSubscription();
		harness.notifications.push(snapshotRequired(40));
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
		harness.notifications.push(snapshotRequired(50));
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
	readonly subscription: BridgeProductSubscription<'file.annotations' | 'review.annotations'>;
}

interface AnnotationProjectionTestHarness {
	readonly controller: BridgeCommWorkerAnnotationProjectionQueryController;
	readonly failures: unknown[];
	readonly notifications: TestNotificationQueue;
	readonly publications: Array<{
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
		onConvergence: ({ state, surface }): void => {
			statuses.push(state.kind);
			if (state.kind === 'ready') publications.push({ snapshot: state.snapshot, surface });
			else if (state.kind === 'unavailable') failures.push(state.error);
		},
		onSourceAuthorityStale: (publication): void => {
			sourceAuthorityStalePublications.push(publication);
		},
		surface: 'file',
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
	};
}

function createNotificationQueue(surface: 'file' | 'review'): TestNotificationQueue {
	const pending: Array<IteratorResult<BridgeProductWorktreeAnnotationEvent>> = [];
	const waiters: Array<(result: IteratorResult<BridgeProductWorktreeAnnotationEvent>) => void> = [];
	const events: AsyncIterable<BridgeProductWorktreeAnnotationEvent> = {
		[Symbol.asyncIterator]: () => ({
			next: async (): Promise<IteratorResult<BridgeProductWorktreeAnnotationEvent>> => {
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
	const subscription: BridgeProductSubscription<'file.annotations' | 'review.annotations'> =
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
			const resolve = waiters.shift();
			if (resolve === undefined) pending.push({ done: false, value: event });
			else resolve({ done: false, value: event });
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
				expectedSessionCount: 1,
				expectedThreadCount: 1,
				isLastPage: pageOrdinal === pages.length - 1,
				nextCursor: pageOrdinal === pages.length - 1 ? null : `cursor-${pageOrdinal + 1}`,
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

function snapshotRequired(sourceGeneration: number): BridgeProductWorktreeAnnotationEvent {
	return { eventKind: 'snapshot.required', sourceGeneration, worktreeId };
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
