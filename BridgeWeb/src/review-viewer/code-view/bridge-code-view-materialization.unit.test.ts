import { parseDiffFromFile, type CodeViewDiffItem, type FileContents } from '@pierre/diffs';
import { describe, expect, expectTypeOf, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import {
	createBridgeCodeViewPlaceholderFileDiff,
	type BridgeCodeViewPlaceholderDiffFilesResult,
} from './bridge-code-view-placeholder-content.js';

describe('Bridge CodeView materialization', () => {
	test('creates placeholder CodeView items from review projection order', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [
					{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
				],
			},
		});

		const items = createBridgeCodeViewInitialItems({ reviewPackage, projection });

		expect(items.map((item: BridgeCodeViewItem): string => item.id)).toEqual(
			projection.orderedItemIds,
		);
		const firstItem = items[0];
		if (firstItem === undefined) {
			throw new Error('expected first placeholder item');
		}

		expect(firstItem).toMatchObject({
			id: 'source-high',
			type: 'diff',
			version: 3,
			fileDiff: {
				name: 'Sources/App/Core.swift',
			},
			bridgeMetadata: {
				contentState: 'placeholder',
				itemId: 'source-high',
				lineCount: 0,
			},
		});
		expect(firstItem.collapsed).toBeUndefined();
		if (firstItem.type !== 'diff') {
			throw new Error('expected first placeholder diff item');
		}
		expect(firstItem.fileDiff.deletionLines).toEqual([]);
		expect(firstItem.fileDiff.additionLines).toEqual([]);
		expectTypeOf(firstItem).toMatchTypeOf<BridgeCodeViewItem>();
	});

	test('bounds placeholder CodeView seed items when requested by demand lanes', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [
					{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
				],
			},
		});

		const items = createBridgeCodeViewInitialItems({
			reviewPackage,
			projection,
			seedItemIds: ['docs-plan', 'source-high'],
		});

		expect(items.map((item: BridgeCodeViewItem): string => item.id)).toEqual([
			'source-high',
			'docs-plan',
		]);
	});

	test('keeps the complete unloaded manifest header-only without fabricating extent bodies', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		if (sourceHighItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const reviewPackageWithLargeExtents = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					contentLineCountsByRole: { base: 4_000, head: 4_271 },
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithLargeExtents,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithLargeExtents,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);

		expect(items.map((item): string => item.id)).toEqual(projection.orderedItemIds);
		if (placeholder?.type !== 'diff') {
			throw new Error('expected diff placeholder item');
		}
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
		expect(placeholder.fileDiff.hunks).toEqual([]);
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			lineCount: 0,
		});
	});

	test('creates header-only one-sided diff placeholders without app-side height rows', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderDiff = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'deleted-source',
		);

		if (placeholderDiff === undefined || placeholderDiff.type !== 'diff') {
			throw new Error('expected deleted-source placeholder diff');
		}
		expect(placeholderDiff.bridgeMetadata.contentState).toBe('placeholder');
		expect(placeholderDiff.fileDiff.deletionLines).toEqual([]);
		expect(placeholderDiff.fileDiff.additionLines).toEqual([]);
		expect(placeholderDiff.collapsed).toBeUndefined();
		expect(placeholderDiff.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: 0,
		});
	});

	test('creates a file placeholder for the selected review file-target presentation', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			itemPresentationsByItemId: new Map([['source-high', { kind: 'file', version: 'current' }]]),
			reviewPackage,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);

		if (placeholder?.type !== 'file') {
			throw new Error('expected selected file-target placeholder item');
		}
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			itemId: 'source-high',
			lineCount: 0,
		});
		expect(countPierreContentLines(placeholder.file.contents)).toBe(0);
		expect(placeholder.collapsed).toBeUndefined();
	});

	test('keeps unloaded file-target placeholders header-only despite streamed extents', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		if (sourceHighItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const reviewPackageWithExtents = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					contentLineCountsByRole: {
						head: 37,
					},
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithExtents,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			itemPresentationsByItemId: new Map([['source-high', { kind: 'file', version: 'current' }]]),
			reviewPackage: reviewPackageWithExtents,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);

		if (placeholder?.type !== 'file') {
			throw new Error('expected selected file-target placeholder item');
		}
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			itemId: 'source-high',
			lineCount: 0,
		});
		expect(countPierreContentLines(placeholder.file.contents)).toBe(0);
		expect(placeholder.collapsed).toBeUndefined();
		expect(placeholder.file.cacheKey).toBe(
			`${sourceHighItem.cacheKey}:placeholder:current:header-only`,
		);
	});

	test('keeps unloaded diff placeholders header-only despite streamed extents', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		if (sourceHighItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const reviewPackageWithExtents = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					contentLineCountsByRole: {
						base: 17,
						head: 19,
					},
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithExtents,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithExtents,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);

		if (placeholder?.type !== 'diff') {
			throw new Error('expected diff placeholder item');
		}
		expect(placeholder.collapsed).toBeUndefined();
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			itemId: 'source-high',
			lineCount: 0,
		});
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
	});

	test('keeps an unresolved modified diff type-stable for later diff hydration', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		if (sourceHighItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const reviewPackageWithUnresolvedDiff = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					changeKind: 'modified' as const,
					contentLineCountsByRole: { base: 17, head: 19 },
					contentRoles: { base: null, diff: null, file: null, head: null },
					itemKind: 'diff' as const,
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithUnresolvedDiff,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		// Act
		const placeholder = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithUnresolvedDiff,
			projection,
			seedItemIds: ['source-high'],
		})[0];

		// Assert
		expect(placeholder?.type).toBe('diff');
		if (placeholder?.type !== 'diff') {
			throw new Error('expected unresolved modified descriptor to keep a diff placeholder');
		}
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			itemId: 'source-high',
			lineCount: 0,
		});
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
	});

	test('does not fabricate unloaded diff bodies from item-local change counts', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		const sourceNormalItem = reviewPackage.itemsById['source-normal'];
		if (sourceHighItem === undefined || sourceNormalItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const reviewPackageWithPartialExtents = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					contentLineCountsByRole: undefined,
				},
				'source-normal': {
					...sourceNormalItem,
					contentLineCountsByRole: {
						base: 20,
						head: 40,
					},
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithPartialExtents,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithPartialExtents,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);

		if (placeholder?.type !== 'diff') {
			throw new Error('expected diff placeholder item');
		}
		expect(placeholder.collapsed).toBeUndefined();
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			itemId: 'source-high',
			lineCount: 0,
		});
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
	});

	test('renders an added placeholder as a header-only diff without cross-item estimates', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		const sourceNormalItem = reviewPackage.itemsById['source-normal'];
		if (sourceHighItem === undefined || sourceNormalItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const reviewPackageWithAddedItem = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				// A pure added file: no base handle, real head extent, sharing the package with a
				// modified sibling whose base extent (20) would otherwise leak into this item's base
				// placeholder via the package-wide average and manufacture phantom context rows.
				'source-high': {
					...sourceHighItem,
					changeKind: 'added' as const,
					basePath: null,
					contentRoles: { ...sourceHighItem.contentRoles, base: null },
					contentLineCountsByRole: { head: 179 },
				},
				'source-normal': {
					...sourceNormalItem,
					contentLineCountsByRole: { base: 20, head: 40 },
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithAddedItem,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithAddedItem,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);
		if (placeholder?.type !== 'diff') {
			throw new Error('expected diff placeholder item');
		}
		// Loading records preserve type and identity without claiming source-backed rows.
		expect(placeholder.collapsed).toBeUndefined();
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
		expect(placeholder.bridgeMetadata.contentRoles).not.toContain('base');
		expect(placeholder.bridgeMetadata.lineCount).toBe(0);
	});

	test('renders a deleted placeholder as a header-only diff without cross-item estimates', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		const sourceNormalItem = reviewPackage.itemsById['source-normal'];
		if (sourceHighItem === undefined || sourceNormalItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const reviewPackageWithDeletedItem = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...sourceHighItem,
					changeKind: 'deleted' as const,
					headPath: null,
					contentRoles: { ...sourceHighItem.contentRoles, head: null },
					contentLineCountsByRole: { base: 179 },
				},
				'source-normal': {
					...sourceNormalItem,
					contentLineCountsByRole: { base: 20, head: 40 },
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithDeletedItem,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithDeletedItem,
			projection,
		});
		const placeholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);
		if (placeholder?.type !== 'diff') {
			throw new Error('expected diff placeholder item');
		}
		// Loading records preserve type and identity without claiming source-backed rows.
		expect(placeholder.collapsed).toBeUndefined();
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
		expect(placeholder.bridgeMetadata.contentRoles).not.toContain('head');
		expect(placeholder.bridgeMetadata.lineCount).toBe(0);
	});

	test('keeps one-sided placeholders header-only without item-local height estimates', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		const sourceNormalItem = reviewPackage.itemsById['source-normal'];
		if (sourceHighItem === undefined || sourceNormalItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const reviewPackageWithOneSidedItems = {
			...reviewPackage,
			orderedItemIds: ['source-high', 'source-normal'],
			itemsById: {
				'source-high': {
					...sourceHighItem,
					additions: 17,
					basePath: null,
					changeKind: 'added' as const,
					contentLineCountsByRole: undefined,
					contentRoles: { ...sourceHighItem.contentRoles, base: null },
					deletions: 0,
				},
				'source-normal': {
					...sourceNormalItem,
					additions: 0,
					changeKind: 'deleted' as const,
					contentLineCountsByRole: undefined,
					contentRoles: { ...sourceNormalItem.contentRoles, head: null },
					deletions: 11,
					headPath: null,
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: reviewPackageWithOneSidedItems,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({
			reviewPackage: reviewPackageWithOneSidedItems,
			projection,
		});
		const addedPlaceholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-high',
		);
		const deletedPlaceholder = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'source-normal',
		);

		if (addedPlaceholder?.type !== 'diff' || deletedPlaceholder?.type !== 'diff') {
			throw new Error('expected one-sided diff placeholders');
		}
		expect(addedPlaceholder.collapsed).toBeUndefined();
		expect(addedPlaceholder.fileDiff.deletionLines).toEqual([]);
		expect(addedPlaceholder.fileDiff.additionLines).toEqual([]);
		expect(addedPlaceholder.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: 0,
		});
		expect(deletedPlaceholder.collapsed).toBeUndefined();
		expect(deletedPlaceholder.fileDiff.deletionLines).toEqual([]);
		expect(deletedPlaceholder.fileDiff.additionLines).toEqual([]);
		expect(deletedPlaceholder.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: 0,
		});
	});

	test('builds placeholder diffs with the same Pierre shape as parsed placeholder contents', () => {
		for (const placeholderFiles of [
			placeholderDiffFiles({
				baseName: 'Sources/App.swift',
				headName: 'Sources/App.swift',
				baseLineCount: 2,
				headLineCount: 3,
			}),
			placeholderDiffFiles({
				baseName: 'Sources/Old.swift',
				headName: 'Sources/New.swift',
				baseLineCount: 2,
				headLineCount: 3,
			}),
			placeholderDiffFiles({
				baseName: 'Sources/New.swift',
				headName: 'Sources/New.swift',
				baseLineCount: 0,
				headLineCount: 3,
			}),
			placeholderDiffFiles({
				baseName: 'Sources/Deleted.swift',
				headName: 'Sources/Deleted.swift',
				baseLineCount: 2,
				headLineCount: 0,
			}),
		]) {
			const helperDiff = createBridgeCodeViewPlaceholderFileDiff(placeholderFiles);
			const parsedDiff = parseDiffFromFile(placeholderFiles.base, placeholderFiles.head);

			expect(normalizedPlaceholderDiff(helperDiff)).toEqual(normalizedPlaceholderDiff(parsedDiff));
		}
	});

	test('keeps visible loading file-target items header-only despite streamed extents', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected source fixture item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(
			{
				...item,
				contentLineCountsByRole: {
					head: 37,
				},
			},
			{ kind: 'file', version: 'current' },
		);

		if (loadingItem.type !== 'file') {
			throw new Error('expected selected review file target loading item to keep file view');
		}
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			itemId: item.itemId,
			lineCount: 0,
		});
		expect(countPierreContentLines(loadingItem.file.contents)).toBe(0);
		expect(loadingItem.file.contents).not.toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:placeholder:current:header-only`);
	});

	test('does not turn file extent facts into current file-target loading bodies', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected source fixture item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(
			{
				...item,
				contentLineCountsByRole: {
					file: 37,
				},
			},
			{ kind: 'file', version: 'current' },
		);

		if (loadingItem.type !== 'file') {
			throw new Error('expected selected review file target loading item to keep file view');
		}
		expect(loadingItem.bridgeMetadata.lineCount).toBe(0);
		expect(countPierreContentLines(loadingItem.file.contents)).toBe(0);
		expect(loadingItem.file.contents).not.toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:placeholder:current:header-only`);
	});

	test('does not reserve one-sided loading height from addition and deletion extents', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceHighItem = reviewPackage.itemsById['source-high'];
		if (sourceHighItem === undefined) {
			throw new Error('expected source fixture item');
		}

		const addedLoadingItem = materializeBridgeCodeViewLoadingItem({
			...sourceHighItem,
			additions: 17,
			basePath: null,
			changeKind: 'added',
			contentLineCountsByRole: undefined,
			contentRoles: { ...sourceHighItem.contentRoles, base: null },
			deletions: 0,
		});
		const deletedLoadingItem = materializeBridgeCodeViewLoadingItem({
			...sourceHighItem,
			additions: 0,
			changeKind: 'deleted',
			contentLineCountsByRole: undefined,
			contentRoles: { ...sourceHighItem.contentRoles, head: null },
			deletions: 11,
			headPath: null,
		});

		if (addedLoadingItem.type !== 'diff' || deletedLoadingItem.type !== 'diff') {
			throw new Error('expected one-sided diff loading items');
		}
		expect(addedLoadingItem.fileDiff.deletionLines).toEqual([]);
		expect(addedLoadingItem.fileDiff.additionLines).toEqual([]);
		expect(addedLoadingItem.fileDiff.additionLines).not.toContain('Loading content...\n');
		expect(deletedLoadingItem.fileDiff.deletionLines).toEqual([]);
		expect(deletedLoadingItem.fileDiff.deletionLines).not.toContain('Loading content...\n');
		expect(deletedLoadingItem.fileDiff.additionLines).toEqual([]);
	});

	test('materializes a visible one-sided loading item as a header-only CodeView record', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		if (item === undefined) {
			throw new Error('expected fixture item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(item);

		if (loadingItem.type !== 'diff') {
			throw new Error('expected loading item to use one-sided diff view');
		}
		expect(loadingItem.fileDiff.additionLines).toEqual([]);
		expect(loadingItem.fileDiff.additionLines).not.toContain('Loading content...\n');
		expect(loadingItem.collapsed).toBeUndefined();
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			contentRoles: [],
			itemId: item.itemId,
			lineCount: 0,
		});
	});

	test('materializes a diff-backed loading item without changing its CodeView item type', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected fixture diff item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(item);

		if (loadingItem.type !== 'diff') {
			throw new Error('expected loading item to keep diff view');
		}
		expect(loadingItem.fileDiff.additionLines).toEqual([]);
		expect(loadingItem.fileDiff.additionLines).not.toContain('Loading content...\n');
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			contentRoles: [],
			itemId: item.itemId,
			lineCount: 0,
		});
	});

	test('materializes a file-target loading item without changing its CodeView item type', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected fixture diff item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(item, {
			kind: 'file',
			version: 'current',
		});

		if (loadingItem.type !== 'file') {
			throw new Error('expected selected review file target loading item to keep file view');
		}
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			contentRoles: [],
			itemId: item.itemId,
		});
	});

	test('does not reserve placeholder line budgets from hydrated content windows', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected fixture item');
		}
		const loadingItem = materializeBridgeCodeViewLoadingItem(
			{
				...item,
				additions: 4000,
				contentLineCountsByRole: { head: 4000 },
			},
			{ kind: 'file', version: 'head' },
		);
		if (loadingItem.type !== 'file') {
			throw new Error('expected a file loading item');
		}

		expect(loadingItem.bridgeMetadata.lineCount).toBe(0);
		expect(countPierreContentLines(loadingItem.file.contents)).toBe(0);
		expect(loadingItem.file.contents).not.toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:placeholder:head:header-only`);
	});
});

function countPierreContentLines(contents: string): number {
	return contents.match(/[^\n]*\n|[^\n]+/g)?.length ?? 0;
}

function placeholderDiffFiles(props: {
	readonly baseName: string;
	readonly headName: string;
	readonly baseLineCount: number;
	readonly headLineCount: number;
}): BridgeCodeViewPlaceholderDiffFilesResult {
	return {
		base: placeholderFileContents({
			cacheKey: `base:${props.baseName}:${props.baseLineCount}`,
			line: '-\n',
			lineCount: props.baseLineCount,
			name: props.baseName,
		}),
		baseLineCount: props.baseLineCount,
		head: placeholderFileContents({
			cacheKey: `head:${props.headName}:${props.headLineCount}`,
			line: '+\n',
			lineCount: props.headLineCount,
			name: props.headName,
		}),
		headLineCount: props.headLineCount,
		lineCount: props.baseLineCount + props.headLineCount,
	};
}

function placeholderFileContents(props: {
	readonly cacheKey: string;
	readonly line: string;
	readonly lineCount: number;
	readonly name: string;
}): FileContents {
	return {
		name: props.name,
		contents: props.line.repeat(props.lineCount),
		cacheKey: props.cacheKey,
	};
}

function normalizedPlaceholderDiff(
	fileDiff: CodeViewDiffItem['fileDiff'],
): Readonly<Record<string, unknown>> {
	return {
		name: fileDiff.name,
		prevName: fileDiff.prevName,
		type: fileDiff.type,
		splitLineCount: fileDiff.splitLineCount,
		unifiedLineCount: fileDiff.unifiedLineCount,
		isPartial: fileDiff.isPartial,
		additionLines: fileDiff.additionLines,
		deletionLines: fileDiff.deletionLines,
		cacheKey: fileDiff.cacheKey,
		hunks: fileDiff.hunks.map((hunk) => ({
			collapsedBefore: hunk.collapsedBefore,
			additionStart: hunk.additionStart,
			additionCount: hunk.additionCount,
			additionLines: hunk.additionLines,
			additionLineIndex: hunk.additionLineIndex,
			deletionStart: hunk.deletionStart,
			deletionCount: hunk.deletionCount,
			deletionLines: hunk.deletionLines,
			deletionLineIndex: hunk.deletionLineIndex,
			hunkContent: hunk.hunkContent,
			hunkSpecs: hunk.hunkSpecs,
			splitLineStart: hunk.splitLineStart,
			splitLineCount: hunk.splitLineCount,
			unifiedLineStart: hunk.unifiedLineStart,
			unifiedLineCount: hunk.unifiedLineCount,
			noEOFCRDeletions: hunk.noEOFCRDeletions,
			noEOFCRAdditions: hunk.noEOFCRAdditions,
		})),
	};
}
