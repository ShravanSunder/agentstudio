import { describe, expect, expectTypeOf, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';

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
			collapsed: true,
			version: 3,
			fileDiff: {
				name: 'Sources/App/Core.swift',
			},
			bridgeMetadata: {
				contentState: 'placeholder',
				itemId: 'source-high',
			},
		});
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

	test('creates one-sided diff placeholders without app-side extent rows', () => {
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
		expect(placeholderDiff.collapsed).toBe(true);
		expect(placeholderDiff.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: null,
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
		});
		expect(placeholder.file.contents).toBe('');
	});

	test('ignores streamed line extents in unloaded file-target placeholders', () => {
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
			lineCount: null,
		});
		expect(placeholder.file.contents).toBe('');
		expect(placeholder.file.cacheKey).toBe(`${sourceHighItem.cacheKey}:placeholder`);
	});

	test('ignores streamed line extents in unloaded diff placeholders', () => {
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
		expect(placeholder.collapsed).toBe(true);
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			itemId: 'source-high',
			lineCount: null,
		});
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
	});

	test('does not estimate unloaded diff placeholders from known role line-count averages', () => {
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
		expect(placeholder.collapsed).toBe(true);
		expect(placeholder.bridgeMetadata).toMatchObject({
			contentState: 'placeholder',
			contentRoles: [],
			itemId: 'source-high',
			lineCount: null,
		});
		expect(placeholder.fileDiff.deletionLines).toEqual([]);
		expect(placeholder.fileDiff.additionLines).toEqual([]);
	});

	test('renders an added placeholder as a one-sided (empty base) diff, ignoring cross-item base estimates', () => {
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
		// Empty base → pure-add diff (no phantom "unmodified"/context rows, no base role).
		expect(placeholder.collapsed).toBe(true);
		expect(placeholder.fileDiff.deletionLines).toHaveLength(0);
		expect(placeholder.fileDiff.additionLines).toHaveLength(0);
		expect(placeholder.bridgeMetadata.contentRoles).not.toContain('base');
	});

	test('renders a deleted placeholder as a one-sided (empty head) diff, ignoring cross-item head estimates', () => {
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
		// Empty head → pure-delete diff (no phantom context rows, no head role).
		expect(placeholder.collapsed).toBe(true);
		expect(placeholder.fileDiff.deletionLines).toHaveLength(0);
		expect(placeholder.fileDiff.additionLines).toHaveLength(0);
		expect(placeholder.bridgeMetadata.contentRoles).not.toContain('head');
	});

	test('does not reserve one-sided placeholder height from addition and deletion extents', () => {
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
		expect(addedPlaceholder.collapsed).toBe(true);
		expect(addedPlaceholder.fileDiff.deletionLines).toHaveLength(0);
		expect(addedPlaceholder.fileDiff.additionLines).toHaveLength(0);
		expect(addedPlaceholder.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: null,
		});
		expect(deletedPlaceholder.collapsed).toBe(true);
		expect(deletedPlaceholder.fileDiff.deletionLines).toHaveLength(0);
		expect(deletedPlaceholder.fileDiff.additionLines).toHaveLength(0);
		expect(deletedPlaceholder.bridgeMetadata).toMatchObject({
			contentRoles: [],
			lineCount: null,
		});
	});

	test('ignores streamed line extents in visible loading file-target items', () => {
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
			lineCount: null,
		});
		expect(loadingItem.file.contents).toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:loading`);
	});

	test('does not use file extent facts as the fallback for current file-target loading items', () => {
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
		expect(loadingItem.bridgeMetadata.lineCount).toBe(null);
		expect(loadingItem.file.contents).toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:loading`);
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
		expect(addedLoadingItem.fileDiff.deletionLines).toHaveLength(0);
		expect(addedLoadingItem.fileDiff.additionLines).toEqual([
			'Loading content...\n',
			'Loading syntax view...\n',
		]);
		expect(deletedLoadingItem.fileDiff.deletionLines).toEqual([
			'Loading content...\n',
			'Loading syntax view...\n',
		]);
		expect(deletedLoadingItem.fileDiff.additionLines).toHaveLength(0);
	});

	test('materializes a visible one-sided loading item with non-empty CodeView body text', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		if (item === undefined) {
			throw new Error('expected fixture item');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(item);

		if (loadingItem.type !== 'diff') {
			throw new Error('expected loading item to use one-sided diff view');
		}
		expect(loadingItem.fileDiff.additionLines).toContain('Loading content...\n');
		expect(loadingItem.fileDiff.lang).toBe('text');
		expect(loadingItem.collapsed).toBeUndefined();
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			contentRoles: [],
			itemId: item.itemId,
			lineCount: null,
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
		expect(loadingItem.fileDiff.additionLines).toContain('Loading content...\n');
		expect(loadingItem.fileDiff.lang).toBe('text');
		expect(loadingItem.bridgeMetadata).toMatchObject({
			contentState: 'loading',
			contentRoles: [],
			itemId: item.itemId,
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

		expect(loadingItem.bridgeMetadata.lineCount).toBe(null);
		expect(loadingItem.file.contents).toBe('Loading content...\nLoading syntax view...\n');
		expect(loadingItem.file.cacheKey).toBe(`${item.cacheKey}:loading`);
	});
});
