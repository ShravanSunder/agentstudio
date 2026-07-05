import { describe, expect, test } from 'vitest';

import { shouldSkipBridgeCodeViewProgrammaticReveal } from './bridge-code-view-programmatic-reveal-gate.js';

describe('Bridge CodeView programmatic reveal gate', () => {
	test('skips same-item reveal reassertions while user scroll is active', () => {
		expect(
			shouldSkipBridgeCodeViewProgrammaticReveal({
				isScrollActive: true,
				lastRevealedItemId: 'selected-item',
				revealIntent: 'selection-effect',
				targetItemId: 'selected-item',
			}),
		).toBe(true);
	});

	test('allows a fresh selected item command while user scroll is active', () => {
		expect(
			shouldSkipBridgeCodeViewProgrammaticReveal({
				isScrollActive: true,
				lastRevealedItemId: 'previous-item',
				revealIntent: 'selection-effect',
				targetItemId: 'clicked-item',
			}),
		).toBe(false);
	});

	test('skips hydration reassertions while user scroll is active', () => {
		expect(
			shouldSkipBridgeCodeViewProgrammaticReveal({
				isScrollActive: true,
				lastRevealedItemId: 'selected-item',
				revealIntent: 'hydration-reissue',
				targetItemId: 'selected-item',
			}),
		).toBe(true);
	});
});
