import { bridgeWorkerRuntimeMessagesContainReadyRequest } from './bridge-comm-worker-runtime-health.js';
import type {
	BridgeWorkerRenderDispositionCommand,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerRenderDispositionReceipt } from './bridge-worker-render-fulfillment.js';

export function applyBridgeCommWorkerRenderDispositionRuntimeEffects(props: {
	readonly advanceRenderFulfillmentLifecycle: (
		surface: BridgeWorkerRenderDispositionReceipt['surface'],
	) => void;
	readonly command: BridgeWorkerRenderDispositionCommand;
	readonly currentFileOperationCorrelationId: () => string | null;
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly onFileOperationSettled: () => void;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly recordFileDisposition: (receipt: BridgeWorkerRenderDispositionReceipt) => void;
	readonly settleFileDisposition: (receipt: BridgeWorkerRenderDispositionReceipt) => {
		readonly settled: boolean;
		readonly terminalPatch: BridgeWorkerServerToMainMessage | null;
	};
}): void {
	if (
		props.command.receipts.some((receipt): boolean => receipt.surface === 'file') &&
		bridgeWorkerRuntimeMessagesContainReadyRequest({
			messages: props.messages,
			requestId: props.command.requestId,
		})
	) {
		for (const receipt of props.command.receipts) {
			if (receipt.surface !== 'file') continue;
			if (receipt.operationCorrelationId === props.currentFileOperationCorrelationId()) {
				props.recordFileDisposition(receipt);
			}
			const settlement = props.settleFileDisposition(receipt);
			if (settlement.terminalPatch !== null) props.publish(settlement.terminalPatch);
			if (settlement.settled) props.onFileOperationSettled();
		}
	}
	for (const surface of new Set(props.command.receipts.map((receipt) => receipt.surface))) {
		props.advanceRenderFulfillmentLifecycle(surface);
	}
}
