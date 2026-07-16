import { describe, expect, test } from 'vitest';

import { bridgeProductControlCommandSchema } from './bridge-product-control-contracts.js';

describe('Bridge product-control contracts', () => {
	test('accepts the closed worker-owned product-control commands', () => {
		expect(
			[
				{ method: 'review.markFileViewed', params: { fileId: 'item-1' } },
				{
					method: 'bridge.activeViewerMode.update',
					params: {
						activeSource: {
							generation: 3,
							protocol: 'review',
							streamId: 'review-stream',
						},
						mode: 'review',
						sequence: 9,
						sessionId: 'viewer-session',
					},
				},
				{
					method: 'bridge.intakeReady',
					params: {
						protocolId: 'review',
						reason: 'bridge-ready',
						streamId: 'review-stream',
					},
				},
			].map((command) => bridgeProductControlCommandSchema.parse(command)),
		).toHaveLength(3);
	});

	test('rejects JSON-RPC envelopes and commands outside product control', () => {
		expect(
			bridgeProductControlCommandSchema.safeParse({
				jsonrpc: '2.0',
				id: 'legacy-command',
				method: 'review.markFileViewed',
				params: { fileId: 'item-1' },
			}).success,
		).toBe(false);
		expect(
			bridgeProductControlCommandSchema.safeParse({
				method: 'bridge.metadata_interest.update',
				params: { itemIds: ['item-1'], lane: 'foreground', protocol: 'review' },
			}).success,
		).toBe(false);
	});
});
