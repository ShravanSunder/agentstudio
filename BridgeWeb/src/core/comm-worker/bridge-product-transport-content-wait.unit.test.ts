import { expect, test } from 'vitest';

import { waitForCondition } from './test-fixtures/bridge-product-transport-content.test-support.js';

test('content proof waits for a scheduled protocol event beyond one hundred event-loop turns', async () => {
	// Arrange: scheduling turns are not elapsed-time or protocol completion guarantees.
	let eventReceived = false;
	let cancelled = false;
	let remainingTurns = 150;
	const deliverEvent = (): void => {
		if (cancelled) return;
		remainingTurns -= 1;
		if (remainingTurns === 0) eventReceived = true;
		else setImmediate(deliverEvent);
	};
	setImmediate(deliverEvent);
	try {
		// Act
		await waitForCondition(() => eventReceived);
		// Assert
		expect(eventReceived).toBe(true);
	} finally {
		cancelled = true;
	}
});
