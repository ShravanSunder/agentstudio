import type { BridgeDemandScheduler } from '../../core/demand/bridge-demand-scheduler.js';
import type {
	BridgeResourceExecutorLoadFailureKind,
	BridgeResourceExecutorResult,
} from '../../core/demand/bridge-resource-executor.js';
import type { BridgeResourceExecutor } from '../../core/demand/bridge-resource-executor.js';
import type {
	BridgeDemandIntent,
	BridgeDemandLane,
} from '../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type {
	BridgeCodeViewContentResources,
	BridgeCodeViewItemPresentation,
} from '../code-view/bridge-code-view-materialization.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';

export interface LoadReviewItemContentResourcesThroughDemandProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly itemId: string;
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative' | 'background';
	readonly presentation?: BridgeCodeViewItemPresentation | null;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	/** Shared review content cache: peeked before enqueueing demand intents
	 * (an all-roles hit produces zero demand traffic) and populated after
	 * every authoritative load so repeat selections become cache hits. */
	readonly contentRegistry?: BridgeReviewContentRegistry;
	readonly signal?: AbortSignal;
	readonly traceContext?: BridgeTraceContext | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly onDemandTelemetry?: (sample: ReviewContentDemandTelemetry) => void;
}

export type ReviewContentDemandInterest =
	LoadReviewItemContentResourcesThroughDemandProps['interest'];

export type ReviewContentDemandLoadResult =
	| {
			readonly status: 'ready';
			readonly resources: BridgeCodeViewContentResources;
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
	readonly configuredSchedulerMaxQueuedEstimatedBytes: number;
	readonly configuredSchedulerMaxQueuedIntentsPerLane: number;
	readonly intentCount: number;
	readonly foregroundIntentCount: number;
	readonly activeIntentCount: number;
	readonly visibleIntentCount: number;
	readonly nearbyIntentCount: number;
	readonly speculativeIntentCount: number;
	readonly idleIntentCount: number;
	readonly enqueueAcceptedCount: number;
	readonly enqueueRejectedCount: number;
	readonly schedulerQueuedIntentCountBefore: number;
	readonly schedulerQueuedIntentCountAfterEnqueue: number;
	readonly schedulerQueuedIntentCountAfter: number;
	readonly schedulerQueuedEstimatedBytesBefore: number;
	readonly schedulerQueuedEstimatedBytesAfterEnqueue: number;
	readonly schedulerQueuedEstimatedBytesAfter: number;
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
	readonly maxSchedulerQueuedIntentCount: number;
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

export interface ReviewContentDemandPlan {
	readonly handle: BridgeContentHandle;
	readonly role: BridgeContentRole;
	readonly descriptorRef: BridgeDescriptorRef;
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
