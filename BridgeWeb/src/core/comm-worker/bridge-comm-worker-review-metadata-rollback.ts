import type { MutableBridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-metadata-applicator-support.js';
import type { BridgeCommWorkerReviewMetadataProjection } from './bridge-comm-worker-review-metadata-projection.js';
import type { ReviewMetadataLineage } from './bridge-comm-worker-review-publication-transaction.js';
import type { BridgeCommWorkerReviewCandidateReadyFacts } from './bridge-comm-worker-review-publication-types.js';
import type { BridgeCommWorkerReviewSuccessorReExposureFence } from './bridge-comm-worker-review-successor-re-exposure.js';
import type {
	BridgeWorkerReviewCandidateStartDisposition,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewApplicatorRollbackSnapshot {
	readonly activeCandidateReadyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null;
	readonly acceptedLineageFloor: ReviewMetadataLineage | null;
	readonly activeDeltaPublicationFingerprint: string | null;
	readonly activeProjection: BridgeCommWorkerReviewMetadataProjection | null;
	readonly contentItemIndexById: ReadonlyMap<string, number>;
	readonly contentRequestIndexByKey: ReadonlyMap<string, number>;
	readonly contentRequestKeysByItemId: ReadonlyMap<string, ReadonlySet<string>>;
	readonly directoryIdByPath: ReadonlyMap<string, string>;
	readonly itemSignatureById: ReadonlyMap<string, string>;
	readonly pendingProjection: BridgeCommWorkerReviewMetadataProjection | null;
	readonly pendingCandidateStart: BridgeWorkerReviewCandidateStartDisposition | null;
	readonly renderSemanticsIndexById: ReadonlyMap<string, number>;
	readonly rowIndexById: ReadonlyMap<string, number>;
	readonly runtimeSource: MutableBridgeCommWorkerReviewRuntimeSource;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly sourceEpoch: number;
	readonly treePathByRowId: ReadonlyMap<string, string>;
	readonly lastSuccessorReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
}
