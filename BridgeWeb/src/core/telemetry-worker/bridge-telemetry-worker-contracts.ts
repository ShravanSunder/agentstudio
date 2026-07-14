import { z } from 'zod';

import { bridgeTelemetrySampleSchema } from '../../foundation/telemetry/bridge-telemetry-event.js';

const safeIdentifierSchema = z
	.string()
	.min(1)
	.max(128)
	.regex(/^[A-Za-z0-9._:-]+$/u);
const capabilitySchema = z
	.string()
	.min(24)
	.max(256)
	.regex(/^[A-Za-z0-9._:-]+$/u);
const positiveIntegerSchema = z.number().int().positive();

export const bridgeTelemetryProducerIdSchema = z.enum(['main', 'comm']);
export type BridgeTelemetryProducerId = z.infer<typeof bridgeTelemetryProducerIdSchema>;

const bridgeTelemetrySurfaceSchema = z.enum(['file', 'review']);

const bridgeTelemetryCorrelationSchema = z
	.object({
		attemptId: safeIdentifierSchema,
		interactionSequence: positiveIntegerSchema,
		surface: bridgeTelemetrySurfaceSchema,
	})
	.strict();

const bridgeTelemetryLifecycleSampleSchema = z
	.object({
		type: z.literal('interaction.lifecycle'),
		stage: z.enum([
			'demand_issued',
			'worker_ready',
			'main_received',
			'validity_accepted',
			'validity_rejected',
			'apply_queued',
			'applied',
			'superseded',
			'painted',
		]),
		timestampMilliseconds: z.number().nonnegative(),
		...bridgeTelemetryCorrelationSchema.shape,
	})
	.strict();

const bridgeTelemetryDurationSampleSchema = z
	.object({
		type: z.literal('duration'),
		metric: z.enum([
			'click_to_first_visible',
			'worker_queue_wait',
			'worker_task',
			'main_apply',
			'paint_wait',
		]),
		durationMilliseconds: z.number().nonnegative(),
		timestampMilliseconds: z.number().nonnegative(),
		...bridgeTelemetryCorrelationSchema.shape,
	})
	.strict();

const bridgeTelemetryFailureSampleSchema = z
	.object({
		type: z.literal('interaction.failure'),
		failure: z.enum([
			'abort',
			'stale',
			'unavailable',
			'timeout',
			'reset',
			'retry',
			'failure',
			'jank',
		]),
		timestampMilliseconds: z.number().nonnegative(),
		...bridgeTelemetryCorrelationSchema.shape,
	})
	.strict();

const bridgeTelemetryIntegritySampleSchema = z
	.object({
		type: z.literal('integrity'),
		failure: z.enum([
			'producer_sequence_gap',
			'batch_sequence_gap',
			'conflicting_duplicate',
			'missing_drain_ack',
			'worker_restart',
		]),
		timestampMilliseconds: z.number().nonnegative(),
	})
	.strict();

const bridgeTelemetryDiagnosticSampleSchema = z
	.object({
		type: z.literal('diagnostic'),
		code: z.enum(['worker_queue_depth', 'buffer_bytes', 'outbox_bytes']),
		timestampMilliseconds: z.number().nonnegative(),
		value: z.number().finite(),
	})
	.strict();

const bridgeTelemetryEventSampleBaseSchema = z.object({
	timestampMilliseconds: z.number().nonnegative(),
	sample: bridgeTelemetrySampleSchema.strict(),
});

const bridgeTelemetryRequiredEventSampleSchema = bridgeTelemetryEventSampleBaseSchema
	.extend({ type: z.literal('event.required') })
	.strict()
	.refine(
		(value) => {
			const priority = value.sample.stringAttributes['agentstudio.bridge.priority'];
			return priority === 'hot' || priority === 'warm' || priority === 'cold';
		},
		{ message: 'Required telemetry events must carry hot, warm, or cold priority.' },
	);

