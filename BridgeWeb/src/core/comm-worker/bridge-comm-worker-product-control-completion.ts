import { buildBridgeWorkerReviewPublicationInstallAdmissionEvent } from './bridge-comm-worker-protocol.js';
import { bridgeWorkerRuntimeMessageIsReadyRequest } from './bridge-comm-worker-runtime-health.js';
import { bridgeProductReviewPublicationInstallAdmissionResultSchema } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';

export interface PublishBridgeCommWorkerProductControlCompletionProps {
	readonly actionResult: unknown;
	readonly command: BridgeProductControlCommand;
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly requestId: string;
}

export function publishBridgeCommWorkerProductControlCompletion(
	props: PublishBridgeCommWorkerProductControlCompletionProps,
): void {
	if (props.command.method === 'review.publication.install.admit') {
		const admissionResult = bridgeProductReviewPublicationInstallAdmissionResultSchema.parse(
			props.actionResult,
		);
		props.publish(
			buildBridgeWorkerReviewPublicationInstallAdmissionEvent({
				candidatePublicationId: props.command.params.candidatePublicationId,
				requestId: props.requestId,
				status: admissionResult.status,
			}),
		);
		return;
	}

	for (const message of props.messages) {
		if (
			bridgeWorkerRuntimeMessageIsReadyRequest({
				message,
				requestId: props.requestId,
			})
		) {
			props.publish(message);
		}
	}
}
