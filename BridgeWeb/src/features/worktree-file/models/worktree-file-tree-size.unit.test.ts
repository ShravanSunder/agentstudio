import { describe, expect, test } from 'vitest';

import { countFlattenedWorktreeFileTreeRows } from './worktree-file-tree-size.js';

describe('countFlattenedWorktreeFileTreeRows', () => {
	test('counts visible directory rows in addition to file rows', () => {
		const rowCount = countFlattenedWorktreeFileTreeRows([
			'src/app.ts',
			'src/components/button.tsx',
			'src/components/menu.tsx',
			'docs/readme.md',
		]);

		expect(rowCount).toBe(7);
	});

	test('keeps the final file-owning directory row after flattening single-directory chains', () => {
		const rowCount = countFlattenedWorktreeFileTreeRows([
			'src/features/worktree-file/models/worktree-file-tree-size.ts',
		]);

		expect(rowCount).toBe(2);
	});
});
