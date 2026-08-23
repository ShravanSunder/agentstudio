import { runBridgeCommWorkerAnnotationOutputInspection } from './bridge-comm-worker-annotation-output-inspection.js';
import {
	completeBridgeCommWorkerProductControlSuccess,
	notifyBridgeCommWorkerProductControlFailure,
} from './bridge-comm-worker-product-control-completion.js';
import type { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import type { BridgeWorkerComparisonTargetsQueryRunner } from './bridge-comm-worker-review-comparison-target-query.js';
import type { BridgeCommWorkerReviewMetadataApplicator } from './bridge-comm-worker-review-metadata-applicator.js';
import { bridgeWorkerRuntimeProductControlCommandForMessage } from './bridge-comm-worker-runtime-command-routing.js';
import {
	bridgeCommWorkerProductControlFailureMessage,
	rejectUninstalledReviewMetadataInterestUpdate,
} from './bridge-comm-worker-runtime-defaults.js';
import {
	bridgeWorkerRuntimeMessageIsReadyRequest,
	bridgeWorkerRuntimeMessagesContainReadyRequest,
	buildBridgeWorkerRuntimeCommandFailedHealthEvent,
} from './bridge-comm-worker-runtime-health.js';
import type { BridgeCommWorkerProductControlSender } from './bridge-comm-worker-runtime-protocol-contracts.js';
import { sendBridgeCommWorkerActionWithTimeout } from './bridge-comm-worker-runtime-support.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export function dispatchBridgeCommWorkerRuntimeProductControl(props: {
	readonly activeReviewWorkerDerivationEpoch: number | null;
	readonly comparisonTargetsQueryRunner: BridgeWorkerComparisonTargetsQueryRunner;
	readonly getActiveComparisonTargetsRequestId: () => string | null;
	readonly mainCommand: BridgeWorkerMainToServerMessage;
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly paneWorkSignal: AbortSignal;
	readonly publish: (
		message: BridgeWorkerServerToMainMessage,
		transfer?: readonly Transferable[],
	) => void;
	readonly productControlTimeoutMilliseconds: number;
	readonly productController: BridgeCommWorkerProductController | null;
	readonly productTransport: BridgeProductTransportSession | undefined;
	readonly reviewMetadataApplicator: BridgeCommWorkerReviewMetadataApplicator | null;
	readonly sendProductControl: BridgeCommWorkerProductControlSender;
	readonly setActiveComparisonTargetsRequestId: (requestId: string | null) => void;
}): void {
	const productControlCommand = bridgeWorkerRuntimeProductControlCommandForMessage(
		props.mainCommand,
	);
	const metadataInterestUpdateCommand =
		props.mainCommand.command === 'metadataInterestUpdate' ? props.mainCommand : null;
	const deferredRequestId =
		metadataInterestUpdateCommand?.requestId ?? productControlCommand?.requestId ?? null;
	const shouldSendProductControl =
		productControlCommand !== null &&
		bridgeWorkerRuntimeMessagesContainReadyRequest({
			messages: props.messages,
			requestId: productControlCommand.requestId,
		});
	const shouldUpdateReviewMetadataInterests =
		metadataInterestUpdateCommand !== null &&
		bridgeWorkerRuntimeMessagesContainReadyRequest({
			messages: props.messages,
			requestId: metadataInterestUpdateCommand.requestId,
		});
	const immediateMessages =
		(shouldSendProductControl || shouldUpdateReviewMetadataInterests) && deferredRequestId !== null
			? props.messages.filter(
					(message): boolean =>
						!bridgeWorkerRuntimeMessageIsReadyRequest({ message, requestId: deferredRequestId }),
				)
			: props.messages;
	for (const message of immediateMessages) props.publish(message);
	if (
		productControlCommand?.command.method === 'review.comparisonTargets.query' &&
		!shouldSendProductControl
	)
		props.comparisonTargetsQueryRunner.fail(productControlCommand.requestId);
	if (props.mainCommand.command === 'annotationOutputInspect' && props.messages.length === 0)
		runBridgeCommWorkerAnnotationOutputInspection({
			command: props.mainCommand,
			publishFailure: props.publish,
			publishInspection: (inspection): void =>
				props.publish(inspection.message, inspection.transferList),
			productTransport: props.productTransport,
			signal: props.paneWorkSignal,
			timeoutMilliseconds: props.productControlTimeoutMilliseconds,
		});
	if (productControlCommand !== null && shouldSendProductControl) {
		if (productControlCommand.command.method === 'review.comparisonTargets.query') {
			props.comparisonTargetsQueryRunner.abort();
			props.setActiveComparisonTargetsRequestId(productControlCommand.requestId);
		}
		void sendBridgeCommWorkerActionWithTimeout({
			send: (): Promise<unknown> => props.sendProductControl(productControlCommand.command),
			timeoutMilliseconds: props.productControlTimeoutMilliseconds,
		})
			.then((actionResult): void => {
				if (
					productControlCommand.command.method === 'review.comparisonTargets.query' &&
					props.getActiveComparisonTargetsRequestId() === productControlCommand.requestId
				)
					void props.comparisonTargetsQueryRunner.run(
						productControlCommand.requestId,
						actionResult,
					);
				completeBridgeCommWorkerProductControlSuccess({
					actionResult,
					command: productControlCommand.command,
					mainCommand: props.mainCommand,
					messages: props.messages,
					publish: props.publish,
					requestId: productControlCommand.requestId,
					reviewSuccessorSettlementOwner: props.reviewMetadataApplicator,
					reviewWorkerDerivationEpoch: props.activeReviewWorkerDerivationEpoch,
				});
			})
			.catch((): void => {
				if (
					productControlCommand.command.method === 'review.comparisonTargets.query' &&
					props.getActiveComparisonTargetsRequestId() === productControlCommand.requestId
				) {
					props.comparisonTargetsQueryRunner.abort();
					props.comparisonTargetsQueryRunner.fail(productControlCommand.requestId);
					props.setActiveComparisonTargetsRequestId(null);
				}
				props.publish(
					buildBridgeWorkerRuntimeCommandFailedHealthEvent({
						requestId: productControlCommand.requestId,
						message: bridgeCommWorkerProductControlFailureMessage({
							command: productControlCommand.command,
						}),
						...(productControlCommand.command.method === 'bridge.activeViewerMode.update'
							? { deliveryStatus: 'unknownAfterDispatch' }
							: {}),
					}),
				);
				notifyBridgeCommWorkerProductControlFailure({
					command: productControlCommand.command,
					reviewSuccessorSettlementOwner: props.reviewMetadataApplicator,
					reviewWorkerDerivationEpoch: props.activeReviewWorkerDerivationEpoch,
				});
			});
	}
	if (metadataInterestUpdateCommand !== null && shouldUpdateReviewMetadataInterests) {
		const activeProductController = props.productController;
		void sendBridgeCommWorkerActionWithTimeout({
			send:
				activeProductController === null
					? rejectUninstalledReviewMetadataInterestUpdate
					: (): Promise<void> =>
							activeProductController.updateReviewMetadataInterests(
								metadataInterestUpdateCommand.request,
							),
			timeoutMilliseconds: props.productControlTimeoutMilliseconds,
		})
			.then((): void => {
				for (const message of props.messages)
					if (
						bridgeWorkerRuntimeMessageIsReadyRequest({
							message,
							requestId: metadataInterestUpdateCommand.requestId,
						})
					)
						props.publish(message);
			})
			.catch((): void =>
				props.publish(
					buildBridgeWorkerRuntimeCommandFailedHealthEvent({
						requestId: metadataInterestUpdateCommand.requestId,
						message: 'Bridge comm worker failed to update Review metadata interests.',
					}),
				),
			);
	}
}
