import { describe, expect, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeReviewItemWindowRegistry,
	makeBridgeReviewItemsResourceUrl,
} from './review-item-window-registry.js';

describe('review item window registry', () => {
	test('serves explicit item-id windows from the active projection without storing item bodies', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
		});
		const registry = createBridgeReviewItemWindowRegistry();
		registry.setActiveIdentity({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
		});
		const resourceUrl = makeBridgeReviewItemsResourceUrl({
			packageId: reviewPackage.packageId,
			generation: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			range: { kind: 'list', itemIds: ['source-high', 'source-normal'] },
		});

		const window = registry.readWindow({
			reviewPackage,
			projection,
			resourceUrl,
		});

		expect(window.itemIds).toEqual(['source-high', 'source-normal']);
		expect(window.items[0]?.itemId).toBe('source-high');
		expect(window.items[0]?.contentRoles.head?.resourceUrl).toContain(
			'agentstudio://resource/content/',
		);
		expect(registry.snapshot()).toMatchObject({
			cachedWindowCount: 1,
			activeIdentity: {
				packageId: reviewPackage.packageId,
				reviewGeneration: reviewPackage.reviewGeneration,
				revision: reviewPackage.revision,
			},
		});
	});

	test('rejects explicit item IDs outside the active projection before reading package items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});
		const registry = createBridgeReviewItemWindowRegistry();
		registry.setActiveIdentity({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
		});
		const resourceUrl = makeBridgeReviewItemsResourceUrl({
			packageId: reviewPackage.packageId,
			generation: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			range: { kind: 'list', itemIds: ['source-high'] },
		});

		expect(() =>
			registry.readWindow({
				reviewPackage,
				projection,
				resourceUrl,
			}),
		).toThrow('Bridge review item window contains item outside active projection');
		expect(registry.snapshot().cachedWindowCount).toBe(0);
	});

	test('rejects explicit item-id windows that exceed the registry budget before reading items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
		});
		const registry = createBridgeReviewItemWindowRegistry({
			budget: { maxExplicitItemIds: 1, maxCursorWindowItems: 8 },
		});
		registry.setActiveIdentity({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
		});
		const resourceUrl = makeBridgeReviewItemsResourceUrl({
			packageId: reviewPackage.packageId,
			generation: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			range: { kind: 'list', itemIds: ['source-high', 'source-normal'] },
		});

		expect(() =>
			registry.readWindow({
				reviewPackage,
				projection,
				resourceUrl,
			}),
		).toThrow('Bridge review item window registry requires a review-items resource URL');
		expect(registry.snapshot().cachedWindowCount).toBe(0);
	});

	test('serves cursor windows only after a cursor has been registered for the active identity', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
		});
		const registry = createBridgeReviewItemWindowRegistry();
		registry.setActiveIdentity({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
		});
		registry.registerCursor({
			cursor: 'cursor-source',
			identity: {
				packageId: reviewPackage.packageId,
				reviewGeneration: reviewPackage.reviewGeneration,
				revision: reviewPackage.revision,
			},
			orderedItemIds: projection.orderedItemIds,
		});
		const resourceUrl = makeBridgeReviewItemsResourceUrl({
			packageId: reviewPackage.packageId,
			generation: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			range: { kind: 'itemWindow', cursor: 'cursor-source', start: 1, end: 3 },
		});

		const window = registry.readWindow({
			reviewPackage,
			projection,
			resourceUrl,
		});

		expect(window.itemIds).toEqual(['source-normal', 'renamed-source']);
	});

	test('clears cached windows when package identity changes', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			},
		});
		const registry = createBridgeReviewItemWindowRegistry();
		const identity = {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
		};
		registry.setActiveIdentity(identity);
		registry.readWindow({
			reviewPackage,
			projection,
			resourceUrl: makeBridgeReviewItemsResourceUrl({
				packageId: reviewPackage.packageId,
				generation: reviewPackage.reviewGeneration,
				revision: reviewPackage.revision,
				range: { kind: 'list', itemIds: ['source-high'] },
			}),
		});

		registry.setActiveIdentity({ ...identity, revision: identity.revision + 1 });

		expect(registry.snapshot().cachedWindowCount).toBe(0);
	});

	test('builds canonical review-items resource URLs for list and cursor ranges', () => {
		expect(
			makeBridgeReviewItemsResourceUrl({
				packageId: 'package-1',
				generation: 7,
				revision: 3,
				range: { kind: 'list', itemIds: ['item-b', 'item-a'] },
			}),
		).toBe(
			'agentstudio://resource/review-items/package-1?generation=7&itemIds=item-b%2Citem-a&rangeKind=list&revision=3',
		);
		expect(
			makeBridgeReviewItemsResourceUrl({
				packageId: 'package-1',
				generation: 7,
				revision: 3,
				range: { kind: 'itemWindow', cursor: 'cursor-1', start: 4, end: 9 },
			}),
		).toBe(
			'agentstudio://resource/review-items/package-1?cursor=cursor-1&end=9&generation=7&rangeKind=itemWindow&revision=3&start=4',
		);
	});
});
