import type {
	BridgeChangeGrouping,
	BridgeViewFilter,
} from '../review-package/bridge-review-package.js';

export type BridgeReviewQueryKind =
	| 'compare'
	| 'openFile'
	| 'browseTree'
	| 'filterPackage'
	| 'groupPackage';

export type BridgeComparisonSemantics =
	| 'twoDot'
	| 'threeDot'
	| 'checkpointDelta'
	| 'indexDelta'
	| 'workingTreeDelta'
	| 'notApplicable';

export interface BridgeProvenanceFilter {
	readonly paneIds: readonly string[];
	readonly agentSessionIds: readonly string[];
	readonly promptIds: readonly string[];
	readonly operationIds: readonly string[];
	readonly createdAfterUnixMilliseconds: number | null;
	readonly createdBeforeUnixMilliseconds: number | null;
	readonly sourceKinds: readonly string[];
}

export interface BridgeReviewQuery {
	readonly queryId: string;
	readonly queryKind: BridgeReviewQueryKind;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly baseEndpointId: string | null;
	readonly headEndpointId: string | null;
	readonly comparisonSemantics: BridgeComparisonSemantics;
	readonly pathScope: readonly string[];
	readonly fileTarget: string | null;
	readonly viewFilter: BridgeViewFilter;
	readonly grouping: BridgeChangeGrouping;
	readonly provenanceFilter: BridgeProvenanceFilter;
}

export function isEndpointComparisonQuery(query: BridgeReviewQuery): boolean {
	return (
		query.queryKind === 'compare' && query.baseEndpointId !== null && query.headEndpointId !== null
	);
}