const bridgeTelemetryOptionalEventSampleSchema = bridgeTelemetryEventSampleBaseSchema
	.extend({ type: z.literal('event.optional') })
	.strict()
	.refine(
		(value) => value.sample.stringAttributes['agentstudio.bridge.priority'] === 'best_effort',
		{ message: 'Optional telemetry events must carry best-effort priority.' },
	);

export const bridgeTelemetryCompactSampleSchema = z.discriminatedUnion('type', [
	bridgeTelemetryLifecycleSampleSchema,
	bridgeTelemetryDurationSampleSchema,
	bridgeTelemetryFailureSampleSchema,
	bridgeTelemetryIntegritySampleSchema,
	bridgeTelemetryDiagnosticSampleSchema,
	bridgeTelemetryRequiredEventSampleSchema,
	bridgeTelemetryOptionalEventSampleSchema,
]);
export type BridgeTelemetryCompactSample = z.infer<typeof bridgeTelemetryCompactSampleSchema>;

export function isRequiredBridgeTelemetrySample(sample: BridgeTelemetryCompactSample): boolean {
	return sample.type !== 'diagnostic' && sample.type !== 'event.optional';
}

const bridgeTelemetryWorkerSampleMessageSchema = z
	.object({
		type: z.literal('sample'),
		sequence: positiveIntegerSchema,
		sample: bridgeTelemetryCompactSampleSchema,
	})
	.strict();

export const bridgeTelemetryLossReasonSchema = z.enum([
	'credit_exhausted',
	'encoded_byte_cap',
	'queue_saturated',
	'outbox_saturated',
	'producer_failure',
]);
export type BridgeTelemetryLossReason = z.infer<typeof bridgeTelemetryLossReasonSchema>;

const bridgeTelemetryWorkerLossSummaryMessageSchema = z
	.object({
		type: z.literal('loss.summary'),
		controlSequence: positiveIntegerSchema,
		lostSequenceStart: positiveIntegerSchema,
		lostSequenceEnd: positiveIntegerSchema,
		requiredCount: z.number().int().nonnegative(),
		optionalCount: z.number().int().nonnegative(),
		reason: bridgeTelemetryLossReasonSchema,
	})
	.strict();

const bridgeTelemetryWorkerBarrierMessageSchema = z
	.object({
		type: z.literal('producer.barrier.receipt'),
		barrierId: safeIdentifierSchema,
		generation: positiveIntegerSchema,
		producerSequenceHighWatermark: z.number().int().nonnegative(),
		preSealLossRange: z
			.object({
				lostSequenceStart: positiveIntegerSchema,
				lostSequenceEnd: positiveIntegerSchema,
				requiredCount: z.number().int().nonnegative(),
				optionalCount: z.number().int().nonnegative(),
			})
			.strict()
			.nullable(),
	})
	.strict();

const bridgeTelemetryWorkerSettlementReceiptSchema = z
	.object({
		type: z.literal('producer.settlement.receipt'),
		barrierId: safeIdentifierSchema,
		generation: positiveIntegerSchema,
		producerSequenceHighWatermark: z.number().int().nonnegative(),
		postSealLossRange: z
			.object({
				lostSequenceStart: positiveIntegerSchema,
				lostSequenceEnd: positiveIntegerSchema,
				requiredCount: z.number().int().nonnegative(),
				optionalCount: z.number().int().nonnegative(),
			})
			.strict()
			.nullable(),
	})
	.strict();

export const bridgeTelemetryWorkerProducerMessageSchema = z.discriminatedUnion('type', [
	bridgeTelemetryWorkerSampleMessageSchema,
	bridgeTelemetryWorkerLossSummaryMessageSchema,
	bridgeTelemetryWorkerBarrierMessageSchema,
	bridgeTelemetryWorkerSettlementReceiptSchema,
]);
export type BridgeTelemetryWorkerProducerMessage = z.infer<
	typeof bridgeTelemetryWorkerProducerMessageSchema
>;

