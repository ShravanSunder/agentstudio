import { readFileSync } from 'node:fs';

import { describe, expect, test, vi } from 'vitest';

import {
	readBridgeFrameJankProbe,
	resetBridgeFrameJankProbeForTesting,
	startBridgeFrameJankProbe,
	type BridgeFrameJankProbe,
} from './bridge-frame-jank-probe.js';

describe('Bridge frame jank probe', () => {
	test('accumulates longtask entries into the debug probe surface', () => {
		ensureTestWindow();
		resetBridgeFrameJankProbeForTesting();
		const fakeObserverController = installFakePerformanceObserver();
		const frameController = createFakeAnimationFrameController();

		const stopProbe = startBridgeFrameJankProbe({
			PerformanceObserver: fakeObserverController.PerformanceObserver,
			cancelAnimationFrame: frameController.cancelAnimationFrame,
			requestAnimationFrame: frameController.requestAnimationFrame,
		});

		fakeObserverController.emit([
			createFakePerformanceEntry({ duration: 12, startTime: 101 }),
			createFakePerformanceEntry({ duration: 44, startTime: 130 }),
		]);
		fakeObserverController.emit([createFakePerformanceEntry({ duration: 7, startTime: 180 })]);

		expect(readRequiredBridgeFrameJankProbe()).toEqual({
			long_task: {
				count: 3,
				total_ms: 63,
				max_ms: 44,
			},
			dropped_frame: {
				count: 0,
				worst_gap_ms: 0,
			},
			last_long_task_at_ms: 180,
		});

		stopProbe();
	});

	test('estimates dropped frames from consecutive requestAnimationFrame gaps', () => {
		ensureTestWindow();
		resetBridgeFrameJankProbeForTesting();
		const fakeObserverController = installFakePerformanceObserver();
		const frameController = createFakeAnimationFrameController();

		const stopProbe = startBridgeFrameJankProbe({
			PerformanceObserver: fakeObserverController.PerformanceObserver,
			cancelAnimationFrame: frameController.cancelAnimationFrame,
			nominalFrameDurationMilliseconds: 16,
			requestAnimationFrame: frameController.requestAnimationFrame,
		});

		frameController.fireNext(0);
		frameController.fireNext(16);
		frameController.fireNext(41);
		frameController.fireNext(65);
		frameController.fireNext(120);

		expect(readRequiredBridgeFrameJankProbe()).toMatchObject({
			dropped_frame: {
				count: 2,
				worst_gap_ms: 55,
			},
		});

		stopProbe();
	});

	test('disconnects the observer and cancels the animation frame on cleanup', () => {
		ensureTestWindow();
		resetBridgeFrameJankProbeForTesting();
		const fakeObserverController = installFakePerformanceObserver();
		const frameController = createFakeAnimationFrameController();

		const stopProbe = startBridgeFrameJankProbe({
			PerformanceObserver: fakeObserverController.PerformanceObserver,
			cancelAnimationFrame: frameController.cancelAnimationFrame,
			requestAnimationFrame: frameController.requestAnimationFrame,
		});

		stopProbe();
		fakeObserverController.emit([createFakePerformanceEntry({ duration: 99, startTime: 320 })]);

		expect(fakeObserverController.disconnectCount()).toBe(1);
		expect(frameController.cancelledFrameIds()).toEqual([1]);
		expect(readRequiredBridgeFrameJankProbe()).toMatchObject({
			long_task: {
				count: 0,
				total_ms: 0,
				max_ms: 0,
			},
		});
	});

	test('is started by both Bridge viewer mode owners', () => {
		expect(
			readSource(new URL('../../app/bridge-app-review-viewer-mode.tsx', import.meta.url)),
		).toContain('startBridgeFrameJankProbe');
		expect(
			readSource(new URL('../../app/bridge-app-file-viewer-mode.tsx', import.meta.url)),
		).toContain('startBridgeFrameJankProbe');
	});
});

