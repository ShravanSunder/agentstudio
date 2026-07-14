import { describe, expect, it, vi } from 'vitest';

import type {
	BridgeTelemetryWorkerBatchTransport,
	BridgeTelemetryWorkerBootstrap,
	BridgeTelemetryWorkerRuntime,
	BridgeTelemetryProducerInstallation,
	BridgeTelemetryWorkerRetryScheduler,
} from './bridge-telemetry-worker-contracts.js';
import { createBridgeTelemetryWorkerRuntime } from './bridge-telemetry-worker-factory.js';

const mainLifecycleSample = {
	type: 'interaction.lifecycle',
	stage: 'demand_issued',
	timestampMilliseconds: 10,
	surface: 'review',
	interactionSequence: 1,
	attemptId: 'attempt-1',
} as const;

const optionalDiagnosticSample = {
	type: 'diagnostic',
	code: 'worker_queue_depth',
	timestampMilliseconds: 11,
	value: 2,
} as const;

function makeBootstrap(
	overrides: Partial<BridgeTelemetryWorkerBootstrap> = {},
): BridgeTelemetryWorkerBootstrap {
	return {
		enabledScopes: ['web'],
		endpointUrl: 'agentstudio://telemetry/batch',
		telemetryCapability: 'telemetry-capability-0123456789abcd',
		telemetryCapabilityDigest: 'telemetry-capability-digest-01234567',
		telemetrySessionId: 'telemetry-session-1',
		policy: {
			initialControlCredits: 2,
			initialSampleCredits: 4,
			compactSampleMaxEncodedBytes: 1_024,
			producerLossKeyCap: 16,
			producerPreReadyBufferMaxBytes: 4 * 1024,
			producerPreReadyBufferMaxSamples: 4,
			workerBufferMaxBytes: 8_192,
			workerBufferMaxSamples: 8,
			batchMaxBytes: 4_096,
			batchMaxSamples: 4,
			outboxMaxBytes: 8_192,
			outboxMaxCount: 2,
			maxRetryAttempts: 2,
			drainTimeoutMilliseconds: 1_000,
			minimumFlushIntervalMilliseconds: 0,
		},
		...overrides,
	};
}

function acceptedTransport(): BridgeTelemetryWorkerBatchTransport {
	return {
		postBatch: async (request) => ({
			type: 'accepted',
			telemetrySessionId: request.telemetrySessionId,
			batchSequence: request.batchSequence,
			nextExpectedBatchSequence: request.batchSequence + 1,
			acceptedSampleCount: request.samples.length,
			acceptedLossCount: request.lossSummaries.reduce(
				(total, summary) => total + summary.requiredCount + summary.optionalCount,
				0,
			),
		}),
	};
}

async function acceptBarrierReceipt(props: {
	readonly runtime: BridgeTelemetryWorkerRuntime;
	readonly installation: BridgeTelemetryProducerInstallation;
	readonly highWatermark: number;
	readonly barrierId?: string;
}): Promise<void> {
	const barrierId = props.barrierId ?? `barrier-${props.installation.producerId}`;
	props.runtime.prepareProducerBarrier(props.installation.producerId, barrierId);
	await props.runtime.acceptProducerMessage(props.installation, {
		type: 'producer.barrier.receipt',
		barrierId,
		generation: props.installation.generation,
		producerSequenceHighWatermark: props.highWatermark,
		preSealLossRange: null,
	});
}

