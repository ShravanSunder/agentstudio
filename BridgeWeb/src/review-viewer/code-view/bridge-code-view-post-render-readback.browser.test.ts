import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderFulfillmentCoordinator } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { makeReviewPublication } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.test-support.js';
import type { BridgeWorkerRenderSourceCorrelation } from '../../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRenderDispositionReceipt } from '../../core/comm-worker/bridge-worker-render-fulfillment.js';
import { observeBridgeCodeViewRenderFulfillment } from './bridge-code-view-render-fulfillment.js';
import { bridgeCodeViewItemFromWorkerPreparedItem } from './bridge-code-view-worker-prepared-items.js';

describe('Bridge CodeView post-render readback', () => {
	test('uses the authoritative post-render node when the CodeView handle is unavailable', async () => {
		// Arrange
		const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
		const pendingAnimationFrames: FrameRequestCallback[] = [];
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (): void => {},
			nowMilliseconds: (): number => 1_000,
			requestAnimationFrame: (callback): number => {
				pendingAnimationFrames.push(callback);
				return 1;
			},
			sendDisposition: (receipt): void => {
				dispositions.push(receipt);
			},
		});
		const sourceCorrelation = {
			descriptorId: 'descriptor-direct-post-render-node',
			itemId: 'direct-post-render-node',
			observedSha256: 'a'.repeat(64),
			position: 'whole',
			requestId: 'request-direct-post-render-node',
			role: 'head',
			sourceGeneration: 1,
			sourceIdentity: 'source-direct-post-render-node',
		} satisfies BridgeWorkerRenderSourceCorrelation;
		const publication = makeReviewPublication({
			itemId: sourceCorrelation.itemId,
			publicationSequence: 1,
			sourceCorrelations: [sourceCorrelation],
		});
		const publicationItem = publication.job.payload.item;
		const exactItem = bridgeCodeViewItemFromWorkerPreparedItem(publicationItem);
		if (exactItem?.type !== 'diff') {
			throw new Error('Expected a main-readable Review diff item.');
		}
		Object.assign(exactItem.bridgeMetadata, { lineCount: 0 });
		Object.assign(exactItem.fileDiff, { additionLines: [], deletionLines: [] });
		const renderedElement = document.createElement('div');
		document.body.append(renderedElement);
		renderFulfillmentCoordinator.acceptPublication(publication);
		renderFulfillmentCoordinator.bindPublicationItem({
			finalItem: exactItem,
			publicationItem,
			residency: 'replaced',
		});
		renderFulfillmentCoordinator.markPublicationQueued(publication);

		try {
			// Act
			observeBridgeCodeViewRenderFulfillment({
				contextItem: exactItem,
				getCodeViewHandle: (): null => null,
				itemId: exactItem.id,
				phase: 'update',
				renderedElement,
				renderFulfillmentCoordinator,
				selectedCodeViewItem: exactItem,
				visibleCodeViewItems: undefined,
			});

			// Assert
			expect(dispositions.map((receipt) => receipt.disposition)).toEqual(['queued', 'applied']);
			expect(pendingAnimationFrames).toHaveLength(1);
			pendingAnimationFrames[0]?.(1_001);
			expect(dispositions.map((receipt) => receipt.disposition)).toEqual([
				'queued',
				'applied',
				'painted',
			]);
			expect(
				renderedElement.getAttribute('data-bridge-painted-source-correlations'),
			).not.toBeNull();
			await Promise.resolve();
			expect(dispositions).toHaveLength(3);
		} finally {
			renderedElement.remove();
			renderFulfillmentCoordinator.dispose();
		}
	});
});
