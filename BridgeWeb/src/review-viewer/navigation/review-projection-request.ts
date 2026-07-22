import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionFacet,
	BridgeReviewProjectionRequest,
} from '../models/review-projection-models.js';

export interface MakeBridgeReviewProjectionRequestProps {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets?: readonly BridgeReviewProjectionFacet[];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
}

export function makeBridgeReviewProjectionRequest(
	props: MakeBridgeReviewProjectionRequestProps,
): BridgeReviewProjectionRequest {
	const facets: BridgeReviewProjectionFacet[] = [...(props.facets ?? [])];
	if (props.gitStatusFilter !== 'all') {
		facets.push({ kind: 'gitStatus', statuses: [props.gitStatusFilter] });
	}
	if (props.fileClassFilter !== 'all') {
		facets.push({ kind: 'fileClass', fileClasses: [props.fileClassFilter] });
	}
	return {
		mode: props.projectionMode,
		facets,
	};
}
