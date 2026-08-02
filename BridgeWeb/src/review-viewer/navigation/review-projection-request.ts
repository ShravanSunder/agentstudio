import type { BridgeFileChangeKind } from '../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeReviewFilterCategory,
	BridgeReviewProjectionMode,
	BridgeReviewProjectionFacet,
	BridgeReviewProjectionRequest,
} from '../models/review-projection-models.js';

export interface MakeBridgeReviewProjectionRequestProps {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets?: readonly BridgeReviewProjectionFacet[];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly categoryFilter: BridgeReviewFilterCategory | 'all';
	readonly showBinary: boolean;
	readonly showLarge: boolean;
}

export function makeBridgeReviewProjectionRequest(
	props: MakeBridgeReviewProjectionRequestProps,
): BridgeReviewProjectionRequest {
	const facets: BridgeReviewProjectionFacet[] = [...(props.facets ?? [])];
	if (props.gitStatusFilter !== 'all') {
		facets.push({ kind: 'gitStatus', statuses: [props.gitStatusFilter] });
	}
	if (props.categoryFilter !== 'all') {
		facets.push({ kind: 'fileClass', fileClasses: [props.categoryFilter] });
	}
	facets.push({
		kind: 'visibility',
		includeBinary: props.showBinary,
		includeHidden: false,
		includeLarge: props.showLarge,
	});
	return {
		mode: props.projectionMode,
		facets,
	};
}
