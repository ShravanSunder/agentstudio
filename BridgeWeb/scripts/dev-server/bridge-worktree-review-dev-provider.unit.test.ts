import { describe, expect, test } from 'vitest';

import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../src/foundation/review-package/bridge-review-package.js';
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
					basePath: 'src/app.ts',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'export const value = 2;\nexport const next = true;\n',
					headPath: 'src/app.ts',
					path: 'src/app.ts',
				},
				{
					additions: 3,
					baseContent: null,
					basePath: null,
					changeKind: 'added',
					deletions: 0,
					headContent: '# Docs\n\nNew docs\n',
					headPath: 'docs/readme.md',
					path: 'docs/readme.md',
				},
				{
					additions: 1,
					baseContent: 'ignored-old\n',
					basePath: '.gitignore',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'ignored-new\n',
					headPath: '.gitignore',
					path: '.gitignore',
				},
				{
					additions: 1,
					baseContent: 'export const renamed = 1;\n',
					basePath: 'src/old-name.ts',
					changeKind: 'renamed',
					deletions: 1,
					headContent: 'export const renamed = 2;\n',
					headPath: 'src/new-name.ts',
					path: 'src/new-name.ts',
				},
				{
					additions: 1,
					baseContent: 'export const copied = 1;\n',
					basePath: 'src/template.ts',
					changeKind: 'copied',
					deletions: 0,
					headContent: 'export const copied = 1;\nexport const extra = true;\n',
					headPath: 'src/copied.ts',
					path: 'src/copied.ts',
				},
				{
					additions: 1,
					baseContent: null,
					basePath: null,
					changeKind: 'added',
					deletions: 0,
					headContent: 'dash\n',
					headPath: 'a-b.ts',
					path: 'a-b.ts',
				},
				{
					additions: 1,
					baseContent: null,
					basePath: null,
					changeKind: 'added',
					deletions: 0,
					headContent: 'slash\n',
					headPath: 'a/b.ts',
					path: 'a/b.ts',
				},
			],
		} satisfies BridgeWorktreeReviewDevSnapshot;

		const result = createBridgeWorktreeReviewDevPackage({
			baseRef: 'base-sha',
			snapshot,
		});

		expect(result.reviewPackage.packageId).toBe('worktree-review-abc123def456');
		expect(new Set(result.reviewPackage.orderedItemIds).size).toBe(
			result.reviewPackage.orderedItemIds.length,
		);
		expect(result.reviewPackage.summary).toEqual({
			additions: 10,
			deletions: 3,
			filesChanged: 7,
			hiddenFileCount: 0,
			visibleFileCount: 7,
		});
		const modifiedItem = itemByHeadPath(result.reviewPackage, 'src/app.ts');
		expect(modifiedItem?.changeKind).toBe('modified');
		expect(modifiedItem?.itemId).toMatch(/^worktree-review-[a-f0-9]{12}-src-app-ts$/u);
		expect(modifiedItem?.contentRoles.base?.resourceUrl).toContain(
			'?generation=1&revision=1&cursor=worktree-review-abc123def456',
		);
		expect(result.contentByHandleId.get(modifiedItem?.contentRoles.base?.handleId ?? '')).toBe(
			'export const value = 1;\n',
		);
		expect(result.contentByHandleId.get(modifiedItem?.contentRoles.head?.handleId ?? '')).toBe(
			'export const value = 2;\nexport const next = true;\n',
		);
		const addedItem = itemByHeadPath(result.reviewPackage, 'docs/readme.md');
		expect(addedItem?.itemKind).toBe('file');
		expect(addedItem?.contentRoles.base).toBeNull();
		expect(result.contentByHandleId.get(addedItem?.contentRoles.file?.handleId ?? '')).toBe(
			'# Docs\n\nNew docs\n',
		);
		const extensionlessItem = itemByHeadPath(result.reviewPackage, '.gitignore');
		expect(extensionlessItem?.extension).toBeNull();
		expect(extensionlessItem?.language).toBe('text');
		const renamedItem = itemByHeadPath(result.reviewPackage, 'src/new-name.ts');
		expect(renamedItem?.itemKind).toBe('diff');
		expect(renamedItem?.changeKind).toBe('renamed');
		expect(renamedItem?.basePath).toBe('src/old-name.ts');
		expect(renamedItem?.headPath).toBe('src/new-name.ts');
		expect(result.contentByHandleId.get(renamedItem?.contentRoles.base?.handleId ?? '')).toBe(
			'export const renamed = 1;\n',
		);
		const copiedItem = itemByHeadPath(result.reviewPackage, 'src/copied.ts');
		expect(copiedItem?.itemKind).toBe('diff');
		expect(copiedItem?.changeKind).toBe('copied');
		expect(copiedItem?.basePath).toBe('src/template.ts');
		expect(copiedItem?.headPath).toBe('src/copied.ts');
		expect(itemByHeadPath(result.reviewPackage, 'a-b.ts')?.itemId).not.toBe(
			itemByHeadPath(result.reviewPackage, 'a/b.ts')?.itemId,
		);
	});
});

function itemByHeadPath(
	reviewPackage: BridgeReviewPackage,
	path: string,
): BridgeReviewItemDescriptor | undefined {
	return Object.values(reviewPackage.itemsById).find((item) => item.headPath === path);
}
