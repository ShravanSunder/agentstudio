import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const sourceUrl = new URL('./bridge-app-dev-worktree-review.ts', import.meta.url);

describe('Bridge app dev worktree Review backend contract', () => {
	test('does not install old command nonce control-plane state', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).not.toContain('data-bridge-nonce');
		expect(source).not.toContain('previousCommandNonce');
		expect(source).not.toContain('bridgeWorktreeReviewCommandNonce');
	});

	test('uses metadata bootstrap and content-only resource fetches', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).toContain(
			"const worktreeReviewMetadataEndpoint = '/__bridge-worktree/review-metadata'",
		);
		expect(source).not.toContain('/__bridge-worktree/review-package');
		expect(source).toContain("review: new Set(['content'])");
		expect(source).not.toContain('review-package');
		expect(source).not.toContain('review-delta');
		expect(source).toContain("frameKind !== 'review.metadataSnapshot'");
	});
});
