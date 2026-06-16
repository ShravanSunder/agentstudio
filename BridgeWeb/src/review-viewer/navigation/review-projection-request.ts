import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionRefinement,
	BridgeReviewProjectionRequest,
} from '../models/review-projection-models.js';

export interface MakeBridgeReviewProjectionRequestProps {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
}

export function makeBridgeReviewProjectionRequest(
	props: MakeBridgeReviewProjectionRequestProps,
): BridgeReviewProjectionRequest {
	const refinements: BridgeReviewProjectionRefinement[] = [];
	if (props.gitStatusFilter !== 'all') {
		refinements.push({ kind: 'gitStatus', statuses: [props.gitStatusFilter] });
	}
	if (props.fileClassFilter !== 'all') {
		refinements.push({ kind: 'fileClass', fileClasses: [props.fileClassFilter] });
	}
	return {
		base: props.projectionMode,
		refinements,
	};
}
