import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';

export interface BridgeTelemetryBufferSnapshot {
	readonly samples: readonly BridgeTelemetrySample[];
	readonly droppedCount: number;
}

export interface BridgeTelemetryBuffer {
	readonly add: (sample: BridgeTelemetrySample) => void;
	readonly drain: () => BridgeTelemetryBufferSnapshot;
	readonly restore: (snapshot: BridgeTelemetryBufferSnapshot) => void;
}

export function createBridgeTelemetryBuffer(maxSamples: number): BridgeTelemetryBuffer {
	const samples: BridgeTelemetrySample[] = [];
	let droppedCount = 0;

	return {
		add: (sample: BridgeTelemetrySample): void => {
			if (samples.length >= maxSamples) {
				droppedCount += 1;
				return;
			}
			samples.push(sample);
		},
		drain: (): BridgeTelemetryBufferSnapshot => {
			const snapshot = {
				samples: [...samples],
				droppedCount,
			};
			samples.length = 0;
			droppedCount = 0;
			return snapshot;
		},
		restore: (snapshot: BridgeTelemetryBufferSnapshot): void => {
			samples.unshift(...snapshot.samples);
			droppedCount += snapshot.droppedCount;
			if (samples.length > maxSamples) {
				droppedCount += samples.length - maxSamples;
				samples.length = maxSamples;
			}
		},
	};
}
