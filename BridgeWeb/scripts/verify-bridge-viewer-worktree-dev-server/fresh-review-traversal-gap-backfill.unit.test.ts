import { describe, expect, test } from 'vitest';

import {
	detectFreshReviewTraversalCrossedGap,
	nextFreshReviewTraversalBackfillScrollTop,
	requireFreshReviewTraversalComplete,
	revalidateFreshReviewTraversalGapGeometry,
	subdivideFreshReviewTraversalGap,
	type FreshReviewTraversalCoverageObservation,
	type FreshReviewTraversalGap,
} from './fresh-review-traversal-gap-backfill.ts';

describe('detectFreshReviewTraversalCrossedGap', () => {
	test.each([
		{ nextCatalogIndex: 42, transitionLabel: 'same catalog item' },
		{ nextCatalogIndex: 43, transitionLabel: 'adjacent catalog item' },
	])('does not create a gap for a large-body jump to the $transitionLabel', (testCase) => {
		// Arrange
		const previousObservation = makeCoverageObservation({
			headerCatalogIndexes: [42],
			hydratedVisibleCatalogIndexes: [42],
			scrollTop: 1_000,
		});
		const nextObservation = makeCoverageObservation({
			headerCatalogIndexes: [testCase.nextCatalogIndex],
			hydratedVisibleCatalogIndexes: [testCase.nextCatalogIndex],
			scrollTop: 8_000,
		});

		// Act
		const gap = detectFreshReviewTraversalCrossedGap({
			nextObservation,
			observedHeaderCatalogIndexes: new Set([42, testCase.nextCatalogIndex]),
			observedHydrationCatalogIndexes: new Set([42, testCase.nextCatalogIndex]),
			previousObservation,
		});

		// Assert
		expect(gap).toBeNull();
	});

	test('captures the exact independent header and hydration ranges crossed by a fast jump', () => {
		// Arrange
		const previousObservation = makeCoverageObservation({
			headerCatalogIndexes: [1_142, 1_143, 1_144],
			hydratedVisibleCatalogIndexes: [1_128, 1_129],
			scrollTop: 80_000,
		});
		const nextObservation = makeCoverageObservation({
			headerCatalogIndexes: [1_201, 1_202],
			hydratedVisibleCatalogIndexes: [1_207, 1_208],
			scrollTop: 132_000,
		});

		// Act
		const gap = detectFreshReviewTraversalCrossedGap({
			nextObservation,
			observedHeaderCatalogIndexes: new Set([
				...previousObservation.headerCatalogIndexes,
				...nextObservation.headerCatalogIndexes,
			]),
			observedHydrationCatalogIndexes: new Set([
				...previousObservation.hydratedVisibleCatalogIndexes,
				...nextObservation.hydratedVisibleCatalogIndexes,
			]),
			previousObservation,
		});

		// Assert
		expect(gap).toMatchObject({
			missingHeaderCatalogIndexes: catalogIndexRange(1_145, 1_200),
			missingHydrationCatalogIndexes: catalogIndexRange(1_130, 1_206),
		});
	});

	test('captures a hydration-only singleton without inventing a header gap', () => {
		// Arrange
		const previousObservation = makeCoverageObservation({
			headerCatalogIndexes: [752],
			hydratedVisibleCatalogIndexes: [752],
			scrollTop: 20_000,
		});
		const nextObservation = makeCoverageObservation({
			headerCatalogIndexes: [753],
			hydratedVisibleCatalogIndexes: [754],
			scrollTop: 26_000,
		});

		// Act
		const gap = detectFreshReviewTraversalCrossedGap({
			nextObservation,
			observedHeaderCatalogIndexes: new Set([752, 753]),
			observedHydrationCatalogIndexes: new Set([752, 754]),
			previousObservation,
		});

		// Assert
		expect(gap).toMatchObject({
			missingHeaderCatalogIndexes: [],
			missingHydrationCatalogIndexes: [753],
		});
	});
});

