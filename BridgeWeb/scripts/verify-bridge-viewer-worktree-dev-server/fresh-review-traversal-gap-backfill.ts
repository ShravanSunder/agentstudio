export interface FreshReviewTraversalCoverageObservation {
	readonly clientHeight: number;
	readonly headerCatalogIndexes: readonly number[];
	readonly hydratedVisibleCatalogIndexes: readonly number[];
	readonly scrollHeight: number;
	readonly scrollTop: number;
}

export interface FreshReviewTraversalGap {
	readonly clientHeight: number;
	readonly lowerScrollTop: number;
	readonly missingHeaderCatalogIndexes: readonly number[];
	readonly missingHydrationCatalogIndexes: readonly number[];
	readonly scrollHeight: number;
	readonly upperScrollTop: number;
}

export interface FreshReviewTraversalBackfillResult {
	readonly backfillStepsUsed: number;
	readonly pendingGaps: readonly FreshReviewTraversalGap[];
}

export function createFreshReviewTraversalCoverageObservation(props: {
	readonly expectedItemIndexById: ReadonlyMap<string, number>;
	readonly hydrationWindow: { readonly hydratedNonSelectedItemIds: readonly string[] };
	readonly viewportState: {
		readonly codeScroll: {
			readonly clientHeight: number;
			readonly scrollHeight: number;
			readonly scrollTop: number;
		};
		readonly mountedItemIds: readonly string[];
	};
}): FreshReviewTraversalCoverageObservation {
	return {
		...props.viewportState.codeScroll,
		headerCatalogIndexes: expectedCatalogIndexesForItemIds({
			expectedItemIndexById: props.expectedItemIndexById,
			itemIds: props.viewportState.mountedItemIds,
		}),
		hydratedVisibleCatalogIndexes: expectedCatalogIndexesForItemIds({
			expectedItemIndexById: props.expectedItemIndexById,
			itemIds: props.hydrationWindow.hydratedNonSelectedItemIds,
		}),
	};
}

export function recordFreshReviewTraversalCatalogCoverage(props: {
	readonly observation: FreshReviewTraversalCoverageObservation;
	readonly observedHeaderCatalogIndexes: Set<number>;
	readonly observedHydrationCatalogIndexes: Set<number>;
}): void {
	for (const catalogIndex of props.observation.headerCatalogIndexes) {
		props.observedHeaderCatalogIndexes.add(catalogIndex);
	}
	for (const catalogIndex of props.observation.hydratedVisibleCatalogIndexes) {
		props.observedHydrationCatalogIndexes.add(catalogIndex);
	}
}

export function expectedCatalogIndexesForItemIds(props: {
	readonly expectedItemIndexById: ReadonlyMap<string, number>;
	readonly itemIds: readonly string[];
}): number[] {
	return [
		...new Set(
			props.itemIds.flatMap((itemId): readonly number[] => {
				const catalogIndex = props.expectedItemIndexById.get(itemId);
				return catalogIndex === undefined ? [] : [catalogIndex];
			}),
		),
	].toSorted((leftCatalogIndex, rightCatalogIndex): number => leftCatalogIndex - rightCatalogIndex);
}

export function appendFirstSeenItemIds(props: {
	readonly itemIds: readonly string[];
	readonly observedItemIds: string[];
	readonly observedItemIdSet: Set<string>;
}): void {
	for (const itemId of props.itemIds) {
		if (props.observedItemIdSet.has(itemId)) continue;
		props.observedItemIdSet.add(itemId);
		props.observedItemIds.push(itemId);
	}
}

