import { z } from 'zod';

import { bridgeTelemetryScopeSchema } from '../../foundation/telemetry/bridge-telemetry-scope.js';

const messagePortSchema = z.custom<MessagePort>(
	(value): boolean =>
		typeof value === 'object' &&
		value !== null &&
		'addEventListener' in value &&
		typeof value.addEventListener === 'function' &&
		'postMessage' in value &&
		typeof value.postMessage === 'function' &&
		'close' in value &&
		typeof value.close === 'function' &&
		'start' in value &&
		typeof value.start === 'function',
);

export const bridgeCommTelemetryProducerInstallSchema = z
	.object({
		type: z.literal('bridgePaneCommWorker.telemetryProducer.install'),
		enabledScopes: z.array(bridgeTelemetryScopeSchema).min(1).readonly(),
		preReadyRequiredSampleCapacity: z.number().int().positive(),
		preReadyRequiredSampleMaxEncodedBytes: z.number().int().positive(),
		producerPort: messagePortSchema,
	})
	.strict();
export type BridgeCommTelemetryProducerInstall = z.infer<
	typeof bridgeCommTelemetryProducerInstallSchema
>;

export interface BridgeCommTelemetryProducerInstallTarget {
	readonly postMessage: (
		message: BridgeCommTelemetryProducerInstall,
		transfer: Transferable[],
	) => void;
}

export function postBridgeCommTelemetryProducerInstall(
	target: BridgeCommTelemetryProducerInstallTarget,
	install: BridgeCommTelemetryProducerInstall,
): void {
	const validatedInstall = bridgeCommTelemetryProducerInstallSchema.parse(install);
	target.postMessage(validatedInstall, [validatedInstall.producerPort]);
}
