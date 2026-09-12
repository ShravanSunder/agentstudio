import type { CodeViewHandle } from '@pierre/diffs/react';
import type { MutableRefObject } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { scheduleBridgeCodeViewInstantRevealRetarget } from './bridge-code-view-instant-reveal-retarget.js';
import type { BridgeCodeViewInstantRevealRearmCandidate } from './bridge-code-view-panel-support.js';
import type { BridgeCodeViewProgrammaticRevealGate } from './bridge-code-view-programmatic-reveal-gate.js';

describe('Bridge CodeView instant reveal retarget', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	test('cancels retarget writes when user scroll becomes active', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const scrollCalls: unknown[] = [];
		const recentRevealRef = mutableRef<BridgeCodeViewInstantRevealRearmCandidate | null>({
			annotationReveal: {
				itemId: 'selected-item',
				range: { end: 8, side: 'additions', start: 4 },
				requestId: 7,
				threadId: 'thread-7',
			},
			itemId: 'selected-item',
			revealedAtMilliseconds: 1_000,
			selectionScrollKey: 'source:1:selected-item',
		});
		const handle = makeCodeViewHandle({ scrollCalls });
		let skippedCount = 0;
		let completedCount = 0;
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			frameCallbacks.push(callback);
			return frameCallbacks.length;
		});
		vi.stubGlobal('cancelAnimationFrame', vi.fn());

		scheduleBridgeCodeViewInstantRevealRetarget({
			annotationReveal: {
				itemId: 'selected-item',
				range: { end: 8, side: 'additions', start: 4 },
				requestId: 7,
				threadId: 'thread-7',
			},
			codeViewHandle: handle,
			codeViewHandleRef: mutableRef<CodeViewHandle<undefined> | null>(handle),
			completedSelectionScrollKeyRef: mutableRef<string | null>(null),
			itemId: 'selected-item',
			lastSelectionScrollKeyRef: mutableRef<string | null>('source:1:selected-item'),
			pendingSelectionScrollFrameRef: mutableRef<number | null>(null),
			pendingPreHydrationSelectionScrollKeyRef: mutableRef<string | null>(null),
			pendingSelectionRevealBehaviorRef: mutableRef<'instant' | null>(null),
			pendingSmoothSelectionScrollKeyRef: mutableRef<string | null>(null),
			programmaticRevealGate: {
				beginSelectionReveal: (): boolean => true,
				onProgrammaticRevealSkipped: (): void => {
					skippedCount += 1;
				},
				recordUserScrollIntent: (): void => {},
				shouldSkipProgrammaticReveal: (): boolean => true,
				transitionSelectionReveal: (): void => {},
			},
			onAnnotationRevealCompleteRef: mutableRef<((requestId: number) => void) | undefined>(
				(): void => {
					completedCount += 1;
				},
			),
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
		expect(completedCount).toBe(0);
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
			completedSelectionScrollKeyRef: mutableRef<string | null>(null),
			itemId: 'clicked-item',
			lastSelectionScrollKeyRef: mutableRef<string | null>('source:1:clicked-item'),
			pendingSelectionScrollFrameRef: mutableRef<number | null>(null),
			pendingPreHydrationSelectionScrollKeyRef: mutableRef<string | null>(null),
			pendingSelectionRevealBehaviorRef: mutableRef<'instant' | null>(null),
			pendingSmoothSelectionScrollKeyRef: mutableRef<string | null>(null),
			programmaticRevealGate: {
				beginSelectionReveal: (): boolean => true,
				onProgrammaticRevealSkipped: (): void => {},
				recordUserScrollIntent: (): void => {},
				shouldSkipProgrammaticReveal: (): boolean => false,
				transitionSelectionReveal: (): void => {},
			},
			onAnnotationRevealCompleteRef: mutableRef<((requestId: number) => void) | undefined>(
				undefined,
			),
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

	test('retargets a mounted annotation thread and completes only after it is visible', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const scrollCalls: unknown[] = [];
		let scrollTop = 0;
		const threadElement = {
			dataset: { annotationThreadId: 'thread-7' },
			getBoundingClientRect: () => rect(700 - scrollTop, 100),
		};
		const scrollOwner = {
			clientHeight: 500,
			getBoundingClientRect: () => rect(0, 500),
			querySelectorAll: () => [threadElement],
			get scrollTop(): number {
				return scrollTop;
			},
		};
		const handle = makeCodeViewHandle({
			materialized: true,
			onScroll: (target): void => {
				if (
					typeof target === 'object' &&
					target !== null &&
					'type' in target &&
					target.type === 'position' &&
					'position' in target &&
					typeof target.position === 'number'
				)
					scrollTop = target.position;
			},
			scrollCalls,
			scrollOwner: scrollOwner as unknown as HTMLElement,
		});
		const completedRequests: number[] = [];
		const completedSelectionRef = mutableRef<string | null>(null);
		const pendingHydrationRef = mutableRef<string | null>('annotation-key');
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			frameCallbacks.push(callback);
			return frameCallbacks.length;
		});
		vi.stubGlobal('cancelAnimationFrame', vi.fn());

		scheduleBridgeCodeViewInstantRevealRetarget({
			annotationReveal: {
				itemId: 'selected-item',
				range: { end: 8, side: 'additions', start: 4 },
				requestId: 7,
				threadId: 'thread-7',
			},
			codeViewHandle: handle,
			codeViewHandleRef: mutableRef<CodeViewHandle<undefined> | null>(handle),
			completedSelectionScrollKeyRef: completedSelectionRef,
			itemId: 'selected-item',
			lastSelectionScrollKeyRef: mutableRef<string | null>('annotation-key'),
			onAnnotationRevealCompleteRef: mutableRef<((requestId: number) => void) | undefined>(
				(requestId): void => {
					completedRequests.push(requestId);
				},
			),
			pendingPreHydrationSelectionScrollKeyRef: pendingHydrationRef,
			pendingSelectionRevealBehaviorRef: mutableRef<'instant' | null>('instant'),
			pendingSelectionScrollFrameRef: mutableRef<number | null>(null),
			pendingSmoothSelectionScrollKeyRef: mutableRef<string | null>(null),
			programmaticRevealGate: permissiveRevealGate(),
			recentInstantSelectionRevealRef: mutableRef<BridgeCodeViewInstantRevealRearmCandidate | null>(
				{
					annotationReveal: {
						itemId: 'selected-item',
						range: { end: 8, side: 'additions', start: 4 },
						requestId: 7,
						threadId: 'thread-7',
					},
					itemId: 'selected-item',
					revealedAtMilliseconds: 1_000,
					selectionScrollKey: 'annotation-key',
				},
			),
			remainingFrameBudget: 3,
			selectionScrollKey: 'annotation-key',
			settledInstantSelectionRevealKeyRef: mutableRef<string | null>(null),
			viewportOffsetTolerancePixels: 0,
		});

		frameCallbacks.shift()?.(0);
		expect(completedRequests).toEqual([]);
		expect(scrollCalls.at(-1)).toEqual({ behavior: 'instant', position: 500, type: 'position' });
		frameCallbacks.shift()?.(0);
		expect(completedRequests).toEqual([7]);
		expect(completedSelectionRef.current).toBe('annotation-key');
		expect(pendingHydrationRef.current).toBeNull();
	});
});

