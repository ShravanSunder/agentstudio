import { describe, expect, test } from 'vitest';

import {
	bridgeReviewItemWindowBudgetInputsSchema,
	bridgeReviewItemWindowBudgetSchema,
	resolveBridgeReviewItemWindowBudget,
} from './review-item-window-budget.js';

describe('review item window budget', () => {
	test('derives a bounded request size from visible rows, overscan, latency, and cache health', () => {
		const budget = resolveBridgeReviewItemWindowBudget({
			measuredVisibleItemCount: 42,
			overscanItemCount: 12,
			resourceCacheHitRate: 0.52,
			workerLatencyMilliseconds: 260,
			fetchLatencyMilliseconds: 288,
			currentPackageItemCount: 3420,
			memoryPressure: 'normal',
		});

		expect(bridgeReviewItemWindowBudgetSchema.parse(budget)).toEqual(budget);
		expect(budget.requestedItemCount).toBeGreaterThan(42 + 12);
		expect(budget.requestedItemCount).toBeLessThanOrEqual(budget.maxCursorWindowItems);
		expect(budget.maxExplicitItemIds).toBeLessThan(budget.maxCursorWindowItems);
	});

	test('contracts request size under high memory pressure without changing safety ceilings', () => {
		const normalBudget = resolveBridgeReviewItemWindowBudget({
			measuredVisibleItemCount: 64,
			overscanItemCount: 16,
			resourceCacheHitRate: 0.4,
			workerLatencyMilliseconds: 260,
			fetchLatencyMilliseconds: 320,
			currentPackageItemCount: 5000,
			memoryPressure: 'normal',
		});
		const pressuredBudget = resolveBridgeReviewItemWindowBudget({
			measuredVisibleItemCount: 64,
			overscanItemCount: 16,
			resourceCacheHitRate: 0.4,
			workerLatencyMilliseconds: 260,
			fetchLatencyMilliseconds: 320,
			currentPackageItemCount: 5000,
			memoryPressure: 'high',
		});

		expect(pressuredBudget.requestedItemCount).toBeLessThan(normalBudget.requestedItemCount);
		expect(pressuredBudget.maxExplicitItemIds).toBe(normalBudget.maxExplicitItemIds);
		expect(pressuredBudget.maxCursorWindowItems).toBe(normalBudget.maxCursorWindowItems);
	});

	test('rejects nonsensical metric inputs at the schema boundary', () => {
		expect(() =>
			bridgeReviewItemWindowBudgetInputsSchema.parse({
				measuredVisibleItemCount: -1,
				overscanItemCount: 4,
				resourceCacheHitRate: 0.5,
				workerLatencyMilliseconds: 10,
				fetchLatencyMilliseconds: 10,
				currentPackageItemCount: 20,
				memoryPressure: 'normal',
			}),
		).toThrow();
	});
});
