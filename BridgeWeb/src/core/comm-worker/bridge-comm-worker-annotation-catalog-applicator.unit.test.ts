import { describe, expect, test } from 'vitest';

import {
	BridgeCommWorkerAnnotationCatalogApplicator,
	type BridgeCommWorkerAnnotationCatalogApplicatorResult,
	type BridgeCommWorkerAnnotationCatalogAuthority,
} from './bridge-comm-worker-annotation-catalog-applicator.js';
import type {
	BridgeProductWorktreeAnnotationCatalogEntry,
	BridgeProductWorktreeAnnotationEvent,
} from './bridge-product-worktree-annotation-contracts.js';

const sessionId = '01890abc-def0-7abc-8def-0123456789ab';
const threadId = '01890abc-def0-7abc-8def-0123456789ac';
const messageId = '01890abc-def0-7abc-8def-0123456789ad';
const initialAuthority = {
	subscriptionId: 'annotation-subscription-1',
	workerDerivationEpoch: 1,
	worktreeId: 'worktree-1',
} satisfies BridgeCommWorkerAnnotationCatalogAuthority;

describe('Bridge communication worker annotation catalog applicator', () => {
	test('keeps the active catalog unchanged until one valid transfer commits', () => {
		const applicator = new BridgeCommWorkerAnnotationCatalogApplicator(initialAuthority);
		const entries = validCatalogEntries();

		expect(
			applicator.accept(catalogEvent(7, beginTransfer('transfer-7', 7, entries.length))),
		).toEqual({
			status: 'accepted',
		});
		expect(applicator.activeCatalog).toBeNull();
		expect(applicator.accept(catalogEvent(7, windowTransfer('transfer-7', 7, entries)))).toEqual({
			status: 'accepted',
		});
		expect(applicator.activeCatalog).toBeNull();

		const completed = applicator.accept(
			catalogEvent(7, commitTransfer('transfer-7', 7, entries.length)),
		);
		expect(completed.status).toBe('completed');
		expect(applicator.activeCatalog?.orderedSessionIds).toEqual([sessionId]);
		expect(applicator.activeCatalog?.threadIdsBySessionId.get(sessionId)).toEqual([threadId]);
		expect(applicator.activeCatalog?.messageIdsByThreadId.get(threadId)).toEqual([messageId]);
	});

	test('rejects invalid relationships without replacing the last complete catalog', () => {
		const applicator = new BridgeCommWorkerAnnotationCatalogApplicator(initialAuthority);
		commitCatalog(applicator, 3, 'valid-3', validCatalogEntries());
		const priorCatalog = applicator.activeCatalog;
		const orphanThread = {
			createdOrdinal: 0,
			kind: 'thread',
			scope: 'located',
			sessionId: '01890abc-def0-7abc-8def-0123456789ae',
			threadId: '01890abc-def0-7abc-8def-0123456789af',
		} satisfies BridgeProductWorktreeAnnotationCatalogEntry;

		expect(commitCatalog(applicator, 4, 'invalid-4', [orphanThread])).toEqual({
			reason: 'unknown_session',
			status: 'rejected',
		});
		expect(applicator.activeCatalog).toBe(priorCatalog);
	});

	test('ignores late superseded frames without damaging the newer candidate', () => {
		const applicator = new BridgeCommWorkerAnnotationCatalogApplicator(initialAuthority);
		const entries = validCatalogEntries();
		applicator.accept(catalogEvent(5, beginTransfer('transfer-5', 5, entries.length)));
		applicator.accept(catalogEvent(6, beginTransfer('transfer-6', 6, entries.length)));

		expect(applicator.accept(catalogEvent(5, windowTransfer('transfer-5', 5, entries)))).toEqual({
			reason: 'noncurrent_transfer',
			status: 'rejected',
		});
		expect(applicator.accept(catalogEvent(6, windowTransfer('transfer-6', 6, entries)))).toEqual({
			status: 'accepted',
		});
		expect(
			applicator.accept(catalogEvent(6, commitTransfer('transfer-6', 6, entries.length))).status,
		).toBe('completed');
		expect(applicator.activeCatalog?.catalogRevision).toBe(6);
	});

	test('admits a lower first revision after lifecycle authority replacement', () => {
		const applicator = new BridgeCommWorkerAnnotationCatalogApplicator(initialAuthority);
		commitCatalog(applicator, 20, 'transfer-20', validCatalogEntries());
		applicator.replaceExpectedAuthority({
			...initialAuthority,
			subscriptionId: 'annotation-subscription-2',
			workerDerivationEpoch: 2,
		});

		expect(commitCatalog(applicator, 1, 'transfer-1', validCatalogEntries()).status).toBe(
			'completed',
		);
		expect(applicator.activeCatalog?.catalogRevision).toBe(1);
	});

	test('rejects an event for an unexpected worktree authority', () => {
		const applicator = new BridgeCommWorkerAnnotationCatalogApplicator(initialAuthority);
		const event = catalogEvent(1, beginTransfer('transfer-1', 1, 0));

		expect(
			applicator.accept({
				...event,
				authority: { ...event.authority, worktreeId: 'worktree-2' },
			}),
		).toEqual({ reason: 'unexpected_authority', status: 'rejected' });
	});
});