function mutableRef<TValue>(current: TValue): MutableRefObject<TValue> {
	return { current };
}

function makeCodeViewHandle(props: {
	readonly materialized?: boolean;
	readonly onScroll?: (target: unknown) => void;
	readonly scrollCalls: unknown[];
	readonly scrollOwner?: HTMLElement;
}): CodeViewHandle<undefined> {
	const instance = {
		getContainerElement: (): HTMLElement | { readonly clientHeight: number } =>
			props.scrollOwner ?? ({ clientHeight: 500 } as HTMLElement),
		getScrollTop: (): number => 0,
		getTopForItem: (): number => 100,
		render: (): void => {},
	};
	// oxlint-disable-next-line no-unsafe-type-assertion -- Minimal fake for the Pierre handle surface exercised by this scheduler.
	return {
		getInstance: () => instance,
		getItem: () =>
			props.materialized === true
				? {
						bridgeMetadata: { contentState: 'hydrated' },
						id: 'selected-item',
					}
				: { id: 'selected-item' },
		scrollTo: (target: unknown): void => {
			props.scrollCalls.push(target);
			props.onScroll?.(target);
		},
	} as unknown as CodeViewHandle<undefined>;
}

function permissiveRevealGate(): BridgeCodeViewProgrammaticRevealGate {
	return {
		beginSelectionReveal: (): boolean => true,
		onProgrammaticRevealSkipped: (): void => {},
		recordUserScrollIntent: (): void => {},
		shouldSkipProgrammaticReveal: (): boolean => false,
		transitionSelectionReveal: (): void => {},
	};
}

function rect(top: number, height: number): DOMRect {
	return {
		bottom: top + height,
		height,
		left: 0,
		right: 100,
		top,
		width: 100,
		x: 0,
		y: top,
		toJSON: (): Record<string, never> => ({}),
	} as DOMRect;
}
