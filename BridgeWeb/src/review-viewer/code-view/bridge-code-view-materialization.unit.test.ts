import { describe, expect, expectTypeOf, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewItemDescriptor } from '../../foundation/review-package/bridge-review-package.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
	placeholderLineCountBudgetForItem,
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

	test('creates collapsed one-sided diff placeholders so unloaded content does not render as blank body rows', () => {
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

	test('reserves streamed line extents in unloaded file-target placeholders', () => {
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
			lineCount: 37,
		});
		expect(placeholder.file.contents.split('\n')).toHaveLength(38);
		expect(placeholder.file.contents).toContain('Loading content...');
		expect(placeholder.file.cacheKey).toContain(':placeholder:extent:37');
	});

	test('reserves streamed line extents in unloaded diff placeholders', () => {
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
			contentRoles: ['base', 'head'],
			itemId: 'source-high',
			lineCount: 36,
		});
		expect(placeholder.fileDiff.deletionLines).toContain('Loading content...\n');
		expect(placeholder.fileDiff.additionLines).toContain('Loading content...\n');
	});

	test('estimates unloaded diff placeholders from known role line-count averages', () => {
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
			contentRoles: ['base', 'head'],
			itemId: 'source-high',
			lineCount: 60,
		});
		expect(placeholder.fileDiff.deletionLines).toHaveLength(20);
		expect(placeholder.fileDiff.additionLines).toHaveLength(40);
	});

	test('reserves streamed line extents in visible loading file-target items', () => {
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
			lineCount: 37,
		});
		expect(loadingItem.file.contents.split('\n')).toHaveLength(38);
		expect(loadingItem.file.contents).toContain('Loading content...');
		expect(loadingItem.file.cacheKey).toContain(':loading:extent:37');
	});

	test('uses file extent facts as the fallback for current file-target placeholders', () => {
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
		expect(loadingItem.bridgeMetadata.lineCount).toBe(37);
		expect(loadingItem.file.contents.split('\n')).toHaveLength(38);
		expect(loadingItem.file.cacheKey).toContain(':loading:extent:37');
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

	test('reserves a placeholder line budget that matches the hydrated content window (F2)', () => {
		// A normal file (well under the materialization budget) that hydrates to 4000 lines.
		const normalItem: BridgeReviewItemDescriptor = {
			...makeBridgeReviewItem({ itemId: 'big-file', path: 'Sources/App/Big.ts' }),
			additions: 4000,
			deletions: 0,
			contentLineCountsByRole: { head: 4000 },
		};
		const placeholder = materializeBridgeCodeViewLoadingItem(normalItem, {
			kind: 'file',
			version: 'head',
		});
		if (placeholder.type !== 'file') {
			throw new Error('expected a file placeholder');
		}
		// Number of reserved rows Pierre will estimate from = newline count of the placeholder.
		const reservedLineCount = placeholder.file.contents.split('\n').length - 1;
		// Before F2 the placeholder was capped at 1500 rows while the head hydrates to 4000,
		// so the item grew ~2.6x on hydrate. Now the placeholder reserves the hydrated count.
		expect(reservedLineCount).toBeGreaterThan(1500);
		expect(reservedLineCount).toBeLessThanOrEqual(4000);

		// Budget decision: a normal item reserves the full materialization budget; an item that
		// hydrates to a bounded window keeps the window cap, so both match hydrated height.
		expect(placeholderLineCountBudgetForItem(normalItem)).toBe(20_000);
		const windowedItem: BridgeReviewItemDescriptor = { ...normalItem, additions: 30_000 };
		expect(placeholderLineCountBudgetForItem(windowedItem)).toBe(1500);
	});
});
