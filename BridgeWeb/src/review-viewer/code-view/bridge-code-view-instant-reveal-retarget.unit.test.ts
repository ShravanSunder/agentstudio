import type { CodeViewHandle } from '@pierre/diffs/react';
import type { MutableRefObject } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { scheduleBridgeCodeViewInstantRevealRetarget } from './bridge-code-view-instant-reveal-retarget.js';
import type { BridgeCodeViewInstantRevealRearmCandidate } from './bridge-code-view-panel-support.js';

describe('Bridge CodeView instant reveal retarget', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	test('cancels retarget writes when user scroll becomes active', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const scrollCalls: unknown[] = [];
		const recentRevealRef = mutableRef<BridgeCodeViewInstantRevealRearmCandidate | null>({
			itemId: 'selected-item',
			revealedAtMilliseconds: 1_000,
			selectionScrollKey: 'source:1:selected-item',
		});
		const handle = makeCodeViewHandle({ scrollCalls });
		let skippedCount = 0;
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			frameCallbacks.push(callback);
			return frameCallbacks.length;
		});
		vi.stubGlobal('cancelAnimationFrame', vi.fn());

		scheduleBridgeCodeViewInstantRevealRetarget({
			codeViewHandle: handle,
			codeViewHandleRef: mutableRef<CodeViewHandle<undefined> | null>(handle),
			itemId: 'selected-item',
			lastSelectionScrollKeyRef: mutableRef<string | null>('source:1:selected-item'),
			pendingSelectionScrollFrameRef: mutableRef<number | null>(null),
			programmaticRevealGate: {
				onProgrammaticRevealSkipped: (): void => {
					skippedCount += 1;
				},
				shouldSkipProgrammaticReveal: (): boolean => true,
			},
			recentInstantSelectionRevealRef: recentRevealRef,
			remainingFrameBudget: 3,
			selectionScrollKey: 'source:1:selected-item',
			settledInstantSelectionRevealKeyRef: mutableRef<string | null>(null),
			viewportOffsetTolerancePixels: 0,
		});

		frameCallbacks[0]?.(0);

		expect(scrollCalls).toEqual([]);
		expect(recentRevealRef.current).toBeNull();
		expect(skippedCount).toBe(1);
	});

	test('keeps a fresh user-commanded reveal eligible for one Pierre write', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const scrollCalls: unknown[] = [];
		const handle = makeCodeViewHandle({ scrollCalls });
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			frameCallbacks.push(callback);
			return frameCallbacks.length;
		});
		vi.stubGlobal('cancelAnimationFrame', vi.fn());

		scheduleBridgeCodeViewInstantRevealRetarget({
			codeViewHandle: handle,
			codeViewHandleRef: mutableRef<CodeViewHandle<undefined> | null>(handle),
			itemId: 'clicked-item',
			lastSelectionScrollKeyRef: mutableRef<string | null>('source:1:clicked-item'),
			pendingSelectionScrollFrameRef: mutableRef<number | null>(null),
			programmaticRevealGate: {
				onProgrammaticRevealSkipped: (): void => {},
				shouldSkipProgrammaticReveal: (): boolean => false,
			},
			recentInstantSelectionRevealRef: mutableRef<BridgeCodeViewInstantRevealRearmCandidate | null>(
				{
					itemId: 'clicked-item',
					revealedAtMilliseconds: 1_000,
					selectionScrollKey: 'source:1:clicked-item',
				},
			),
			remainingFrameBudget: 3,
			selectionScrollKey: 'source:1:clicked-item',
			settledInstantSelectionRevealKeyRef: mutableRef<string | null>(null),
			viewportOffsetTolerancePixels: 0,
		});

		frameCallbacks[0]?.(0);

		expect(scrollCalls).toEqual([
			{
				align: 'start',
				behavior: 'instant',
				id: 'clicked-item',
				type: 'item',
			},
		]);
	});
});

function mutableRef<TValue>(current: TValue): MutableRefObject<TValue> {
	return { current };
}

function makeCodeViewHandle(props: { readonly scrollCalls: unknown[] }): CodeViewHandle<undefined> {
	const instance = {
		getContainerElement: (): { readonly clientHeight: number } => ({ clientHeight: 500 }),
		getScrollTop: (): number => 0,
		getTopForItem: (): number => 100,
		render: (): void => {},
	};
	// oxlint-disable-next-line no-unsafe-type-assertion -- Minimal fake for the Pierre handle surface exercised by this scheduler.
	return {
		getInstance: () => instance,
		getItem: () => ({ id: 'selected-item' }),
		scrollTo: (target: unknown): void => {
			props.scrollCalls.push(target);
		},
	} as unknown as CodeViewHandle<undefined>;
}
