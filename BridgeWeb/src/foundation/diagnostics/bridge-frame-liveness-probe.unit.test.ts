import { readFileSync } from 'node:fs';

import { describe, expect, test, vi } from 'vitest';

import {
	readBridgeFrameLivenessProbe,
	resetBridgeFrameLivenessProbeForTesting,
	startBridgeFrameLivenessProbe,
	type BridgeFrameLivenessProbe,
} from './bridge-frame-liveness-probe.js';

describe('Bridge frame liveness probe', () => {
	test('records unknown until the startup requestAnimationFrame canary fires', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const timerCallbacks: (() => void)[] = [];
		let nowMilliseconds = 100;
		ensureTestWindow();
		resetBridgeFrameLivenessProbeForTesting();

		startBridgeFrameLivenessProbe({
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
			setTimeout: (callback): number => {
				timerCallbacks.push(callback);
				return timerCallbacks.length;
			},
			clearTimeout: (): void => {},
		});

		expect(readRequiredBridgeFrameLivenessProbe()).toMatchObject({
			rafAlive: 'unknown',
			rafFiredLatencyBucket: 'unknown',
			rafScheduledCount: 1,
			rafFiredCount: 0,
		});

		nowMilliseconds = 118;
		frameCallbacks[0]?.(118);
		timerCallbacks[0]?.();

		expect(readRequiredBridgeFrameLivenessProbe()).toMatchObject({
			rafAlive: 'true',
			rafFiredLatencyBucket: '16_50ms',
			rafScheduledCount: 1,
			rafFiredCount: 1,
			boundedWindowElapsedCount: 0,
		});
	});

	test('records false when the bounded liveness window elapses before RAF fires', () => {
		const frameCallbacks: FrameRequestCallback[] = [];
		const timerCallbacks: (() => void)[] = [];
		ensureTestWindow();
		resetBridgeFrameLivenessProbeForTesting();

		startBridgeFrameLivenessProbe({
			now: (): number => 500,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
			setTimeout: (callback): number => {
				timerCallbacks.push(callback);
				return timerCallbacks.length;
			},
			clearTimeout: (): void => {},
		});

		timerCallbacks[0]?.();

		expect(readRequiredBridgeFrameLivenessProbe()).toMatchObject({
			rafAlive: 'false',
			rafFiredLatencyBucket: 'not_fired',
			rafScheduledCount: 1,
			rafFiredCount: 0,
			boundedWindowElapsedCount: 1,
		});
		expect(frameCallbacks).toHaveLength(1);
	});

	test('is started by both Bridge viewer mode owners', () => {
		expect(
			readSource(new URL('../../app/bridge-app-review-viewer-mode.tsx', import.meta.url)),
		).toContain('startBridgeFrameLivenessProbe');
		expect(
			readSource(new URL('../../app/bridge-app-file-viewer-mode.tsx', import.meta.url)),
		).toContain('startBridgeFrameLivenessProbe');
	});
});

function readRequiredBridgeFrameLivenessProbe(): BridgeFrameLivenessProbe {
	const probe = readBridgeFrameLivenessProbe();
	if (probe === null) {
		throw new Error('Expected frame liveness probe');
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
