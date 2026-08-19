import { describe, expect, test } from 'vitest';

import {
	BridgeCommWorkerSelectedFileContentOperationController,
	settleAcceptedSelectedFileRenderDisposition,
} from './bridge-comm-worker-selected-file-content-operation.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import { bridgeWorkerRenderDispositionReceiptSchema } from './bridge-worker-render-fulfillment.js';

describe('BridgeCommWorkerSelectedFileContentOperationController', () => {
	test('keeps one operation generation from selection through descriptor and render preparation', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();

		const selected = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });
		const descriptorContinuation = controller.admitSelection({
			itemId: 'file-1',
			selectionEpoch: 10,
		});
		const beganContent = controller.advance(selected.generation, 'preparingContent');
		const beganRender = controller.advance(selected.generation, 'preparingRender');

		expect(selected.phase).toBe('preparingDescriptor');
		expect(descriptorContinuation.generation).toBe(selected.generation);
		expect(beganContent).toBe(true);
		expect(beganRender).toBe(true);
		expect(controller.current).toMatchObject({
			generation: selected.generation,
			phase: 'preparingRender',
		});
	});

	test('rejects late predecessor transitions after selection replacement', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const predecessor = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });
		const successor = controller.admitSelection({ itemId: 'file-2', selectionEpoch: 11 });

		expect(controller.advance(predecessor.generation, 'preparingContent')).toBe(false);
		expect(controller.settle(predecessor.generation)).toBe(false);
		expect(controller.current).toEqual(successor);
		expect(controller.settle(successor.generation)).toBe(true);
		expect(controller.current).toBeNull();
	});

	test('binds the first source and supersedes when its derivation generation changes', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const selected = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });
		const bound = controller.bindSource({
			generation: selected.generation,
			workerDerivationEpoch: 7,
		});
		const successor = controller.bindSource({
			generation: selected.generation,
			workerDerivationEpoch: 8,
		});

		expect(bound).toMatchObject({
			generation: selected.generation,
			workerDerivationEpoch: 7,
		});
		expect(successor?.generation).not.toBe(selected.generation);
		expect(successor?.workerDerivationEpoch).toBe(8);
	});

	test('cancels descriptor wait when selection clears', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const current = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });

		expect(controller.cancel()).toEqual(current);
		expect(controller.current).toBeNull();
	});

	test('settles only the current item from an accepted terminal render receipt', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const current = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 11 });
		const currentReceipt = renderReceipt('current');
		controller.bindRenderReceipt({
			generation: current.generation,
			receiptIdentity: currentReceipt,
		});

		expect(
			controller.handleAcceptedRenderDisposition({
				receipt: { ...currentReceipt, attemptId: 'attempt-stale', disposition: 'painted' },
			}),
		).toBe('stale');
		expect(controller.current?.itemId).toBe('file-1');
		expect(
			controller.handleAcceptedRenderDisposition({
				receipt: { ...currentReceipt, disposition: 'applied' },
			}),
		).toBe('current');
		expect(controller.current?.phase).toBe('preparingRender');
		expect(
			controller.handleAcceptedRenderDisposition({
				receipt: { ...currentReceipt, disposition: 'painted' },
			}),
		).toBe('settled');
		expect(controller.current).toBeNull();
	});

	test('rejects a predecessor render receipt after the same item is reselected', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const predecessor = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });
		controller.bindRenderReceipt({
			generation: predecessor.generation,
			receiptIdentity: renderReceipt('predecessor'),
		});
		const successor = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 11 });

		expect(
			controller.handleAcceptedRenderDisposition({
				receipt: renderReceipt('predecessor', 'painted'),
			}),
		).toBe('stale');
		expect(controller.current).toEqual(successor);
	});

	test('retains last paint when an accepted render receipt rejects the replacement', () => {
		const controller = new BridgeCommWorkerSelectedFileContentOperationController();
		const store = createBridgeCommWorkerStore({
			contentItems: [],
			rows: [{ id: 'file-1', index: 0, parentId: null }],
			surface: 'file',
		});
		store.actions.applySelectedFact({ epoch: 10, itemId: 'file-1' });
		store.actions.applyContentReady({ contentCacheKey: 'file-content-key', itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 10, sequence: 1 });
		const receipt = bridgeWorkerRenderDispositionReceiptSchema.parse({
			attemptId: 'attempt-id',
			disposition: 'rejected',
			itemId: 'file-1',
			kind: 'render.disposition',
			paneSessionId: 'pane-session',
			publicationId: 'publication-id',
			publicationSequence: 1,
			reason: 'stale_attempt',
			receivedAtMilliseconds: 1,
			retryAtMilliseconds: 1,
			submissionId: 'submission-id',
			surface: 'file',
			windowKey: 'file-1',
			workerDerivationEpoch: 1,
			workerInstanceId: 'worker-instance',
		});
		const operation = controller.admitSelection({ itemId: 'file-1', selectionEpoch: 10 });
		controller.bindRenderReceipt({
			generation: operation.generation,
			receiptIdentity: receipt,
		});

		const result = settleAcceptedSelectedFileRenderDisposition({
			controller,
			createSequence: (): number => 2,
			receipt,
			store,
		});

		expect(result.settled).toBe(true);
		expect(result.terminalPatch).toMatchObject({
			kind: 'slicePatch',
			patches: [
				{
					itemId: 'file-1',
					operation: 'upsert',
					payload: { reason: 'descriptor_rejected', state: 'unavailable' },
					slice: 'contentAvailability',
				},
			],
		});
		expect(store.getState().paintReadyByItemId.get('file-1')).toBe('file-content-key');
	});
});

function renderReceipt(
	identitySuffix: string,
	disposition: 'queued' | 'applied' | 'painted' = 'queued',
): ReturnType<typeof bridgeWorkerRenderDispositionReceiptSchema.parse> {
	return bridgeWorkerRenderDispositionReceiptSchema.parse({
		attemptId: `attempt-${identitySuffix}`,
		disposition,
		itemId: 'file-1',
		kind: 'render.disposition',
		paneSessionId: 'pane-session',
		publicationId: `publication-${identitySuffix}`,
		publicationSequence: 1,
		receivedAtMilliseconds: 1,
		submissionId: `submission-${identitySuffix}`,
		surface: 'file',
		windowKey: `window-${identitySuffix}`,
		workerDerivationEpoch: 1,
		workerInstanceId: 'worker-instance',
	});
}
