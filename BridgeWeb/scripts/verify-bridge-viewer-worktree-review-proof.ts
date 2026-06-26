export interface ReviewContentRouteDeltaProof {
	readonly afterHitCount: number;
	readonly beforeHitCount: number;
	readonly contentRouteSatisfiedBy:
		| 'matching-pre-click-route-with-rendered-selection'
		| 'matching-post-click-route';
	readonly expectedItemId: string;
	readonly matchingPreClickHitUrls: readonly string[];
	readonly matchingPostClickHitUrls: readonly string[];
	readonly preClickHitCount: number;
	readonly preClickHitUrls: readonly string[];
	readonly postClickHitCount: number;
	readonly postClickHitUrls: readonly string[];
}

export interface BuildReviewContentRouteDeltaProofProps {
	readonly allHitUrls: readonly string[];
	readonly beforeHitCount: number;
	readonly expectedItemId: string;
}

export function buildReviewContentRouteDeltaProof(
	props: BuildReviewContentRouteDeltaProofProps,
): ReviewContentRouteDeltaProof {
	const preClickHitUrls = props.allHitUrls.slice(0, props.beforeHitCount);
	const postClickHitUrls = props.allHitUrls.slice(props.beforeHitCount);
	const matchingPreClickHitUrls = preClickHitUrls.filter((url: string): boolean =>
		url.includes(props.expectedItemId),
	);
	const matchingPostClickHitUrls = postClickHitUrls.filter((url: string): boolean =>
		url.includes(props.expectedItemId),
	);

	return {
		afterHitCount: props.allHitUrls.length,
		beforeHitCount: props.beforeHitCount,
		contentRouteSatisfiedBy:
			matchingPostClickHitUrls.length > 0
				? 'matching-post-click-route'
				: 'matching-pre-click-route-with-rendered-selection',
		expectedItemId: props.expectedItemId,
		matchingPreClickHitUrls,
		matchingPostClickHitUrls,
		preClickHitCount: preClickHitUrls.length,
		preClickHitUrls,
		postClickHitCount: postClickHitUrls.length,
		postClickHitUrls,
	};
}

export function reviewContentRouteDeltaSatisfied(proof: ReviewContentRouteDeltaProof): boolean {
	return proof.matchingPostClickHitUrls.length > 0 || proof.matchingPreClickHitUrls.length > 0;
}

export function normalizeReviewTreeSearchQuery(path: string): string {
	return path.toLowerCase();
}

export interface ReviewRenderedSelectionSnapshot {
	readonly codeViewOverflow: string | null;
	readonly selectedHeaderPresent: boolean;
	readonly selectedItemId: string | null;
	readonly selectedMaterializedFileLineCount: number;
	readonly selectedMaterializedItemType: string | null;
	readonly visibleText: string;
}

export interface ReviewRenderedSelectionExpectation {
	readonly expectedCodeViewOverflow: 'wrap';
	readonly expectedItemId: string;
	readonly expectedMaterializedItemType: 'diff' | 'file';
	readonly expectedVisibleText: string;
}

export function reviewRenderedSelectionSatisfied(props: {
	readonly expectation: ReviewRenderedSelectionExpectation;
	readonly snapshot: ReviewRenderedSelectionSnapshot;
}): boolean {
	return (
		props.snapshot.codeViewOverflow === props.expectation.expectedCodeViewOverflow &&
		props.snapshot.selectedItemId === props.expectation.expectedItemId &&
		props.snapshot.selectedHeaderPresent &&
		props.snapshot.selectedMaterializedItemType ===
			props.expectation.expectedMaterializedItemType &&
		props.snapshot.visibleText.includes(props.expectation.expectedVisibleText)
	);
}
