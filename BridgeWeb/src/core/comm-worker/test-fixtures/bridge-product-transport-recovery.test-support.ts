import { bridgeProductFileMetadataApplicationProtocol } from '../bridge-product-metadata-application-registry.js';
import type { BridgeProductControlRequest } from '../bridge-product-session-contracts.js';
import {
	createTransportHarness,
	emptyInterestHash,
	fileSourceAcceptedData,
	fileSourceConfiguration,
	metadataAccepted,
	subscriptionAccepted,
} from './bridge-product-transport-metadata.test-support.js';

export async function establishFileSubscription(
	harness: ReturnType<typeof createTransportHarness>,
): Promise<{
	readonly events: AsyncIterator<unknown>;
	readonly subscription: { cancel(): Promise<void>; readonly subscriptionId: string };
}> {
	const subscription = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
		interests: [],
		pathScope: [],
		source: fileSourceConfiguration(),
	});
	const events = subscription.events[Symbol.asyncIterator]();
	await harness.server.waitForMetadataStream();
	const request = harness.server.requiredMetadataRequest();
	const hash = emptyInterestHash('file.metadata');
	harness.server.emitMetadata(metadataAccepted(request, 0));
	harness.server.emitMetadata(
		subscriptionAccepted({
			epoch: 0,
			interestHash: hash,
			kind: 'file.metadata',
			request,
			streamSequence: 1,
			subscriptionId: subscription.subscriptionId,
		}),
	);
	harness.server.emitMetadata(
		fileSourceAcceptedData({
			epoch: 0,
			interestHash: hash,
			request,
			streamSequence: 2,
			subscriptionId: subscription.subscriptionId,
		}),
	);
	await events.next();
	await harness.server.waitForFrameAcknowledgementCount(3);
	return { subscription, events };
}

export function retainedResponse(
	request: Extract<BridgeProductControlRequest, { kind: 'workerSession.resync' }>,
): Response {
	return resyncResponse(
		request,
		request.activeSubscriptions.map((item) => ({ ...item, disposition: 'retained' as const })),
	);
}

export function resyncResponse(
	request: Extract<BridgeProductControlRequest, { kind: 'workerSession.resync' }>,
	reconciliation: readonly unknown[],
	metadataStreamSequenceBarrier = request.lastAcceptedStreamSequence,
): Response {
	return new Response(
		JSON.stringify({
			paneSessionId: request.paneSessionId,
			requestId: request.requestId,
			requestSequence: request.requestSequence,
			wireVersion: request.wireVersion,
			workerInstanceId: request.workerInstanceId,
			kind: 'resync.accepted',
			metadataStreamSequenceBarrier,
			nextExpectedRequestSequence: request.requestSequence + 1,
			reconciliation,
		}),
		{ status: 200 },
	);
}

export function observeSettlement(promise: Promise<unknown>, observe: () => void): void {
	void promise.then(observe, observe);
}
