import { describe, expect, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import {
	makeBridgeCodeViewSourceKey,
	reconcileBridgeCodeViewMetadataItems,
	selectedContentSummaryForPanel,
	shouldApplyBridgeCodeViewMaterialization,
	shouldContinueCodeViewHeaderPinLoop,
} from './bridge-code-view-panel.js';

describe('BridgeCodeViewPanel diagnostics', () => {
	test('keys the mounted Pierre viewer by review source and projection identity', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const sameSourceNextRevision = {
			...reviewPackage,
			revision: reviewPackage.revision + 1,
		};
		const differentGeneration = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const differentProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});

		expect(makeBridgeCodeViewSourceKey({ projection, reviewPackage: sameSourceNextRevision })).toBe(
			makeBridgeCodeViewSourceKey({ projection, reviewPackage }),
		);
		expect(
			makeBridgeCodeViewSourceKey({ projection, reviewPackage: differentGeneration }),
		).not.toBe(makeBridgeCodeViewSourceKey({ projection, reviewPackage }));
		expect(
			makeBridgeCodeViewSourceKey({ projection: differentProjection, reviewPackage }),
		).not.toBe(makeBridgeCodeViewSourceKey({ projection, reviewPackage }));
	});

	test('reconciles metadata projection changes without blanking hydrated CodeView items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const metadataPlaceholder = materializeBridgeCodeViewLoadingItem(sourceItem);
		const hydratedItem = {
			...metadataPlaceholder,
			bridgeMetadata: {
				...metadataPlaceholder.bridgeMetadata,
				contentState: 'hydrated' as const,
			},
			version: (metadataPlaceholder.version ?? 0) + 1,
		};
		const [metadataItem] = projection.orderedItemIds
			.filter((itemId: string): boolean => itemId === sourceItem.itemId)
			.map(() => metadataPlaceholder);
		if (metadataItem === undefined) {
			throw new Error('expected metadata item');
		}

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) => (itemId === sourceItem.itemId ? hydratedItem : undefined),
			metadataItems: [metadataItem],
		});

		expect(reconciledItems).toEqual([hydratedItem]);
	});

	test('keeps selected hydrated CodeView item when metadata window does not include it', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const selectedOffWindowItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || selectedOffWindowItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const metadataItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const selectedHydratedItem = {
			...materializeBridgeCodeViewLoadingItem(selectedOffWindowItem),
			bridgeMetadata: {
				...materializeBridgeCodeViewLoadingItem(selectedOffWindowItem).bridgeMetadata,
				contentState: 'hydrated' as const,
			},
			version: selectedOffWindowItem.itemVersion + 1,
		};

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) =>
				itemId === selectedOffWindowItem.itemId ? selectedHydratedItem : undefined,
			metadataItems: [metadataItem],
			preserveItemIds: [selectedOffWindowItem.itemId],
		});

		expect(reconciledItems.map((item) => item.id)).toEqual([
			sourceItem.itemId,
			selectedOffWindowItem.itemId,
		]);
		expect(reconciledItems[1]).toBe(selectedHydratedItem);
	});

	test('does not read large selected content bodies to build panel summary attributes', () => {
		let readTextCallCount = 0;
		const resource: BridgeContentResource = {
			authoritative: true,
			byteLength: 512_000,
			handle: makeBridgeContentHandle('source-high', 'head'),
			readText: (): string => {
				readTextCallCount += 1;
				return 'large body\n'.repeat(50_000);
			},
		};

		const summary = selectedContentSummaryForPanel({
			selectedContentResources: { head: resource },
		});

		expect(summary.cacheKeyCount).toBe(1);
		expect(summary.characterCount).toBe(512_000);
		expect(summary.lineCount).toBe(0);
		expect(readTextCallCount).toBe(0);
	});

	test('stops selected header pinning once the header is settled', () => {
		expect(
			shouldContinueCodeViewHeaderPinLoop({
				frameBudget: 30,
				pinResult: 'settled',
			}),
		).toBe(false);
		expect(
			shouldContinueCodeViewHeaderPinLoop({
				frameBudget: 30,
				pinResult: 'adjusted',
			}),
		).toBe(true);
		expect(
			shouldContinueCodeViewHeaderPinLoop({
				frameBudget: 0,
				pinResult: 'missing',
			}),
		).toBe(false);
		expect(
			shouldContinueCodeViewHeaderPinLoop({
				frameBudget: 30,
				pinResult: 'missing',
			}),
		).toBe(false);
	});

	test('blocks non-selected CodeView materialization while review scroll is active', () => {
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: true,
				itemId: 'visible-neighbor',
				selectedItemId: 'selected-item',
			}),
		).toBe(false);
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: true,
				itemId: 'selected-item',
				selectedItemId: 'selected-item',
			}),
		).toBe(true);
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: false,
				itemId: 'visible-neighbor',
				selectedItemId: 'selected-item',
			}),
		).toBe(true);
	});
});