export function mountedHeaderOrderViolationForExpectedOrder(props: {
	readonly expectedItemIndexById: ReadonlyMap<string, number>;
	readonly mountedItemIds: readonly string[];
}): {
	readonly expectedItemIndexes: readonly (number | null)[];
	readonly mountedItemIds: readonly string[];
} | null {
	const expectedItemIndexes = props.mountedItemIds.map(
		(itemId): number | null => props.expectedItemIndexById.get(itemId) ?? null,
	);
	const preservesExpectedOrder = expectedItemIndexes.every(
		(expectedItemIndex, mountedItemIndex): boolean => {
			if (expectedItemIndex === null) return false;
			if (mountedItemIndex === 0) return true;
			const previousExpectedItemIndex = expectedItemIndexes[mountedItemIndex - 1];
			return (
				previousExpectedItemIndex !== undefined &&
				previousExpectedItemIndex !== null &&
				previousExpectedItemIndex < expectedItemIndex
			);
		},
	);
	return preservesExpectedOrder
		? null
		: { expectedItemIndexes, mountedItemIds: [...props.mountedItemIds] };
}

export function nextFreshReviewTraversalScrollTop(props: {
	readonly codeScroll: {
		readonly clientHeight: number;
		readonly scrollHeight: number;
		readonly scrollTop: number;
	};
	readonly visibleItems: readonly {
		readonly contentState: string | null;
		readonly hostBottomOffset: number;
		readonly hostTopOffset: number;
		readonly itemId: string;
	}[];
}): number {
	const maximumCodeScrollTop = maximumScrollTop(props.codeScroll);
	const viewportAdvance = Math.max(1, props.codeScroll.clientHeight * 0.8);
	const finalVisibleHostBottomOffset = props.visibleItems.reduce(
		(maximumBottomOffset, item): number =>
			Number.isFinite(item.hostBottomOffset)
				? Math.max(maximumBottomOffset, item.hostBottomOffset)
				: maximumBottomOffset,
		0,
	);
	const hydratedHostAdvance = Math.max(
		0,
		finalVisibleHostBottomOffset - props.codeScroll.clientHeight * 0.1,
	);
	return Math.min(
		maximumCodeScrollTop,
		Math.floor(props.codeScroll.scrollTop + Math.max(viewportAdvance, hydratedHostAdvance)),
	);
}

export function detectFreshReviewTraversalCrossedGap(props: {
	readonly nextObservation: FreshReviewTraversalCoverageObservation;
	readonly observedHeaderCatalogIndexes: ReadonlySet<number>;
	readonly observedHydrationCatalogIndexes: ReadonlySet<number>;
	readonly previousObservation: FreshReviewTraversalCoverageObservation;
}): FreshReviewTraversalGap | null {
	const missingHeaderCatalogIndexes = missingCrossedCatalogIndexes({
		nextCatalogIndexes: props.nextObservation.headerCatalogIndexes,
		observedCatalogIndexes: props.observedHeaderCatalogIndexes,
		previousCatalogIndexes: props.previousObservation.headerCatalogIndexes,
	});
	const missingHydrationCatalogIndexes = missingCrossedCatalogIndexes({
		nextCatalogIndexes: props.nextObservation.hydratedVisibleCatalogIndexes,
		observedCatalogIndexes: props.observedHydrationCatalogIndexes,
		previousCatalogIndexes: props.previousObservation.hydratedVisibleCatalogIndexes,
	});
	if (missingHeaderCatalogIndexes.length === 0 && missingHydrationCatalogIndexes.length === 0) {
		return null;
	}

	const nextMaximumScrollTop = maximumScrollTop(props.nextObservation);
	const previousMaximumScrollTop = maximumScrollTop(props.previousObservation);
	if (nextMaximumScrollTop <= 0 || previousMaximumScrollTop <= 0) {
		throw freshReviewTraversalBackfillError('GEOMETRY_REBRACKET_FAILED', {
			nextMaximumScrollTop,
			previousMaximumScrollTop,
		});
	}
	const lowerScrollTop = Math.floor(
		(props.previousObservation.scrollTop / previousMaximumScrollTop) * nextMaximumScrollTop,
	);
	const upperScrollTop = Math.floor(props.nextObservation.scrollTop);
	if (lowerScrollTop >= upperScrollTop) {
		throw freshReviewTraversalBackfillError('GEOMETRY_REBRACKET_FAILED', {
			lowerScrollTop,
			upperScrollTop,
		});
	}

	return {
		clientHeight: props.nextObservation.clientHeight,
		lowerScrollTop,
		missingHeaderCatalogIndexes,
		missingHydrationCatalogIndexes,
		scrollHeight: props.nextObservation.scrollHeight,
		upperScrollTop,
	};
}

