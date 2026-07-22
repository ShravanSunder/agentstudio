import { describe, expect, test } from 'vitest';

import { createBridgeCodeViewVisibleInterestPublisher } from './bridge-code-view-visible-interest-publisher.js';

describe('Bridge CodeView visible-interest scroll publisher', () => {
	test('publishes on scroll start, throttles during continuous scroll, and publishes at idle', () => {
		let nowMilliseconds = 0;
		const publishTimes: number[] = [];
		const timeouts = new Map<number, () => void>();
		let nextTimeoutId = 1;
		const publisher = createBridgeCodeViewVisibleInterestPublisher({
			clearTimeout: (timeoutId: number): void => {
				timeouts.delete(timeoutId);
			},
			now: (): number => nowMilliseconds,
			publish: (): void => {
				publishTimes.push(nowMilliseconds);
			},
			setTimeout: (callback: () => void): number => {
				const timeoutId = nextTimeoutId;
				nextTimeoutId += 1;
				timeouts.set(timeoutId, (): void => {
					timeouts.delete(timeoutId);
					callback();
				});
				return timeoutId;
			},
			throttleMilliseconds: 120,
		});

		publisher.publishDuringScroll();
		nowMilliseconds = 40;
		publisher.publishDuringScroll();
		nowMilliseconds = 80;
		publisher.publishDuringScroll();

		expect(publishTimes).toEqual([0]);
		expect(timeouts.size).toBe(1);

		nowMilliseconds = 120;
		timeouts.values().next().value?.();
		nowMilliseconds = 160;
		publisher.publishDuringScroll();

		expect(publishTimes).toEqual([0, 120]);
		expect(timeouts.size).toBe(1);

		nowMilliseconds = 180;
		publisher.publishAtScrollIdle();

		expect(publishTimes).toEqual([0, 120, 180]);
		expect(timeouts.size).toBe(0);
	});
});
