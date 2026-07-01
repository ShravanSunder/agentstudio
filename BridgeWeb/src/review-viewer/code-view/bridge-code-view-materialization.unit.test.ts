import { describe, expect, expectTypeOf, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
	materializeBridgeCodeViewItem,
	type BridgeCodeViewDiffItem,
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

	test('keeps a diff placeholder as a diff when only one role is loaded', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['docs-plan'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected docs fixture with head handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 7 },
			resources: {
				head: makeContentResource(headHandle, '# Plan\n\nText body.'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized).toMatchObject({
			id: 'docs-plan',
			type: 'diff',
			version: 23,
			fileDiff: {
				name: 'docs/plans/2026-bridge-plan.md',
				deletionLines: [],
				additionLines: expect.arrayContaining(['# Plan\n', '\n', 'Text body.']),
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
				itemId: 'docs-plan',
			},
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('keeps unloaded diff side extents when partially hydrating visible content', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected source fixture with head handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				contentLineCountsByRole: {
					base: 17,
					head: 19,
				},
			},
			resources: {
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized.fileDiff.deletionLines).toContain('Loading content...\n');
		expect(materialized.fileDiff.deletionLines).toHaveLength(17);
		expect(materialized.fileDiff.additionLines).toContain('let value = 2\n');
		expect(materialized.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			contentRoles: ['head'],
			itemId: 'source-high',
			lineCount: 19,
		});
	});

	test('uses a newer CodeView render version when hydrating generation zero', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const originalItem = reviewPackage.itemsById['source-high'];
		if (originalItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const generationZeroPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...originalItem,
					itemVersion: 0,
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: generationZeroPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const placeholder = createBridgeCodeViewInitialItems({
			reviewPackage: generationZeroPackage,
			projection,
		}).find((item: BridgeCodeViewItem): boolean => item.id === 'source-high');
		const item = generationZeroPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			placeholder === undefined ||
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 0 },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}
		if (placeholder.version === undefined || materialized.version === undefined) {
			throw new Error('expected CodeView render versions');
		}

		expect(placeholder.version).toBe(0);
		expect(materialized.version).toBe(2);
		expect(materialized.version).toBeGreaterThan(placeholder.version);
	});

	test('hydrates an added new file as a one-sided CodeView diff with full content', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected added fixture with head handle');
		}
		const sourceText = [
			'export function renderAddedFile(): string {',
			"\treturn 'new file content';",
			'}',
			'',
		].join('\n');

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				headPath: 'Sources/NewFeature/AddedFile.ts',
				fileClass: 'source',
				extension: 'ts',
				language: 'typescript',
				isHiddenByDefault: false,
				hiddenReason: null,
			},
			resources: {
				head: makeContentResource(
					{
						...headHandle,
						isBinary: false,
						mimeType: 'text/typescript',
						language: 'typescript',
					},
					sourceText,
				),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected added diff materialization');
		}

		expect(materialized).toMatchObject({
			type: 'diff',
			fileDiff: {
				name: 'Sources/NewFeature/AddedFile.ts',
				deletionLines: [],
				additionLines: expect.arrayContaining([
					'export function renderAddedFile(): string {\n',
					"\treturn 'new file content';\n",
					'}\n',
				]),
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
			},
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('hydrates a modified item as a diff when base and head roles are loaded', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 9 },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized.fileDiff.name).toBe('Sources/App/Core.swift');
		expect(materialized.version).toBe(29);
		expect(materialized.fileDiff.deletionLines).toContain('let value = 1\n');
		expect(materialized.fileDiff.additionLines).toContain('let value = 2\n');
		expect(materialized.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			contentRoles: ['base', 'head'],
			itemId: 'source-high',
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('bounds oversized diff body materialization while keeping selected content visible', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}
		const baseText = makeGeneratedLines('base', 50_000);
		const headText = makeGeneratedLines('head', 50_000);

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				additions: 50_000,
				deletions: 50_000,
				itemVersion: 12,
			},
			resources: {
				base: makeContentResource({ ...baseHandle, sizeBytes: baseText.length }, baseText),
				head: makeContentResource({ ...headHandle, sizeBytes: headText.length }, headText),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected oversized content to remain a diff item');
		}

		expect(materialized.bridgeMetadata.contentState).toBe('windowed');
		expect(materialized.bridgeMetadata.cacheKey).toContain(':window:1500');
		expect(materialized.fileDiff.additionLines).toContain(
			"export const generatedLine0000 = 'head';\n",
		);
		expect(materialized.fileDiff.additionLines).not.toContain(
			"export const generatedLine5000 = 'head';\n",
		);
		expect(materialized.fileDiff.additionLines.length).toBeLessThan(3_000);
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('renders a review file target as a Pierre file item from the requested head version', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const itemWithStreamedLineCounts = {
			...item,
			contentLineCountsByRole: {
				head: 37,
			},
		};
		const materialized = materializeBridgeCodeViewItem({
			item: { ...itemWithStreamedLineCounts, itemVersion: 11 },
			presentation: { kind: 'file', version: 'current' },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'file') {
			throw new Error('expected file presentation materialization');
		}

		expect(materialized).toMatchObject({
			id: 'source-high',
			type: 'file',
			version: 35,
			file: {
				name: 'Sources/App/Core.swift',
				contents: 'let value = 2\n',
				cacheKey: headHandle.cacheKey,
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
				itemId: 'source-high',
				lineCount: 37,
			},
		});
	});

	test('renders a review file target as a Pierre file item from the requested base version', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item,
			presentation: { kind: 'file', version: 'base' },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'file') {
			throw new Error('expected file presentation materialization');
		}

		expect(materialized.file.contents).toBe('let value = 1\n');
		expect(materialized.bridgeMetadata.contentRoles).toEqual(['base']);
	});
});

function makeContentResource(
	handle: BridgeContentResource['handle'],
	text: string,
): BridgeContentResource {
	return { handle, readText: (): string => text };
}

function makeGeneratedLines(label: 'base' | 'head', lineCount: number): string {
	return Array.from({ length: lineCount }, (_value: unknown, index: number): string => {
		const paddedIndex = index.toString().padStart(4, '0');
		return `export const generatedLine${paddedIndex} = '${label}';`;
	}).join('\n');
}
