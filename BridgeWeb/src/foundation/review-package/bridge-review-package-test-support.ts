import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from './bridge-review-package.js';

export interface MakeBridgeReviewItemProps {
	readonly itemId: string;
	readonly path: string;
}

export function makeBridgeContentHandle(
	itemId: string,
	role: 'base' | 'head',
): BridgeContentHandle {
	const handleId = `handle-${itemId}-${role}`;
	return {
		handleId,
		itemId,
		role,
		endpointId: role === 'base' ? 'endpoint-base' : 'endpoint-head',
		reviewGeneration: 1,
		resourceUrl: `agentstudio://resource/content/${handleId}?generation=1`,
		contentHash: `sha256:${itemId}:${role}`,
		contentHashAlgorithm: 'sha256',
		cacheKey: `${itemId}:${role}`,
		mimeType: 'text/x-swift',
		language: 'swift',
		sizeBytes: 10,
		isBinary: false,
	};
}

export function makeBridgeReviewItem(props: MakeBridgeReviewItemProps): BridgeReviewItemDescriptor {
	const base = makeBridgeContentHandle(props.itemId, 'base');
	const head = makeBridgeContentHandle(props.itemId, 'head');
	return {
		itemId: props.itemId,
		itemKind: 'diff',
		itemVersion: 1,
		basePath: props.path,
		headPath: props.path,
		changeKind: 'modified',
		fileClass: 'source',
		language: 'swift',
		extension: 'swift',
		sizeBytes: 10,
		baseContentHash: base.contentHash,
		headContentHash: head.contentHash,
		contentHashAlgorithm: 'sha256',
		additions: 1,
		deletions: 1,
		isHiddenByDefault: false,
		hiddenReason: null,
		reviewPriority: 'normal',
		contentRoles: { base, head, diff: null, file: null },
		cacheKey: `${base.cacheKey}|${head.cacheKey}`,
		provenance: {
			paneIds: [],
			agentSessionIds: [],
			promptIds: [],
			operationIds: [],
			sourceKinds: [],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: 'unreviewed',
		collapsed: false,
	};
}

export function makeBridgeReviewPackage(): BridgeReviewPackage {
	const item = makeBridgeReviewItem({ itemId: 'item-source', path: 'Sources/App/View.swift' });
	return {
		packageId: 'package-1',
		schemaVersion: 1,
		reviewGeneration: 1,
		revision: 1,
		query: {
			queryId: 'query-1',
			queryKind: 'compare',
			repoId: 'repo',
			worktreeId: 'worktree',
			baseEndpointId: 'endpoint-base',
			headEndpointId: 'endpoint-head',
			comparisonSemantics: 'workingTreeDelta',
			pathScope: ['Sources/**'],
			fileTarget: null,
			viewFilter: {
				includedPathGlobs: [],
				excludedPathGlobs: [],
				includedFileClasses: [],
				excludedFileClasses: [],
				includedExtensions: [],
				excludedExtensions: [],
				changeKinds: [],
				reviewStates: [],
				showHiddenFiles: false,
				showBinaryFiles: false,
				showLargeFiles: false,
			},
			grouping: { kind: 'flat', label: null },
			provenanceFilter: {
				paneIds: [],
				agentSessionIds: [],
				promptIds: [],
				operationIds: [],
				createdAfterUnixMilliseconds: null,
				createdBeforeUnixMilliseconds: null,
				sourceKinds: [],
			},
		},
		baseEndpoint: {
			endpointId: 'endpoint-base',
			kind: 'gitRef',
			repoId: 'repo',
			worktreeId: 'worktree',
			label: 'main',
			createdAtUnixMilliseconds: 1,
			contentSetHash: 'sha256:base',
			providerIdentity: 'refs/heads/main',
		},
		headEndpoint: {
			endpointId: 'endpoint-head',
			kind: 'workingTree',
			repoId: 'repo',
			worktreeId: 'worktree',
			label: 'Working tree',
			createdAtUnixMilliseconds: 2,
			contentSetHash: 'sha256:head',
			providerIdentity: 'working-tree',
		},
		orderedItemIds: [item.itemId],
		itemsById: { [item.itemId]: item },
		groups: [],
		summary: {
			filesChanged: 1,
			additions: 1,
			deletions: 1,
			visibleFileCount: 1,
			hiddenFileCount: 0,
		},
		filterState: {
			includedPathGlobs: [],
			excludedPathGlobs: [],
			includedFileClasses: [],
			excludedFileClasses: [],
			includedExtensions: [],
			excludedExtensions: [],
			changeKinds: [],
			reviewStates: [],
			showHiddenFiles: false,
			showBinaryFiles: false,
			showLargeFiles: false,
		},
		generatedAtUnixMilliseconds: 3,
	};
}
