import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetrySink } from '../foundation/telemetry/bridge-telemetry-sink.js';

export interface CreateBridgeTelemetryEventSinkProps {
	readonly endpointUrl?: string;
	readonly fetch?: (input: RequestInfo | URL, init?: RequestInit) => boolean | Promise<Response>;
}

export function createBridgeTelemetryEventSink(
	props: CreateBridgeTelemetryEventSinkProps,
): BridgeTelemetrySink {
	const endpointUrl = props.endpointUrl ?? 'agentstudio://telemetry/batch';
	const fetchTelemetry = props.fetch ?? globalThis.fetch.bind(globalThis);
	return {
		flush: (batch: BridgeTelemetryBatch): boolean => {
			try {
				void fetchTelemetry(endpointUrl, {
					body: JSON.stringify(batch),
					headers: { 'Content-Type': 'application/json' },
					method: 'POST',
				});
				return true;
			} catch {
				return false;
			}
		},
	};
}
