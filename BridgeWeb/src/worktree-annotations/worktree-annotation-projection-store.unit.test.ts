import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerAnnotationCatalog } from '../core/comm-worker/bridge-comm-worker-annotation-catalog-applicator.js';
import type { BridgeWorkerAnnotationProjectionSnapshot } from '../core/comm-worker/bridge-comm-worker-annotation-projection-decoder.js';
import { bridgeCommWorkerAnnotationCatalogStagingEvents } from '../core/comm-worker/bridge-comm-worker-annotation-runtime-events.js';
import type { BridgeWorkerAnnotationCatalogStagingEvent } from '../core/comm-worker/bridge-worker-annotation-contracts.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { reviewAnnotationApplicationItemIds } from '../review-viewer/code-view/use-bridge-code-view-worktree-annotations.js';
import { WorktreeAnnotationProjectionStore } from './worktree-annotation-projection-store.js';

describe('WorktreeAnnotationProjectionStore read convergence', () => {
	test('starts without a pending Review annotation application', () => {
		const store = new WorktreeAnnotationProjectionStore();

		expect(store.getSnapshot().reviewAnnotationApplication).toBeNull();
	});

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
		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 1));
		}
		const complete = snapshot(4, 7);
		applyProjection(store, complete);

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

		applyProjection(store, snapshot(5, 8));
		expect(store.getSnapshot().readStatus).toEqual({ kind: 'ready' });
		expect(store.getSnapshot().revision).toBe(5);
	});

	test('publishes bounded Review item scope and both owners of a semantic thread change', () => {
		const store = new WorktreeAnnotationProjectionStore();
		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 1));
		}
		const previous = snapshot(4, 7);
		const previousThread = {
			context: {
				diffSide: 'additions' as const,
				endLine: 8,
				path: 'Sources/Old.swift',
				placement: 'exact' as const,
				resolution: 'open' as const,
				scope: 'located' as const,
				sourceIdentity: 'head-old',
				sourceRole: 'review_head' as const,
				startLine: 7,
				threadId: '00000000-0000-7000-8000-000000000012',
			},
			messages: [],
		};
		store.apply({
			contentSessionIds: undefined,
			expectedContentSessionIds: [],
			operationCorrelationId: 'a'.repeat(64),
			reviewAnnotationApplication: null,
			snapshot: { ...previous, expectedThreadCount: 1, threads: [previousThread] },
		});
		const currentThread = {
			...previousThread,
			context: {
				...previousThread.context,
				path: 'Sources/New.swift',
				sourceIdentity: 'head-new',
			},
		};

		store.apply({
			contentSessionIds: undefined,
			expectedContentSessionIds: [],
			operationCorrelationId: 'b'.repeat(64),
			reviewAnnotationApplication: { affectedItemIds: ['item-new'], applicationId: 1 },
			snapshot: {
				...snapshot(5, 8),
				expectedThreadCount: 1,
				threads: [currentThread],
			},
		});

		expect(store.getSnapshot().reviewAnnotationApplication).toEqual({
			affectedItemIds: ['item-new'],
			applicationId: 1,
			changedThreadOwnerContexts: [previousThread.context, currentThread.context],
		});
	});

	test('does not report thread owners when the complete semantic projection is equal', () => {
		const store = new WorktreeAnnotationProjectionStore();
		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 1));
		}
		const complete = snapshot(4, 7);
		store.apply({
			contentSessionIds: undefined,
			expectedContentSessionIds: [],
			operationCorrelationId: 'a'.repeat(64),
			reviewAnnotationApplication: null,
			snapshot: complete,
		});

		store.apply({
			contentSessionIds: undefined,
			expectedContentSessionIds: [],
			operationCorrelationId: 'b'.repeat(64),
			reviewAnnotationApplication: { affectedItemIds: [], applicationId: 1 },
			snapshot: { ...complete, projectionRevision: 5 },
		});

		expect(store.getSnapshot().reviewAnnotationApplication).toEqual({
			affectedItemIds: [],
			applicationId: 1,
			changedThreadOwnerContexts: [],
		});
	});

	test('stops exposing an acknowledged Review annotation application', () => {
		const store = new WorktreeAnnotationProjectionStore();
		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 1));
		}
		store.apply({
			contentSessionIds: undefined,
			expectedContentSessionIds: [],
			operationCorrelationId: 'a'.repeat(64),
			reviewAnnotationApplication: { affectedItemIds: ['item-source'], applicationId: 1 },
			snapshot: snapshot(4, 7),
		});
		const presentationRevisionBeforeAcknowledgement = store.getSnapshot().presentationRevision;

		expect(store.acknowledgeReviewAnnotationApplication(1)).toBe(true);

		expect(store.getSnapshot().reviewAnnotationApplication).toBeNull();
		expect(
			reviewAnnotationApplicationItemIds({
				activeEditorItemIds: [],
				application: store.getSnapshot().reviewAnnotationApplication,
				reviewPackage: makeBridgeReviewPackage(),
			}),
		).toEqual([]);
		expect(store.getSnapshot().presentationRevision).toBe(
			presentationRevisionBeforeAcknowledgement + 1,
		);
		expect(store.acknowledgeReviewAnnotationApplication(1)).toBe(false);
	});

	test('keeps catalog windows hidden and publishes exactly once at commit', () => {
		const store = new WorktreeAnnotationProjectionStore();
		let publicationCount = 0;
		store.subscribe((): void => {
			publicationCount += 1;
		});

		store.applyCatalogStaging(catalogStaging('catalog.begin', 7));
		store.applyCatalogStaging(catalogStaging('catalog.window', 7));
		expect(publicationCount).toBe(0);
		expect(store.getCatalogSnapshot()).toEqual({ kind: 'unknown' });

		expect(store.applyCatalogStaging(catalogStaging('catalog.commit', 7)).status).toBe('completed');
		expect(publicationCount).toBe(1);
		expect(store.getCatalogSnapshot()).toMatchObject({
			catalog: { catalogRevision: 7, orderedSessionIds: ['01890abc-def0-7abc-8def-0123456789ab'] },
			kind: 'current',
		});
	});

	test('worker replacement retires the candidate, retains active stale, and admits a lower revision', () => {
		const store = new WorktreeAnnotationProjectionStore();
		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 20));
		}
		store.applyCatalogStaging(catalogStaging('catalog.begin', 21));

		store.prepareForWorkerReplacement();
		expect(store.getCatalogSnapshot()).toMatchObject({
			catalog: { catalogRevision: 20 },
			kind: 'stale',
		});

		for (const phase of ['catalog.begin', 'catalog.window', 'catalog.commit'] as const) {
			store.applyCatalogStaging(catalogStaging(phase, 1, 'annotation-subscription-2', 2));
		}
		expect(store.getCatalogSnapshot()).toMatchObject({
			catalog: { catalogRevision: 1 },
			kind: 'current',
		});
	});

	test('rejects a late superseded Main window without discarding the newer candidate', () => {
		const store = new WorktreeAnnotationProjectionStore();
		store.applyCatalogStaging(catalogStaging('catalog.begin', 5));
		store.applyCatalogStaging(catalogStaging('catalog.begin', 6));

		expect(store.applyCatalogStaging(catalogStaging('catalog.window', 5))).toEqual({
			reason: 'noncurrent_transfer',
			status: 'rejected',
		});
		expect(store.applyCatalogStaging(catalogStaging('catalog.window', 6))).toEqual({
			status: 'accepted',
		});
		expect(store.applyCatalogStaging(catalogStaging('catalog.commit', 6)).status).toBe('completed');
		expect(store.getCatalogSnapshot()).toMatchObject({
			catalog: { catalogRevision: 6 },
			kind: 'current',
		});
	});

	test('applies a multi-window catalog incrementally and publishes only the final swap', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const entries = Array.from({ length: 2_000 }, (_, index) => ({
			kind: 'session' as const,
			semanticRevision: index,
			sessionId: `01890abc-def0-7abc-8def-${index.toString(16).padStart(12, '0')}`,
		}));
		const sessionsById = new Map(entries.map((entry) => [entry.sessionId, entry]));
		const catalog = {
			authority: {
				subscriptionId: 'annotation-subscription-large',
				workerDerivationEpoch: 1,
				worktreeId: 'worktree-1',
			},
			catalogRevision: 7,
			entries,
			messageIdsByThreadId: new Map(),
			messagesById: new Map(),
			orderedSessionIds: entries.map((entry) => entry.sessionId),
			sessionsById,
			threadIdsBySessionId: new Map(),
			threadsById: new Map(),
			transferId: 'annotation-transfer-large',
		} satisfies BridgeCommWorkerAnnotationCatalog;
		const messages = bridgeCommWorkerAnnotationCatalogStagingEvents({
			catalog,
			operationCorrelationId: 'a'.repeat(64),
			surface: 'file',
		});
		let publicationCount = 0;
		store.subscribe((): void => {
			publicationCount += 1;
		});

		for (const message of messages.slice(0, -1)) store.applyCatalogStaging(message);
		expect(publicationCount).toBe(0);
		expect(store.getCatalogSnapshot()).toEqual({ kind: 'unknown' });
		const commit = messages.at(-1);
		if (commit === undefined) throw new Error('Expected annotation catalog commit.');
		store.applyCatalogStaging(commit);

		expect(publicationCount).toBe(1);
		expect(store.getCatalogSnapshot()).toMatchObject({
			catalog: { catalogRevision: 7, orderedSessionIds: catalog.orderedSessionIds },
			kind: 'current',
		});
	});
});

