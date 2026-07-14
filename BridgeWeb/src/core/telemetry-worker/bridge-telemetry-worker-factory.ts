import {
	bridgeTelemetryWorkerBootstrapSchema,
	type BridgeTelemetryWorkerRuntime,
	type CreateBridgeTelemetryWorkerRuntimeProps,
} from './bridge-telemetry-worker-contracts.js';
import { defaultBridgeTelemetryWorkerRetryScheduler } from './bridge-telemetry-worker-runtime-support.js';
import { BridgeTelemetryWorkerRuntimeCore } from './bridge-telemetry-worker-runtime.js';

export function createBridgeTelemetryWorkerRuntime(
	props: CreateBridgeTelemetryWorkerRuntimeProps,
): BridgeTelemetryWorkerRuntime | null {
	if (props.bootstrap === null) {
		return null;
	}
	const decodedBootstrap = bridgeTelemetryWorkerBootstrapSchema.safeParse(props.bootstrap);
	if (!decodedBootstrap.success) {
		throw new Error('Invalid telemetry worker bootstrap');
	}
	return new BridgeTelemetryWorkerRuntimeCore(
		decodedBootstrap.data,
		props.transport,
		props.scheduleRetry ?? defaultBridgeTelemetryWorkerRetryScheduler,
	);
}
