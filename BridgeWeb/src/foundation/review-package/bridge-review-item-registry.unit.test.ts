import { describe, expect, test } from 'vitest';

import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from './bridge-review-item-registry.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from './bridge-review-package-test-support.js';

describe('bridge review item registry', () => {
	test('rejects stale generation deltas with an explicit fact', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const registry = createBridgeReviewItemRegistry({
			reviewPackage,
			selectedItemId: 'item-source',
		});

		const result = applyDeltaToBridgeReviewItemRegistry(registry, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
			revision: 2,
			operations: {
				addItems: [makeBridgeReviewItem({ itemId: 'item-added', path: 'Sources/App/New.swift' })],
				updateItems: [],
				removeItems: [],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(result).toEqual({
			accepted: false,
			reason: 'generationMismatch',
			registry,
		});
	});

	test('rejects non-contiguous revision deltas before mutating package state', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const registry = createBridgeReviewItemRegistry({
			reviewPackage,
			selectedItemId: 'item-source',
		});

		const result = applyDeltaToBridgeReviewItemRegistry(registry, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 2,
			operations: {
				addItems: [makeBridgeReviewItem({ itemId: 'item-added', path: 'Sources/App/New.swift' })],
				updateItems: [],
				removeItems: [],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(result).toEqual({
			accepted: false,
			reason: 'revisionGap',
			registry,
		});
	});

	test('applies deltas in package order and exposes selected visible priority facts', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const updatedItem = {
			...makeBridgeReviewItem({ itemId: 'item-source', path: 'Sources/App/View.swift' }),
			reviewPriority: 'high' as const,
		};
		const addedHiddenItem = {
			...makeBridgeReviewItem({ itemId: 'item-hidden', path: 'Sources/App/Generated.swift' }),
			fileClass: 'generated' as const,
			isHiddenByDefault: true,
			hiddenReason: 'generated',
		};
		const registry = createBridgeReviewItemRegistry({
			reviewPackage,
			selectedItemId: 'item-source',
		});

		const result = applyDeltaToBridgeReviewItemRegistry(registry, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [addedHiddenItem],
				updateItems: [updatedItem],
				removeItems: [],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(result.accepted).toBe(true);
		if (!result.accepted) {
			throw new Error('expected delta acceptance');
		}
		expect(result.registry.orderedItems.map((item) => item.itemId)).toEqual([
			'item-source',
			'item-hidden',
		]);
		expect(result.registry.visiblePriorityFacts).toEqual([
			{
				itemId: 'item-source',
				pathLabel: 'Sources/App/View.swift',
				reviewPriority: 'high',
				isSelected: true,
			},
		]);
	});

	test('keeps out-of-scope added items out of visible review facts', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const registry = createBridgeReviewItemRegistry({
			reviewPackage,
			selectedItemId: 'item-source',
		});

		const result = applyDeltaToBridgeReviewItemRegistry(registry, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [
					makeBridgeReviewItem({
						itemId: 'item-doc',
						path: 'Docs/Guide.md',
					}),
				],
				updateItems: [],
				removeItems: [],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(result.accepted).toBe(true);
		if (!result.accepted) {
			throw new Error('expected delta acceptance');
		}
		expect(result.registry.orderedItems.map((item) => item.itemId)).toEqual([
			'item-source',
			'item-doc',
		]);
		expect(result.registry.visibleItems.map((item) => item.itemId)).toEqual(['item-source']);
	});
});