function catalogStaging(
	phase: 'catalog.begin' | 'catalog.commit' | 'catalog.window',
	catalogRevision: number,
	subscriptionId = 'annotation-subscription-1',
	workerDerivationEpoch = 1,
): BridgeWorkerAnnotationCatalogStagingEvent {
	const transfer =
		phase === 'catalog.begin'
			? {
					catalogRevision,
					expectedEntryCount: 1,
					kind: phase,
					transferId: `annotation-transfer-${catalogRevision}`,
				}
			: phase === 'catalog.window'
				? {
						catalogRevision,
						entries: [
							{
								kind: 'session' as const,
								semanticRevision: catalogRevision,
								sessionId: '01890abc-def0-7abc-8def-0123456789ab',
							},
						],
						kind: phase,
						transferId: `annotation-transfer-${catalogRevision}`,
						windowOrdinal: 0,
					}
				: {
						catalogRevision,
						entryCount: 1,
						kind: phase,
						transferId: `annotation-transfer-${catalogRevision}`,
						windowCount: 1,
					};
	return {
		authority: { subscriptionId, workerDerivationEpoch, worktreeId: 'worktree-1' },
		direction: 'serverWorkerToMain',
		kind: 'annotationCatalogStaging',
		operationCorrelationId: 'a'.repeat(64),
		surface: 'fileView',
		transfer,
		transferDescriptors: [],
		wireVersion: 1,
	};
}

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

function applyProjection(
	store: WorktreeAnnotationProjectionStore,
	projectionSnapshot: BridgeWorkerAnnotationProjectionSnapshot,
): void {
	store.apply({
		contentSessionIds: undefined,
		expectedContentSessionIds: [],
		operationCorrelationId: 'a'.repeat(64),
		reviewAnnotationApplication: null,
		snapshot: projectionSnapshot,
	});
}
