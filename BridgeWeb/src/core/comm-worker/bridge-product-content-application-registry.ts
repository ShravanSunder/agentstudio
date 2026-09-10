import {
	bridgeProductContentIdentityFromDescriptor,
	bridgeProductMaximumBytesForIdentity,
	type BridgeProductAnnotationOutputContentIdentity,
	type BridgeProductAnnotationProjectionContentIdentity,
	type BridgeProductContentIdentity,
	type BridgeProductContentKind,
	type BridgeProductContentRequest,
	type BridgeProductFileContentIdentity,
	type BridgeProductReviewComparisonTargetsContentIdentity,
	type BridgeProductReviewContentIdentity,
} from './bridge-product-content-contracts.js';

export interface BridgeProductContentExactFacts {
	readonly declaredByteLength: number | null;
	readonly expectedSha256: string | null;
}

export function bridgeProductContentExactFactsForRequest(
	request: BridgeProductContentRequest,
): BridgeProductContentExactFacts {
	switch (request.contentKind) {
		case 'annotation.output':
		case 'file.content':
		case 'review.content':
			return {
				declaredByteLength: request.descriptor.declaredByteLength,
				expectedSha256: request.descriptor.expectedSha256,
			};
		case 'annotation.projection':
		case 'review.comparisonTargets':
			return { declaredByteLength: null, expectedSha256: null };
	}
	return assertNeverBridgeProductContentRequest(request);
}

export function bridgeProductContentAcceptedIdentityMatchesRequest(props: {
	readonly identity: BridgeProductContentIdentity<BridgeProductContentKind>;
	readonly request: BridgeProductContentRequest;
}): boolean {
	return bridgeProductContentIdentitiesEqual(
		props.identity,
		bridgeProductContentIdentityFromDescriptor(props.request.descriptor),
	);
}

export function bridgeProductContentAcceptedMaximumMatchesIdentity(props: {
	readonly identity: BridgeProductContentIdentity<BridgeProductContentKind>;
	readonly maximumBytes: number;
}): boolean {
	return props.maximumBytes === bridgeProductMaximumBytesForIdentity(props.identity);
}

export function validateBridgeProductContentEndOfSource(props: {
	readonly endOfSource: boolean;
	readonly identity: BridgeProductContentIdentity<BridgeProductContentKind>;
}): void {
	if (props.identity.contentKind === 'file.content' && !props.endOfSource) {
		throw new Error('Bridge product File content terminal must reach the end of source.');
	}
}

function bridgeProductContentIdentitiesEqual(
	left:
		| BridgeProductAnnotationOutputContentIdentity
		| BridgeProductAnnotationProjectionContentIdentity
		| BridgeProductFileContentIdentity
		| BridgeProductReviewContentIdentity
		| BridgeProductReviewComparisonTargetsContentIdentity,
	right:
		| BridgeProductAnnotationOutputContentIdentity
		| BridgeProductAnnotationProjectionContentIdentity
		| BridgeProductFileContentIdentity
		| BridgeProductReviewContentIdentity
		| BridgeProductReviewComparisonTargetsContentIdentity,
): boolean {
	if (left.contentKind !== right.contentKind) return false;
	switch (left.contentKind) {
		case 'annotation.output':
			if (right.contentKind !== 'annotation.output') return false;
			return (
				left.attemptId === right.attemptId &&
				left.descriptorId === right.descriptorId &&
				left.formatVersion === right.formatVersion &&
				left.maximumBytes === right.maximumBytes &&
				left.outputKind === right.outputKind &&
				left.surface === right.surface
			);
		case 'annotation.projection':
			if (right.contentKind !== 'annotation.projection') return false;
			return (
				left.descriptorId === right.descriptorId &&
				left.maximumBytes === right.maximumBytes &&
				left.page.aggregateSha256 === right.page.aggregateSha256 &&
				left.page.expectedMessageCount === right.page.expectedMessageCount &&
				left.page.expectedSessionCount === right.page.expectedSessionCount &&
				left.page.expectedThreadCount === right.page.expectedThreadCount &&
				left.page.isLastPage === right.page.isLastPage &&
				left.page.nextCursor === right.page.nextCursor &&
				left.page.pageOrdinal === right.page.pageOrdinal &&
				left.page.projectionRevision === right.page.projectionRevision &&
				left.page.snapshotId === right.page.snapshotId &&
				left.page.sourceGeneration === right.page.sourceGeneration &&
				left.surface === right.surface
			);
		case 'file.content':
			if (right.contentKind !== 'file.content') return false;
			return (
				left.descriptorId === right.descriptorId &&
				left.fileId === right.fileId &&
				left.source.repoId === right.source.repoId &&
				left.source.rootRevisionToken === right.source.rootRevisionToken &&
				left.source.sourceCursor === right.source.sourceCursor &&
				left.source.sourceId === right.source.sourceId &&
				left.source.subscriptionGeneration === right.source.subscriptionGeneration &&
				left.source.worktreeId === right.source.worktreeId &&
				left.window.kind === right.window.kind &&
				left.window.maximumBytes === right.window.maximumBytes &&
				left.window.maximumLines === right.window.maximumLines &&
				left.window.startByte === right.window.startByte
			);
		case 'review.content':
			if (right.contentKind !== 'review.content') return false;
			return (
				left.contentDigest.authority === right.contentDigest.authority &&
				left.contentDigest.algorithm === right.contentDigest.algorithm &&
				left.contentDigest.value === right.contentDigest.value &&
				left.descriptorId === right.descriptorId &&
				left.endpointId === right.endpointId &&
				left.handleId === right.handleId &&
				left.itemId === right.itemId &&
				left.packageId === right.packageId &&
				left.reviewGeneration === right.reviewGeneration &&
				left.role === right.role &&
				left.sourceIdentity === right.sourceIdentity &&
				left.wholeByteLength === right.wholeByteLength &&
				left.window.kind === right.window.kind &&
				left.window.maximumBytes === right.window.maximumBytes &&
				left.window.startByte === right.window.startByte
			);
		case 'review.comparisonTargets':
			if (right.contentKind !== 'review.comparisonTargets') return false;
			return left.descriptorId === right.descriptorId && left.maximumBytes === right.maximumBytes;
	}
}

function assertNeverBridgeProductContentRequest(request: never): never {
	throw new Error(`Unsupported Bridge product content request: ${String(request)}`);
}
