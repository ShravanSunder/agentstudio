import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';

export interface BridgeTelemetryBufferConfig {
	readonly maxSamplesPerBatch: number;
	readonly maxEncodedBatchBytes: number;
}

export interface BridgeTelemetryDropCounter {
	readonly count: number;
	readonly eventName: string;
	readonly lane: string;
	readonly result: string;
	readonly reason: 'encoded_byte_cap' | 'queue_saturated';
}

export interface BridgeTelemetryBufferSnapshot {
	readonly samples: readonly BridgeTelemetrySample[];
	readonly droppedCount: number;
	readonly dropCounters: readonly BridgeTelemetryDropCounter[];
	readonly shedRequiredEventCount: number;
}

export interface BridgeTelemetryBuffer {
	readonly add: (sample: BridgeTelemetrySample) => void;
	readonly drain: () => BridgeTelemetryBufferSnapshot;
	readonly restore: (snapshot: BridgeTelemetryBufferSnapshot) => void;
}

export function createBridgeTelemetryBuffer(
	config: number | BridgeTelemetryBufferConfig,
): BridgeTelemetryBuffer {
	const maxSamples = typeof config === 'number' ? config : config.maxSamplesPerBatch;
	const maxEncodedBatchBytes =
		typeof config === 'number' ? Number.POSITIVE_INFINITY : config.maxEncodedBatchBytes;
	const samples: BridgeTelemetrySample[] = [];
	const dropCounters = new Map<string, BridgeTelemetryDropCounter>();
	let shedRequiredEventCount = 0;

	return {
		add: (sample: BridgeTelemetrySample): void => {
			if (samples.length >= maxSamples) {
				recordDropCounter(dropCounters, sample, 'queue_saturated');
				if (isRequiredTelemetrySample(sample)) {
					shedRequiredEventCount += 1;
				}
				return;
			}
			samples.push(sample);
		},
		drain: (): BridgeTelemetryBufferSnapshot => {
			shedRequiredEventCount += shedOldestSamplesOverEncodedCap(
				samples,
				maxEncodedBatchBytes,
				dropCounters,
			);
			const counters = [...dropCounters.values()];
			const snapshot = {
				samples: [...samples],
				droppedCount: counters.reduce((total, counter) => total + counter.count, 0),
				dropCounters: counters,
				shedRequiredEventCount,
			};
			samples.length = 0;
			dropCounters.clear();
			shedRequiredEventCount = 0;
			return snapshot;
		},
		restore: (snapshot: BridgeTelemetryBufferSnapshot): void => {
			samples.unshift(...snapshot.samples);
			for (const counter of snapshot.dropCounters) {
				recordDropCounter(dropCounters, counter, counter.reason, counter.count);
			}
			shedRequiredEventCount += snapshot.shedRequiredEventCount;
			if (samples.length > maxSamples) {
				const removedSamples = samples.splice(maxSamples);
				for (const removedSample of removedSamples) {
					recordDropCounter(dropCounters, removedSample, 'queue_saturated');
					if (isRequiredTelemetrySample(removedSample)) {
						shedRequiredEventCount += 1;
					}
				}
			}
			shedRequiredEventCount += shedOldestSamplesOverEncodedCap(
				samples,
				maxEncodedBatchBytes,
				dropCounters,
			);
		},
	};
}

function shedOldestSamplesOverEncodedCap(
	samples: BridgeTelemetrySample[],
	maxEncodedBatchBytes: number,
	dropCounters: Map<string, BridgeTelemetryDropCounter>,
): number {
	let shedRequiredCount = 0;
	while (encodedSampleBytes(samples) > maxEncodedBatchBytes && samples.length > 0) {
		const optionalIndex = samples.findIndex((sample) => !isRequiredTelemetrySample(sample));
		const dropIndex = optionalIndex === -1 ? 0 : optionalIndex;
		const [droppedSample] = samples.splice(dropIndex, 1);
		if (droppedSample === undefined) {
			break;
		}
		recordDropCounter(dropCounters, droppedSample, 'encoded_byte_cap');
		if (isRequiredTelemetrySample(droppedSample)) {
			shedRequiredCount += 1;
		}
	}
	return shedRequiredCount;
}

function encodedSampleBytes(samples: readonly BridgeTelemetrySample[]): number {
	return new TextEncoder().encode(JSON.stringify(samples)).byteLength;
}

function isRequiredTelemetrySample(sample: BridgeTelemetrySample): boolean {
	const priority = sample.stringAttributes['agentstudio.bridge.priority'];
	return priority === 'hot' || priority === 'warm';
}

function recordDropCounter(
	dropCounters: Map<string, BridgeTelemetryDropCounter>,
	sampleOrCounter: BridgeTelemetrySample | BridgeTelemetryDropCounter,
	reason: BridgeTelemetryDropCounter['reason'],
	count = 1,
): void {
	const eventName = 'name' in sampleOrCounter ? sampleOrCounter.name : sampleOrCounter.eventName;
	const lane =
		'stringAttributes' in sampleOrCounter
			? (sampleOrCounter.stringAttributes['agentstudio.bridge.priority'] ?? 'unknown')
			: sampleOrCounter.lane;
	const result =
		'stringAttributes' in sampleOrCounter
			? (sampleOrCounter.stringAttributes['agentstudio.bridge.result'] ?? 'unknown')
			: sampleOrCounter.result;
	const key = `${eventName}\u0000${lane}\u0000${result}\u0000${reason}`;
	const existingCounter = dropCounters.get(key);
	dropCounters.set(key, {
		count: (existingCounter?.count ?? 0) + count,
		eventName,
		lane,
		result,
		reason,
	});
}