export function revalidateFreshReviewTraversalGapGeometry(props: {
	readonly codeScroll: {
		readonly clientHeight: number;
		readonly scrollHeight: number;
		readonly scrollTop: number;
	};
	readonly gap: FreshReviewTraversalGap;
}): FreshReviewTraversalGap {
	if (
		props.gap.clientHeight === props.codeScroll.clientHeight &&
		props.gap.scrollHeight === props.codeScroll.scrollHeight
	) {
		return props.gap;
	}
	const previousMaximumScrollTop = maximumScrollTop(props.gap);
	const nextMaximumScrollTop = maximumScrollTop(props.codeScroll);
	if (previousMaximumScrollTop <= 0 || nextMaximumScrollTop <= 0) {
		throw freshReviewTraversalBackfillError('GEOMETRY_REBRACKET_FAILED', {
			nextMaximumScrollTop,
			previousMaximumScrollTop,
		});
	}
	const lowerScrollTop = Math.max(
		0,
		Math.floor((props.gap.lowerScrollTop / previousMaximumScrollTop) * nextMaximumScrollTop),
	);
	const upperScrollTop = Math.min(
		nextMaximumScrollTop,
		Math.ceil((props.gap.upperScrollTop / previousMaximumScrollTop) * nextMaximumScrollTop),
	);
	if (lowerScrollTop >= upperScrollTop) {
		throw freshReviewTraversalBackfillError('GEOMETRY_REBRACKET_FAILED', {
			lowerScrollTop,
			nextMaximumScrollTop,
			upperScrollTop,
		});
	}
	return {
		...props.gap,
		clientHeight: props.codeScroll.clientHeight,
		lowerScrollTop,
		scrollHeight: props.codeScroll.scrollHeight,
		upperScrollTop,
	};
}

export function unresolvedFreshReviewTraversalGap(props: {
	readonly gap: FreshReviewTraversalGap;
	readonly observedHeaderCatalogIndexes: ReadonlySet<number>;
	readonly observedHydrationCatalogIndexes: ReadonlySet<number>;
}): FreshReviewTraversalGap | null {
	const missingHeaderCatalogIndexes = props.gap.missingHeaderCatalogIndexes.filter(
		(catalogIndex): boolean => !props.observedHeaderCatalogIndexes.has(catalogIndex),
	);
	const missingHydrationCatalogIndexes = props.gap.missingHydrationCatalogIndexes.filter(
		(catalogIndex): boolean => !props.observedHydrationCatalogIndexes.has(catalogIndex),
	);
	return missingHeaderCatalogIndexes.length === 0 && missingHydrationCatalogIndexes.length === 0
		? null
		: {
				...props.gap,
				missingHeaderCatalogIndexes,
				missingHydrationCatalogIndexes,
			};
}

export function nextFreshReviewTraversalBackfillScrollTop(gap: FreshReviewTraversalGap): number {
	const nextScrollTop = Math.floor((gap.lowerScrollTop + gap.upperScrollTop) / 2);
	if (nextScrollTop <= gap.lowerScrollTop || nextScrollTop >= gap.upperScrollTop) {
		throw freshReviewTraversalBackfillError('PIXEL_RESOLUTION_STALLED', {
			lowerScrollTop: gap.lowerScrollTop,
			upperScrollTop: gap.upperScrollTop,
		});
	}
	return nextScrollTop;
}

