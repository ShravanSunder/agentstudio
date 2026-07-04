import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import { bridgeReviewPackageSchema } from '../../src/foundation/review-package/bridge-review-package-schema.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../src/foundation/review-package/bridge-review-package.js';
import { buildBridgeReviewProjectionFromInput } from '../../src/review-viewer/navigation/review-projection.js';
import {
	bridgeWorktreeReviewDevContentHashForRole,
	createBridgeWorktreeReviewDevProvider,
	createBridgeWorktreeReviewDevMetadata,
	type BridgeWorktreeReviewDevSnapshot,
} from './bridge-worktree-review-dev-provider.js';

type BridgeWorktreeChangedFileWithHashMetadata =
	BridgeWorktreeReviewDevSnapshot['changedFiles'][number] & {
		readonly contentHashAlgorithm: string;
		readonly newContentHash?: string | null;
		readonly oldContentHash?: string | null;
	};
type BridgeWorktreeReviewDevSnapshotWithHashMetadata = Omit<
	BridgeWorktreeReviewDevSnapshot,
	'changedFiles'
> & {
	readonly changedFiles: readonly BridgeWorktreeChangedFileWithHashMetadata[];
};

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
		const modifiedBase = modifiedItem?.contentRoles.base;
		const modifiedHead = modifiedItem?.contentRoles.head;
		expect(modifiedBase?.resourceUrl).toBe(
			`agentstudio://resource/review/content/${modifiedBase?.handleId}?generation=1`,
		);
		expect(modifiedHead?.resourceUrl).toBe(
			`agentstudio://resource/review/content/${modifiedHead?.handleId}?generation=1`,
		);
		expect(modifiedBase?.contentHashAlgorithm).toBe('git-blob-sha1');
		expect(modifiedHead?.contentHashAlgorithm).toBe('git-blob-sha1');
		expect(modifiedBase?.contentHash).toBe(gitBlobSha1('export const value = 1;\n'));
		expect(modifiedHead?.contentHash).toBe(
			gitBlobSha1('export const value = 2;\nexport const next = true;\n'),
		);
		expect(modifiedBase?.handleId).toBe(
			swiftContentHandleId({
				contentHash: gitBlobSha1('export const value = 1;\n'),
				endpointId: 'baseline-local-default',
				itemId: modifiedItem?.itemId ?? '',
				role: 'base',
			}),
		);
		expect(modifiedHead?.handleId).toBe(
			swiftContentHandleId({
				contentHash: gitBlobSha1('export const value = 2;\nexport const next = true;\n'),
				endpointId: 'working-tree',
				itemId: modifiedItem?.itemId ?? '',
				role: 'head',
			}),
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
		expect(addedItem?.itemKind).toBe('diff');
		expect(addedItem?.contentRoles.base).toBeNull();
		expect(addedItem?.contentRoles.file).toBeNull();
		expect(addedItem?.contentRoles.head?.contentHashAlgorithm).toBe('git-blob-sha1');
		expect(result.contentByHandleId.get(addedItem?.contentRoles.head?.handleId ?? '')).toBe(
			'# Docs\n\nNew docs\n',
		);
		expect(addedItem?.contentLineCountsByRole).toEqual({ head: 3 });
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

	test('increments package revision on each explicit metadata refresh in the same generation', async () => {
		let fingerprintIndex = 0;
		const provider = createBridgeWorktreeReviewDevProvider(
			{
				baseRef: 'base-sha',
				scenarioName: 'current-worktree',
				worktreeRoot: '/tmp/bridge-review-revision-fixture',
			},
			{
				loadSnapshot: async () => {
					fingerprintIndex += 1;
					return {
						fingerprint: `revision${fingerprintIndex}`,
						changedFiles: [
							{
								additions: 1,
								baseContent: 'export const value = 1;\n',
								basePath: 'src/app.ts',
								changeKind: 'modified',
								deletions: 1,
								headContent: `export const value = ${fingerprintIndex + 1};\n`,
								headPath: 'src/app.ts',
								path: 'src/app.ts',
							},
						],
					};
				},
			},
		);

		const firstMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const secondMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const thirdMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });

		expect(firstMetadataResult.metadataFrame.comparison.revision).toBe(1);
		expect(secondMetadataResult.metadataFrame.comparison.revision).toBe(2);
		expect(thirdMetadataResult.metadataFrame.comparison.revision).toBe(3);
		expect(secondMetadataResult.metadataFrame.generation).toBe(
			firstMetadataResult.metadataFrame.generation,
		);
		expect(thirdMetadataResult.metadataFrame.streamId).toBe(
			firstMetadataResult.metadataFrame.streamId,
		);
	});

	test('rotates review generation and stream id while revoking stale content leases', async () => {
		const provider = createBridgeWorktreeReviewDevProvider(
			{
				baseRef: 'base-sha',
				scenarioName: 'current-worktree',
				worktreeRoot: '/tmp/bridge-review-identity-fixture',
			},
			{
				loadSnapshot: async () => ({
					fingerprint: 'identity12345',
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
				}),
			},
		);
		const firstMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const firstItemId = firstMetadataResult.reviewMetadataSource.orderedItemIds[0];
		const firstItem = firstMetadataResult.reviewMetadataSource.itemsById[firstItemId ?? ''];
		const firstHeadHandle = firstItem?.contentRoles.head;
		expect(firstHeadHandle).not.toBeNull();

		const rotation = provider.rotateIdentity({ reason: 'authorityChanged' });
		const secondMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });

		expect(rotation.generation).toBe(2);
		expect(rotation.revokedPackageIds).toEqual([
			firstMetadataResult.metadataFrame.comparison.packageId,
		]);
		expect(secondMetadataResult.metadataFrame.generation).toBe(2);
		expect(secondMetadataResult.metadataFrame.streamId).not.toBe(
			firstMetadataResult.metadataFrame.streamId,
		);
		expect(secondMetadataResult.metadataFrame.comparison.revision).toBe(1);
		await expect(
			provider.loadReviewContent({
				generation: firstMetadataResult.metadataFrame.comparison.generation,
				handleId: firstHeadHandle?.handleId ?? '',
				packageId: firstMetadataResult.metadataFrame.comparison.packageId,
				revision: firstMetadataResult.metadataFrame.comparison.revision,
			}),
		).rejects.toThrow(
			/does not match loaded metadata|Unknown Bridge worktree review content handle/u,
		);
	});

	test('periodic identity rotation is opt-in and revokes the current content cache', async () => {
		const intervalHandles = new Map<unknown, () => void>();
		let nextIntervalHandle = 0;
		const provider = createBridgeWorktreeReviewDevProvider(
			{
				baseRef: 'base-sha',
				scenarioName: 'current-worktree',
				worktreeRoot: '/tmp/bridge-review-periodic-identity-fixture',
			},
			{
				identityRotation: {
					intervalMilliseconds: 250,
					setInterval: (callback) => {
						nextIntervalHandle += 1;
						intervalHandles.set(nextIntervalHandle, callback);
						return nextIntervalHandle;
					},
					clearInterval: (handle) => {
						intervalHandles.delete(handle);
					},
				},
				loadSnapshot: async () => ({
					fingerprint: 'periodic12345',
					changedFiles: [
						{
							additions: 1,
							baseContent: null,
							basePath: null,
							changeKind: 'added',
							deletions: 0,
							headContent: 'export const value = 1;\n',
							headPath: 'src/app.ts',
							path: 'src/app.ts',
						},
					],
				}),
			},
		);
		const firstMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		const intervalCallback = intervalHandles.get(1);
		expect(intervalCallback).toBeDefined();

		intervalCallback?.();
		const secondMetadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
		provider.dispose();

		expect(secondMetadataResult.metadataFrame.generation).toBe(
			firstMetadataResult.metadataFrame.generation + 1,
		);
		expect(secondMetadataResult.metadataFrame.streamId).not.toBe(
			firstMetadataResult.metadataFrame.streamId,
		);
		expect(intervalHandles.size).toBe(0);
	});

	test('matches Swift review package builder sentinels and content hash algorithm cascade', () => {
		const snapshot: BridgeWorktreeReviewDevSnapshotWithHashMetadata = {
			fingerprint: 'hashsentinel1',
			changedFiles: [
				{
					additions: 1,
					baseContent: null,
					basePath: null,
					changeKind: 'added',
					deletions: 0,
					headContent: 'added\n',
					headPath: 'src/added.ts',
					newContentHash: 'sha256:provided-added',
					path: 'src/added.ts',
					contentHashAlgorithm: 'sha256',
				},
				{
					additions: 0,
					baseContent: 'deleted\n',
					basePath: 'src/deleted.ts',
					changeKind: 'deleted',
					deletions: 1,
					headContent: null,
					headPath: null,
					oldContentHash: 'status-fallback:deleted',
					path: 'src/deleted.ts',
					contentHashAlgorithm: 'status-fallback-sha256',
				},
				{
					additions: 1,
					baseContent: 'base\n',
					basePath: 'src/modified.ts',
					changeKind: 'modified',
					deletions: 1,
					headContent: 'head\n',
					headPath: 'src/modified.ts',
					oldContentHash: 'tree-fs-fallback:base',
					newContentHash: 'tree-fs-fallback:head',
					path: 'src/modified.ts',
					contentHashAlgorithm: 'tree-filesystem-fallback-sha256',
				},
			],
		};

		const result = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot,
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const addedItem = itemByHeadPath(result.reviewMetadataSource, 'src/added.ts');
		const deletedItem = itemByBasePath(result.reviewMetadataSource, 'src/deleted.ts');
		const modifiedItem = itemByHeadPath(result.reviewMetadataSource, 'src/modified.ts');

		expect(addedItem?.baseContentHash).toBeNull();
		expect(addedItem?.headContentHash).toBe('sha256:provided-added');
		expect(addedItem?.contentHashAlgorithm).toBe('sha256');
		expect(addedItem?.contentRoles.head?.contentHash).toBe('sha256:provided-added');
		expect(addedItem?.contentRoles.head?.contentHashAlgorithm).toBe('sha256');
		expect(deletedItem?.baseContentHash).toBe('status-fallback:deleted');
		expect(deletedItem?.headContentHash).toBeNull();
		expect(deletedItem?.contentHashAlgorithm).toBe('status-fallback-sha256');
		expect(deletedItem?.contentRoles.base?.contentHash).toBe('status-fallback:deleted');
		expect(modifiedItem?.contentHashAlgorithm).toBe('tree-filesystem-fallback-sha256');
		expect(modifiedItem?.cacheKey).toContain('tree-fs-fallback:base');
		expect(modifiedItem?.cacheKey).toContain('tree-fs-fallback:head');
		expect(
			bridgeWorktreeReviewDevContentHashForRole(
				snapshot.changedFiles[0] ?? failChangedFile(),
				'base',
			),
		).toBe('missing-base');
		expect(
			bridgeWorktreeReviewDevContentHashForRole(
				snapshot.changedFiles[1] ?? failChangedFile(),
				'diff',
			),
		).toBe('status-fallback:deleted...none');
	});

	test('keeps dev provider review content URLs aligned with the Swift contract fixture', () => {
		const contractPackage = bridgeReviewPackageSchema.parse(
			JSON.parse(
				readFileSync(
					new URL(
						'../../../Tests/BridgeContractFixtures/valid/bridge-review-package.json',
						import.meta.url,
					),
					'utf8',
				),
			),
		);
		const contractHandle = contractPackage.itemsById['item-file-source-1']?.contentRoles.head;
		if (contractHandle === null || contractHandle === undefined) {
			throw new Error('Expected Swift contract fixture head handle');
		}
		const result = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot: {
				fingerprint: 'golden123456',
				changedFiles: [
					{
						additions: 1,
						baseContent: 'base\n',
						basePath: 'src/app.ts',
						changeKind: 'modified',
						deletions: 1,
						headContent: 'head\n',
						headPath: 'src/app.ts',
						path: 'src/app.ts',
					},
				],
			},
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const generatedHandle = itemByHeadPath(result.reviewMetadataSource, 'src/app.ts')?.contentRoles
			.head;

		expect(new URL(contractHandle.resourceUrl).search).toBe('?generation=42');
		expect(generatedHandle?.resourceUrl).toBe(
			`agentstudio://resource/review/content/${generatedHandle?.handleId}?generation=1`,
		);
		expect(new URL(generatedHandle?.resourceUrl ?? '').searchParams.has('cursor')).toBe(false);
		expect(new URL(generatedHandle?.resourceUrl ?? '').searchParams.has('revision')).toBe(false);
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

	test('changes head handle identity when the same item content changes', () => {
		const first = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot: {
				fingerprint: 'sameitem1111',
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
			},
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const second = createBridgeWorktreeReviewDevMetadata({
			baseRef: 'base-sha',
			snapshot: {
				fingerprint: 'sameitem2222',
				changedFiles: [
					{
						additions: 1,
						baseContent: 'export const value = 1;\n',
						basePath: 'src/app.ts',
						changeKind: 'modified',
						deletions: 1,
						headContent: 'export const value = 3;\n',
						headPath: 'src/app.ts',
						path: 'src/app.ts',
					},
				],
			},
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
		});
		const firstItem = itemByHeadPath(first.reviewMetadataSource, 'src/app.ts');
		const secondItem = itemByHeadPath(second.reviewMetadataSource, 'src/app.ts');

		expect(firstItem?.itemId).toBe(secondItem?.itemId);
		expect(firstItem?.contentRoles.head?.handleId).not.toBe(
			secondItem?.contentRoles.head?.handleId,
		);
	});
});

function itemByHeadPath(
	reviewPackage: BridgeReviewPackage,
	path: string,
): BridgeReviewItemDescriptor | undefined {
	return Object.values(reviewPackage.itemsById).find((item) => item.headPath === path);
}

function itemByBasePath(
	reviewPackage: BridgeReviewPackage,
	path: string,
): BridgeReviewItemDescriptor | undefined {
	return Object.values(reviewPackage.itemsById).find((item) => item.basePath === path);
}

function failChangedFile(): never {
	throw new Error('Expected changed file fixture');
}

function gitBlobSha1(content: string): string {
	return createHash('sha1')
		.update(
			Buffer.concat([Buffer.from(`blob ${Buffer.byteLength(content)}\0`), Buffer.from(content)]),
		)
		.digest('hex');
}

function swiftContentHandleId(props: {
	readonly contentHash: string;
	readonly endpointId: string;
	readonly itemId: string;
	readonly role: 'base' | 'head';
}): string {
	return `handle-${createHash('sha256')
		.update(`${props.endpointId}:${props.itemId}:${props.role}:${props.contentHash}`)
		.digest('hex')}`;
}
