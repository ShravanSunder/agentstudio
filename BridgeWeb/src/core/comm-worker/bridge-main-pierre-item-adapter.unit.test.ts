import { describe, expect, test } from 'vitest';

import { prepareBridgeMainPierreItemForPresentation } from './bridge-main-pierre-item-adapter.js';
import type { BridgeMainRenderPublicationItem } from './bridge-main-render-fulfillment-coordinator.js';

type BridgeMainFilePierreItem = Extract<BridgeMainRenderPublicationItem, { readonly type: 'file' }>;
type BridgeMainReviewPierreItem = Extract<
	BridgeMainRenderPublicationItem,
	{ readonly type: 'diff' }
>;

describe('Bridge main Pierre item adapter', () => {
	test('mints version 1 for the first final item without inheriting the worker version', () => {
		// Arrange
		const presentationItem = makeFilePresentationItem({
			contents: 'export const revision = 1;\n',
			version: 37,
		});

		// Act
		const prepared = prepareBridgeMainPierreItemForPresentation({
			currentItem: undefined,
			presentationItem,
		});

		// Assert
		expect(prepared.residency).toBe('replaced');
		expect(prepared.item).not.toBe(presentationItem);
		expect(prepared.item).toMatchObject({
			bridgeMetadata: presentationItem.bridgeMetadata,
			file: presentationItem.file,
			id: presentationItem.id,
			type: 'file',
			version: 1,
		});
		expect(presentationItem.version).toBe(37);
	});

	test('mints the next version for changed Review content while preserving local collapse', () => {
		// Arrange
		const currentItem = makeReviewPresentationItem({
			collapsed: true,
			revision: 1,
			version: 7,
		});
		const presentationItem = makeReviewPresentationItem({ revision: 2, version: 93 });

		// Act
		const prepared = prepareBridgeMainPierreItemForPresentation({
			currentItem,
			presentationItem,
		});

		// Assert
		expect(prepared.residency).toBe('replaced');
		expect(prepared.item).not.toBe(currentItem);
		expect(prepared.item).not.toBe(presentationItem);
		expect(prepared.item).toMatchObject({
			bridgeMetadata: presentationItem.bridgeMetadata,
			collapsed: true,
			fileDiff: presentationItem.fileDiff,
			id: presentationItem.id,
			type: 'diff',
			version: 8,
		});
		expect(presentationItem.collapsed).toBeUndefined();
		expect(presentationItem.version).toBe(93);
	});

	test('reuses the exact painted item when the collapse-preserved final fingerprint is equal', () => {
		// Arrange
		const currentItem = makeReviewPresentationItem({
			collapsed: true,
			revision: 4,
			version: 12,
		});
		const retryPresentationItem = makeReviewPresentationItem({ revision: 4, version: 1_200 });
		expect(retryPresentationItem).not.toBe(currentItem);

		// Act
		const prepared = prepareBridgeMainPierreItemForPresentation({
			currentItem,
			presentationItem: retryPresentationItem,
		});

		// Assert
		expect(prepared).toEqual({ item: currentItem, residency: 'reusedPainted' });
		expect(prepared.item).toBe(currentItem);
		expect(prepared.item.collapsed).toBe(true);
		expect(prepared.item.version).toBe(12);
		expect(retryPresentationItem.collapsed).toBeUndefined();
		expect(retryPresentationItem.version).toBe(1_200);
	});
});

function makeFilePresentationItem(props: {
	readonly contents: string;
	readonly version: number;
}): BridgeMainFilePierreItem {
	const cacheKey = `file:${props.contents}`;
	return {
		bridgeMetadata: {
			cacheKey,
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: 'Sources/File.ts',
			itemId: 'file-item',
			lineCount: 1,
		},
		file: {
			cacheKey,
			contents: props.contents,
			lang: 'typescript',
			name: 'Sources/File.ts',
		},
		id: 'file:file-item',
		type: 'file',
		version: props.version,
	};
}

function makeReviewPresentationItem(props: {
	readonly collapsed?: boolean;
	readonly revision: number;
	readonly version: number;
}): BridgeMainReviewPierreItem {
	const contentCacheKey = `review:${props.revision}`;
	return {
		bridgeMetadata: {
			cacheKey: contentCacheKey,
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: 'Sources/Review.ts',
			itemId: 'review-item',
			lineCount: 2,
		},
		fileDiff: {
			additionLines: [`export const revision = ${props.revision};`],
			deletionLines: ['export const revision = 0;'],
			hunks: [],
			isPartial: false,
			name: 'Sources/Review.ts',
			splitLineCount: 2,
			type: 'change',
			unifiedLineCount: 2,
		},
		id: 'review-item',
		type: 'diff',
		version: props.version,
		...(props.collapsed === undefined ? {} : { collapsed: props.collapsed }),
	};
}