export const bridgeTelemetryWorkerPolicySchema = z
	.object({
		initialControlCredits: positiveIntegerSchema,
		initialSampleCredits: positiveIntegerSchema,
		compactSampleMaxEncodedBytes: positiveIntegerSchema,
		producerLossKeyCap: positiveIntegerSchema,
		producerPreReadyBufferMaxBytes: positiveIntegerSchema,
		producerPreReadyBufferMaxSamples: positiveIntegerSchema,
		workerBufferMaxBytes: positiveIntegerSchema,
		workerBufferMaxSamples: positiveIntegerSchema,
		batchMaxBytes: positiveIntegerSchema,
		batchMaxSamples: positiveIntegerSchema,
		outboxMaxBytes: positiveIntegerSchema,
		outboxMaxCount: positiveIntegerSchema,
		maxRetryAttempts: positiveIntegerSchema,
		drainTimeoutMilliseconds: positiveIntegerSchema,
		minimumFlushIntervalMilliseconds: z.number().int().nonnegative(),
	})
	.strict();
export type BridgeTelemetryWorkerPolicy = z.infer<typeof bridgeTelemetryWorkerPolicySchema>;

export const bridgeTelemetryWorkerBootstrapSchema = z
	.object({
		enabledScopes: z.tuple([z.literal('web')]).readonly(),
		endpointUrl: z.string().min(1).max(512),
		telemetryCapability: capabilitySchema,
		telemetryCapabilityDigest: capabilitySchema,
		telemetrySessionId: safeIdentifierSchema,
		policy: bridgeTelemetryWorkerPolicySchema,
	})
	.strict();
export type BridgeTelemetryWorkerBootstrap = z.infer<typeof bridgeTelemetryWorkerBootstrapSchema>;

const messagePortSchema = z.custom<MessagePort>(
	(value): boolean => typeof MessagePort !== 'undefined' && value instanceof MessagePort,
);

export const bridgeTelemetryWorkerInstallSchema = z
	.object({
		type: z.literal('telemetry.bootstrap'),
		bootstrap: bridgeTelemetryWorkerBootstrapSchema,
		mainPort: messagePortSchema,
		commPort: messagePortSchema,
	})
	.strict();
export type BridgeTelemetryWorkerInstall = z.infer<typeof bridgeTelemetryWorkerInstallSchema>;

const bridgeTelemetryStampedSampleSchema = z
	.object({
		producerId: bridgeTelemetryProducerIdSchema,
		producerSequence: positiveIntegerSchema,
		sample: bridgeTelemetryCompactSampleSchema,
	})
	.strict();
export type BridgeTelemetryStampedSample = z.infer<typeof bridgeTelemetryStampedSampleSchema>;

const bridgeTelemetryStampedLossSummarySchema = z
	.object({
		producerId: bridgeTelemetryProducerIdSchema,
		lostSequenceStart: positiveIntegerSchema,
		lostSequenceEnd: positiveIntegerSchema,
		requiredCount: z.number().int().nonnegative(),
		optionalCount: z.number().int().nonnegative(),
		reason: bridgeTelemetryLossReasonSchema,
	})
	.strict();
export type BridgeTelemetryStampedLossSummary = z.infer<
	typeof bridgeTelemetryStampedLossSummarySchema
>;

export const bridgeTelemetryWorkerBatchRequestSchema = z
	.object({
		type: z.literal('telemetry.batch'),
		schemaVersion: z.literal(2),
		telemetrySessionId: safeIdentifierSchema,
		batchSequence: positiveIntegerSchema,
		samples: z.array(bridgeTelemetryStampedSampleSchema).readonly(),
		lossSummaries: z.array(bridgeTelemetryStampedLossSummarySchema).readonly(),
	})
	.strict();
export type BridgeTelemetryWorkerBatchRequest = z.infer<
	typeof bridgeTelemetryWorkerBatchRequestSchema
>;

const bridgeTelemetryWorkerAcceptedResponseFields = {
	telemetrySessionId: safeIdentifierSchema,
	batchSequence: positiveIntegerSchema,
	nextExpectedBatchSequence: positiveIntegerSchema,
	acceptedSampleCount: z.number().int().nonnegative(),
	acceptedLossCount: z.number().int().nonnegative(),
};

