import { describe, expect, test } from 'vitest';

import { createBridgeCodeViewPostRenderVisibleInterestPublisher } from './bridge-code-view-post-render-visible-interest.js';

describe('Bridge CodeView post-render visible-interest publisher in Browser Mode', () => {
	test('publishes through the production browser microtask scheduler without an illegal invocation', async () => {
		// Arrange
		let publicationCount = 0;
		const publisher = createBridgeCodeViewPostRenderVisibleInterestPublisher({
			publishSettledWindow: (): void => {
				publicationCount += 1;
			},
			queueMicrotask: (callback): void => {
				globalThis.queueMicrotask(callback);
			},
		});

		// Act
		publisher.schedule();
		await Promise.resolve();

		// Assert
		expect(publicationCount).toBe(1);
	});
});
