import { describe, expect, test } from 'vitest';

import { parseBridgeVerifierFileMetadataEvent } from '../../../scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.js';

describe('Bridge verifier File metadata application consumer', () => {
	test('rejects malformed and cross-kind raw data before the File predicate runs', () => {
		for (const rawData of [
			{},
			{
				event: {
					authority: {
						applicationSourceGeneration: 1,
						worktreeId: 'worktree-1',
					},
					kind: 'annotation.catalog',
					transfer: {
						catalogRevision: 1,
						expectedEntryCount: 0,
						kind: 'catalog.begin',
						transferId: 'annotation-catalog-transfer-1',
					},
				},
				subscriptionKind: 'review.annotations',
			},
		]) {
			let predicateInvocationCount = 0;
			expect(() => {
				const event = parseBridgeVerifierFileMetadataEvent(rawData);
				predicateInvocationCount += 1;
				return event.eventKind;
			}).toThrow();
			expect(predicateInvocationCount).toBe(0);
		}
	});
});
