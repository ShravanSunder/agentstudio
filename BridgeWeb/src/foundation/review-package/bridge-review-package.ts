export type {
	BridgeAnnotationSummary,
	BridgeChangeGrouping,
	BridgeChangeGroupingKind,
	BridgeContentHandle,
	BridgeContentRole,
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeFileReviewState,
	BridgeProvenanceFilter,
	BridgeProvenanceSummary,
	BridgeReviewContentRoles,
	BridgeReviewGeneration,
	BridgeReviewGroup,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeReviewPackageSummary,
	BridgeReviewPriority,
	BridgeReviewQuery,
	BridgeSourceEndpoint,
	BridgeSourceEndpointKind,
	BridgeViewFilter,
} from './bridge-review-package-schema.js';

export type BridgeReviewCheckpointKind = 'prompt' | 'session' | 'manual' | 'savedTimeWindow';

export interface BridgeReviewCheckpoint {
	readonly checkpointId: string;
	readonly checkpointKind: BridgeReviewCheckpointKind;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly paneId: string;
	readonly createdAtUnixMilliseconds: number;
	readonly reviewGeneration: number;
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
