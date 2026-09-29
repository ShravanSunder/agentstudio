import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import { deriveWorktreeAnnotationShareProjection } from '../../worktree-annotations/worktree-annotation-share-projection.js';
import { installBridgeProductCommentBatch } from './bridge-product-comment-batch-installer.js';
import {
	createHarness,
	makeCommentCatalogInstallation,
	makeProjectionPages,
	sessionId,
	uuidv7,
	worktreeId,
} from './test-fixtures/bridge-comm-worker-annotation-projection.test-support.js';

describe('Bridge annotation projection session demand', () => {
	test('newly demanded installed session fetches rich content and exposes pending Share', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		harness.notifications.installCatalog(8);
		await harness.controller.waitForIdle();
		expect(harness.querySessionIds).toEqual([[]]);

		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
		const publication = harness.publications.at(-1);
		expect(publication?.contentSessionIds).toEqual([sessionId]);
		expect(publication?.snapshot.threads[0]?.messages[0]?.sessionId).toBe(sessionId);
		if (publication === undefined) throw new Error('Expected demanded annotation publication.');
		const share = deriveWorktreeAnnotationShareProjection({
			scope: 'pending',
			threads: publication.snapshot.threads,
		});
		expect(share.pendingCount).toBe(1);
		expect(share.inlineThreads[0]?.messages).toHaveLength(1);
	});

	test('A to B to A re-reads A from current content without a catalog change', async () => {
		const otherSessionId = uuidv7(42);
		const pagesA = await makeProjectionPages(1, 8);
		const pageA = pagesA[0];
		if (pageA === undefined) throw new Error('Expected one A projection page.');
		const bytesB = new TextEncoder().encode(
			new TextDecoder().decode(pageA.bytes).replaceAll(sessionId, otherSessionId),
		);
		const pageB = {
			bytes: bytesB,
			descriptor: {
				...pageA.descriptor,
				descriptorId: 'projection-session-b',
				maximumBytes: bytesB.byteLength,
				page: {
					...pageA.descriptor.page,
					aggregateSha256: createHash('sha256').update(bytesB).digest('hex'),
				},
			},
		};
		const harness = await createHarness({
			pages: [pageA, pageB],
			queryOverride: (request) =>
				Promise.resolve({
					descriptor: request.sessionIds.includes(otherSessionId)
						? pageB.descriptor
						: pageA.descriptor,
					kind: 'content',
				}),
		});
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		const subscriptionId = harness.notifications.subscription.subscriptionId;
		const catalog = installBridgeProductCommentBatch(
			makeCommentCatalogInstallation({
				entries: [
					{ kind: 'session', semanticRevision: 1, sessionId },
					{ kind: 'session', semanticRevision: 1, sessionId: otherSessionId },
				],
				revision: 8,
				subscriptionId,
				subscriptionKind: 'file.annotations',
				worktreeId,
			}),
			{ subscriptionId, workerDerivationEpoch: 1, worktreeId },
		);
		expect(harness.controller.acceptInstalledCatalog(catalog)).toBe(true);
		await harness.controller.waitForIdle();

		harness.controller.setDemand({
			active: true,
			sessionIds: [otherSessionId],
			sourceGeneration: 8,
		});
		await harness.controller.waitForIdle();
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();

		expect(harness.querySessionIds).toEqual([[], [sessionId], [otherSessionId], [sessionId]]);
		expect(harness.publications.at(-1)?.snapshot.threads[0]?.messages[0]?.sessionId).toBe(
			sessionId,
		);
	});

	test('equal demand adds no E4 query and pre-install demand uses the existing install path once', async () => {
		const harness = await createHarness({ pages: await makeProjectionPages(1, 8) });
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		harness.controller.ensureSubscription();
		harness.controller.setDemand({
			active: true,
			sessionIds: [sessionId, sessionId],
			sourceGeneration: 8,
		});
		expect(harness.querySessionIds).toEqual([]);

		harness.notifications.installCatalog(8);
		await harness.controller.waitForIdle();
		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
		harness.controller.setDemand({ active: true, sessionIds: [sessionId], sourceGeneration: 8 });
		await harness.controller.waitForIdle();
		expect(harness.querySessionIds).toEqual([[], [sessionId]]);
	});
});