const bridgeTelemetryWorkerAcceptedBatchResponseSchema = z
	.object({ type: z.literal('accepted'), ...bridgeTelemetryWorkerAcceptedResponseFields })
	.strict();
const bridgeTelemetryWorkerDuplicateBatchResponseSchema = z
	.object({ type: z.literal('duplicate'), ...bridgeTelemetryWorkerAcceptedResponseFields })
	.strict();
const bridgeTelemetryWorkerAcceptedWithLossBatchResponseSchema = z
	.object({
		type: z.literal('accepted_with_loss'),
		...bridgeTelemetryWorkerAcceptedResponseFields,
		nativeRequiredLossCount: z.number().int().nonnegative(),
		nativeOptionalLossCount: z.number().int().nonnegative(),
	})
	.strict();
const bridgeTelemetryWorkerRejectedBatchResponseSchema = z
	.object({
		type: z.literal('rejected'),
		telemetrySessionId: safeIdentifierSchema,
		batchSequence: positiveIntegerSchema,
		nextExpectedBatchSequence: positiveIntegerSchema,
		reason: z.enum(['conflict', 'invalid_body', 'sequence_gap', 'unavailable']),
		retryable: z.boolean(),
		retryAfterMilliseconds: z.number().int().nonnegative().optional(),
	})
	.strict();

export const bridgeTelemetryWorkerBatchResponseSchema = z.discriminatedUnion('type', [
	bridgeTelemetryWorkerAcceptedBatchResponseSchema,
	bridgeTelemetryWorkerDuplicateBatchResponseSchema,
	bridgeTelemetryWorkerAcceptedWithLossBatchResponseSchema,
	bridgeTelemetryWorkerRejectedBatchResponseSchema,
]);
export type BridgeTelemetryWorkerBatchResponse = z.infer<
	typeof bridgeTelemetryWorkerBatchResponseSchema
>;

export interface BridgeTelemetryWorkerBatchTransport {
	readonly postBatch: (
		request: BridgeTelemetryWorkerBatchRequest,
		encodedBody: Uint8Array,
		telemetryCapability: string,
	) => Promise<BridgeTelemetryWorkerBatchResponse>;
}

export type BridgeTelemetryWorkerRetryScheduler = (
	callback: () => Promise<void>,
	retryAttempt: number,
) => void;

export interface BridgeTelemetryProducerInstallation {
	readonly producerId: BridgeTelemetryProducerId;
	readonly generation: number;
}

export type BridgeTelemetryWorkerIngressRejectionReason =
	| 'closed'
	| 'control_credit_exhausted'
	| 'duplicate_control_sequence'
	| 'duplicate_sequence'
	| 'invalid_loss_summary'
	| 'invalid_message'
	| 'revoked_port'
	| 'sample_credit_exhausted'
	| 'sample_too_large'
	| 'sequence_gap';

export type BridgeTelemetryWorkerIngressResult =
	| {
			readonly type: 'accepted';
			readonly producerId: BridgeTelemetryProducerId;
			readonly sequence: number;
			readonly buffered: boolean;
	  }
	| {
			readonly type: 'rejected';
			readonly reason: BridgeTelemetryWorkerIngressRejectionReason;
	  };

export const bridgeTelemetryWorkerProducerCreditGrantSchema = z.union([
	z
		.object({
			type: z.literal('producer.credit-grant'),
			sampleCredits: positiveIntegerSchema,
		})
		.strict(),
	z
		.object({
			type: z.literal('producer.credit-grant'),
			controlCredits: positiveIntegerSchema,
		})
		.strict(),
]);
export type BridgeTelemetryWorkerProducerCreditGrant = z.infer<
	typeof bridgeTelemetryWorkerProducerCreditGrantSchema
>;

