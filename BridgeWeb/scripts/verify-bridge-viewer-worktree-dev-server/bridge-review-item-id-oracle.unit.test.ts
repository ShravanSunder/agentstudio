import { describe, expect, test } from 'vitest';

import { bridgeReviewItemIdOracle } from './bridge-review-item-id-oracle.ts';

describe('Bridge Review item identity oracle', () => {
	test('matches Swift direct-Git identity normalization', () => {
		expect(
			bridgeReviewItemIdOracle({
				newContentHash: '0012d07b3e39f11fe4bb62d90b73c097e358b026',
				oldContentHash: '1536fbf375512b5e24ec4640d8603098aaf71b80',
				path: 'nested/group-01/file-01.ts',
				previousPath: null,
			}),
		).toBe('item-git-diff-78e41be96d6cf64961ba6b389a2cb3ffe47c9dd3d8a1681bf191aceaee956d16');
	});
});
