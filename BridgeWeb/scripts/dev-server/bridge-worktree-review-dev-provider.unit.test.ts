import { describe, expect, test } from 'vitest';

import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../src/foundation/review-package/bridge-review-package.js';
import { buildBridgeReviewProjectionFromInput } from '../../src/review-viewer/navigation/review-projection.js';
import {
	createBridgeWorktreeReviewDevProvider,
	createBridgeWorktreeReviewDevMetadata,
	type BridgeWorktreeReviewDevSnapshot,
} from './bridge-worktree-review-dev-provider.js';

describe('Bridge worktree review dev provider', () => {
	test('builds review metadata and content map from changed worktree files', () => {
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

		const result = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot,
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});

		expect(result.metadataFrame.frameKind).toBe('review.metadataSnapshot');
		expect(result.metadataFrame.comparison.packageId).toBe('worktree-review-abc123def456');
		expect(result.metadataFrame.comparison).not.toHaveProperty('rootDescriptor');
		expect(new Set(result.metadataFrame.itemMetadata.map((item) => item.itemId)).size).toBe(
			result.metadataFrame.itemMetadata.length,
		);
		expect(
			new Set(
				result.metadataFrame.comparison.contentDescriptors?.map(
					(attachedDescriptor) => attachedDescriptor.descriptor.resourceKind,
				),
			),
		).toEqual(new Set(['content']));
		const reviewPackage = result.reviewMetadataSource;
		expect(reviewPackage.query.baseEndpointId).toBe('baseline-local-default');
		expect(reviewPackage.query.headEndpointId).toBe('working-tree');
		expect(reviewPackage.baseEndpoint.label).toBe('Default');
		expect(reviewPackage.baseEndpoint.providerIdentity).toBe('base-sha');
		expect(reviewPackage.headEndpoint.kind).toBe('workingTree');
		const modifiedItem = itemByHeadPath(reviewPackage, 'src/app.ts');
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
		expect(modifiedItem?.contentLineCountsByRole).toEqual({
			base: 1,
			head: 2,
		});
		expect(
			result.metadataFrame.extentFacts.filter((fact) => fact.itemId === modifiedItem?.itemId),
		).toEqual([
			{ itemId: modifiedItem?.itemId, contentRole: 'base', lineCount: 1 },
			{ itemId: modifiedItem?.itemId, contentRole: 'head', lineCount: 2 },
		]);
		const addedItem = itemByHeadPath(reviewPackage, 'docs/readme.md');
		expect(addedItem?.itemKind).toBe('file');
		expect(addedItem?.contentRoles.base).toBeNull();
		expect(result.contentByHandleId.get(addedItem?.contentRoles.file?.handleId ?? '')).toBe(
			'# Docs\n\nNew docs\n',
		);
		expect(addedItem?.contentLineCountsByRole).toEqual({ file: 3 });
		const extensionlessItem = itemByHeadPath(reviewPackage, '.gitignore');
		expect(extensionlessItem?.extension).toBeNull();
		expect(extensionlessItem?.language).toBe('text');
		const renamedItem = itemByHeadPath(reviewPackage, 'src/new-name.ts');
		expect(renamedItem?.itemKind).toBe('diff');
		expect(renamedItem?.changeKind).toBe('renamed');
		expect(renamedItem?.basePath).toBe('src/old-name.ts');
		expect(renamedItem?.headPath).toBe('src/new-name.ts');
		expect(result.contentByHandleId.get(renamedItem?.contentRoles.base?.handleId ?? '')).toBe(
			'export const renamed = 1;\n',
		);
		const copiedItem = itemByHeadPath(reviewPackage, 'src/copied.ts');
		expect(copiedItem?.itemKind).toBe('diff');
		expect(copiedItem?.changeKind).toBe('copied');
		expect(copiedItem?.basePath).toBe('src/template.ts');
		expect(copiedItem?.headPath).toBe('src/copied.ts');
		expect(itemByHeadPath(reviewPackage, 'a-b.ts')?.itemId).not.toBe(
			itemByHeadPath(reviewPackage, 'a/b.ts')?.itemId,
		);
	});

	test('reuses current metadata for windows and refreshes only on explicit snapshot reload', async () => {
		let loadSnapshotCallCount = 0;
		const snapshot = {
			fingerprint: 'cached123456',
			changedFiles: [
				{
					additions: 1,
					baseContent: 'export const value = 1;\n',
					basePath: 'src/app.ts',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'export const value = 2;\n',
					headPath: 'src/app.ts',
					path: 'src/app.ts',
				},
			],
		} satisfies BridgeWorktreeReviewDevSnapshot;
		const provider = createBridgeWorktreeReviewDevProvider(
			{
				baseRef: 'base-sha',
				scenarioName: 'current-worktree',
				worktreeRoot: '/tmp/bridge-review-cache-fixture',
			},
			{
				loadSnapshot: async () => {
					loadSnapshotCallCount += 1;
					return snapshot;
				},
			},
		);

		const firstMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const secondMetadataResult = await provider.loadReviewMetadata();
		const refreshedMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const firstItemId = firstMetadataResult.reviewMetadataSource.orderedItemIds[0];
		expect(firstItemId).toBeDefined();
		const firstItem = firstMetadataResult.reviewMetadataSource.itemsById[firstItemId ?? ''];
		const headHandle = firstItem?.contentRoles.head;
		expect(headHandle).not.toBeNull();
		const content = await provider.loadReviewContent({
			generation: firstMetadataResult.metadataFrame.comparison.generation,
			handleId: headHandle?.handleId ?? '',
			packageId: firstMetadataResult.metadataFrame.comparison.packageId,
			revision: firstMetadataResult.metadataFrame.comparison.revision,
		});

		expect(secondMetadataResult).toBe(firstMetadataResult);
		expect(refreshedMetadataResult).not.toBe(firstMetadataResult);
		expect(refreshedMetadataResult.metadataFrame.comparison.packageId).toBe(
			firstMetadataResult.metadataFrame.comparison.packageId,
		);
		expect(secondMetadataResult.metadataFrame.comparison.packageId).toBe(
			firstMetadataResult.metadataFrame.comparison.packageId,
		);
		expect(content).toBe('export const value = 2;\n');
		expect(loadSnapshotCallCount).toBe(2);
	});

	test('bounds the initial metadata frame for large worktree reviews', () => {
		const snapshot = {
			fingerprint: 'large1234567',
			changedFiles: Array.from({ length: 1_000 }, (_, index) => ({
				additions: 1,
				baseContent: `export const previous${index} = ${index};\n`,
				basePath: `src/generated/file-${index}.ts`,
				changeKind: 'modified' as const,
				deletions: 1,
				headContent: `export const next${index} = ${index + 1};\n`,
				headPath: `src/generated/file-${index}.ts`,
				path: `src/generated/file-${index}.ts`,
			})),
		} satisfies BridgeWorktreeReviewDevSnapshot;

		const result = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot,
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const frameBytes = new TextEncoder().encode(JSON.stringify(result.metadataFrame)).byteLength;

		expect(result.reviewMetadataSource.orderedItemIds).toHaveLength(1_000);
		expect(result.metadataFrame.visibleItemIds).toHaveLength(80);
		expect(result.metadataFrame.itemMetadata).toHaveLength(80);
		expect(result.metadataFrame.treeRows).toHaveLength(80);
		expect(result.metadataFrame.extentFacts).toHaveLength(160);
		expect(result.metadataFrame.comparison.contentDescriptors).toHaveLength(160);
		expect(result.metadataWindowFrames).toHaveLength(12);
		expect(result.metadataWindowFrames[0]?.itemMetadata).toHaveLength(80);
		expect(result.metadataWindowFrames.at(-1)?.itemMetadata).toHaveLength(40);
		expect(result.metadataWindowFrames[0]?.sequence).toBe(result.metadataFrame.sequence + 1);
		expect(frameBytes).toBeLessThan(1024 * 1024);
	});

	test('streams metadata frames that remain valid projection input', () => {
		const snapshot = {
			fingerprint: 'project12345',
			changedFiles: Array.from({ length: 120 }, (_, index) => ({
				additions: 1,
				baseContent: `export const previous${index} = ${index};\n`,
				basePath: `src/generated/file-${index}.ts`,
				changeKind: 'modified' as const,
				deletions: 1,
				headContent: `export const next${index} = ${index + 1};\n`,
				headPath: `src/generated/file-${index}.ts`,
				path: `src/generated/file-${index}.ts`,
			})),
		} satisfies BridgeWorktreeReviewDevSnapshot;
		const result = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot,
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const projection = buildBridgeReviewProjectionFromInput({
			projectionInput: {
				packageId: result.metadataFrame.comparison.packageId,
				reviewGeneration: result.metadataFrame.comparison.generation,
				revision: result.metadataFrame.comparison.revision,
				orderedItems: [
					...result.metadataFrame.itemMetadata,
					...result.metadataWindowFrames.flatMap((frame) => frame.itemMetadata),
				],
			},
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		expect(projection.orderedItemIds).toHaveLength(120);
	});
});

function itemByHeadPath(
	reviewPackage: BridgeReviewPackage,
	path: string,
): BridgeReviewItemDescriptor | undefined {
	return Object.values(reviewPackage.itemsById).find((item) => item.headPath === path);
}