export function subdivideFreshReviewTraversalGap(props: {
	readonly gap: FreshReviewTraversalGap;
	readonly observedHeaderCatalogIndexes: ReadonlySet<number>;
	readonly observedHydrationCatalogIndexes: ReadonlySet<number>;
	readonly splitObservation: FreshReviewTraversalCoverageObservation;
}): FreshReviewTraversalGap[] {
	if (
		props.gap.clientHeight !== props.splitObservation.clientHeight ||
		props.gap.scrollHeight !== props.splitObservation.scrollHeight
	) {
		throw freshReviewTraversalBackfillError('STALE_GEOMETRY_SUBDIVISION', {
			gapClientHeight: props.gap.clientHeight,
			gapScrollHeight: props.gap.scrollHeight,
			observationClientHeight: props.splitObservation.clientHeight,
			observationScrollHeight: props.splitObservation.scrollHeight,
		});
	}
	if (
		props.splitObservation.scrollTop <= props.gap.lowerScrollTop ||
		props.splitObservation.scrollTop >= props.gap.upperScrollTop
	) {
		throw freshReviewTraversalBackfillError('PIXEL_RESOLUTION_STALLED', {
			actualScrollTop: props.splitObservation.scrollTop,
			lowerScrollTop: props.gap.lowerScrollTop,
			upperScrollTop: props.gap.upperScrollTop,
		});
	}
	const unresolvedGap = unresolvedFreshReviewTraversalGap({
		gap: props.gap,
		observedHeaderCatalogIndexes: props.observedHeaderCatalogIndexes,
		observedHydrationCatalogIndexes: props.observedHydrationCatalogIndexes,
	});
	if (unresolvedGap === null) return [];

	const headerSubdivision = splitMissingCatalogIndexes({
		anchorCatalogIndexes: props.splitObservation.headerCatalogIndexes,
		coverageKind: 'header',
		missingCatalogIndexes: unresolvedGap.missingHeaderCatalogIndexes,
	});
	const hydrationSubdivision = splitMissingCatalogIndexes({
		anchorCatalogIndexes: props.splitObservation.hydratedVisibleCatalogIndexes,
		coverageKind: 'hydration',
		missingCatalogIndexes: unresolvedGap.missingHydrationCatalogIndexes,
	});
	const subdivisions: FreshReviewTraversalGap[] = [];
	if (headerSubdivision.left.length > 0 || hydrationSubdivision.left.length > 0) {
		subdivisions.push({
			...unresolvedGap,
			missingHeaderCatalogIndexes: headerSubdivision.left,
			missingHydrationCatalogIndexes: hydrationSubdivision.left,
			upperScrollTop: props.splitObservation.scrollTop,
		});
	}
	if (headerSubdivision.right.length > 0 || hydrationSubdivision.right.length > 0) {
		subdivisions.push({
			...unresolvedGap,
			lowerScrollTop: props.splitObservation.scrollTop,
			missingHeaderCatalogIndexes: headerSubdivision.right,
			missingHydrationCatalogIndexes: hydrationSubdivision.right,
		});
	}
	return subdivisions;
}

export async function backfillFreshReviewTraversalGaps(props: {
	readonly backfillStepBudget: number;
	readonly observedHeaderCatalogIndexes: Set<number>;
	readonly observedHydrationCatalogIndexes: Set<number>;
	readonly pendingGaps: readonly FreshReviewTraversalGap[];
	readonly readCodeScroll: () => Promise<{
		readonly clientHeight: number;
		readonly scrollHeight: number;
		readonly scrollTop: number;
	}>;
	readonly settleAtScrollTop: (
		nextScrollTop: number,
	) => Promise<FreshReviewTraversalCoverageObservation>;
}): Promise<FreshReviewTraversalBackfillResult> {
	const pendingGaps = [...props.pendingGaps];
	let backfillStepsUsed = 0;
	while (pendingGaps.length > 0) {
		const candidateGap = pendingGaps.shift();
		if (candidateGap === undefined) break;
		const unresolvedGap = unresolvedFreshReviewTraversalGap({
			gap: candidateGap,
			observedHeaderCatalogIndexes: props.observedHeaderCatalogIndexes,
			observedHydrationCatalogIndexes: props.observedHydrationCatalogIndexes,
		});
		if (unresolvedGap === null) continue;
		if (backfillStepsUsed >= props.backfillStepBudget) {
			pendingGaps.unshift(unresolvedGap);
			break;
		}

		// oxlint-disable-next-line no-await-in-loop -- Each bracket must use geometry settled by the prior midpoint.
		const currentCodeScroll = await props.readCodeScroll();
		const currentGeometryGap = revalidateFreshReviewTraversalGapGeometry({
			codeScroll: currentCodeScroll,
			gap: unresolvedGap,
		});
		// oxlint-disable-next-line no-await-in-loop -- Midpoint coverage determines the next serial subdivisions.
		const observation = await props.settleAtScrollTop(
			nextFreshReviewTraversalBackfillScrollTop(currentGeometryGap),
		);
		recordFreshReviewTraversalCatalogCoverage({
			observation,
			observedHeaderCatalogIndexes: props.observedHeaderCatalogIndexes,
			observedHydrationCatalogIndexes: props.observedHydrationCatalogIndexes,
		});
		const settledGeometryGap = revalidateFreshReviewTraversalGapGeometry({
			codeScroll: observation,
			gap: currentGeometryGap,
		});
		pendingGaps.push(
			...subdivideFreshReviewTraversalGap({
				gap: settledGeometryGap,
				observedHeaderCatalogIndexes: props.observedHeaderCatalogIndexes,
				observedHydrationCatalogIndexes: props.observedHydrationCatalogIndexes,
				splitObservation: observation,
			}),
		);
		backfillStepsUsed += 1;
	}
	return { backfillStepsUsed, pendingGaps };
}