function validCatalogEntries(): readonly BridgeProductWorktreeAnnotationCatalogEntry[] {
	return [
		{ kind: 'session', semanticRevision: 3, sessionId },
		{ createdOrdinal: 0, kind: 'thread', scope: 'whole_file', sessionId, threadId },
		{ kind: 'message', messageId, ordinal: 0, threadId },
	];
}

function catalogEvent(
	applicationSourceGeneration: number,
	transfer: Extract<
		BridgeProductWorktreeAnnotationEvent,
		{ kind: 'annotation.catalog' }
	>['transfer'],
): Extract<BridgeProductWorktreeAnnotationEvent, { kind: 'annotation.catalog' }> {
	return {
		authority: { applicationSourceGeneration, worktreeId: initialAuthority.worktreeId },
		kind: 'annotation.catalog',
		transfer,
	};
}

function beginTransfer(
	transferId: string,
	catalogRevision: number,
	expectedEntryCount: number,
): Extract<
	Extract<BridgeProductWorktreeAnnotationEvent, { kind: 'annotation.catalog' }>['transfer'],
	{ kind: 'catalog.begin' }
> {
	return { catalogRevision, expectedEntryCount, kind: 'catalog.begin', transferId };
}

function windowTransfer(
	transferId: string,
	catalogRevision: number,
	entries: readonly BridgeProductWorktreeAnnotationCatalogEntry[],
): Extract<
	Extract<BridgeProductWorktreeAnnotationEvent, { kind: 'annotation.catalog' }>['transfer'],
	{ kind: 'catalog.window' }
> {
	return { catalogRevision, entries, kind: 'catalog.window', transferId, windowOrdinal: 0 };
}

function commitTransfer(
	transferId: string,
	catalogRevision: number,
	entryCount: number,
): Extract<
	Extract<BridgeProductWorktreeAnnotationEvent, { kind: 'annotation.catalog' }>['transfer'],
	{ kind: 'catalog.commit' }
> {
	return { catalogRevision, entryCount, kind: 'catalog.commit', transferId, windowCount: 1 };
}

function commitCatalog(
	applicator: BridgeCommWorkerAnnotationCatalogApplicator,
	catalogRevision: number,
	transferId: string,
	entries: readonly BridgeProductWorktreeAnnotationCatalogEntry[],
): BridgeCommWorkerAnnotationCatalogApplicatorResult {
	applicator.accept(
		catalogEvent(catalogRevision, beginTransfer(transferId, catalogRevision, entries.length)),
	);
	applicator.accept(
		catalogEvent(catalogRevision, windowTransfer(transferId, catalogRevision, entries)),
	);
	return applicator.accept(
		catalogEvent(catalogRevision, commitTransfer(transferId, catalogRevision, entries.length)),
	);
}
