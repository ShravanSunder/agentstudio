import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const sourceUrl = new URL('./review-projection-worker-entry.ts', import.meta.url);

describe('review projection worker entry abort contract', () => {
	test('does not persist abort keys across replacement projection requests', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).not.toContain('abortedRequestKeys.add');
		expect(source).not.toContain('Projection request was aborted');
	});
});