export async function settleFreshReviewTraversalAtBottom(props: {
	readonly observedHeaderCatalogIndexes: Set<number>;
	readonly observedHydrationCatalogIndexes: Set<number>;
	readonly requiredSettledBottomTurnCount: number;
	readonly settleAtScrollTop: (
		nextScrollTop: number,
	) => Promise<FreshReviewTraversalCoverageObservation>;
	readonly settleStepBudget: number;
	readonly readCodeScroll: () => Promise<{
		readonly clientHeight: number;
		readonly scrollHeight: number;
		readonly scrollTop: number;
	}>;
}): Promise<number> {
	let settledBottomTurnCount = 0;
	for (let stepIndex = 0; stepIndex < props.settleStepBudget; stepIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Hydration can change document height after every bottom settle.
		const currentCodeScroll = await props.readCodeScroll();
		// oxlint-disable-next-line no-await-in-loop -- Each bottom turn must settle before the next geometry read.
		const observation = await props.settleAtScrollTop(maximumScrollTop(currentCodeScroll));
		recordFreshReviewTraversalCatalogCoverage({
			observation,
			observedHeaderCatalogIndexes: props.observedHeaderCatalogIndexes,
			observedHydrationCatalogIndexes: props.observedHydrationCatalogIndexes,
		});
		settledBottomTurnCount =
			observation.scrollTop >= maximumScrollTop(observation) - 1 ? settledBottomTurnCount + 1 : 0;
		if (settledBottomTurnCount >= props.requiredSettledBottomTurnCount) break;
	}
	return settledBottomTurnCount;
}

export function missingExpectedCatalogIndexes(props: {
	readonly excludedCatalogIndexes?: ReadonlySet<number>;
	readonly expectedItemCount: number;
	readonly observedCatalogIndexes: ReadonlySet<number>;
}): number[] {
	return Array.from(
		{ length: props.expectedItemCount },
		(_, catalogIndex): number => catalogIndex,
	).filter(
		(catalogIndex): boolean =>
			!(props.excludedCatalogIndexes?.has(catalogIndex) ?? false) &&
			!props.observedCatalogIndexes.has(catalogIndex),
	);
}

export function requireFreshReviewTraversalComplete(props: {
	readonly backfillStepBudget: number;
	readonly backfillStepsUsed: number;
	readonly missingHeaderCatalogIndexes: readonly number[];
	readonly missingHydrationCatalogIndexes: readonly number[];
	readonly pendingGapCount: number;
	readonly requiredSettledBottomTurnCount: number;
	readonly settledBottomTurnCount: number;
}): void {
	if (props.settledBottomTurnCount < props.requiredSettledBottomTurnCount) {
		throw freshReviewTraversalBackfillError('BOTTOM_NOT_SETTLED', props);
	}
	if (
		props.pendingGapCount === 0 &&
		props.missingHeaderCatalogIndexes.length === 0 &&
		props.missingHydrationCatalogIndexes.length === 0
	) {
		return;
	}
	const failureCode =
		props.backfillStepsUsed >= props.backfillStepBudget
			? 'BUDGET_EXHAUSTED'
			: 'COVERAGE_INCOMPLETE';
	throw freshReviewTraversalBackfillError(failureCode, props);
}

