import { describe, expect, test } from 'vitest';

import {
	createBridgeCodeViewProgrammaticRevealGate,
	skipBridgeCodeViewProgrammaticRevealIfNeeded,
	shouldSkipBridgeCodeViewProgrammaticReveal,
} from './bridge-code-view-programmatic-reveal-gate.js';

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

	test('allows a distinct selection to finish retargeting across an older active scroll', () => {
		let isScrollActive = true;
		let lastRevealedItemId = 'previous-item';
		const gate = createBridgeCodeViewProgrammaticRevealGate({
			isScrollActive: (): boolean => isScrollActive,
			lastRevealedItemId: (): string => lastRevealedItemId,
			onProgrammaticRevealSkipped: (): void => {},
		});

		gate.recordUserScrollIntent();
		expect(
			gate.beginSelectionReveal({
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
		lastRevealedItemId = 'clicked-item';
		gate.transitionSelectionReveal({
			phase: 'retargeting',
			selectionScrollKey: 'source:1:clicked-item',
		});

		expect(
			gate.shouldSkipProgrammaticReveal({
				revealIntent: 'retarget',
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(false);

		isScrollActive = false;
	});

	test('cancels the active selection reveal when a newer user scroll begins', () => {
		const gate = createBridgeCodeViewProgrammaticRevealGate({
			isScrollActive: (): boolean => true,
			lastRevealedItemId: (): string => 'previous-item',
			onProgrammaticRevealSkipped: (): void => {},
		});

		gate.recordUserScrollIntent();
		expect(
			gate.beginSelectionReveal({
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
		gate.transitionSelectionReveal({
			phase: 'awaiting-hydration',
			selectionScrollKey: 'source:1:clicked-item',
		});
		gate.recordUserScrollIntent();
		gate.transitionSelectionReveal({
			phase: 'retargeting',
			selectionScrollKey: 'source:1:clicked-item',
		});

		expect(
			gate.shouldSkipProgrammaticReveal({
				revealIntent: 'retarget',
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
	});

	test('does not re-open a settled reveal or admit a stale selection identity', () => {
		const gate = createBridgeCodeViewProgrammaticRevealGate({
			isScrollActive: (): boolean => false,
			lastRevealedItemId: (): string | null => null,
			onProgrammaticRevealSkipped: (): void => {},
		});

		expect(
			gate.beginSelectionReveal({
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
		gate.transitionSelectionReveal({
			phase: 'settled',
			selectionScrollKey: 'source:1:clicked-item',
		});

		expect(
			gate.shouldSkipProgrammaticReveal({
				revealIntent: 'retarget',
				selectionScrollKey: 'source:1:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
		expect(
			gate.shouldSkipProgrammaticReveal({
				revealIntent: 'retarget',
				selectionScrollKey: 'source:2:clicked-item',
				targetItemId: 'clicked-item',
			}),
		).toBe(true);
	});

	test('does not let a stale skipped reveal clear the newer selection reveal identity', () => {
		const newerReveal = {
			itemId: 'newer-item',
			revealedAtMilliseconds: 10,
			selectionScrollKey: 'source:1:newer-item',
		};
		const recentRevealRef = { current: newerReveal };
		const settledRevealRef = { current: null as string | null };
		let skippedCleanupCount = 0;
		const gate = createBridgeCodeViewProgrammaticRevealGate({
			isScrollActive: (): boolean => false,
			lastRevealedItemId: (): string => 'newer-item',
			onProgrammaticRevealSkipped: (): void => {
				skippedCleanupCount += 1;
			},
		});
		gate.beginSelectionReveal({
			selectionScrollKey: newerReveal.selectionScrollKey,
			targetItemId: newerReveal.itemId,
		});

		const didSkip = skipBridgeCodeViewProgrammaticRevealIfNeeded({
			currentSelectionScrollKeyRef: { current: newerReveal.selectionScrollKey },
			programmaticRevealGate: gate,
			recentInstantSelectionRevealRef: recentRevealRef,
			revealIntent: 'retarget',
			selectionScrollKey: 'source:1:stale-item',
			settledInstantSelectionRevealKeyRef: settledRevealRef,
			targetItemId: 'stale-item',
		});

		expect(didSkip).toBe(true);
		expect(recentRevealRef.current).toEqual(newerReveal);
		expect(settledRevealRef.current).toBeNull();
		expect(skippedCleanupCount).toBe(0);
	});
});