async function completeDrainWithSettlements(props: {
	readonly runtime: BridgeTelemetryWorkerRuntime;
	readonly producers: readonly {
		readonly installation: BridgeTelemetryProducerInstallation;
		readonly highWatermark: number;
		readonly postSealLossRange?: {
			readonly lostSequenceStart: number;
			readonly lostSequenceEnd: number;
			readonly requiredCount: number;
			readonly optionalCount: number;
		} | null;
	}[];
	readonly close: boolean;
}): Promise<ReturnType<BridgeTelemetryWorkerRuntime['finishDrain']>> {
	await props.runtime.drainBufferedForSettlement();
	await Promise.all(
		props.producers.map(async (producer): Promise<void> => {
			const barrierId = `barrier-${producer.installation.producerId}`;
			props.runtime.prepareProducerSettlement(producer.installation.producerId, barrierId);
			await props.runtime.acceptProducerMessage(producer.installation, {
				type: 'producer.settlement.receipt',
				barrierId,
				generation: producer.installation.generation,
				producerSequenceHighWatermark: producer.highWatermark,
				postSealLossRange: producer.postSealLossRange ?? null,
			});
		}),
	);
	return props.runtime.finishDrain(props.close);
}

describe('BridgeTelemetryWorkerRuntime', () => {
	it('constructs no runtime when telemetry is disabled and rejects invalid bootstrap scopes', () => {
		expect(
			createBridgeTelemetryWorkerRuntime({ bootstrap: null, transport: acceptedTransport() }),
		).toBeNull();
		expect(() =>
			Reflect.apply(createBridgeTelemetryWorkerRuntime, undefined, [
				{
					bootstrap: { ...makeBootstrap(), enabledScopes: ['web', 'swift'] },
					transport: acceptedTransport(),
				},
			]),
		).toThrow(/invalid telemetry worker bootstrap/i);
	});

	it('strictly rejects unknown, extra, duplicate, and gap producer messages', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		expect(runtime).not.toBeNull();
		if (runtime === null) return;
		const main = runtime.installProducer('main');

		expect(await runtime.acceptProducerMessage(main, { type: 'unknown' })).toMatchObject({
			type: 'rejected',
			reason: 'invalid_message',
		});
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
				producerId: 'comm',
			}),
		).toMatchObject({ type: 'rejected', reason: 'invalid_message' });
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'accepted', producerId: 'main', sequence: 1 });
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'duplicate_sequence' });
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 3,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'sequence_gap' });

		const snapshot = runtime.snapshot();
		expect(snapshot.proofEligible).toBe(false);
		expect(snapshot.requiredLossCount).toBe(2);
		expect(snapshot.sequenceGapCount).toBe(1);
	});

	it('binds producer identity to the installed port generation and revokes old ports', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const commV1 = runtime.installProducer('comm');
		const commV2 = runtime.replaceProducer('comm');
		expect(runtime.snapshot().proofEligible).toBe(false);

		expect(
			await runtime.acceptProducerMessage(commV1, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'revoked_port' });
		expect(
			await runtime.acceptProducerMessage(commV2, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'accepted', producerId: 'comm' });
		expect(runtime.snapshot().proofEligible).toBe(false);

		const commV3 = runtime.replaceProducer('comm');
		await runtime.flush();
		expect(runtime.takeProducerCreditGrants()).toEqual({ comm: 0, main: 0 });
		expect(runtime.snapshot().producers.comm).toMatchObject({
			generation: commV3.generation,
			availableSampleCredits: makeBootstrap().policy.initialSampleCredits,
		});
	});

	it('enforces credits and deterministic required versus optional loss accounting', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, initialSampleCredits: 1 },
			}),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 1,
				sample: optionalDiagnosticSample,
			}),
		).toMatchObject({ type: 'accepted' });
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 2,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'sample_credit_exhausted' });

		const snapshot = runtime.snapshot();
		expect(snapshot.optionalLossCount).toBe(0);
		expect(snapshot.requiredLossCount).toBe(1);
		expect(snapshot.proofEligible).toBe(false);
	});

	it('returns native-admitted sample credits exactly once per producer', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();

		expect(runtime.takeProducerCreditGrants()).toEqual({ comm: 0, main: 1 });
		expect(runtime.takeProducerCreditGrants()).toEqual({ comm: 0, main: 0 });
	});

	it('acknowledges accepted loss-summary control credits exactly once per producer', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');

		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'loss.summary',
				controlSequence: 1,
				lostSequenceStart: 1,
				lostSequenceEnd: 1,
				requiredCount: 0,
				optionalCount: 1,
				reason: 'credit_exhausted',
			}),
		).toMatchObject({ type: 'accepted', producerId: 'main' });
		expect(runtime.takeProducerControlCreditGrants()).toEqual({ comm: 0, main: 1 });
		expect(runtime.takeProducerControlCreditGrants()).toEqual({ comm: 0, main: 0 });

		await acceptBarrierReceipt({ runtime, installation: main, highWatermark: 1 });
		expect(runtime.takeProducerControlCreditGrants()).toEqual({ comm: 0, main: 0 });
	});

	it('snapshots producer sample and control credit state without exposing producer payloads', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');

		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 1,
			requiredCount: 1,
			optionalCount: 0,
			reason: 'credit_exhausted',
		});

		expect(runtime.snapshot().producers.main).toEqual({
			generation: 1,
			nextExpectedSequence: 2,
			nextExpectedControlSequence: 2,
			availableSampleCredits: makeBootstrap().policy.initialSampleCredits,
			availableControlCredits: makeBootstrap().policy.initialControlCredits,
			barrierHighWatermark: null,
		});
	});

	it('attributes exact producer loss reasons, counts, and last sequence ranges', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		const comm = runtime.installProducer('comm');

		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 1,
			reason: 'credit_exhausted',
		});
		await runtime.acceptProducerMessage(comm, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 3,
			requiredCount: 3,
			optionalCount: 0,
			reason: 'queue_saturated',
		});

		expect(runtime.snapshot()).toMatchObject({
			bufferedLossSummaryCount: 2,
			lossDiagnostics: [
				{
					origin: 'producer',
					producerId: 'main',
					reason: 'credit_exhausted',
					requiredCount: 1,
					optionalCount: 1,
					lastLostSequenceStart: 1,
					lastLostSequenceEnd: 2,
				},
				{
					origin: 'producer',
					producerId: 'comm',
					reason: 'queue_saturated',
					requiredCount: 3,
					optionalCount: 0,
					lastLostSequenceStart: 1,
					lastLostSequenceEnd: 3,
				},
			],
		});
	});

	it('attributes worker encoded-byte cap without retaining the sample body', async () => {
		const encodedCapRuntime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, compactSampleMaxEncodedBytes: 64 },
			}),
			transport: acceptedTransport(),
		});
		if (encodedCapRuntime === null) return;
		const encodedCapMain = encodedCapRuntime.installProducer('main');
		await encodedCapRuntime.acceptProducerMessage(encodedCapMain, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		expect(encodedCapRuntime.snapshot().lossDiagnostics).toEqual([
			{
				origin: 'worker',
				producerId: 'main',
				reason: 'encoded_byte_cap',
				requiredCount: 1,
				optionalCount: 0,
				lastLostSequenceStart: 1,
				lastLostSequenceEnd: 1,
			},
		]);
	});

	it('attributes worker queue saturation to the exact producer sequence', async () => {
		const queueRuntime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, workerBufferMaxSamples: 1 },
			}),
			transport: acceptedTransport(),
		});
		if (queueRuntime === null) return;
		const queueMain = queueRuntime.installProducer('main');
		await queueRuntime.acceptProducerMessage(queueMain, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await queueRuntime.acceptProducerMessage(queueMain, {
			type: 'sample',
			sequence: 2,
			sample: mainLifecycleSample,
		});
		expect(queueRuntime.snapshot().lossDiagnostics).toEqual([
			{
				origin: 'worker',
				producerId: 'main',
				reason: 'queue_saturated',
				requiredCount: 1,
				optionalCount: 0,
				lastLostSequenceStart: 2,
				lastLostSequenceEnd: 2,
			},
		]);
	});

	it('attributes worker outbox saturation to the exact producer sequence', async () => {
		const outboxRuntime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, outboxMaxBytes: 64 },
			}),
			transport: acceptedTransport(),
		});
		if (outboxRuntime === null) return;
		const outboxMain = outboxRuntime.installProducer('main');
		await outboxRuntime.acceptProducerMessage(outboxMain, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await outboxRuntime.flush();
		expect(outboxRuntime.snapshot().lossDiagnostics).toEqual([
			{
				origin: 'worker',
				producerId: 'main',
				reason: 'outbox_saturated',
				requiredCount: 1,
				optionalCount: 0,
				lastLostSequenceStart: 1,
				lastLostSequenceEnd: 1,
			},
		]);
	});

	it('enforces compact sample, worker sample, and worker byte caps', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: {
					...makeBootstrap().policy,
					compactSampleMaxEncodedBytes: 180,
					workerBufferMaxBytes: 180,
					workerBufferMaxSamples: 1,
				},
			}),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 1,
				sample: optionalDiagnosticSample,
			}),
		).toMatchObject({ type: 'accepted' });
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 2,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'accepted' });

		const oversizedRuntime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, compactSampleMaxEncodedBytes: 64 },
			}),
			transport: acceptedTransport(),
		});
		if (oversizedRuntime === null) return;
		const oversizedMain = oversizedRuntime.installProducer('main');
		expect(
			await oversizedRuntime.acceptProducerMessage(oversizedMain, {
				type: 'sample',
				sequence: 1,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'sample_too_large' });
		expect(oversizedRuntime.snapshot().requiredLossCount).toBe(1);
	});

	it('retries identical encoded bytes and preserves sequence across attempts', async () => {
		const postedBodies: Uint8Array[] = [];
		const retryCallbacks: Array<() => Promise<void>> = [];
		const scheduleRetry: BridgeTelemetryWorkerRetryScheduler = (callback): void => {
			retryCallbacks.push(callback);
		};
		let attempt = 0;
		const transport: BridgeTelemetryWorkerBatchTransport = {
			postBatch: async (request, encodedBody) => {
				postedBodies.push(encodedBody.slice());
				attempt += 1;
				if (attempt <= 2) {
					throw new Error('offline');
				}
				return {
					type: 'accepted',
					telemetrySessionId: request.telemetrySessionId,
					batchSequence: request.batchSequence,
					nextExpectedBatchSequence: request.batchSequence + 1,
					acceptedSampleCount: request.samples.length,
					acceptedLossCount: 0,
				};
			},
		};
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, outboxMaxCount: 1 },
			}),
			transport,
			scheduleRetry,
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await runtime.flush();
		expect(retryCallbacks).toHaveLength(1);
		await retryCallbacks.shift()?.();
		expect(postedBodies).toHaveLength(2);
		const [firstBody, secondBody] = postedBodies;
		expect(firstBody).toBeDefined();
		expect(secondBody).toBeDefined();
		if (firstBody === undefined || secondBody === undefined) return;
		expect([...firstBody]).toEqual([...secondBody]);

		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 2,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 0,
			reason: 'credit_exhausted',
		});
		await runtime.flush();
		expect(runtime.snapshot().proofEligible).toBe(false);
		expect(runtime.snapshot().outboxCount).toBe(0);
	});

	it('snapshots only bounded head-outbox and in-flight retry state', async () => {
		let releaseAdmission!: () => void;
		const admission = new Promise<void>((resolve): void => {
			releaseAdmission = resolve;
		});
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => {
					await admission;
					return {
						type: 'accepted',
						telemetrySessionId: request.telemetrySessionId,
						batchSequence: request.batchSequence,
						nextExpectedBatchSequence: request.batchSequence + 1,
						acceptedSampleCount: request.samples.length,
						acceptedLossCount: 0,
					};
				},
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		const flush = runtime.flush();
		expect(runtime.snapshot()).toMatchObject({
			isPostInFlight: true,
			outboxCount: 1,
			headOutbox: {
				batchSequence: 1,
				retryAttempts: 0,
				retryScheduled: false,
			},
		});

		releaseAdmission();
		await flush;
		expect(runtime.snapshot()).toMatchObject({
			isPostInFlight: false,
			headOutbox: null,
		});
	});

	it('attributes terminal transport retry exhaustion to exact queued producer sequences', async () => {
		const retryCallbacks: Array<() => Promise<void>> = [];
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async () => {
					throw new Error('native admission unavailable');
				},
			},
			scheduleRetry: (callback): void => {
				retryCallbacks.push(callback);
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();
		expect(runtime.snapshot()).toMatchObject({
			isPostInFlight: false,
			headOutbox: {
				batchSequence: 1,
				retryAttempts: 1,
				retryScheduled: true,
			},
		});

		await retryCallbacks.shift()?.();
		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			headOutbox: null,
			lossDiagnostics: [
				{
					origin: 'worker',
					producerId: 'main',
					reason: 'transport_retry_exhausted',
					requiredCount: 1,
					optionalCount: 0,
					lastLostSequenceStart: 1,
					lastLostSequenceEnd: 1,
				},
			],
		});
	});

	it('preserves retryable native rejection reason, sequence, and attempts after exhaustion', async () => {
		const retryCallbacks: Array<() => Promise<void>> = [];
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => ({
					type: 'rejected',
					telemetrySessionId: request.telemetrySessionId,
					batchSequence: request.batchSequence,
					nextExpectedBatchSequence: request.batchSequence + 1,
					reason: 'sequence_gap',
					retryable: true,
					retryAfterMilliseconds: 0,
				}),
			},
			scheduleRetry: (callback): void => {
				retryCallbacks.push(callback);
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();
		await retryCallbacks.shift()?.();

		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			lastBatchDeliveryFailure: {
				kind: 'native_rejection',
				batchSequence: 1,
				retryAttempts: 2,
				reason: 'sequence_gap',
				retryable: true,
			},
		});
	});

	it('preserves a nonretryable native rejection without fabricating retry attempts', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => ({
					type: 'rejected',
					telemetrySessionId: request.telemetrySessionId,
					batchSequence: request.batchSequence,
					nextExpectedBatchSequence: request.batchSequence + 1,
					reason: 'invalid_body',
					retryable: false,
				}),
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			lastBatchDeliveryFailure: {
				kind: 'native_rejection',
				batchSequence: 1,
				retryAttempts: 0,
				reason: 'invalid_body',
				retryable: false,
			},
		});
	});

	it('preserves the exact response identity field that mismatched the queued batch', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => ({
					type: 'accepted',
					telemetrySessionId: 'telemetry-session-wrong',
					batchSequence: request.batchSequence,
					nextExpectedBatchSequence: request.batchSequence + 1,
					acceptedSampleCount: request.samples.length,
					acceptedLossCount: 0,
				}),
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			lastBatchDeliveryFailure: {
				kind: 'response_mismatch',
				batchSequence: 1,
				retryAttempts: 0,
				mismatchField: 'telemetry_session_id',
			},
		});
	});

	it('never posts a later batch sequence after an unaccepted batch exhausts retries', async () => {
		const postedBatchSequences: number[] = [];
		const retryCallbacks: Array<() => Promise<void>> = [];
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => {
					postedBatchSequences.push(request.batchSequence);
					if (request.batchSequence === 2) {
						throw new Error('batch 2 remains unaccepted');
					}
					return {
						type: 'accepted',
						telemetrySessionId: request.telemetrySessionId,
						batchSequence: request.batchSequence,
						nextExpectedBatchSequence: request.batchSequence + 1,
						acceptedSampleCount: request.samples.length,
						acceptedLossCount: 0,
					};
				},
			},
			scheduleRetry: (callback): void => {
				retryCallbacks.push(callback);
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await runtime.flush();
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 2,
			sample: mainLifecycleSample,
		});
		await runtime.flush();
		await retryCallbacks.shift()?.();

		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 3,
			sample: mainLifecycleSample,
		});
		await runtime.flush();

		expect(postedBatchSequences).toEqual([1, 2, 2]);
		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			proofEligible: false,
			acceptedBatchSequence: 1,
		});
	});

	it('never emits a fully encoded batch body beyond the native byte cap', async () => {
		const batchMaxBytes = 250;
		const postedByteLengths: number[] = [];
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, batchMaxBytes },
			}),
			transport: {
				postBatch: async (request, encodedBody) => {
					postedByteLengths.push(encodedBody.byteLength);
					return {
						type: 'accepted',
						telemetrySessionId: request.telemetrySessionId,
						batchSequence: request.batchSequence,
						nextExpectedBatchSequence: request.batchSequence + 1,
						acceptedSampleCount: request.samples.length,
						acceptedLossCount: 0,
					};
				},
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();

		expect(postedByteLengths.every((byteLength) => byteLength <= batchMaxBytes)).toBe(true);
		expect(postedByteLengths).toEqual([]);
		expect(runtime.snapshot()).toMatchObject({
			proofEligible: false,
			requiredLossCount: 1,
		});
	});

	it('keeps producer loss accounting exact when the full envelope cannot carry a summary', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, batchMaxBytes: 200 },
			}),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 1,
			reason: 'credit_exhausted',
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			proofEligible: false,
			requiredLossCount: 1,
			optionalLossCount: 1,
			bufferedSampleCount: 0,
			outboxCount: 0,
		});
	});

	it('keeps producer loss accounting exact when terminal transport failure clears summaries', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, maxRetryAttempts: 1 },
			}),
			transport: {
				postBatch: async () => {
					throw new Error('native admission unavailable');
				},
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 1,
			reason: 'credit_exhausted',
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			state: 'closed',
			proofEligible: false,
			requiredLossCount: 1,
			optionalLossCount: 1,
			bufferedSampleCount: 0,
			outboxCount: 0,
		});
	});

	it('does not recount an individually unbatchable producer loss summary', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, batchMaxBytes: 64 },
			}),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 1,
			reason: 'credit_exhausted',
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			requiredLossCount: 1,
			optionalLossCount: 1,
		});
	});

	it('does not recount producer loss summaries when the outbox cannot retain them', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, outboxMaxBytes: 64 },
			}),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'loss.summary',
			controlSequence: 1,
			lostSequenceStart: 1,
			lostSequenceEnd: 2,
			requiredCount: 1,
			optionalCount: 1,
			reason: 'credit_exhausted',
		});

		await runtime.flush();

		expect(runtime.snapshot()).toMatchObject({
			requiredLossCount: 1,
			optionalLossCount: 1,
		});
	});

	it('fails proof and retains no body when the outbox byte cap is exhausted', async () => {
		const postBatch = vi.fn(acceptedTransport().postBatch);
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap({
				policy: { ...makeBootstrap().policy, outboxMaxBytes: 64 },
			}),
			transport: { postBatch },
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		await runtime.flush();

		expect(postBatch).not.toHaveBeenCalled();
		expect(runtime.snapshot()).toMatchObject({
			proofEligible: false,
			requiredLossCount: 1,
			outboxCount: 0,
		});
	});

	it('fails proof when a required sample races after its accepted producer barrier', async () => {
		let releaseNativeAdmission!: () => void;
		const nativeAdmission = new Promise<void>((resolve): void => {
			releaseNativeAdmission = resolve;
		});
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: {
				postBatch: async (request) => {
					await nativeAdmission;
					return {
						type: 'accepted',
						telemetrySessionId: request.telemetrySessionId,
						batchSequence: request.batchSequence,
						nextExpectedBatchSequence: request.batchSequence + 1,
						acceptedSampleCount: request.samples.length,
						acceptedLossCount: 0,
					};
				},
			},
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		const comm = runtime.installProducer('comm');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await acceptBarrierReceipt({ runtime, installation: main, highWatermark: 1 });
		await acceptBarrierReceipt({ runtime, installation: comm, highWatermark: 0 });

		const drain = completeDrainWithSettlements({
			runtime,
			close: true,
			producers: [
				{
					installation: main,
					highWatermark: 2,
					postSealLossRange: {
						lostSequenceStart: 2,
						lostSequenceEnd: 2,
						requiredCount: 1,
						optionalCount: 0,
					},
				},
				{ installation: comm, highWatermark: 0 },
			],
		});
		const racedRequiredSample = await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 2,
			sample: mainLifecycleSample,
		});
		releaseNativeAdmission();

		expect(racedRequiredSample).toMatchObject({ type: 'rejected', reason: 'closed' });
		expect((await drain).proofEligible).toBe(false);
	});

	it('fails proof when a nonempty comm generation is replaced before it is sealed', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		const commV1 = runtime.installProducer('comm');
		await runtime.acceptProducerMessage(commV1, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});

		const commV2 = runtime.replaceProducer('comm');
		await acceptBarrierReceipt({ runtime, installation: main, highWatermark: 0 });
		await acceptBarrierReceipt({ runtime, installation: commV2, highWatermark: 0 });

		expect(
			(
				await completeDrainWithSettlements({
					runtime,
					close: true,
					producers: [
						{ installation: main, highWatermark: 0 },
						{ installation: commV2, highWatermark: 0 },
					],
				})
			).proofEligible,
		).toBe(false);
	});

	it('preserves proof when a clean comm generation is sealed before replacement', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		const commV1 = runtime.installProducer('comm');
		await runtime.acceptProducerMessage(commV1, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await acceptBarrierReceipt({ runtime, installation: commV1, highWatermark: 1 });

		const commV2 = runtime.replaceProducer('comm');
		await acceptBarrierReceipt({ runtime, installation: main, highWatermark: 0 });
		await acceptBarrierReceipt({ runtime, installation: commV2, highWatermark: 0 });

		expect(
			(
				await completeDrainWithSettlements({
					runtime,
					close: true,
					producers: [
						{ installation: main, highWatermark: 0 },
						{ installation: commV2, highWatermark: 0 },
					],
				})
			).proofEligible,
		).toBe(true);
	});

	it('drains exact producer high-watermarks, evicts stale replay, and closes permanently', async () => {
		const runtime = createBridgeTelemetryWorkerRuntime({
			bootstrap: makeBootstrap(),
			transport: acceptedTransport(),
		});
		if (runtime === null) return;
		const main = runtime.installProducer('main');
		const comm = runtime.installProducer('comm');
		await runtime.acceptProducerMessage(main, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await runtime.acceptProducerMessage(comm, {
			type: 'sample',
			sequence: 1,
			sample: mainLifecycleSample,
		});
		await acceptBarrierReceipt({ runtime, installation: main, highWatermark: 1 });
		await acceptBarrierReceipt({ runtime, installation: comm, highWatermark: 1 });

		const drain = await completeDrainWithSettlements({
			runtime,
			close: true,
			producers: [
				{ installation: main, highWatermark: 1 },
				{ installation: comm, highWatermark: 1 },
			],
		});
		expect(drain).toMatchObject({
			type: 'drained',
			proofEligible: true,
			settlementDisposition: 'closed',
			requiredLossCount: 0,
			optionalLossCount: 0,
			sequenceGapCount: 0,
			producerHighWatermarks: { comm: 1, main: 1 },
		});
		expect(runtime.snapshot().state).toBe('closed');
		expect(
			await runtime.acceptProducerMessage(main, {
				type: 'sample',
				sequence: 2,
				sample: mainLifecycleSample,
			}),
		).toMatchObject({ type: 'rejected', reason: 'closed' });
	});
});
