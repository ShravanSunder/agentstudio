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
	test('models base projection and refinements as discriminated unions', () => {
		expect(
			bridgeReviewProjectionRequestSchema.safeParse({
				base: { kind: 'currentChangeSet' },
				refinements: [],
			}).success,
		).toBe(false);
		expect(
			bridgeReviewProjectionRequestSchema.safeParse({
				base: { kind: 'currentChangeSet', scope: { kind: 'activePackage' } },
				refinements: [{ kind: 'folder', folderPath: 'Sources/App' }],
			}).success,
		).toBe(true);
	});

	test('projects base modes without content fetches or raw bodies', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();

		expect(projectItemIds({ base: { kind: 'allFiles' }, refinements: [] })).toEqual([
			'source-high',
			'source-normal',
			'test-view',
			'docs-plan',
			'renamed-source',
			'deleted-source',
			'duplicate-display',
		]);
		expect(projectItemIds({ base: { kind: 'docsAndPlans' }, refinements: [] })).toEqual([
			'docs-plan',
		]);
		expect(projectItemIds({ base: { kind: 'tests' }, refinements: [] })).toEqual(['test-view']);
		expect(projectItemIds({ base: { kind: 'source' }, refinements: [] })).toEqual([
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

	test('keeps rename and duplicate display-path maps deterministic', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'allFiles' }, refinements: [] },
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

	test('applies composable folder, extension, class, status, and visibility refinements', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const project = (request: BridgeReviewProjectionRequest): readonly string[] =>
			buildBridgeReviewProjection({ reviewPackage, request }).orderedItemIds;

		expect(
			project({
				base: { kind: 'changedFiles' },
				refinements: [{ kind: 'folder', folderPath: 'Sources/App' }],
			}),
		).toEqual(['source-high', 'source-normal', 'duplicate-display']);
		expect(
			project({
				base: { kind: 'allFiles' },
				refinements: [{ kind: 'extension', extensions: ['md'] }],
			}),
		).toEqual(['docs-plan']);
		expect(
			project({
				base: { kind: 'allFiles' },
				refinements: [{ kind: 'gitStatus', statuses: ['deleted'] }],
			}),
		).toEqual(['deleted-source']);
		expect(
			project({
				base: { kind: 'allFiles' },
				refinements: [
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
				base: { kind: 'guidedReview' },
				refinements: [
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
});

function itemWithOmittedLanguageFields(
	item: ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string],
): ReturnType<typeof makeBridgeViewerProjectionFixture>['itemsById'][string] {
	const { language: omittedLanguage, extension: omittedExtension, ...itemWithOmittedFields } = item;
	void omittedLanguage;
	void omittedExtension;
	return itemWithOmittedFields;
}
