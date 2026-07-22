import { describe, expect, it, vi } from 'vitest';

import { createBridgeTelemetryWorkerRuntime } from './bridge-telemetry-worker-factory.js';
import {
	acceptBarrierReceipt,
	acceptedTransport,
	completeDrainWithSettlements,
	mainLifecycleSample,
	makeBootstrap,
} from './bridge-telemetry-worker-runtime.test-support.js';

describe('BridgeTelemetryWorkerRuntime drain and proof settlement', () => {
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