function missingCrossedCatalogIndexes(props: {
	readonly nextCatalogIndexes: readonly number[];
	readonly observedCatalogIndexes: ReadonlySet<number>;
	readonly previousCatalogIndexes: readonly number[];
}): number[] {
	const previousMaximumCatalogIndex = maximumCatalogIndex(props.previousCatalogIndexes);
	const nextMinimumCatalogIndex = minimumCatalogIndex(props.nextCatalogIndexes);
	if (
		previousMaximumCatalogIndex === null ||
		nextMinimumCatalogIndex === null ||
		previousMaximumCatalogIndex >= nextMinimumCatalogIndex - 1
	) {
		return [];
	}
	return Array.from(
		{ length: nextMinimumCatalogIndex - previousMaximumCatalogIndex - 1 },
		(_, offset): number => previousMaximumCatalogIndex + offset + 1,
	).filter((catalogIndex): boolean => !props.observedCatalogIndexes.has(catalogIndex));
}

function splitMissingCatalogIndexes(props: {
	readonly anchorCatalogIndexes: readonly number[];
	readonly coverageKind: 'header' | 'hydration';
	readonly missingCatalogIndexes: readonly number[];
}): { readonly left: number[]; readonly right: number[] } {
	if (props.missingCatalogIndexes.length === 0) return { left: [], right: [] };
	const minimumAnchorCatalogIndex = minimumCatalogIndex(props.anchorCatalogIndexes);
	const maximumAnchorCatalogIndex = maximumCatalogIndex(props.anchorCatalogIndexes);
	if (minimumAnchorCatalogIndex === null || maximumAnchorCatalogIndex === null) {
		throw freshReviewTraversalBackfillError('CATALOG_ANCHOR_MISSING', {
			coverageKind: props.coverageKind,
			missingCatalogIndexes: props.missingCatalogIndexes,
		});
	}
	const unresolvedInteriorCatalogIndexes = props.missingCatalogIndexes.filter(
		(catalogIndex): boolean =>
			catalogIndex >= minimumAnchorCatalogIndex && catalogIndex <= maximumAnchorCatalogIndex,
	);
	if (unresolvedInteriorCatalogIndexes.length > 0) {
		throw freshReviewTraversalBackfillError('CATALOG_COVERAGE_STALLED', {
			coverageKind: props.coverageKind,
			maximumAnchorCatalogIndex,
			minimumAnchorCatalogIndex,
			unresolvedInteriorCatalogIndexes,
		});
	}
	return {
		left: props.missingCatalogIndexes.filter(
			(catalogIndex): boolean => catalogIndex < minimumAnchorCatalogIndex,
		),
		right: props.missingCatalogIndexes.filter(
			(catalogIndex): boolean => catalogIndex > maximumAnchorCatalogIndex,
		),
	};
}

function minimumCatalogIndex(catalogIndexes: readonly number[]): number | null {
	return catalogIndexes.length === 0 ? null : Math.min(...catalogIndexes);
}

function maximumCatalogIndex(catalogIndexes: readonly number[]): number | null {
	return catalogIndexes.length === 0 ? null : Math.max(...catalogIndexes);
}

function maximumScrollTop(codeScroll: {
	readonly clientHeight: number;
	readonly scrollHeight: number;
}): number {
	return Math.max(0, codeScroll.scrollHeight - codeScroll.clientHeight);
}

function freshReviewTraversalBackfillError(failureCode: string, details: unknown): Error {
	return new Error(`REVIEW_FRESH_ROUTE_BACKFILL_${failureCode} ${JSON.stringify(details)}`);
}
