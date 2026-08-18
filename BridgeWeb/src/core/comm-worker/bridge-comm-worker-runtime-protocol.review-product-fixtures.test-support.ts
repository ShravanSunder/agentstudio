import type { BridgeProductReviewItemMetadata } from './bridge-product-review-metadata-contracts.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';

const reviewItemMetadata = {
	additions: 1,
	deletions: 1,
	basePath: 'Sources/App.swift',
	changeKind: 'modified',
	contentDescriptorIdsByRole: {},
	contentHashesByRole: {},
	contentRoles: [],
	extension: 'swift',
	fileClass: 'source',
	headPath: 'Sources/App.swift',
	isHiddenByDefault: false,
	itemId: 'item-1',
	language: 'swift',
	mimeTypes: ['text/plain'],
	provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
	reviewPriority: 'normal',
	reviewState: 'unreviewed',
} satisfies BridgeProductReviewItemMetadata;

export const reviewSnapshotEvent = {
	baseEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'base',
		kind: 'gitRef',
		label: 'base',
		providerIdentity: 'base-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	contentSources: [],
	eventKind: 'review.snapshot',
	extentFacts: [],
	generation: 7,
	headEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'head',
		kind: 'workingTree',
		label: 'head',
		providerIdentity: 'head-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	itemMetadata: [reviewItemMetadata],
	itemWindow: { finalWindow: true, itemCount: 1, startIndex: 0, totalItemCount: 1 },
	packageId: 'package-1',
	presentationRevision: 11,
	publicationId: '00000000-0000-7000-8000-000000000011',
	query: {
		baseEndpointId: 'base',
		comparisonSemantics: 'threeDot',
		fileTarget: null,
		grouping: { kind: 'folder' },
		headEndpointId: 'head',
		pathScope: [],
		provenanceFilter: {
			agentSessionIds: [],
			operationIds: [],
			paneIds: [],
			promptIds: [],
			sourceKinds: [],
		},
		queryId: 'query-1',
		queryKind: 'compare',
		repoId: 'repo-1',
		viewFilter: {
			changeKinds: [],
			excludedExtensions: [],
			excludedFileClasses: [],
			excludedPathGlobs: [],
			includedExtensions: [],
			includedFileClasses: [],
			includedPathGlobs: [],
			reviewStates: [],
			showBinaryFiles: true,
			showHiddenFiles: false,
			showLargeFiles: true,
		},
		worktreeId: 'worktree-1',
	},
	revision: 11,
	reviewComparison: null,
	sourceIdentity: 'source-1',
	summary: {
		additions: 1,
		deletions: 1,
		filesChanged: 1,
		hiddenFileCount: 0,
		visibleFileCount: 1,
	},
	treeRows: [
		{
			depth: 0,
			isDirectory: false,
			itemId: 'item-1',
			path: 'Sources/App.swift',
			rowId: 'row-1',
		},
	],
	treeWindow: { finalWindow: true, rowCount: 1, startIndex: 0, totalRowCount: 1 },
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;

const reviewContentSource = {
	contentDigest: {
		algorithm: 'sha256',
		authority: 'authoritative',
		value: 'a'.repeat(64),
	},
	contentKind: 'review.content',
	descriptorId: 'review-descriptor-item-1-head',
	encoding: 'utf-8',
	endpointId: 'head',
	handleId: 'review-handle-item-1-head',
	isBinary: false,
	itemId: 'item-1',
	language: 'swift',
	mimeType: 'text/plain',
	packageId: 'package-1',
	reviewGeneration: 7,
	role: 'head',
	sourceIdentity: 'source-1',
	wholeByteLength: 12,
} as const;

const reviewBaseContentSource = {
	...reviewContentSource,
	contentDigest: {
		algorithm: 'sha256',
		authority: 'authoritative',
		value: 'b'.repeat(64),
	},
	descriptorId: 'review-descriptor-item-1-base',
	endpointId: 'base',
	handleId: 'review-handle-item-1-base',
	role: 'base',
} as const;

export const reviewSnapshotWithContentEvent = {
	...reviewSnapshotEvent,
	contentSources: [reviewBaseContentSource, reviewContentSource],
	extentFacts: [
		{ contentRole: 'base', itemId: 'item-1', lineCount: 1 },
		{ contentRole: 'head', itemId: 'item-1', lineCount: 1 },
	],
	itemMetadata: [
		{
			...reviewItemMetadata,
			contentDescriptorIdsByRole: {
				base: reviewBaseContentSource.descriptorId,
				head: reviewContentSource.descriptorId,
			},
			contentHashesByRole: {
				base: reviewBaseContentSource.contentDigest.value,
				head: reviewContentSource.contentDigest.value,
			},
			contentRoles: ['base', 'head'],
		},
	],
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;
