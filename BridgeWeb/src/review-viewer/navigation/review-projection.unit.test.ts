import { describe, expect, test } from 'vitest';

import {
	bridgeReviewProjectionRequestSchema,
	type BridgeReviewProjectionRequest,
} from '../models/review-projection-models.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	buildBridgeReviewProjection,
	makeBridgeReviewProjectionInput,
} from './review-projection.js';

describe('Bridge review projection', () => {
	test('models base projection and facets as discriminated unions', () => {
		expect(
			bridgeReviewProjectionRequestSchema.safeParse({
				base: { kind: 'currentChangeSet' },
				facets: [],
			}).success,
		).toBe(false);
		expect(
			bridgeReviewProjectionRequestSchema.safeParse({
				mode: { kind: 'normalReview' },
				facets: [
					{ kind: 'changeScope', scope: { kind: 'activePackage' } },
					{ kind: 'folder', folderPath: 'Sources/App' },
				],
			}).success,
		).toBe(true);
	});

	test('projects base modes without content fetches or raw bodies', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();

		expect(projectItemIds({ mode: { kind: 'normalReview' }, facets: [] })).toEqual([
			'source-high',
			'source-normal',
			'test-view',
			'docs-plan',
			'renamed-source',
			'deleted-source',
			'duplicate-display',
		]);
		expect(projectItemIds({ mode: { kind: 'plansAndSpecs' }, facets: [] })).toEqual(['docs-plan']);
		expect(
			projectItemIds({
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['test'] }],
			}),
		).toEqual(['test-view']);
		expect(
			projectItemIds({
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'fileClass', fileClasses: ['source'] }],
			}),
		).toEqual([
			'source-high',
			'source-normal',
			'renamed-source',
			'deleted-source',
			'duplicate-display',
		]);

		function projectItemIds(request: BridgeReviewProjectionRequest): readonly string[] {
			return buildBridgeReviewProjection({ reviewPackage, request }).orderedItemIds;
		}
	});

	test('normalizes omitted Swift optional language and extension fields', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const itemWithoutLanguage = reviewPackage.itemsById['source-normal'];

		if (itemWithoutLanguage === undefined) {
			throw new Error('expected source-normal fixture item');
		}

		const nextPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[itemWithoutLanguage.itemId]: itemWithOmittedLanguageFields(itemWithoutLanguage),
			},
		};

		const projectionInput = makeBridgeReviewProjectionInput(nextPackage);
		const projectedItem = projectionInput.orderedItems.find(
			(item) => item.itemId === itemWithoutLanguage.itemId,
		);

		expect(projectedItem?.language).toBeNull();
		expect(projectedItem?.extension).toBeNull();
	});

	test('normalizes omitted Swift optional path fields for deleted files', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const deletedItem = reviewPackage.itemsById['deleted-source'];

		if (deletedItem === undefined) {
			throw new Error('expected deleted-source fixture item');
		}

		const nextPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[deletedItem.itemId]: itemWithOmittedHeadPath(deletedItem),
			},
		};

		const projectionInput = makeBridgeReviewProjectionInput(nextPackage);
		const projectedItem = projectionInput.orderedItems.find(
			(item) => item.itemId === deletedItem.itemId,
		);

		expect(projectedItem?.basePath).toBe('Sources/Removed.swift');
		expect(projectedItem?.headPath).toBeNull();
	});

	test('keeps rename and duplicate display-path maps deterministic', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});

		expect(projection.candidatePathsByItemId['renamed-source']).toEqual([
			'Sources/NewName.swift',
			'Sources/OldName.swift',
		]);
		expect(projection.primaryItemIdByTreePath['Sources/App/View.swift']).toBe('source-normal');
		expect(projection.secondaryItemIdsByTreePath['Sources/App/View.swift']).toEqual([
			'duplicate-display',
		]);
		expect(projection.availableContentRolesByItemId['deleted-source']).toEqual(['base']);
	});

	test('applies composable folder, extension, class, status, and visibility facets', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const project = (request: BridgeReviewProjectionRequest): readonly string[] =>
			buildBridgeReviewProjection({ reviewPackage, request }).orderedItemIds;

		expect(
			project({
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'folder', folderPath: 'Sources/App' }],
			}),
		).toEqual(['source-high', 'source-normal', 'duplicate-display']);
		expect(
			project({
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'extension', extensions: ['md'] }],
			}),
		).toEqual(['docs-plan']);
		expect(
			project({
				mode: { kind: 'normalReview' },
				facets: [{ kind: 'gitStatus', statuses: ['deleted'] }],
			}),
		).toEqual(['deleted-source']);
		expect(
			project({
				mode: { kind: 'normalReview' },
				facets: [
					{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
				],
			}),
		).toContain('hidden-binary');
	});

	test('orders guided review from descriptor metadata only', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: {
				mode: { kind: 'guidedReview' },
				facets: [
					{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
				],
			},
		});

		expect(projection.orderedItemIds.slice(0, 2)).toEqual(['source-high', 'source-normal']);
		expect(projection.orderedItemIds.indexOf('test-view')).toBeLessThan(
			projection.orderedItemIds.indexOf('docs-plan'),
		);
		expect(projection.orderedItemIds.at(-1)).toBe('hidden-binary');
	});

	test('orders guided review without requiring ES2023 Array toSorted', () => {
		const arrayPrototype = Array.prototype as Array<unknown> & {
			toSorted?: Array<unknown>['toSorted'];
		};
		const originalToSorted = arrayPrototype.toSorted;
		Reflect.deleteProperty(arrayPrototype, 'toSorted');

		try {
			const reviewPackage = makeBridgeViewerProjectionFixture();
			const projection = buildBridgeReviewProjection({
				reviewPackage,
				request: {
					mode: { kind: 'guidedReview' },
					facets: [
						{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
					],
				},
			});

			expect(projection.orderedItemIds.slice(0, 2)).toEqual(['source-high', 'source-normal']);
		} finally {
			if (originalToSorted !== undefined) {
				arrayPrototype.toSorted = originalToSorted;
			}
		}
	});

	test('freezes guided order for already-projected rows while streaming flips ranking keys (F5/R7)', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const guidedRequest: BridgeReviewProjectionRequest = {
			mode: { kind: 'guidedReview' },
			facets: [
				{ kind: 'visibility', includeHidden: true, includeBinary: true, includeLarge: true },
			],
		};
		const initialOrder = buildBridgeReviewProjection({
			reviewPackage,
			request: guidedRequest,
		}).orderedItemIds;
		expect(initialOrder[0]).toBe('source-high');

		// Streaming metadata flips a ranking key on an already-projected row (source-high becomes
		// resolved), which drops its guided rank.
		const sourceHigh = reviewPackage.itemsById['source-high'];
		if (sourceHigh === undefined) {
			throw new Error('expected source-high fixture item');
		}
		const streamedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': { ...sourceHigh, reviewState: 'resolved' as const },
			},
		};

		// Without the freeze hint the re-rank reshuffles source-high out of the top row.
		const reshuffledOrder = buildBridgeReviewProjection({
			reviewPackage: streamedPackage,
			request: guidedRequest,
		}).orderedItemIds;
		expect(reshuffledOrder[0]).not.toBe('source-high');

		// With the prior order as the stable hint, already-projected rows keep their order.
		const frozenProjection = buildBridgeReviewProjection({
			reviewPackage: streamedPackage,
			request: guidedRequest,
			stableGuidedOrderHint: initialOrder,
		});
		expect(frozenProjection.orderedItemIds).toEqual(initialOrder);

		// Load-bearing: the freeze hint must NOT change the projectionId — otherwise the CodeView
		// mount key / worker fingerprint would churn every streaming window and remount the view.
		const unhintedProjection = buildBridgeReviewProjection({
			reviewPackage: streamedPackage,
			request: guidedRequest,
		});
		expect(frozenProjection.projectionId).toBe(unhintedProjection.projectionId);
	});
});

function itemWithOmittedLanguageFields(
	item: ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string],
): ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string] {
	const { language: omittedLanguage, extension: omittedExtension, ...itemWithOmittedFields } = item;
	void omittedLanguage;
	void omittedExtension;
	return itemWithOmittedFields;
}

function itemWithOmittedHeadPath(
	item: ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string],
): ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string] {
	const { headPath: omittedHeadPath, ...itemWithOmittedField } = item;
	void omittedHeadPath;
	return itemWithOmittedField;
}
