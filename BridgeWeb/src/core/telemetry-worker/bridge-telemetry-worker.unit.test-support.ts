import type {
	BridgeTelemetryWorkerBatchRequest,
	BridgeTelemetryWorkerBatchTransport,
	BridgeTelemetryWorkerBootstrap,
	BridgeTelemetryWorkerDrainResult,
	BridgeTelemetryWorkerSnapshot,
} from './bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetryWorkerPortReply } from './bridge-telemetry-worker-entry.js';
import {
	createBridgeTelemetryWorkerProducer,
	type BridgeTelemetryWorkerProducer,
} from './bridge-telemetry-worker-producer.js';

export function makeBootstrap(): BridgeTelemetryWorkerBootstrap {
	return {
		enabledScopes: ['web'],
		endpointUrl: 'agentstudio://telemetry/batch',
		telemetryCapability: 'telemetry-capability-0123456789abcd',
		telemetryCapabilityDigest: 'telemetry-capability-digest-01234567',
		telemetrySessionId: 'telemetry-session-entry',
		policy: {
			initialControlCredits: 2,
			initialSampleCredits: 2,
			compactSampleMaxEncodedBytes: 1_024,
			producerLossKeyCap: 16,
			producerPreReadyBufferMaxBytes: 4 * 1024,
			producerPreReadyBufferMaxSamples: 2,
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
	};
}

export function nextPortReply(port: MessagePort): Promise<BridgeTelemetryWorkerPortReply> {
	return new Promise((resolve) => {
		port.addEventListener(
			'message',
			(event: MessageEvent<BridgeTelemetryWorkerPortReply>): void => resolve(event.data),
			{ once: true },
		);
		port.start();
	});
}

export function nextPortReplies(
	port: MessagePort,
	count: number,
): Promise<readonly BridgeTelemetryWorkerPortReply[]> {
	return new Promise((resolve) => {
		const replies: BridgeTelemetryWorkerPortReply[] = [];
		const listener = (event: MessageEvent<BridgeTelemetryWorkerPortReply>): void => {
			replies.push(event.data);
			if (replies.length === count) {
				port.removeEventListener('message', listener);
				resolve(replies);
			}
		};
		port.addEventListener('message', listener);
		port.start();
	});
}

export function attachTestProducer(
	port: MessagePort,
	props: { readonly generation?: number; readonly receivesReady?: boolean } = {},
): BridgeTelemetryWorkerProducer {
	const producer = createBridgeTelemetryWorkerProducer({
		initialSampleCredits: 0,
		initialControlCredits: 0,
		send: (message): void => port.postMessage(message),
	});
	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		producer.acceptWorkerCommand(event.data);
	});
	port.start();
	if (props.receivesReady !== true) {
		producer.acceptWorkerCommand({
			type: 'producer.ready',
			generation: props.generation ?? 1,
			initialSampleCredits: makeBootstrap().policy.initialSampleCredits,
			initialControlCredits: makeBootstrap().policy.initialControlCredits,
		});
	}
	return producer;
}

export function acceptedTransport(
	captured: BridgeTelemetryWorkerBatchRequest[],
): BridgeTelemetryWorkerBatchTransport {
	return {
		postBatch: async (request) => {
			captured.push(request);
			return {
				type: 'accepted',
				telemetrySessionId: request.telemetrySessionId,
				batchSequence: request.batchSequence,
				nextExpectedBatchSequence: request.batchSequence + 1,
				acceptedSampleCount: request.samples.length,
				acceptedLossCount: request.lossSummaries.reduce(
					(total, summary) => total + summary.requiredCount + summary.optionalCount,
					0,
				),
			};
		},
	};
}

export function makeWorkerSnapshot(): BridgeTelemetryWorkerSnapshot {
	return {
		state: 'active',
		proofEligible: true,
		lossy: false,
		requiredLossCount: 0,
		optionalLossCount: 0,
		sequenceGapCount: 0,
		bufferedSampleCount: 0,
		bufferedSampleBytes: 0,
		bufferedLossSummaryCount: 0,
		bufferedLossSummaryBytes: 0,
		bufferedBytes: 0,
		outboxCount: 0,
		outboxBytes: 0,
		isPostInFlight: false,
		headOutbox: null,
		lastBatchDeliveryFailure: null,
		nextBatchSequence: 1,
		acceptedBatchSequence: 0,
		lossDiagnostics: [],
		producers: { main: null, comm: null },
	};
}

export function makeDrainResult(
	settlementDisposition: BridgeTelemetryWorkerDrainResult['settlementDisposition'] = 'reopened',
): BridgeTelemetryWorkerDrainResult {
	return {
		type: 'drained',
		proofEligible: true,
		settlementDisposition,
		requiredLossCount: 0,
		optionalLossCount: 0,
		sequenceGapCount: 0,
		producerHighWatermarks: { main: 0, comm: 0 },
		acceptedBatchSequence: 0,
	};
}