export const bridgeTelemetryWorkerProducerReadySchema = z
	.object({
		type: z.literal('producer.ready'),
		generation: positiveIntegerSchema,
		initialSampleCredits: z.number().int().nonnegative(),
		initialControlCredits: z.number().int().nonnegative(),
	})
	.strict();
export type BridgeTelemetryWorkerProducerReady = z.infer<
	typeof bridgeTelemetryWorkerProducerReadySchema
>;

export const bridgeTelemetryWorkerProducerCommandSchema = z.union([
	bridgeTelemetryWorkerProducerReadySchema,
	bridgeTelemetryWorkerProducerCreditGrantSchema,
	z
		.object({
			type: z.literal('producer.barrier.request'),
			barrierId: safeIdentifierSchema,
			generation: positiveIntegerSchema,
		})
		.strict(),
	z
		.object({
			type: z.literal('producer.settlement.request'),
			barrierId: safeIdentifierSchema,
			generation: positiveIntegerSchema,
			disposition: z.enum(['reopen', 'close']),
			sampleCredits: z.number().int().nonnegative(),
			controlCredits: z.number().int().nonnegative(),
		})
		.strict(),
]);
export type BridgeTelemetryWorkerProducerCommand = z.infer<
	typeof bridgeTelemetryWorkerProducerCommandSchema
>;

export type BridgeTelemetryWorkerProducerCreditGrants = Readonly<
	Record<BridgeTelemetryProducerId, number>
>;

const bridgeTelemetryProducerSnapshotSchema = z
	.object({
		generation: positiveIntegerSchema,
		nextExpectedSequence: positiveIntegerSchema,
		nextExpectedControlSequence: positiveIntegerSchema,
		availableSampleCredits: z.number().int().nonnegative(),
		availableControlCredits: z.number().int().nonnegative(),
		barrierHighWatermark: z.number().int().nonnegative().nullable(),
	})
	.strict();
export type BridgeTelemetryProducerSnapshot = z.infer<typeof bridgeTelemetryProducerSnapshotSchema>;

const bridgeTelemetrySnapshotLossReasonSchema = z.enum([
	...bridgeTelemetryLossReasonSchema.options,
	'transport_retry_exhausted',
]);

const bridgeTelemetryLossDiagnosticSchema = z
	.object({
		origin: z.enum(['producer', 'worker']),
		producerId: bridgeTelemetryProducerIdSchema,
		reason: bridgeTelemetrySnapshotLossReasonSchema,
		requiredCount: z.number().int().nonnegative(),
		optionalCount: z.number().int().nonnegative(),
		lastLostSequenceStart: positiveIntegerSchema,
		lastLostSequenceEnd: positiveIntegerSchema,
	})
	.strict();
export type BridgeTelemetryLossDiagnostic = z.infer<typeof bridgeTelemetryLossDiagnosticSchema>;

const bridgeTelemetryHeadOutboxSnapshotSchema = z
	.object({
		batchSequence: positiveIntegerSchema,
		retryAttempts: z.number().int().nonnegative(),
		retryScheduled: z.boolean(),
	})
	.strict();

const bridgeTelemetryHTTPStatusSchema = z.number().int().min(100).max(599);
const bridgeTelemetryTransportFailureSnapshotSchema = z.discriminatedUnion('stage', [
	z
		.object({
			stage: z.literal('fetch'),
			httpStatus: z.null(),
			retryAttempts: positiveIntegerSchema,
		})
		.strict(),
	z
		.object({
			stage: z.literal('http_status'),
			httpStatus: bridgeTelemetryHTTPStatusSchema,
			retryAttempts: positiveIntegerSchema,
		})
		.strict(),
	z
		.object({
			stage: z.literal('response_body'),
			httpStatus: bridgeTelemetryHTTPStatusSchema,
			retryAttempts: positiveIntegerSchema,
		})
		.strict(),
	z
		.object({
			stage: z.literal('response_schema'),
			httpStatus: bridgeTelemetryHTTPStatusSchema,
			retryAttempts: positiveIntegerSchema,
		})
		.strict(),
]);
export type BridgeTelemetryTransportFailureSnapshot = z.infer<
	typeof bridgeTelemetryTransportFailureSnapshotSchema
