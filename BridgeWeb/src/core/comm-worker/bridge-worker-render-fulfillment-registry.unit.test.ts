import { describe, expect, test } from 'vitest';

import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import {
	BridgeWorkerRenderFulfillmentRegistry,
	type BridgeWorkerRenderFulfillmentRegistryContext,
} from './bridge-worker-render-fulfillment-registry.js';
import type {
	BridgeWorkerRenderDisposition,
	BridgeWorkerRenderDispositionReceipt,
	BridgeWorkerRenderReceiptIdentity,
} from './bridge-worker-render-fulfillment.js';

const reviewContext: BridgeWorkerRenderFulfillmentRegistryContext = {
	paneSessionId: 'pane-session-1',
	surface: 'review',
	workerInstanceId: 'worker-instance-1',
};

describe('Bridge worker render fulfillment registry', () => {
	test('requires a strictly positive receipt lease before publication can become reachable', () => {
		expect(
			() =>
				new BridgeWorkerRenderFulfillmentRegistry({
					context: reviewContext,
					receiptLeaseDurationMilliseconds: 0,
					retryBackoffMilliseconds: 5,
				}),
		).toThrow('Bridge render receipt lease duration must be finite and positive.');
	});

	test('mints one full publication identity and fulfills only after painted', () => {
		const identifiers = createIdentifierSequence();
		const registry = new BridgeWorkerRenderFulfillmentRegistry({
			context: reviewContext,
			createIdentifier: identifiers.create,
			now: (): number => 10,
			receiptLeaseDurationMilliseconds: 100,
			retryBackoffMilliseconds: 5,
		});

		const publication = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});

		expect(publication.status).toBe('published');
		expect(publication.shouldPublish).toBe(true);
		expect(publication.receiptIdentity).toEqual({
			attemptId: 'attempt-1',
			itemId: 'review-item-1',
			paneSessionId: 'pane-session-1',
			publicationId: 'publication-1',
			publicationSequence: 8,
			submissionId: 'submission-1',
			surface: 'review',
			windowKey: expect.stringContaining('bridge-render-window-v1'),
			workerDerivationEpoch: 3,
			workerInstanceId: 'worker-instance-1',
		});
		expect(registry.getItemState('review-item-1')?.isDesired).toBe(true);

		expect(
			registry.applyDisposition(disposition(publication.receiptIdentity, 'queued', 11)),
		).toEqual(expect.objectContaining({ status: 'accepted' }));
		expect(
			registry.applyDisposition(disposition(publication.receiptIdentity, 'applied', 12)),
		).toEqual(expect.objectContaining({ status: 'accepted' }));
		expect(registry.getItemState('review-item-1')?.isDesired).toBe(true);
		expect(
			registry.applyDisposition(disposition(publication.receiptIdentity, 'painted', 13)),
		).toEqual(expect.objectContaining({ status: 'accepted' }));
		expect(registry.getItemState('review-item-1')?.isDesired).toBe(false);
		expect(registry.getItemState('review-item-1')?.stage).toBe('painted');
	});

	test('coalesces one semantic publication and treats matching receipts idempotently', () => {
		const registry = createRegistry(reviewContext);
		const first = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});
		const duplicate = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 9,
			workerDerivationEpoch: 3,
		});

		expect(duplicate).toMatchObject({
			receiptIdentity: first.receiptIdentity,
			shouldPublish: false,
			status: 'duplicate',
		});
		const queuedReceipt = disposition(first.receiptIdentity, 'queued', 1);
		const accepted = registry.applyDisposition(queuedReceipt);
		const repeated = registry.applyDisposition(queuedReceipt);
		expect(accepted.status).toBe('accepted');
		expect(repeated.status).toBe('duplicate');
		expect(repeated.state).toBe(accepted.state);
	});

	test('replaces same-window publication authority when the surface derivation epoch advances', () => {
		const registry = createRegistry(reviewContext);
		const first = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});
		const replacement = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 9,
			workerDerivationEpoch: 4,
		});

		expect(replacement).toMatchObject({ shouldPublish: true, status: 'published' });
		expect(replacement.receiptIdentity).toMatchObject({
			publicationSequence: 9,
			workerDerivationEpoch: 4,
		});
		expect(replacement.receiptIdentity.publicationId).not.toBe(first.receiptIdentity.publicationId);
		expect(
			registry.applyDisposition(disposition(first.receiptIdentity, 'queued', 1)),
		).toMatchObject({ status: 'rejected' });
		expect(registry.getItemState('review-item-1')?.stage).toBe('published');
	});

	test('rejects stale, foreign, out-of-order and conflicting receipts without mutation', () => {
		const registry = createRegistry(reviewContext);
		const publication = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});
		const initial = registry.getItemState('review-item-1');

		for (const receipt of [
			disposition(publication.receiptIdentity, 'applied', 1),
			disposition({ ...publication.receiptIdentity, attemptId: 'attempt-foreign' }, 'queued', 1),
			disposition({ ...publication.receiptIdentity, paneSessionId: 'pane-foreign' }, 'queued', 1),
			disposition({ ...publication.receiptIdentity, windowKey: 'window-foreign' }, 'queued', 1),
		]) {
			expect(registry.applyDisposition(receipt)).toMatchObject({ status: 'rejected' });
			expect(registry.getItemState('review-item-1')).toBe(initial);
		}

		registry.applyDisposition(disposition(publication.receiptIdentity, 'queued', 2));
		registry.applyDisposition(disposition(publication.receiptIdentity, 'applied', 3));
		registry.applyDisposition(disposition(publication.receiptIdentity, 'painted', 4));
		const painted = registry.getItemState('review-item-1');
		expect(
			registry.applyDisposition(
				terminalDisposition(publication.receiptIdentity, 'rejected', 4, 'already_terminal'),
			),
		).toMatchObject({ status: 'rejected' });
		expect(registry.getItemState('review-item-1')).toBe(painted);
	});

	test('does not convert an internal receipt-parser failure into a recoverable rejection', () => {
		const registry = createRegistry(reviewContext);
		const publication = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});
		const invalidReceipt = {
			...disposition(publication.receiptIdentity, 'queued', 1),
			receivedAtMilliseconds: Number.NaN,
		} satisfies BridgeWorkerRenderDispositionReceipt;

		expect(() => registry.applyDisposition(invalidReceipt)).toThrow();
		expect(registry.getItemState('review-item-1')?.stage).toBe('published');
	});

	test.each(['rejected', 'superseded'] as const)(
		'keeps desired demand through %s and republishes with a new attempt only',
		(dispositionKind) => {
			let now = 0;
			const registry = createRegistry(reviewContext, (): number => now);
			const first = registry.beginPublication({
				job: makeRenderJob('review-item-1'),
				publicationSequence: 8,
				workerDerivationEpoch: 3,
			});
			registry.applyDisposition(
				terminalDisposition(first.receiptIdentity, dispositionKind, now, 'stale_attempt'),
			);

			expect(registry.getItemState('review-item-1')).toMatchObject({
				isDesired: true,
				stage: 'retry_wait',
			});
			now = 5;
			expect(registry.releaseReadyRetries()).toEqual(['review-item-1']);
			const retry = registry.beginPublication({
				job: makeRenderJob('review-item-1'),
				publicationSequence: 99,
				workerDerivationEpoch: 3,
			});
			expect(retry).toMatchObject({ shouldPublish: true, status: 'published' });
			expect(retry.receiptIdentity.attemptId).not.toBe(first.receiptIdentity.attemptId);
			expect(retry.receiptIdentity.publicationId).toBe(first.receiptIdentity.publicationId);
			expect(retry.receiptIdentity.submissionId).toBe(first.receiptIdentity.submissionId);
			expect(retry.receiptIdentity.publicationSequence).toBe(
				first.receiptIdentity.publicationSequence,
			);
		},
	);

	test('keeps desired demand through lease expiry and bounded retry release', () => {
		let now = 0;
		const registry = createRegistry(reviewContext, (): number => now);
		const publication = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});

		now = 100;
		expect(registry.expireReceiptLeases()).toEqual(['review-item-1']);
		expect(registry.getItemState('review-item-1')).toMatchObject({
			isDesired: true,
			retryAtMilliseconds: 105,
			stage: 'retry_wait',
		});
		now = 104;
		expect(registry.releaseReadyRetries()).toEqual([]);
		now = 105;
		expect(registry.releaseReadyRetries()).toEqual(['review-item-1']);
		const retry = registry.beginPublication({
			job: makeRenderJob('review-item-1'),
			publicationSequence: 9,
			workerDerivationEpoch: 3,
		});
		expect(retry.receiptIdentity.attemptId).not.toBe(publication.receiptIdentity.attemptId);
	});

	test('isolates identical File and Review item ids in separate surface registries', () => {
		const reviewRegistry = createRegistry(reviewContext);
		const fileRegistry = createRegistry({ ...reviewContext, surface: 'file' });
		const reviewPublication = reviewRegistry.beginPublication({
			job: makeRenderJob('shared-item'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});
		const filePublication = fileRegistry.beginPublication({
			job: makeRenderJob('shared-item'),
			publicationSequence: 8,
			workerDerivationEpoch: 3,
		});

		expect(
			fileRegistry.applyDisposition(disposition(reviewPublication.receiptIdentity, 'queued', 1)),
		).toMatchObject({ status: 'rejected' });
		expect(reviewRegistry.getItemState('shared-item')?.stage).toBe('published');
		expect(fileRegistry.getItemState('shared-item')?.stage).toBe('published');
		expect(filePublication.receiptIdentity.surface).toBe('file');
	});
});

