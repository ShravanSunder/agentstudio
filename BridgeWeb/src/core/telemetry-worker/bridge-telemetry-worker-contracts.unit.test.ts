import { describe, expect, it } from 'vitest';

import { bridgeTelemetryWorkerSnapshotSchema } from './bridge-telemetry-worker-contracts.js';

const producerLossDiagnostic = {
	origin: 'producer',
	producerId: 'main',
	reason: 'credit_exhausted',
	requiredCount: 1,
	optionalCount: 0,
	lastLostSequenceStart: 4,
	lastLostSequenceEnd: 4,
} as const;

function workerSnapshotFixture(): Readonly<Record<string, unknown>> {
	return {
		state: 'active',
		proofEligible: false,
		lossy: true,
		requiredLossCount: 1,
		optionalLossCount: 0,
		sequenceGapCount: 0,
		bufferedSampleCount: 0,
		bufferedSampleBytes: 80,
		bufferedLossSummaryCount: 1,
		bufferedLossSummaryBytes: 48,
		bufferedBytes: 128,
		outboxCount: 1,
		outboxBytes: 256,
		isPostInFlight: false,
		headOutbox: {
			batchSequence: 2,
			retryAttempts: 1,
			retryScheduled: true,
		},
		lastBatchDeliveryFailure: null,
		nextBatchSequence: 3,
		acceptedBatchSequence: 1,
		lossDiagnostics: [producerLossDiagnostic],
		producers: {
			main: {
				generation: 1,
				nextExpectedSequence: 5,
				nextExpectedControlSequence: 2,
				availableSampleCredits: 3,
				availableControlCredits: 1,
				barrierHighWatermark: null,
			},
			comm: null,
		},
	} as const;
}

describe('Bridge telemetry worker snapshot contract', () => {
	it('accepts the complete bounded diagnostic snapshot without payloads or capabilities', () => {
		expect(bridgeTelemetryWorkerSnapshotSchema.safeParse(workerSnapshotFixture()).success).toBe(
			true,
		);
		expect(JSON.stringify(workerSnapshotFixture())).not.toMatch(
			/"sample"\s*:|attemptId|telemetryCapability|encodedBody/u,
		);
	});

	it('strictly rejects unknown diagnostic fields and unknown loss reasons', () => {
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				payload: { attemptId: 'must-not-cross' },
			}).success,
		).toBe(false);
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				lossDiagnostics: [
					{
						...producerLossDiagnostic,
						reason: 'unbounded_ad_hoc_reason',
					},
				],
			}).success,
		).toBe(false);
	});

	it('accepts only discriminated delivery failures with nested transport stage facts', () => {
		const deliveryFailures = [
			{
				kind: 'transport',
				transport: { stage: 'fetch', httpStatus: null, retryAttempts: 2 },
			},
			{
				kind: 'native_rejection',
				batchSequence: 2,
				retryAttempts: 2,
				reason: 'sequence_gap',
				retryable: true,
			},
			{
				kind: 'response_mismatch',
				batchSequence: 2,
				retryAttempts: 0,
				mismatchField: 'telemetry_session_id',
			},
		] as const;

		for (const lastBatchDeliveryFailure of deliveryFailures) {
			expect(
				bridgeTelemetryWorkerSnapshotSchema.safeParse({
					...workerSnapshotFixture(),
					lastBatchDeliveryFailure,
				}).success,
			).toBe(true);
		}
	});

	it('rejects transport delivery failures whose HTTP status contradicts the nested stage', () => {
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				lastBatchDeliveryFailure: {
					kind: 'transport',
					transport: { stage: 'fetch', httpStatus: 403, retryAttempts: 1 },
				},
			}).success,
		).toBe(false);
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				lastBatchDeliveryFailure: {
					kind: 'transport',
					transport: { stage: 'http_status', httpStatus: null, retryAttempts: 1 },
				},
			}).success,
		).toBe(false);
	});

	it('caps loss diagnostics at sixteen fixed-shape entries', () => {
		const sixteenDiagnostics = Array.from({ length: 16 }, () => producerLossDiagnostic);
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				lossDiagnostics: sixteenDiagnostics,
			}).success,
		).toBe(true);
		expect(
			bridgeTelemetryWorkerSnapshotSchema.safeParse({
				...workerSnapshotFixture(),
				lossDiagnostics: [...sixteenDiagnostics, producerLossDiagnostic],
			}).success,
		).toBe(false);
	});
});