>;

const bridgeTelemetryBatchDeliveryFailureSnapshotSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('transport'),
			transport: bridgeTelemetryTransportFailureSnapshotSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('native_rejection'),
			batchSequence: positiveIntegerSchema,
			retryAttempts: z.number().int().nonnegative(),
			reason: z.enum(['conflict', 'invalid_body', 'sequence_gap', 'unavailable']),
			retryable: z.boolean(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('response_mismatch'),
			batchSequence: positiveIntegerSchema,
			retryAttempts: z.number().int().nonnegative(),
			mismatchField: z.enum([
				'telemetry_session_id',
				'batch_sequence',
				'next_expected_batch_sequence',
				'accepted_sample_count',
				'accepted_loss_count',
			]),
		})
		.strict(),
]);
export type BridgeTelemetryBatchDeliveryFailureSnapshot = z.infer<
	typeof bridgeTelemetryBatchDeliveryFailureSnapshotSchema
>;

export const bridgeTelemetryWorkerSnapshotSchema = z
	.object({
		state: z.enum(['active', 'draining', 'closed', 'failed']),
		proofEligible: z.boolean(),
		lossy: z.boolean(),
		requiredLossCount: z.number().int().nonnegative(),
		optionalLossCount: z.number().int().nonnegative(),
		sequenceGapCount: z.number().int().nonnegative(),
		bufferedSampleCount: z.number().int().nonnegative(),
		bufferedSampleBytes: z.number().int().nonnegative(),
		bufferedLossSummaryCount: z.number().int().nonnegative(),
		bufferedLossSummaryBytes: z.number().int().nonnegative(),
		bufferedBytes: z.number().int().nonnegative(),
		outboxCount: z.number().int().nonnegative(),
		outboxBytes: z.number().int().nonnegative(),
		isPostInFlight: z.boolean(),
		headOutbox: bridgeTelemetryHeadOutboxSnapshotSchema.nullable(),
		lastBatchDeliveryFailure: bridgeTelemetryBatchDeliveryFailureSnapshotSchema.nullable(),
		nextBatchSequence: positiveIntegerSchema,
		acceptedBatchSequence: z.number().int().nonnegative(),
		lossDiagnostics: z.array(bridgeTelemetryLossDiagnosticSchema).max(16).readonly(),
		producers: z
			.object({
				main: bridgeTelemetryProducerSnapshotSchema.nullable(),
				comm: bridgeTelemetryProducerSnapshotSchema.nullable(),
			})
			.strict(),
	})
	.strict();
export type BridgeTelemetryWorkerSnapshot = z.infer<typeof bridgeTelemetryWorkerSnapshotSchema>;

export const bridgeTelemetryWorkerDrainResultSchema = z
	.object({
		type: z.literal('drained'),
		proofEligible: z.boolean(),
		settlementDisposition: z.enum(['reopened', 'closed']),
		requiredLossCount: z.number().int().nonnegative(),
		optionalLossCount: z.number().int().nonnegative(),
		sequenceGapCount: z.number().int().nonnegative(),
		producerHighWatermarks: z
			.object({
				main: z.number().int().nonnegative(),
				comm: z.number().int().nonnegative(),
			})
			.strict(),
		acceptedBatchSequence: z.number().int().nonnegative(),
	})
	.strict();
export type BridgeTelemetryWorkerDrainResult = z.infer<
	typeof bridgeTelemetryWorkerDrainResultSchema
>;

