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
			request: { base: { kind: 'allFiles' }, refinements: [] },
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
			version: 0,
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

	test('hydrates a selected item as a file when only one role is loaded', () => {
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

		if (materialized?.type !== 'file') {
			throw new Error('expected file materialization');
		}

		expect(materialized).toMatchObject({
			id: 'docs-plan',
			type: 'file',
			version: 7,
			file: {
				name: 'docs/plans/2026-bridge-plan.md',
				contents: '# Plan\n\nText body.',
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
				itemId: 'docs-plan',
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
		expect(materialized.version).toBe(9);
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
