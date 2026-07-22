export type BridgeFrameLivenessRafAlive = 'false' | 'true' | 'unknown';

export type BridgeFrameLivenessLatencyBucket =
	| '16_50ms'
	| '50_250ms'
	| 'gt_250ms'
	| 'lt_16ms'
	| 'not_fired'
	| 'unknown';

export interface BridgeFrameLivenessProbe {
	rafAlive: BridgeFrameLivenessRafAlive;
	rafFiredLatencyBucket: BridgeFrameLivenessLatencyBucket;
	rafScheduledCount: number;
	rafFiredCount: number;
	boundedWindowElapsedCount: number;
	lastStartedAtMilliseconds: number | null;
	lastFiredAtMilliseconds: number | null;
}

export interface StartBridgeFrameLivenessProbeOptions {
	readonly clearTimeout?: (timerId: number) => void;
	readonly now?: () => number;
	readonly requestAnimationFrame?: (callback: FrameRequestCallback) => number;
	readonly setTimeout?: (callback: () => void, delayMilliseconds: number) => number;
	readonly timeoutMilliseconds?: number;
}

declare global {
	interface Window {
		__bridgeFrameLivenessProbe?: BridgeFrameLivenessProbe;
	}
}

const defaultFrameLivenessTimeoutMilliseconds = 1_000;

export function startBridgeFrameLivenessProbe(
	options: StartBridgeFrameLivenessProbeOptions = {},
): () => void {
	const probeWindow = bridgeFrameLivenessProbeWindow();
	if (probeWindow === null) {
		return (): void => {};
	}
	const requestFrame =
		options.requestAnimationFrame ?? probeWindow.requestAnimationFrame?.bind(probeWindow);
	const setTimer = options.setTimeout ?? probeWindow.setTimeout?.bind(probeWindow);
	const clearTimer = options.clearTimeout ?? probeWindow.clearTimeout?.bind(probeWindow);
	if (requestFrame === undefined || setTimer === undefined || clearTimer === undefined) {
		return (): void => {};
	}
	const probe = ensureBridgeFrameLivenessProbe(probeWindow);
	if (probe.rafScheduledCount > 0) {
		return (): void => {};
	}
	const now = options.now ?? probeWindow.performance.now.bind(probeWindow.performance);
	const startedAtMilliseconds = now();
	let didFire = false;
	let timerId: number | null = null;

	probe.rafAlive = 'unknown';
	probe.rafFiredLatencyBucket = 'unknown';
	probe.rafScheduledCount += 1;
	probe.lastStartedAtMilliseconds = startedAtMilliseconds;
	probe.lastFiredAtMilliseconds = null;

	requestFrame((): void => {
		if (didFire) {
			return;
		}
		didFire = true;
		if (timerId !== null) {
			clearTimer(timerId);
			timerId = null;
		}
		const firedAtMilliseconds = now();
		probe.rafAlive = 'true';
		probe.rafFiredCount += 1;
		probe.lastFiredAtMilliseconds = firedAtMilliseconds;
		probe.rafFiredLatencyBucket = bridgeFrameLivenessLatencyBucket(
			firedAtMilliseconds - startedAtMilliseconds,
		);
	});

	timerId = setTimer((): void => {
		timerId = null;
		if (didFire) {
			return;
		}
		probe.rafAlive = 'false';
		probe.rafFiredLatencyBucket = 'not_fired';
		probe.boundedWindowElapsedCount += 1;
	}, options.timeoutMilliseconds ?? defaultFrameLivenessTimeoutMilliseconds);

	return (): void => {};
}

export function readBridgeFrameLivenessProbe(): BridgeFrameLivenessProbe | null {
	const probeWindow = bridgeFrameLivenessProbeWindow();
	if (probeWindow === null) {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return probeWindow.__bridgeFrameLivenessProbe ?? null;
}

export function resetBridgeFrameLivenessProbeForTesting(): void {
	const probeWindow = bridgeFrameLivenessProbeWindow();
	if (probeWindow === null) {
		return;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	delete probeWindow.__bridgeFrameLivenessProbe;
}

function ensureBridgeFrameLivenessProbe(probeWindow: Window): BridgeFrameLivenessProbe {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeFrameLivenessProbe ??= {
		rafAlive: 'unknown',
		rafFiredLatencyBucket: 'unknown',
		rafScheduledCount: 0,
		rafFiredCount: 0,
		boundedWindowElapsedCount: 0,
		lastStartedAtMilliseconds: null,
		lastFiredAtMilliseconds: null,
	};
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return probeWindow.__bridgeFrameLivenessProbe;
}

function bridgeFrameLivenessLatencyBucket(
	latencyMilliseconds: number,
): BridgeFrameLivenessLatencyBucket {
	if (latencyMilliseconds < 16) {
		return 'lt_16ms';
	}
	if (latencyMilliseconds < 50) {
		return '16_50ms';
	}
	if (latencyMilliseconds < 250) {
		return '50_250ms';
	}
	return 'gt_250ms';
}

function bridgeFrameLivenessProbeWindow(): Window | null {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return null;
	}
	return probeWindow;
}
