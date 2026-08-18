import { buildBridgeWorkerRuntimeCommandFailedHealthEvent } from './bridge-comm-worker-runtime-health.js';
import { sendBridgeCommWorkerActionWithTimeout } from './bridge-comm-worker-runtime-support.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	bridgeWorkerAnnotationOutputInspectionEventSchema,
	type BridgeWorkerAnnotationOutputInspectCommand,
	type BridgeWorkerAnnotationOutputInspectionEvent,
} from './bridge-worker-annotation-contracts.js';
import { BRIDGE_WORKER_WIRE_VERSION } from './bridge-worker-contracts.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export type PreparedBridgeWorkerAnnotationOutputInspection =
	PreparedBridgeWorkerStructuredMessage<BridgeWorkerAnnotationOutputInspectionEvent>;

export function runBridgeCommWorkerAnnotationOutputInspection(props: {
	readonly command: BridgeWorkerAnnotationOutputInspectCommand;
	readonly publishFailure: (
		failure: ReturnType<typeof buildBridgeWorkerRuntimeCommandFailedHealthEvent>,
	) => void;
	readonly publishInspection: (inspection: PreparedBridgeWorkerAnnotationOutputInspection) => void;
	readonly productTransport: BridgeProductTransportSession | undefined;
	readonly signal: AbortSignal;
	readonly timeoutMilliseconds: number;
}): void {
	const productTransport = props.productTransport;
	void sendBridgeCommWorkerActionWithTimeout({
		send:
			productTransport === undefined
				? rejectUninstalledAnnotationOutputInspection
				: (): Promise<PreparedBridgeWorkerAnnotationOutputInspection> =>
						inspectBridgeCommWorkerAnnotationOutput({
							command: props.command,
							productTransport,
							signal: props.signal,
						}),
		timeoutMilliseconds: props.timeoutMilliseconds,
	})
		.then((preparedInspection): void => {
			props.publishInspection(preparedInspection);
		})
		.catch((): void => {
			props.publishFailure(
				buildBridgeWorkerRuntimeCommandFailedHealthEvent({
					message: 'Bridge comm worker failed to inspect annotation output.',
					requestId: props.command.requestId,
				}),
			);
		});
}

export async function inspectBridgeCommWorkerAnnotationOutput(props: {
	readonly command: BridgeWorkerAnnotationOutputInspectCommand;
	readonly productTransport: BridgeProductTransportSession;
	readonly signal: AbortSignal;
}): Promise<PreparedBridgeWorkerAnnotationOutputInspection> {
	const expectedProductSurface = props.command.surface === 'fileView' ? 'file' : 'review';
	const result =
		props.command.surface === 'fileView'
			? await props.productTransport.call(
					'file.annotations.output.inspect',
					{ attemptId: props.command.attemptId },
					{ signal: props.signal },
				)
			: await props.productTransport.call(
					'review.annotations.output.inspect',
					{ attemptId: props.command.attemptId },
					{ signal: props.signal },
				);
	if (
		result.descriptor.attemptId !== props.command.attemptId ||
		result.descriptor.surface !== expectedProductSurface
	) {
		throw new Error('Annotation output descriptor does not match the inspection request.');
	}

	const terminal = await props.productTransport.openContent(result.descriptor, props.signal)
		.terminal;
	if (terminal.kind !== 'complete') {
		throw new Error('Annotation output content did not complete.');
	}
	if (
		terminal.descriptorId !== result.descriptor.descriptorId ||
		terminal.bytes.byteLength !== result.descriptor.declaredByteLength ||
		terminal.observedSha256 !== result.descriptor.expectedSha256
	) {
		throw new Error('Annotation output content identity did not match its descriptor.');
	}

	const prepared = prepareBridgeWorkerStructuredMessage({
		declaredFields: [{ fieldPath: ['exactBytes'], mode: 'transfer' }],
		message: {
			descriptor: result.descriptor,
			direction: 'serverWorkerToMain',
			exactBytes: terminal.bytes,
			kind: 'annotationOutputInspection',
			requestId: props.command.requestId,
			surface: props.command.surface,
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		},
	});
	bridgeWorkerAnnotationOutputInspectionEventSchema.parse(prepared.message);
	return prepared;
}

async function rejectUninstalledAnnotationOutputInspection(): Promise<never> {
	throw new Error('Bridge annotation output product transport is not installed.');
}
