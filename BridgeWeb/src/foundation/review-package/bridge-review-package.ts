import type { BridgeReviewQuery } from '../review-query/bridge-review-query.js';

export type BridgeReviewGeneration = number;

export type BridgeReviewCheckpointKind = 'prompt' | 'session' | 'manual' | 'savedTimeWindow';

export interface BridgeReviewCheckpoint {
	readonly checkpointId: string;
	readonly checkpointKind: BridgeReviewCheckpointKind;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly paneId: string;
	readonly createdAtUnixMilliseconds: number;
	readonly reviewGeneration: BridgeReviewGeneration;
	readonly baseEndpointId: string;
	readonly headEndpointId: string;
	readonly eventSequenceStart: number;
	readonly eventSequenceEnd: number;
	readonly batchSequenceStart: number;
	readonly batchSequenceEnd: number;
	readonly contentSetHash: string;
	readonly agentSessionId: string | null;
	readonly promptId: string | null;
	readonly summary: string;
}

export type BridgeSourceEndpointKind =
	| 'gitRef'
	| 'workingTree'
	| 'index'
	| 'promptCheckpoint'
	| 'sessionCheckpoint'
	| 'manualCheckpoint'
	| 'savedTimeWindowCheckpoint';

export interface BridgeSourceEndpoint {
	readonly endpointId: string;
	readonly kind: BridgeSourceEndpointKind;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly label: string;
	readonly createdAtUnixMilliseconds: number;
	readonly contentSetHash: string | null;
	readonly providerIdentity: string;
}

export type BridgeFileClass =
	| 'source'
	| 'test'
	| 'docs'
	| 'config'
	| 'generated'
	| 'vendor'
	| 'binary'
	| 'large'
	| 'fixture'
	| 'unknown';

export type BridgeFileChangeKind = 'added' | 'modified' | 'deleted' | 'renamed' | 'copied';
export type BridgeFileReviewState = 'unreviewed' | 'viewed' | 'annotated' | 'resolved';
export type BridgeReviewPriority = 'low' | 'normal' | 'high';
export type BridgeContentRole = 'base' | 'head' | 'diff' | 'file';

export interface BridgeContentHandle {
	readonly handleId: string;
	readonly itemId: string;
	readonly role: BridgeContentRole;
	readonly endpointId: string;
	readonly reviewGeneration: BridgeReviewGeneration;
	readonly resourceUrl: string;
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly cacheKey: string;
	readonly mimeType: string;
	readonly language?: string | null;
	readonly sizeBytes: number;
	readonly isBinary: boolean;
}

export interface BridgeReviewContentRoles {
	readonly base?: BridgeContentHandle | null;
	readonly head?: BridgeContentHandle | null;
	readonly diff?: BridgeContentHandle | null;
	readonly file?: BridgeContentHandle | null;
}

export interface BridgeProvenanceSummary {
	readonly paneIds: readonly string[];
	readonly agentSessionIds: readonly string[];
	readonly promptIds: readonly string[];
	readonly operationIds: readonly string[];
	readonly sourceKinds: readonly string[];
}

export interface BridgeAnnotationSummary {
	readonly threadCount: number;
	readonly unresolvedThreadCount: number;
	readonly commentCount: number;
}

export interface BridgeReviewItemDescriptor {
	readonly itemId: string;
	readonly itemKind: 'file' | 'diff';
	readonly itemVersion: number;
	readonly basePath?: string | null;
	readonly headPath?: string | null;
	readonly changeKind: BridgeFileChangeKind;
	readonly fileClass: BridgeFileClass;
	readonly language?: string | null;
	readonly extension?: string | null;
	readonly sizeBytes: number;
	readonly baseContentHash: string | null;
	readonly headContentHash: string | null;
	readonly contentHashAlgorithm: string;
	readonly additions: number;
	readonly deletions: number;
	readonly isHiddenByDefault: boolean;
	readonly hiddenReason: string | null;
	readonly reviewPriority: BridgeReviewPriority;
	readonly contentRoles: BridgeReviewContentRoles;
	readonly cacheKey: string;
	readonly provenance: BridgeProvenanceSummary;
	readonly annotationSummary: BridgeAnnotationSummary;
	readonly reviewState: BridgeFileReviewState;
	readonly collapsed: boolean;
}

export interface BridgeViewFilter {
	readonly includedPathGlobs: readonly string[];
	readonly excludedPathGlobs: readonly string[];
	readonly includedFileClasses: readonly BridgeFileClass[];
	readonly excludedFileClasses: readonly BridgeFileClass[];
	readonly includedExtensions: readonly string[];
	readonly excludedExtensions: readonly string[];
	readonly changeKinds: readonly BridgeFileChangeKind[];
	readonly reviewStates: readonly BridgeFileReviewState[];
	readonly showHiddenFiles: boolean;
	readonly showBinaryFiles: boolean;
	readonly showLargeFiles: boolean;
}

export type BridgeChangeGroupingKind =
	| 'flat'
	| 'folder'
	| 'fileClass'
	| 'changeKind'
	| 'reviewState'
	| 'agentStream'
	| 'prompt'
	| 'session'
	| 'checkpoint'
	| 'timeWindow'
	| 'custom';

export interface BridgeChangeGrouping {
	readonly kind: BridgeChangeGroupingKind;
	readonly label: string | null;
}

export interface BridgeReviewGroup {
	readonly groupId: string;
	readonly grouping: BridgeChangeGrouping;
	readonly label: string;
	readonly orderedItemIds: readonly string[];
	readonly summary: {
		readonly filesChanged: number;
		readonly additions: number;
		readonly deletions: number;
	};
	readonly hiddenSummary: {
		readonly hiddenFileCount: number;
		readonly hiddenAdditions: number;
		readonly hiddenDeletions: number;
		readonly hiddenFileClasses: readonly BridgeFileClass[];
	};
}

export interface BridgeReviewPackageSummary {
	readonly filesChanged: number;
	readonly additions: number;
	readonly deletions: number;
	readonly visibleFileCount: number;
	readonly hiddenFileCount: number;
}

export interface BridgeReviewPackage {
	readonly packageId: string;
	readonly schemaVersion: 1;
	readonly reviewGeneration: BridgeReviewGeneration;
	readonly revision: number;
	readonly query: BridgeReviewQuery;
	readonly baseEndpoint: BridgeSourceEndpoint;
	readonly headEndpoint: BridgeSourceEndpoint;
	readonly orderedItemIds: readonly string[];
	readonly itemsById: Readonly<Record<string, BridgeReviewItemDescriptor>>;
	readonly groups: readonly BridgeReviewGroup[];
	readonly summary: BridgeReviewPackageSummary;
	readonly filterState: BridgeViewFilter;
	readonly generatedAtUnixMilliseconds: number;
}
