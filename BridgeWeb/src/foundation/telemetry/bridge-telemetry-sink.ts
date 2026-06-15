import type { BridgeTelemetryBatch } from './bridge-telemetry-event.js';

export interface BridgeTelemetrySink {
	readonly flush: (batch: BridgeTelemetryBatch) => boolean;
}

export const nullBridgeTelemetrySink: BridgeTelemetrySink = {
	flush: (): boolean => true,
};
