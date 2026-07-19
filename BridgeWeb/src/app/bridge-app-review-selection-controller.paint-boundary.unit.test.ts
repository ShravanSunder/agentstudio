import { describe, expect, test } from 'vitest';

import {
	commitBridgeReviewPresentationSelection,
	createBridgeReviewPostPaintSelectionFrameScheduler,
} from './bridge-app-review-selection-controller.js';

describe('Bridge review selection post-paint intent scheduling', () => {
	test('commits locally and submits only the latest intent after two renderer frames', async () => {
		// Arrange
		const animationFrames = createControlledAnimationFrames();
		const calls: string[] = [];
		const diagnosticStages: string[] = [];
		const isActive = true;
		let selectedItemId: string | null = null;
		const selectIntentScheduler = createBridgeReviewPostPaintSelectionFrameScheduler({
			cancelAnimationFrame: animationFrames.cancelAnimationFrame,
			onPostPaintSelection: (itemId, selectedSource): void => {
				calls.push(`intent:${itemId}:${selectedSource}`);
			},
			onSelectionIntentDiagnosticStage: (stage): void => {
				diagnosticStages.push(stage);
			},
			isPendingIntentCurrent: (itemId): boolean => isActive && selectedItemId === itemId,
			requestAnimationFrame: animationFrames.requestAnimationFrame,
		});
		const selectItem = (
			itemId: string,
			selectedSource: 'keyboard' | 'programmatic' | 'user',
		): boolean =>
			commitBridgeReviewPresentationSelection({
				commitLocalSelection: (nextItemId): void => {
					selectedItemId = nextItemId;
					calls.push(`local:${nextItemId}`);
				},
				currentSelectedItemId: selectedItemId,
				hasReviewItem: (): boolean => true,
				isActive,
				itemId,
				scheduleSelectIntentAfterLocalPaint: selectIntentScheduler.schedule,
				selectedSource,
			});

		// Act
		expect(selectItem('review-item-a', 'user')).toBe(true);

		// Assert
		expect(calls).toEqual(['local:review-item-a']);
		expect(animationFrames.pendingFrameCount()).toBe(1);
		await Promise.resolve();
		expect(calls).toEqual(['local:review-item-a']);

		// Act
		expect(selectItem('review-item-b', 'keyboard')).toBe(true);
		animationFrames.flushNextFrame();
		animationFrames.flushNextFrame();

		// Assert
		expect(calls).toEqual([
			'local:review-item-a',
			'local:review-item-b',
			'intent:review-item-b:keyboard',
		]);
		expect(diagnosticStages).toEqual([
			'selection_scheduled',
			'selection_scheduled',
			'selection_first_frame_reached',
			'selection_second_frame_reached',
			'selection_submitted',
		]);
	});

	test('drops a pending intent when the surface is inactive or local selection moved', () => {
		// Arrange
		const animationFrames = createControlledAnimationFrames();
		const diagnosticStages: string[] = [];
		const emittedItemIds: string[] = [];
		let isActive = true;
		let selectedItemId: string | null = 'review-item-a';
		const selectIntentScheduler = createBridgeReviewPostPaintSelectionFrameScheduler({
			cancelAnimationFrame: animationFrames.cancelAnimationFrame,
			onPostPaintSelection: (itemId): void => {
				emittedItemIds.push(itemId);
			},
			onSelectionIntentDiagnosticStage: (stage): void => {
				diagnosticStages.push(stage);
			},
			isPendingIntentCurrent: (itemId): boolean => isActive && selectedItemId === itemId,
			requestAnimationFrame: animationFrames.requestAnimationFrame,
		});

		// Act
		selectIntentScheduler.schedule('review-item-a', 'user');
		isActive = false;
		animationFrames.flushNextFrame();
		animationFrames.flushNextFrame();
		isActive = true;
		selectIntentScheduler.schedule('review-item-a', 'user');
		animationFrames.flushNextFrame();
		selectedItemId = 'review-item-b';
		animationFrames.flushNextFrame();

		// Assert
		expect(emittedItemIds).toEqual([]);
		expect(diagnosticStages).toEqual([
			'selection_scheduled',
			'selection_first_frame_reached',
			'selection_second_frame_reached',
			'selection_dropped',
			'selection_scheduled',
			'selection_first_frame_reached',
			'selection_second_frame_reached',
			'selection_dropped',
		]);
	});

	test('cancels the pending animation frame during unmount cleanup', () => {
		// Arrange
		const animationFrames = createControlledAnimationFrames();
		const diagnosticStages: string[] = [];
		const emittedItemIds: string[] = [];
		const selectIntentScheduler = createBridgeReviewPostPaintSelectionFrameScheduler({
			cancelAnimationFrame: animationFrames.cancelAnimationFrame,
			onPostPaintSelection: (itemId): void => {
				emittedItemIds.push(itemId);
			},
			onSelectionIntentDiagnosticStage: (stage): void => {
				diagnosticStages.push(stage);
			},
			isPendingIntentCurrent: (): boolean => true,
			requestAnimationFrame: animationFrames.requestAnimationFrame,
		});
		selectIntentScheduler.schedule('review-item-a', 'user');

		// Act
		selectIntentScheduler.cancelPending();

		// Assert
		expect(animationFrames.pendingFrameCount()).toBe(0);
		expect(animationFrames.cancelledFrameIds()).toEqual([1]);
		expect(emittedItemIds).toEqual([]);
		expect(diagnosticStages).toEqual(['selection_scheduled']);
	});
});

interface ControlledAnimationFrames {
	readonly cancelAnimationFrame: (frameId: number) => void;
	readonly cancelledFrameIds: () => readonly number[];
	readonly flushNextFrame: () => void;
	readonly pendingFrameCount: () => number;
	readonly requestAnimationFrame: (callback: FrameRequestCallback) => number;
}

function createControlledAnimationFrames(): ControlledAnimationFrames {
	let nextFrameId = 1;
	const callbacksByFrameId = new Map<number, FrameRequestCallback>();
	const cancelledFrameIds: number[] = [];
	return {
		cancelAnimationFrame: (frameId): void => {
			cancelledFrameIds.push(frameId);
			callbacksByFrameId.delete(frameId);
		},
		cancelledFrameIds: (): readonly number[] => cancelledFrameIds,
		flushNextFrame: (): void => {
			const nextEntry = callbacksByFrameId.entries().next();
			if (nextEntry.done) {
				throw new Error('Expected a pending animation frame.');
			}
			const [frameId, callback] = nextEntry.value;
			callbacksByFrameId.delete(frameId);
			callback(16.67);
		},
		pendingFrameCount: (): number => callbacksByFrameId.size,
		requestAnimationFrame: (callback): number => {
			const frameId = nextFrameId;
			nextFrameId += 1;
			callbacksByFrameId.set(frameId, callback);
			return frameId;
		},
	};
}