export interface BridgeTelemetryWorkerRuntime {
	readonly installProducer: (
		producerId: BridgeTelemetryProducerId,
	) => BridgeTelemetryProducerInstallation;
	readonly replaceProducer: (
		producerId: BridgeTelemetryProducerId,
	) => BridgeTelemetryProducerInstallation;
	readonly acceptProducerMessage: (
		installation: BridgeTelemetryProducerInstallation,
		value: unknown,
	) => Promise<BridgeTelemetryWorkerIngressResult>;
	readonly takeProducerCreditGrants: () => BridgeTelemetryWorkerProducerCreditGrants;
	readonly takeProducerControlCreditGrants: () => BridgeTelemetryWorkerProducerCreditGrants;
	readonly flush: () => Promise<void>;
	readonly snapshot: () => BridgeTelemetryWorkerSnapshot;
	readonly prepareProducerBarrier: (
		producerId: BridgeTelemetryProducerId,
		barrierId: string,
	) => BridgeTelemetryProducerInstallation;
	readonly prepareProducerSettlement: (
		producerId: BridgeTelemetryProducerId,
		barrierId: string,
	) => void;
	readonly producerSettlementReceived: (producerId: BridgeTelemetryProducerId) => boolean;
	readonly finishDrain: (closeAfterDrain: boolean) => BridgeTelemetryWorkerDrainResult;
	readonly failProof: () => void;
	readonly drainBufferedForSettlement: () => Promise<void>;
	readonly drain: () => Promise<BridgeTelemetryWorkerDrainResult>;
	readonly drainAndClose: () => Promise<BridgeTelemetryWorkerDrainResult>;
}

export interface CreateBridgeTelemetryWorkerRuntimeProps {
	readonly bootstrap: BridgeTelemetryWorkerBootstrap | null;
	readonly transport: BridgeTelemetryWorkerBatchTransport;
	readonly scheduleRetry?: BridgeTelemetryWorkerRetryScheduler;
}

export const bridgeTelemetryWorkerControlRequestSchema = z.discriminatedUnion('type', [
	z
		.object({
			type: z.literal('telemetry.snapshot'),
			requestId: safeIdentifierSchema,
		})
		.strict(),
	z
		.object({
			type: z.literal('telemetry.drain'),
			requestId: safeIdentifierSchema,
		})
		.strict(),
	z
		.object({
			type: z.literal('telemetry.drainAndClose'),
			requestId: safeIdentifierSchema,
		})
		.strict(),
	z
		.object({
			type: z.literal('telemetry.producer.replace'),
			requestId: safeIdentifierSchema,
			producerId: bridgeTelemetryProducerIdSchema,
			producerPort: messagePortSchema,
		})
		.strict(),
]);
export type BridgeTelemetryWorkerControlRequest = z.infer<
	typeof bridgeTelemetryWorkerControlRequestSchema
>;

export const bridgeTelemetryWorkerSnapshotResultSchema = z
	.object({
		type: z.literal('telemetry.snapshot.result'),
		requestId: safeIdentifierSchema,
		snapshot: bridgeTelemetryWorkerSnapshotSchema,
	})
	.strict();
export const bridgeTelemetryWorkerDrainedResultSchema = z
	.object({
		type: z.literal('telemetry.drained'),
		requestId: safeIdentifierSchema,
		result: bridgeTelemetryWorkerDrainResultSchema,
	})
	.strict();
export const bridgeTelemetryWorkerDrainedAndClosedResultSchema = z
	.object({
		type: z.literal('telemetry.drainedAndClosed'),
		requestId: safeIdentifierSchema,
		result: bridgeTelemetryWorkerDrainResultSchema,
	})
	.strict();

export type BridgeTelemetryWorkerControlResponse =
	| {
			readonly type: 'telemetry.snapshot.result';
			readonly requestId: string;
			readonly snapshot: BridgeTelemetryWorkerSnapshot;
	  }
	| {
			readonly type: 'telemetry.drained';
			readonly requestId: string;
			readonly result: BridgeTelemetryWorkerDrainResult;
	  }
	| {
			readonly type: 'telemetry.drainedAndClosed';
			readonly requestId: string;
			readonly result: BridgeTelemetryWorkerDrainResult;
	  }
	| {
			readonly type: 'telemetry.producer.replaced';
			readonly requestId: string;
			readonly producerId: BridgeTelemetryProducerId;
	  };
