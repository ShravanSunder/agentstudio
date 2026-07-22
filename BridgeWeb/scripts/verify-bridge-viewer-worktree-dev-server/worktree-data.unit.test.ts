import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

const worktreeDataSourcePath = fileURLToPath(new URL('./worktree-data.ts', import.meta.url));

describe('Bridge viewer worktree verifier File transport', () => {
	test('uses the typed product File session without legacy File routes', async () => {
		// Arrange
		const source = await readFile(worktreeDataSourcePath, 'utf8');

		// Act
		const legacyFileRoutes = [
			'/__bridge-worktree/surface',
			'/__bridge-worktree/file-descriptor',
			'/__bridge-worktree/file-content',
		].filter((route) => source.includes(route));

		// Assert
		expect(legacyFileRoutes).toEqual([]);
		expect(source).toContain('BridgeVerifierProductFileSession');
		expect(source).toContain('session.open()');
		expect(source).toContain('session.demandDescriptor(');
		expect(source).toContain('session.openContent(');
	});
});
