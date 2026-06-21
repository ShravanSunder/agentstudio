import { describe, expect, expectTypeOf, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	type BridgeCodeViewDiffItem,
	type BridgeCodeViewFileItem,
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
			version: 2,
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

	test('creates collapsed placeholder file items so unloaded content does not render as blank body rows', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		const items = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderFile = items.find(
			(item: BridgeCodeViewItem): boolean => item.id === 'deleted-source',
		);

		if (placeholderFile === undefined || placeholderFile.type !== 'file') {
			throw new Error('expected deleted-source placeholder file');
		}
		expect(placeholderFile.bridgeMetadata.contentState).toBe('placeholder');
		expect(placeholderFile.file.contents).toBe('');
		expect(placeholderFile.collapsed).toBe(true);
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
			version: 15,
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
		expect(materialized.version).toBe(1);
		expect(materialized.version).toBeGreaterThan(placeholder.version);
	});

	test('hydrates an added new file as full CodeView file content', () => {
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

		if (materialized?.type !== 'file') {
			throw new Error('expected added file materialization');
		}

		expect(materialized).toMatchObject({
			type: 'file',
			file: {
				name: 'Sources/NewFeature/AddedFile.ts',
				contents: sourceText,
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
			},
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewFileItem>();
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
		expect(materialized.version).toBe(19);
		expect(materialized.fileDiff.deletionLines).toContain('let value = 1\n');
		expect(materialized.fileDiff.additionLines).toContain('let value = 2\n');
		expect(materialized.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			contentRoles: ['base', 'head'],
			itemId: 'source-high',
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});
});

function makeContentResource(
	handle: BridgeContentResource['handle'],
	text: string,
): BridgeContentResource {
	return { handle, text };
}
