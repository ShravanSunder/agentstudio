import type {
	BridgeResourceExecutorLoadFailureKind,
	BridgeResourceExecutorResult,
} from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
	BridgeDemandLane,
} from '../../core/models/bridge-demand-models.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import type { BridgeContentRole } from '../../foundation/review-package/bridge-review-package.js';

export type ReviewContentDemandInterest =
	| 'selected'
	| 'visible'
	| 'nearby'
	| 'speculative'
	| 'background';

export type ReviewContentDemandLoadResult =
	| {
			readonly status: 'ready';
	  }
	| {
			readonly status: 'deferred';
			readonly reason: 'aborted' | 'concurrency_exceeded' | 'stale_completion';
	  }
	| {
			readonly status: 'failed';
			readonly reason: 'byte_budget_exceeded' | 'descriptor_missing' | 'load_failed';
	  };

export type ReviewContentDemandResultReason = Exclude<
	ReviewContentDemandLoadResult,
	{ readonly status: 'ready' }
>['reason'];

export interface ReviewContentDemandTelemetry {
	readonly itemId: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly interest: ReviewContentDemandInterest;
	readonly resultReason?: ReviewContentDemandResultReason;
	readonly resultStatus?: ReviewContentDemandLoadResult['status'];
	readonly resultLoadFailureKind?: BridgeResourceExecutorLoadFailureKind;
	readonly byteBudgetSource: 'review-content-demand';
	readonly durationMilliseconds: number;
	readonly configuredExecutorMaxConcurrentLoads: number;
	readonly configuredExecutorMaxInFlightBytes: number;
	readonly intentCount: number;
	readonly foregroundIntentCount: number;
	readonly activeIntentCount: number;
	readonly visibleIntentCount: number;
	readonly nearbyIntentCount: number;
	readonly speculativeIntentCount: number;
	readonly idleIntentCount: number;
	readonly executorInFlightCountBefore: number;
	readonly executorInFlightCountAfterDispatch: number;
	readonly executorInFlightCountAfter: number;
	readonly executorInFlightBytesBefore: number;
	readonly executorInFlightBytesAfterDispatch: number;
	readonly executorInFlightBytesAfter: number;
	readonly executorQueuedLoadCountBefore: number;
	readonly executorQueuedLoadCountAfterDispatch: number;
	readonly executorQueuedLoadCountAfter: number;
	readonly executorQueuedBytesBefore: number;
	readonly executorQueuedBytesAfterDispatch: number;
	readonly executorQueuedBytesAfter: number;
	readonly laneUpgradeCount: number;
	readonly maxExecutorInFlightCount: number;
	readonly maxExecutorQueuedLoadCount: number;
	readonly admittedBytes: number;
	readonly admittedBytesByLane: Record<BridgeDemandLane, number>;
	readonly deferredCount: number;
	readonly deferredEstimatedBytesByLane: Record<BridgeDemandLane, number>;
	readonly droppedEstimatedBytesByLane: Record<BridgeDemandLane, number>;
	readonly droppedIntentCount: number;
	readonly failedCount: number;
	readonly loadedCount: number;
	readonly staleDropCount: number;
}

export interface LoadedReviewContentDemandResult {
	readonly estimatedBytes: number;
	readonly intent: BridgeDemandIntent;
	readonly role: BridgeContentRole;
	readonly result: BridgeResourceExecutorResult<BridgeTextResourceStreamResult>;
}

export type LoadedReviewContentDemandSettledResult =
	| {
			readonly status: 'fulfilled';
			readonly value: LoadedReviewContentDemandResult;
	  }
	| {
			readonly status: 'rejected';
	  };