describe('fresh Review traversal gap backfill', () => {
	test('rebuilds a pixel bracket against changed scroll geometry before choosing a midpoint', () => {
		// Arrange
		const staleGap = makeTraversalGap({
			clientHeight: 1_000,
			lowerScrollTop: 10_000,
			scrollHeight: 101_000,
			upperScrollTop: 60_000,
		});

		// Act
		const revalidatedGap = revalidateFreshReviewTraversalGapGeometry({
			codeScroll: {
				clientHeight: 1_000,
				scrollHeight: 201_000,
				scrollTop: 200_000,
			},
			gap: staleGap,
		});
		const midpoint = nextFreshReviewTraversalBackfillScrollTop(revalidatedGap);

		// Assert
		expect(revalidatedGap).toMatchObject({
			clientHeight: 1_000,
			lowerScrollTop: 20_000,
			scrollHeight: 201_000,
			upperScrollTop: 120_000,
		});
		expect(midpoint).toBe(70_000);
	});

	test('splits only the sub-brackets that still contain unresolved catalog indexes', () => {
		// Arrange
		const gap = makeTraversalGap({
			missingHeaderCatalogIndexes: [2, 3, 4],
			missingHydrationCatalogIndexes: [2, 3, 4],
		});

		// Act
		const subdivisions = subdivideFreshReviewTraversalGap({
			gap,
			observedHeaderCatalogIndexes: new Set([3]),
			observedHydrationCatalogIndexes: new Set([3]),
			splitObservation: makeCoverageObservation({
				clientHeight: 1_000,
				headerCatalogIndexes: [3],
				hydratedVisibleCatalogIndexes: [3],
				scrollHeight: 101_000,
				scrollTop: 50_000,
			}),
		});

		// Assert
		expect(subdivisions).toEqual([
			expect.objectContaining({
				lowerScrollTop: 0,
				missingHeaderCatalogIndexes: [2],
				missingHydrationCatalogIndexes: [2],
				upperScrollTop: 50_000,
			}),
			expect.objectContaining({
				lowerScrollTop: 50_000,
				missingHeaderCatalogIndexes: [4],
				missingHydrationCatalogIndexes: [4],
				upperScrollTop: 100_000,
			}),
		]);
	});

	test('cannot report success when the backfill budget ends with missing coverage', () => {
		// Arrange / Act / Assert
		expect((): void => {
			requireFreshReviewTraversalComplete({
				backfillStepBudget: 8,
				backfillStepsUsed: 8,
				missingHeaderCatalogIndexes: [1_145],
				missingHydrationCatalogIndexes: [1_130],
				pendingGapCount: 1,
				requiredSettledBottomTurnCount: 3,
				settledBottomTurnCount: 3,
			});
		}).toThrowError(/REVIEW_FRESH_ROUTE_BACKFILL_BUDGET_EXHAUSTED/);
	});
});

function makeCoverageObservation(props: {
	readonly clientHeight?: number;
	readonly headerCatalogIndexes: readonly number[];
	readonly hydratedVisibleCatalogIndexes: readonly number[];
	readonly scrollHeight?: number;
	readonly scrollTop: number;
}): FreshReviewTraversalCoverageObservation {
	return {
		clientHeight: props.clientHeight ?? 1_000,
		headerCatalogIndexes: props.headerCatalogIndexes,
		hydratedVisibleCatalogIndexes: props.hydratedVisibleCatalogIndexes,
		scrollHeight: props.scrollHeight ?? 201_000,
		scrollTop: props.scrollTop,
	};
}

function makeTraversalGap(
	overrides: Partial<FreshReviewTraversalGap> = {},
): FreshReviewTraversalGap {
	return {
		clientHeight: 1_000,
		lowerScrollTop: 0,
		missingHeaderCatalogIndexes: [2],
		missingHydrationCatalogIndexes: [2],
		scrollHeight: 101_000,
		upperScrollTop: 100_000,
		...overrides,
	};
}

function catalogIndexRange(firstCatalogIndex: number, lastCatalogIndex: number): number[] {
	return Array.from(
		{ length: lastCatalogIndex - firstCatalogIndex + 1 },
		(_, offset): number => firstCatalogIndex + offset,
	);
}
