import { describe, expect, test } from 'vitest';

import { createBridgeCodeViewPostRenderVisibleInterestPublisher } from './bridge-code-view-post-render-visible-interest.js';

describe('Bridge CodeView post-render visible-interest publisher', () => {
	test('coalesces one Pierre render into one settled-window publication', () => {
		// Arrange
		const microtasks: Array<() => void> = [];
		let publicationCount = 0;
		const publisher = createBridgeCodeViewPostRenderVisibleInterestPublisher({
			publishSettledWindow: (): void => {
				publicationCount += 1;
			},
			queueMicrotask: (callback): void => {
				microtasks.push(callback);
			},
		});

		// Act
		publisher.schedule();
		publisher.schedule();
		publisher.schedule();

		// Assert
		expect(microtasks).toHaveLength(1);
		expect(publicationCount).toBe(0);
		microtasks[0]?.();
		expect(publicationCount).toBe(1);
	});

	test('cancels a queued publication when the CodeView unmounts', () => {
		// Arrange
		const microtasks: Array<() => void> = [];
		let publicationCount = 0;
		const publisher = createBridgeCodeViewPostRenderVisibleInterestPublisher({
			publishSettledWindow: (): void => {
				publicationCount += 1;
			},
			queueMicrotask: (callback): void => {
				microtasks.push(callback);
			},
		});

		// Act
		publisher.schedule();
		publisher.cancel();
		microtasks[0]?.();

		// Assert
		expect(publicationCount).toBe(0);
	});
});
