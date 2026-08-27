import { describe, expect, test } from 'vitest';

import { parseBridgeVerifierFileMetadataEvent } from '../../../scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.js';

describe('Bridge verifier File metadata application consumer', () => {
	test('rejects malformed and cross-kind raw data before the File predicate runs', () => {
		for (const rawData of [
			{},
			{
				event: {
					eventKind: 'snapshot.required',
					operationCorrelationId: null,
					sourceGeneration: 1,
					worktreeId: 'worktree-1',
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
