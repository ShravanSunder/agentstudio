import { describe, expect, test } from 'vitest';

import {
	createBridgeWorktreeReviewDevPackage,
	type BridgeWorktreeReviewDevSnapshot,
} from './bridge-worktree-review-dev-provider.js';

describe('Bridge worktree review dev provider', () => {
	test('builds a review package and content map from changed worktree files', () => {
		const snapshot = {
			fingerprint: 'abc123def456',
			changedFiles: [
				{
					additions: 2,
					baseContent: 'export const value = 1;\n',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'export const value = 2;\nexport const next = true;\n',
					path: 'src/app.ts',
				},
				{
					additions: 3,
					baseContent: null,
					changeKind: 'added',
					deletions: 0,
					headContent: '# Docs\n\nNew docs\n',
					path: 'docs/readme.md',
				},
				{
					additions: 1,
					baseContent: 'ignored-old\n',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'ignored-new\n',
					path: '.gitignore',
				},
			],
		} satisfies BridgeWorktreeReviewDevSnapshot;

		const result = createBridgeWorktreeReviewDevPackage({
			baseRef: 'base-sha',
			snapshot,
		});

		expect(result.reviewPackage.packageId).toBe('worktree-review-abc123def456');
		expect(result.reviewPackage.orderedItemIds).toEqual([
			'worktree-review-src-app-ts',
			'worktree-review-docs-readme-md',
			'worktree-review-gitignore',
		]);
		expect(result.reviewPackage.summary).toEqual({
			additions: 6,
			deletions: 2,
			filesChanged: 3,
			hiddenFileCount: 0,
			visibleFileCount: 3,
		});
		const modifiedItem = result.reviewPackage.itemsById['worktree-review-src-app-ts'];
		expect(modifiedItem?.changeKind).toBe('modified');
		expect(modifiedItem?.contentRoles.base?.handleId).toBe('worktree-review-src-app-ts-base');
		expect(modifiedItem?.contentRoles.head?.handleId).toBe('worktree-review-src-app-ts-head');
		expect(result.contentByHandleId.get('worktree-review-src-app-ts-base')).toBe(
			'export const value = 1;\n',
		);
		expect(result.contentByHandleId.get('worktree-review-src-app-ts-head')).toBe(
			'export const value = 2;\nexport const next = true;\n',
		);
		const addedItem = result.reviewPackage.itemsById['worktree-review-docs-readme-md'];
		expect(addedItem?.itemKind).toBe('file');
		expect(addedItem?.contentRoles.base).toBeNull();
		expect(addedItem?.contentRoles.file?.handleId).toBe('worktree-review-docs-readme-md-file');
		expect(result.contentByHandleId.get('worktree-review-docs-readme-md-file')).toBe(
			'# Docs\n\nNew docs\n',
		);
		const extensionlessItem = result.reviewPackage.itemsById['worktree-review-gitignore'];
		expect(extensionlessItem?.extension).toBeNull();
		expect(extensionlessItem?.language).toBe('text');
	});
});
