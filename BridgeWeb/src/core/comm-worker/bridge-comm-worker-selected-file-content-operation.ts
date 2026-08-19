import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerSlicePatchEvent } from './bridge-worker-contracts.js';
import type {
	BridgeWorkerRenderDispositionReceipt,
	BridgeWorkerRenderReceiptIdentity,
} from './bridge-worker-render-fulfillment.js';

export type BridgeSelectedFileContentOperationPhase =
	| 'preparingDescriptor'
	| 'preparingContent'
	| 'preparingRender';

export type BridgeSelectedFileContentOperation = {
	readonly generation: number;
	readonly itemId: string;
	readonly renderReceiptIdentity: BridgeWorkerRenderReceiptIdentity | null;
	readonly selectionEpoch: number;
	readonly workerDerivationEpoch: number | null;
	readonly phase: BridgeSelectedFileContentOperationPhase;
};

export class BridgeCommWorkerSelectedFileContentOperationController {
	private currentOperation: BridgeSelectedFileContentOperation | null = null;
	private nextGeneration = 0;

	get current(): BridgeSelectedFileContentOperation | null {
		return this.currentOperation;
	}

	admitSelection(props: {
		readonly itemId: string;
		readonly selectionEpoch: number;
	}): BridgeSelectedFileContentOperation {
		if (
			this.currentOperation?.itemId === props.itemId &&
			this.currentOperation.selectionEpoch === props.selectionEpoch
		) {
			return this.currentOperation;
		}
		this.nextGeneration += 1;
		this.currentOperation = {
			generation: this.nextGeneration,
			itemId: props.itemId,
			phase: 'preparingDescriptor',
			renderReceiptIdentity: null,
			selectionEpoch: props.selectionEpoch,
			workerDerivationEpoch: null,
		};
		return this.currentOperation;
	}

	bindSource(props: {
		readonly generation: number;
		readonly workerDerivationEpoch: number;
	}): BridgeSelectedFileContentOperation | null {
		const currentOperation = this.currentOperation;
		if (currentOperation?.generation !== props.generation) return null;
		if (currentOperation.workerDerivationEpoch === props.workerDerivationEpoch) {
			return currentOperation;
		}
		if (currentOperation.workerDerivationEpoch === null) {
			this.currentOperation = {
				...currentOperation,
				workerDerivationEpoch: props.workerDerivationEpoch,
			};
			return this.currentOperation;
		}
		this.nextGeneration += 1;
		this.currentOperation = {
			generation: this.nextGeneration,
			itemId: currentOperation.itemId,
			phase: 'preparingDescriptor',
			renderReceiptIdentity: null,
			selectionEpoch: currentOperation.selectionEpoch,
			workerDerivationEpoch: props.workerDerivationEpoch,
		};
		return this.currentOperation;
	}

	advance(
		generation: number,
		phase: Exclude<BridgeSelectedFileContentOperationPhase, 'preparingDescriptor'>,
	): boolean {
		if (this.currentOperation?.generation !== generation) return false;
		this.currentOperation = { ...this.currentOperation, phase };
		return true;
	}

	bindRenderReceipt(props: {
		readonly generation: number;
		readonly receiptIdentity: BridgeWorkerRenderReceiptIdentity;
	}): boolean {
		if (this.currentOperation?.generation !== props.generation) return false;
		this.currentOperation = {
			...this.currentOperation,
			phase: 'preparingRender',
			renderReceiptIdentity: Object.freeze({ ...props.receiptIdentity }),
		};
		return true;
	}

	settle(generation: number): boolean {
		if (this.currentOperation?.generation !== generation) return false;
		this.currentOperation = null;
		return true;
	}

	handleAcceptedRenderDisposition(props: {
		readonly receipt: BridgeWorkerRenderDispositionReceipt;
	}): 'current' | 'settled' | 'stale' {
		const currentOperation = this.currentOperation;
		if (
			currentOperation === null ||
			currentOperation.renderReceiptIdentity === null ||
			!renderReceiptMatchesIdentity(props.receipt, currentOperation.renderReceiptIdentity)
		) {
			return 'stale';
		}
		if (props.receipt.disposition === 'queued' || props.receipt.disposition === 'applied') {
			this.advance(currentOperation.generation, 'preparingRender');
			return 'current';
		}
		this.settle(currentOperation.generation);
		return 'settled';
	}

	cancel(): BridgeSelectedFileContentOperation | null {
		const cancelledOperation = this.currentOperation;
		this.currentOperation = null;
		return cancelledOperation;
	}
}

export function settleAcceptedSelectedFileRenderDisposition(props: {
	readonly controller: BridgeCommWorkerSelectedFileContentOperationController;
	readonly createSequence: () => number;
	readonly receipt: BridgeWorkerRenderDispositionReceipt;
	readonly store: BridgeCommWorkerStore | null;
}): { readonly settled: boolean; readonly terminalPatch: BridgeWorkerSlicePatchEvent | null } {
	const settlement = props.controller.handleAcceptedRenderDisposition({
		receipt: props.receipt,
	});
	if (settlement !== 'settled') return { settled: false, terminalPatch: null };
	if (
		props.store === null ||
		(props.receipt.disposition !== 'rejected' && props.receipt.disposition !== 'superseded')
	) {
		return { settled: true, terminalPatch: null };
	}
	props.store.actions.applyContentTerminalAvailability({
		itemId: props.receipt.itemId,
		reason: 'descriptor_rejected',
		sourceEpoch: props.store.getState().selectedEpoch,
		state: 'unavailable',
	});
	return {
		settled: true,
		terminalPatch: props.store.actions.takePendingSlicePatchEvent({
			epoch: props.store.getState().selectedEpoch,
			sequence: props.createSequence(),
		}),
	};
}

function renderReceiptMatchesIdentity(
	receipt: BridgeWorkerRenderDispositionReceipt,
	identity: BridgeWorkerRenderReceiptIdentity,
): boolean {
	return (
		receipt.attemptId === identity.attemptId &&
		receipt.itemId === identity.itemId &&
		receipt.paneSessionId === identity.paneSessionId &&
		receipt.publicationId === identity.publicationId &&
		receipt.publicationSequence === identity.publicationSequence &&
		receipt.submissionId === identity.submissionId &&
		receipt.surface === identity.surface &&
		receipt.windowKey === identity.windowKey &&
		receipt.workerDerivationEpoch === identity.workerDerivationEpoch &&
		receipt.workerInstanceId === identity.workerInstanceId
	);
}