function createRegistry(
	context: BridgeWorkerRenderFulfillmentRegistryContext,
	now: () => number = (): number => 0,
): BridgeWorkerRenderFulfillmentRegistry {
	return new BridgeWorkerRenderFulfillmentRegistry({
		context,
		createIdentifier: createIdentifierSequence().create,
		now,
		receiptLeaseDurationMilliseconds: 100,
		retryBackoffMilliseconds: 5,
	});
}

function createIdentifierSequence(): {
	readonly create: (purpose: 'attempt' | 'publication' | 'submission') => string;
} {
	const nextByPurpose = { attempt: 0, publication: 0, submission: 0 };
	return {
		create: (purpose): string => {
			nextByPurpose[purpose] += 1;
			return `${purpose}-${nextByPurpose[purpose]}`;
		},
	};
}

function makeRenderJob(itemId: string): BridgeWorkerPierreRenderJob {
	return buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'visible', priority: 1 },
		budget: { className: 'visible', maxBytes: 1024, maxWindowLines: 4 },
		contentCacheKey: `cache-${itemId}`,
		contentHash: 'a'.repeat(64),
		itemId,
		language: 'text',
		payload: {
			kind: 'codeViewFileItem',
			item: {
				bridgeMetadata: {
					cacheKey: `cache-${itemId}`,
					contentRoles: ['file'],
					contentState: 'hydrated',
					displayPath: `${itemId}.txt`,
					itemId,
					lineCount: 1,
				},
				file: { cacheKey: `cache-${itemId}`, contents: 'content', name: `${itemId}.txt` },
				id: itemId,
				type: 'file',
			},
		},
		renderKind: 'fileText',
		window: { endLine: 1, startLine: 1, totalLineCount: 1 },
	});
}

function disposition(
	identity: BridgeWorkerRenderReceiptIdentity,
	dispositionValue: BridgeWorkerRenderDisposition,
	receivedAtMilliseconds: number,
): BridgeWorkerRenderDispositionReceipt {
	if (dispositionValue === 'rejected' || dispositionValue === 'superseded') {
		return {
			...identity,
			disposition: dispositionValue,
			kind: 'render.disposition',
			reason: 'stale_attempt',
			receivedAtMilliseconds,
			retryAtMilliseconds: receivedAtMilliseconds + 5,
		};
	}
	return {
		...identity,
		disposition: dispositionValue,
		kind: 'render.disposition',
		receivedAtMilliseconds,
	};
}

function terminalDisposition(
	identity: BridgeWorkerRenderReceiptIdentity,
	dispositionValue: 'rejected' | 'superseded',
	receivedAtMilliseconds: number,
	reason: 'already_terminal' | 'stale_attempt',
): BridgeWorkerRenderDispositionReceipt {
	return {
		...identity,
		disposition: dispositionValue,
		kind: 'render.disposition',
		reason,
		receivedAtMilliseconds,
		retryAtMilliseconds: receivedAtMilliseconds + 5,
	};
}
