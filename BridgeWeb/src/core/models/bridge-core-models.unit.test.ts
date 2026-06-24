import { describe, expect, test } from 'vitest';

import {
	bridgeBoundedWindowSchema,
	bridgeProtocolIdSchema,
	bridgeResourceKindSchema,
	bridgeStreamIdentitySchema,
} from './bridge-core-models.js';

describe('bridge core transport models', () => {
	test('parses protocol ids, resource kinds, stream identities, and bounded windows', () => {
		expect(bridgeProtocolIdSchema.parse('review')).toBe('review');
		expect(bridgeProtocolIdSchema.parse('worktree-file')).toBe('worktree-file');
		expect(bridgeResourceKindSchema.parse('content')).toBe('content');
		expect(bridgeResourceKindSchema.parse('review-package')).toBe('review-package');
		expect(
			bridgeStreamIdentitySchema.parse({
				protocol: 'review',
				streamId: 'stream-1',
				generation: 2,
				revision: 4,
				cursor: 'cursor_1',
			}),
		).toEqual({
			protocol: 'review',
			streamId: 'stream-1',
			generation: 2,
			revision: 4,
			cursor: 'cursor_1',
		});
		expect(
			bridgeBoundedWindowSchema.parse({
				start: 0,
				count: 25,
				maxCount: 100,
			}),
		).toEqual({
			start: 0,
			count: 25,
			maxCount: 100,
		});
	});

	test('rejects empty ids, negative revisions, and unbounded request windows', () => {
		expect(bridgeProtocolIdSchema.safeParse('').success).toBe(false);
		expect(bridgeProtocolIdSchema.safeParse('review/open').success).toBe(false);
		expect(bridgeProtocolIdSchema.safeParse('review open').success).toBe(false);
		expect(bridgeResourceKindSchema.safeParse('').success).toBe(false);
		expect(bridgeResourceKindSchema.safeParse('content/open').success).toBe(false);
		expect(
			bridgeStreamIdentitySchema.safeParse({
				protocol: 'review',
				streamId: 'stream-1',
				revision: -1,
			}).success,
		).toBe(false);
		expect(
			bridgeBoundedWindowSchema.safeParse({
				start: 0,
				count: 101,
				maxCount: 100,
			}).success,
		).toBe(false);
	});
});
