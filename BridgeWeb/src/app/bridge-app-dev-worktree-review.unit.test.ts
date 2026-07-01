import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const sourceUrl = new URL('./bridge-app-dev-worktree-review.ts', import.meta.url);

describe('Bridge app dev worktree Review backend contract', () => {
	test('installs the command nonce required for control-plane telemetry commands', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).toContain("const bridgeCommandNonceAttribute = 'data-bridge-nonce'");
		expect(source).toContain('previousCommandNonce');
		expect(source).toContain('bridgeWorktreeReviewCommandNonce');
		expect(source).toContain(
			'restoreDocumentElementAttribute(bridgeCommandNonceAttribute, previousCommandNonce)',
		);
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