interface FakePerformanceEntryProps {
	readonly startTime: number;
	readonly duration: number;
}

interface FakePerformanceObserverController {
	readonly PerformanceObserver: BridgeFrameJankPerformanceObserverConstructor;
	readonly disconnectCount: () => number;
	readonly emit: (entries: PerformanceEntryList) => void;
}

type BridgeFrameJankPerformanceObserverConstructor = new (
	callback: PerformanceObserverCallback,
) => PerformanceObserver;

function installFakePerformanceObserver(): FakePerformanceObserverController {
	let observerCallback: PerformanceObserverCallback | null = null;
	let disconnectCallCount = 0;
	const fakeObserver = {
		disconnect: (): void => {
			disconnectCallCount += 1;
			observerCallback = null;
		},
		observe: vi.fn(),
		takeRecords: (): PerformanceEntryList => [],
	} satisfies PerformanceObserver;
	const PerformanceObserver = class {
		public constructor(callback: PerformanceObserverCallback) {
			observerCallback = callback;
		}

		public disconnect(): void {
			fakeObserver.disconnect();
		}

		public observe(options: PerformanceObserverInit): void {
			fakeObserver.observe(options);
		}

		public takeRecords(): PerformanceEntryList {
			return [];
		}
	} as BridgeFrameJankPerformanceObserverConstructor;
	return {
		PerformanceObserver,
		disconnectCount: (): number => disconnectCallCount,
		emit: (entries): void => {
			observerCallback?.(
				{
					getEntries: (): PerformanceEntryList => entries,
					getEntriesByName: (): PerformanceEntryList => [],
					getEntriesByType: (): PerformanceEntryList => entries,
				},
				fakeObserver,
			);
		},
	};
}

function createFakePerformanceEntry(props: FakePerformanceEntryProps): PerformanceEntry {
	return {
		duration: props.duration,
		entryType: 'longtask',
		name: 'self',
		startTime: props.startTime,
		toJSON: (): Record<string, number | string> => ({
			duration: props.duration,
			entryType: 'longtask',
			name: 'self',
			startTime: props.startTime,
		}),
	};
}

interface FakeAnimationFrameController {
	readonly cancelledFrameIds: () => readonly number[];
	readonly cancelAnimationFrame: (frameId: number) => void;
	readonly fireNext: (timestampMilliseconds: number) => void;
	readonly requestAnimationFrame: (callback: FrameRequestCallback) => number;
}

function createFakeAnimationFrameController(): FakeAnimationFrameController {
	const callbacks = new Map<number, FrameRequestCallback>();
	const cancelledIds: number[] = [];
	let nextId = 1;
	return {
		cancelledFrameIds: (): readonly number[] => cancelledIds,
		cancelAnimationFrame: (frameId): void => {
			cancelledIds.push(frameId);
			callbacks.delete(frameId);
		},
		fireNext: (timestampMilliseconds): void => {
			const firstEntry = callbacks.entries().next().value as
				| readonly [number, FrameRequestCallback]
				| undefined;
			if (firstEntry === undefined) {
				throw new Error('Expected a pending frame callback');
			}
			callbacks.delete(firstEntry[0]);
			firstEntry[1](timestampMilliseconds);
		},
		requestAnimationFrame: (callback): number => {
			const frameId = nextId;
			nextId += 1;
			callbacks.set(frameId, callback);
			return frameId;
		},
	};
}

function readRequiredBridgeFrameJankProbe(): BridgeFrameJankProbe {
	const probe = readBridgeFrameJankProbe();
	if (probe === null) {
		throw new Error('Expected frame jank probe');
	}
	return probe;
}

function readSource(url: URL): string {
	return readFileSync(url, 'utf8');
}

function ensureTestWindow(): void {
	if (typeof window === 'undefined') {
		vi.stubGlobal('window', {});
	}
}
