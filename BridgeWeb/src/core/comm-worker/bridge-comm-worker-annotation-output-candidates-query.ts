import { buildBridgeWorkerRuntimeCommandFailedHealthEvent } from './bridge-comm-worker-runtime-health.js';
import { sendBridgeCommWorkerActionWithTimeout } from './bridge-comm-worker-runtime-support.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	bridgeWorkerAnnotationOutputCandidatesPageEventSchema,
	type BridgeWorkerAnnotationOutputCandidatesPageEvent,
	type BridgeWorkerAnnotationOutputCandidatesQueryCommand,
} from './bridge-worker-annotation-contracts.js';

export function runBridgeCommWorkerAnnotationOutputCandidatesQuery(props: {
	readonly command: BridgeWorkerAnnotationOutputCandidatesQueryCommand;
	readonly productTransport: BridgeProductTransportSession | undefined;
	readonly publishFailure: (
		failure: ReturnType<typeof buildBridgeWorkerRuntimeCommandFailedHealthEvent>,
	) => void;
	readonly publishPage: (page: BridgeWorkerAnnotationOutputCandidatesPageEvent) => void;
	readonly signal: AbortSignal;
	readonly timeoutMilliseconds: number;
}): void {
	const productTransport = props.productTransport;
	void sendBridgeCommWorkerActionWithTimeout({
		send:
			productTransport === undefined
				? rejectUninstalledCandidateQuery
				: (): Promise<BridgeWorkerAnnotationOutputCandidatesPageEvent> =>
						queryBridgeCommWorkerAnnotationOutputCandidates({
							command: props.command,
							productTransport,
							signal: props.signal,
						}),
		timeoutMilliseconds: props.timeoutMilliseconds,
	})
		.then(props.publishPage)
		.catch((): void => {
			props.publishFailure(
				buildBridgeWorkerRuntimeCommandFailedHealthEvent({
					message: 'Bridge comm worker failed to query annotation output candidates.',
					requestId: props.command.requestId,
				}),
			);
		});
}

export async function queryBridgeCommWorkerAnnotationOutputCandidates(props: {
	readonly command: BridgeWorkerAnnotationOutputCandidatesQueryCommand;
	readonly productTransport: BridgeProductTransportSession;
	readonly signal: AbortSignal;
}): Promise<BridgeWorkerAnnotationOutputCandidatesPageEvent> {
	const page =
		props.command.surface === 'fileView'
			? await props.productTransport.call(
					'file.annotations.output.candidates.query',
					props.command.query,
					{ signal: props.signal },
				)
			: await props.productTransport.call(
					'review.annotations.output.candidates.query',
					props.command.query,
					{ signal: props.signal },
				);
	return bridgeWorkerAnnotationOutputCandidatesPageEventSchema.parse({
		direction: 'serverWorkerToMain',
		kind: 'annotationOutputCandidatesPage',
		page,
		requestId: props.command.requestId,
		surface: props.command.surface,
		transferDescriptors: [],
		wireVersion: 1,
	});
}

async function rejectUninstalledCandidateQuery(): Promise<never> {
	throw new Error('Bridge annotation output candidate product transport is not installed.');
}
