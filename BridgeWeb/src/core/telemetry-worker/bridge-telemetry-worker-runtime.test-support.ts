import type {
	BridgeTelemetryWorkerBatchTransport,
	BridgeTelemetryWorkerBootstrap,
	BridgeTelemetryWorkerRuntime,
	BridgeTelemetryProducerInstallation,
} from './bridge-telemetry-worker-contracts.js';

export const mainLifecycleSample = {
	type: 'interaction.lifecycle',
	stage: 'demand_issued',
	timestampMilliseconds: 10,
	surface: 'review',
	interactionSequence: 1,
	attemptId: 'attempt-1',
} as const;

export const optionalDiagnosticSample = {
	type: 'diagnostic',
	code: 'worker_queue_depth',
	timestampMilliseconds: 11,
	value: 2,
} as const;

export function makeBootstrap(
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

export function acceptedTransport(): BridgeTelemetryWorkerBatchTransport {
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

export async function acceptBarrierReceipt(props: {
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

export async function completeDrainWithSettlements(props: {
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
