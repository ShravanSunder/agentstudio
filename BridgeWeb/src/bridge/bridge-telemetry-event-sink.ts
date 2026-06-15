import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetrySink } from '../foundation/telemetry/bridge-telemetry-sink.js';
import type { BridgeRPCClient } from './bridge-rpc-client.js';

export interface CreateBridgeTelemetryEventSinkProps {
	readonly rpcClient: BridgeRPCClient;
	readonly methodName: 'system.bridgeTelemetry';
}

export function createBridgeTelemetryEventSink(
	props: CreateBridgeTelemetryEventSinkProps,
): BridgeTelemetrySink {
	return {
		flush: (batch: BridgeTelemetryBatch): boolean =>
			props.rpcClient.sendCommand({
				method: props.methodName,
				params: batch,
			}),
	};
}
