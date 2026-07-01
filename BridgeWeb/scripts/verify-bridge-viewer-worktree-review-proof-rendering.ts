export interface ReviewRenderedSelectionSnapshot {
	readonly codeViewOverflow: string | null;
	readonly selectedHeaderPresent: boolean;
	readonly selectedItemId: string | null;
	readonly selectedMaterializedFileLineCount: number;
	readonly selectedMaterializedItemType: string | null;
	readonly visibleText: string;
}

export interface ReviewCollapseControlProof {
	readonly ariaExpanded: string | null;
	readonly fontSize: string | null;
	readonly height: number;
	readonly itemId: string | null;
	readonly primitiveSlot: string | null;
	readonly present: boolean;
}

export interface ReviewCollapseControlCandidate {
	readonly proof: ReviewCollapseControlProof;
	readonly visible: boolean;
}

export interface ReviewRouteCollapseControlArtifact {
	readonly reviewCollapseControlProof?: ReviewCollapseControlProof;
}

export interface ReviewStartupTelemetrySampleProof {
	readonly durationMilliseconds: number | null;
	readonly name: string;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly phase: string | null;
	readonly result: string | null;
	readonly slice: string | null;
	readonly transport: string | null;
}

export interface ReviewRenderedSelectionExpectation {
	readonly expectedCodeViewOverflow: 'wrap';
	readonly expectedItemId: string;
	readonly expectedMaterializedItemType: 'diff' | 'file';
	readonly expectedVisibleText: string;
}

export function emptyReviewCollapseControlProof(): ReviewCollapseControlProof {
	return {
		ariaExpanded: null,
		fontSize: null,
		height: 0,
		itemId: null,
		present: false,
		primitiveSlot: null,
	};
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

export function reviewCollapseControlSatisfied(props: {
	readonly expectedItemId: string;
	readonly proof: ReviewCollapseControlProof;
}): boolean {
	return (
		props.proof.present &&
		props.proof.itemId === props.expectedItemId &&
		props.proof.primitiveSlot === 'button' &&
		Math.abs(props.proof.height - 24) <= 1 &&
		(props.proof.ariaExpanded === 'true' || props.proof.ariaExpanded === 'false')
	);
}

export function selectVisibleReviewCollapseControlProof(props: {
	readonly candidates: readonly ReviewCollapseControlCandidate[];
	readonly expectedItemId: string;
}): ReviewCollapseControlProof {
	return (
		props.candidates.find(
			(candidate: ReviewCollapseControlCandidate): boolean =>
				candidate.visible && candidate.proof.itemId === props.expectedItemId,
		)?.proof ?? emptyReviewCollapseControlProof()
	);
}

export function reviewRouteCollapseControlArtifactSatisfied(props: {
	readonly expectedItemId: string;
	readonly routeProof: ReviewRouteCollapseControlArtifact;
}): boolean {
	return (
		props.routeProof.reviewCollapseControlProof !== undefined &&
		reviewCollapseControlSatisfied({
			expectedItemId: props.expectedItemId,
			proof: props.routeProof.reviewCollapseControlProof,
		})
	);
}

export function reviewStartupTelemetrySatisfied(
	samples: readonly ReviewStartupTelemetrySampleProof[],
): boolean {
	const samplesByName = new Map(samples.map((sample) => [sample.name, sample]));
	return expectedReviewStartupTelemetrySampleNames.every((name): boolean => {
		const sample = samplesByName.get(name);
		return sample !== undefined && sample.result === 'success';
	});
}

const expectedReviewStartupTelemetrySampleNames = [
	'performance.bridge.web.review_metadata_apply',
	'performance.bridge.web.projection_total',
	'performance.bridge.web.selected_content_ready',
	'performance.bridge.web.review_ready',
];
