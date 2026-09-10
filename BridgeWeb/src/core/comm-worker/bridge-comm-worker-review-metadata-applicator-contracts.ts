export {
	applyBridgeCommWorkerReviewMetadataApplication,
	type BridgeCommWorkerReviewMetadataApplication,
} from './bridge-comm-worker-review-runtime-application.js';

export type BridgeCommWorkerReviewMetadataFailureDisposition =
	| 'ignored'
	| 'noActive'
	| 'retainedActive';
export interface BridgeCommWorkerReviewPublicationApplicationReceipt {
	readonly publicationId: string;
}
export interface BridgeCommWorkerReviewRuntimeApplicationTransaction {
	readonly commit: () => void;
	readonly rollback: () => void;
	readonly runPostCommitEffects: () => void;
}
