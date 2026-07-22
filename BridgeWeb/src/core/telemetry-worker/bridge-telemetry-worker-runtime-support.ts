import type {
	BridgeTelemetryProducerId,
	BridgeTelemetryStampedLossSummary,
	BridgeTelemetryStampedSample,
	BridgeTelemetryWorkerBatchRequest,
	BridgeTelemetryWorkerBatchResponse,
	BridgeTelemetryWorkerDrainResult,
	BridgeTelemetryWorkerPolicy,
	BridgeTelemetryWorkerProducerCreditGrants,
	BridgeTelemetryWorkerRetryScheduler,
	BridgeTelemetryWorkerSnapshot,
} from './bridge-telemetry-worker-contracts.js';

export class BridgeTelemetryWorkerProducerCreditGrantLedger {
	private sampleGrants: Record<BridgeTelemetryProducerId, number> = { main: 0, comm: 0 };
	private controlGrants: Record<BridgeTelemetryProducerId, number> = { main: 0, comm: 0 };

	discard(producerId: BridgeTelemetryProducerId): void {
		this.sampleGrants[producerId] = 0;
		this.controlGrants[producerId] = 0;
	}

	recordSampleGrant(producerId: BridgeTelemetryProducerId): void {
		this.sampleGrants[producerId] += 1;
	}

	recordControlGrant(producerId: BridgeTelemetryProducerId): void {
		this.controlGrants[producerId] += 1;
	}

	takeSampleGrants(): BridgeTelemetryWorkerProducerCreditGrants {
		const grants = { ...this.sampleGrants };
		this.sampleGrants = { main: 0, comm: 0 };
		return grants;
	}

	takeControlGrants(): BridgeTelemetryWorkerProducerCreditGrants {
		const grants = { ...this.controlGrants };
		this.controlGrants = { main: 0, comm: 0 };
		return grants;
	}
}

export interface BridgeTelemetryWorkerProducerState {
	readonly producerId: BridgeTelemetryProducerId;
	generation: number;
	nextExpectedSequence: number;
	nextExpectedControlSequence: number;
	availableSampleCredits: number;
	availableControlCredits: number;
	barrierHighWatermark: number | null;
	expectedBarrierId: string | null;
	settlementReceived: boolean;
}

export interface BridgeTelemetryWorkerBufferedSample {
	readonly stamped: BridgeTelemetryStampedSample;
	readonly producerGeneration: number;
	readonly encodedBytes: number;
	readonly required: boolean;
}

export interface BridgeTelemetryWorkerBufferedLossSummary {
	readonly stamped: BridgeTelemetryStampedLossSummary;
	readonly encodedBytes: number;
}

export interface BridgeTelemetryWorkerOutboxBatch {
	readonly request: BridgeTelemetryWorkerBatchRequest;
	readonly encodedBody: Uint8Array;
	readonly samples: readonly BridgeTelemetryWorkerBufferedSample[];
	readonly lossSummaries: readonly BridgeTelemetryWorkerBufferedLossSummary[];
	retryAttempts: number;
	retryScheduled: boolean;
}

export function makeBridgeTelemetryWorkerProducerState(
	producerId: BridgeTelemetryProducerId,
	generation: number,
	policy: BridgeTelemetryWorkerPolicy,
): BridgeTelemetryWorkerProducerState {
	return {
		producerId,
		generation,
		nextExpectedSequence: 1,
		nextExpectedControlSequence: 1,
		availableSampleCredits: policy.initialSampleCredits,
		availableControlCredits: policy.initialControlCredits,
		barrierHighWatermark: null,
		expectedBarrierId: null,
		settlementReceived: false,
	};
}

export function makeBridgeTelemetryWorkerProducerSnapshot(
	producer: BridgeTelemetryWorkerProducerState | undefined,
): BridgeTelemetryWorkerSnapshot['producers'][BridgeTelemetryProducerId] {
	return producer === undefined
		? null
		: {
				generation: producer.generation,
				nextExpectedSequence: producer.nextExpectedSequence,
				nextExpectedControlSequence: producer.nextExpectedControlSequence,
				availableSampleCredits: producer.availableSampleCredits,
				availableControlCredits: producer.availableControlCredits,
				barrierHighWatermark: producer.barrierHighWatermark,
			};
}

export function makeBridgeTelemetryWorkerDrainResult(props: {
	readonly proofEligible: boolean;
	readonly settlementDisposition: 'closed' | 'reopened';
	readonly requiredLossCount: number;
	readonly optionalLossCount: number;
	readonly sequenceGapCount: number;
	readonly acceptedBatchSequence: number;
	readonly mainProducer: BridgeTelemetryWorkerProducerState | undefined;
	readonly commProducer: BridgeTelemetryWorkerProducerState | undefined;
}): BridgeTelemetryWorkerDrainResult {
	return {
		type: 'drained',
		proofEligible: props.proofEligible,
		settlementDisposition: props.settlementDisposition,
		requiredLossCount: props.requiredLossCount,
		optionalLossCount: props.optionalLossCount,
		sequenceGapCount: props.sequenceGapCount,
		producerHighWatermarks: {
			main: props.mainProducer?.barrierHighWatermark ?? 0,
			comm: props.commProducer?.barrierHighWatermark ?? 0,
		},
		acceptedBatchSequence: props.acceptedBatchSequence,
	};
}

const encoder = new TextEncoder();

export function bridgeTelemetryEncodedBytes(value: unknown): number {
	return encoder.encode(JSON.stringify(value)).byteLength;
}

export function encodeBridgeTelemetryBatchRequest(
	request: BridgeTelemetryWorkerBatchRequest,
): Uint8Array {
	return encoder.encode(JSON.stringify(request));
}

export type BridgeTelemetryBatchResponseMismatchField =
	| 'telemetry_session_id'
	| 'batch_sequence'
	| 'next_expected_batch_sequence'
	| 'accepted_sample_count'
	| 'accepted_loss_count';

export function bridgeTelemetryBatchResponseMismatch(
	response: BridgeTelemetryWorkerBatchResponse,
	request: BridgeTelemetryWorkerBatchRequest,
): BridgeTelemetryBatchResponseMismatchField | null {
	if (response.telemetrySessionId !== request.telemetrySessionId) {
		return 'telemetry_session_id';
	}
	if (response.batchSequence !== request.batchSequence) {
		return 'batch_sequence';
	}
	if (response.type === 'rejected') {
		return null;
	}
	if (response.nextExpectedBatchSequence !== request.batchSequence + 1) {
		return 'next_expected_batch_sequence';
	}
	const expectedLossCount = request.lossSummaries.reduce(
		(total, summary) => total + summary.requiredCount + summary.optionalCount,
		0,
	);
	if (response.acceptedLossCount !== expectedLossCount) {
		return 'accepted_loss_count';
	}
	if (response.type !== 'accepted_with_loss') {
		return response.acceptedSampleCount === request.samples.length ? null : 'accepted_sample_count';
	}
	return response.acceptedSampleCount +
		response.nativeRequiredLossCount +
		response.nativeOptionalLossCount ===
		request.samples.length
		? null
		: 'accepted_sample_count';
}

export const defaultBridgeTelemetryWorkerRetryScheduler: BridgeTelemetryWorkerRetryScheduler = (
	callback,
	retryAttempt,
): void => {
	globalThis.setTimeout(
		(): void => {
			void callback();
		},
		Math.min(1_000, 10 * 2 ** Math.max(0, retryAttempt - 1)),
	);
};
