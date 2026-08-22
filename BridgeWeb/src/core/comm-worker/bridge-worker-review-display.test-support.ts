import type {
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

export type BridgeWorkerReviewSourceContext = Pick<
	BridgeWorkerReviewSourceDisplayPayload,
	'baseEndpoint' | 'comparisonOrigin' | 'headEndpoint' | 'query' | 'reviewedSubjectLabel'
>;

export function bridgeWorkerReviewSourceContext(
	packageId: string,
): BridgeWorkerReviewSourceContext {
	const repoId = `${packageId}-repo`;
	const worktreeId = `${packageId}-worktree`;
	const baseEndpoint = {
		createdAtUnixMilliseconds: 1,
		endpointId: `${packageId}-base`,
		kind: 'gitRef' as const,
		label: 'Comparison Base',
		providerIdentity: `${packageId}-base-provider`,
		repoId,
		worktreeId,
	};
	const headEndpoint = {
		createdAtUnixMilliseconds: 2,
		endpointId: `${packageId}-head`,
		kind: 'workingTree' as const,
		label: 'Working Tree',
		providerIdentity: `${packageId}-head-provider`,
		repoId,
		worktreeId,
	};
	return {
		baseEndpoint,
		comparisonOrigin: null,
		headEndpoint,
		query: {
			baseEndpointId: baseEndpoint.endpointId,
			comparisonSemantics: 'threeDot',
			fileTarget: null,
			grouping: { kind: 'folder' },
			headEndpointId: headEndpoint.endpointId,
			pathScope: [],
			provenanceFilter: {
				agentSessionIds: [],
				operationIds: [],
				paneIds: [],
				promptIds: [],
				sourceKinds: [],
			},
			queryId: `${packageId}-query`,
			queryKind: 'compare',
			repoId,
			viewFilter: {
				changeKinds: [],
				excludedExtensions: [],
				excludedFileClasses: [],
				excludedPathGlobs: [],
				includedExtensions: [],
				includedFileClasses: [],
				includedPathGlobs: [],
				reviewStates: [],
				showBinaryFiles: false,
				showHiddenFiles: false,
				showLargeFiles: false,
			},
			worktreeId,
		},
		reviewedSubjectLabel: null,
	};
}

export function bridgeWorkerReviewPublicationIdentity(
	packageId: string,
	revision = 1,
	sourceIdentity = `${packageId}-source`,
): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId,
		publicationId: `00000000-0000-7000-8000-${revision.toString().padStart(12, '0')}`,
		reviewGeneration: 1,
		revision,
		sourceIdentity,
	};
}
