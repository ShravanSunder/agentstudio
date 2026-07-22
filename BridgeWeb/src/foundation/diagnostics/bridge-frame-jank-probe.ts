export interface BridgeFrameJankProbe {
	long_task: BridgeFrameJankLongTaskProbe;
	dropped_frame: BridgeFrameJankDroppedFrameProbe;
	last_long_task_at_ms: number | null;
}

export interface BridgeFrameJankLongTaskProbe {
	count: number;
	total_ms: number;
	max_ms: number;
}

export interface BridgeFrameJankDroppedFrameProbe {
	count: number;
	worst_gap_ms: number;
}

export interface BridgeFrameJankSample {
	readonly droppedFrameCount: number;
	readonly droppedFrameWorstGapMilliseconds: number;
	readonly durationMilliseconds: number;
	readonly kind: 'dropped_frame' | 'long_task';
	readonly longTaskCount: number;
	readonly longTaskMaxMilliseconds: number;
	readonly longTaskTotalMilliseconds: number;
}

export interface StartBridgeFrameJankProbeOptions {
	readonly PerformanceObserver?: BridgeFrameJankPerformanceObserverConstructor;
	readonly cancelAnimationFrame?: (frameId: number) => void;
	readonly nominalFrameDurationMilliseconds?: number;
	readonly onJankSample?: (sample: BridgeFrameJankSample) => void;
	readonly requestAnimationFrame?: (callback: FrameRequestCallback) => number;
}

interface BridgeFrameJankPerformanceObserverConstructor {
	new (callback: PerformanceObserverCallback): PerformanceObserver;
	readonly supportedEntryTypes?: readonly string[];
}

interface ActiveBridgeFrameJankProbeSession {
	frameId: number | null;
	isRunning: boolean;
	onJankSampleCallbacks: Set<(sample: BridgeFrameJankSample) => void>;
	observer: PerformanceObserver | null;
	refCount: number;
}

declare global {
	interface Window {
		__bridgeFrameJankProbe?: BridgeFrameJankProbe;
	}
}

const defaultNominalFrameDurationMilliseconds = 1_000 / 60;
const droppedFrameGapMultiplier = 1.5;

let activeSession: ActiveBridgeFrameJankProbeSession | null = null;

export function startBridgeFrameJankProbe(
	options: StartBridgeFrameJankProbeOptions = {},
): () => void {
	const probeWindow = bridgeFrameJankProbeWindow();
	if (probeWindow === null) {
		return (): void => {};
	}
	const requestFrame =
		options.requestAnimationFrame ?? probeWindow.requestAnimationFrame?.bind(probeWindow);
	const cancelFrame =
		options.cancelAnimationFrame ?? probeWindow.cancelAnimationFrame?.bind(probeWindow);
	if (requestFrame === undefined || cancelFrame === undefined) {
		return (): void => {};
	}
	const probe = ensureBridgeFrameJankProbe(probeWindow);
	if (activeSession !== null) {
		const session = activeSession;
		session.refCount += 1;
		registerBridgeFrameJankSampleCallback(session, options.onJankSample);
		return (): void => {
			unregisterBridgeFrameJankSampleCallback(session, options.onJankSample);
			stopBridgeFrameJankProbeSession(session, cancelFrame);
		};
	}

	const observerConstructor =
		options.PerformanceObserver ?? bridgeFrameJankProbePerformanceObserver(probeWindow);
	const nominalFrameDurationMilliseconds =
		options.nominalFrameDurationMilliseconds ?? defaultNominalFrameDurationMilliseconds;
	const droppedFrameThresholdMilliseconds =
		nominalFrameDurationMilliseconds * droppedFrameGapMultiplier;
	let previousFrameTimestampMilliseconds: number | null = null;
	const onJankSampleCallbacks = new Set<(sample: BridgeFrameJankSample) => void>();

	const session: ActiveBridgeFrameJankProbeSession = {
		frameId: null,
		isRunning: true,
		onJankSampleCallbacks,
		observer: createBridgeFrameJankLongTaskObserver({
			getSampleCallbacks: () => onJankSampleCallbacks,
			observerConstructor,
			probe,
		}),
		refCount: 1,
	};
	registerBridgeFrameJankSampleCallback(session, options.onJankSample);
	activeSession = session;

	const onFrame = (timestampMilliseconds: DOMHighResTimeStamp): void => {
		if (!session.isRunning) {
			return;
		}
		if (previousFrameTimestampMilliseconds !== null) {
			const gapMilliseconds = timestampMilliseconds - previousFrameTimestampMilliseconds;
			if (gapMilliseconds > droppedFrameThresholdMilliseconds) {
				probe.dropped_frame.count += 1;
				if (gapMilliseconds > probe.dropped_frame.worst_gap_ms) {
					probe.dropped_frame.worst_gap_ms = gapMilliseconds;
				}
				emitBridgeFrameJankSample(session.onJankSampleCallbacks, probe, {
					durationMilliseconds: gapMilliseconds,
					kind: 'dropped_frame',
				});
			}
		}
		previousFrameTimestampMilliseconds = timestampMilliseconds;
		session.frameId = requestFrame(onFrame);
	};

	session.frameId = requestFrame(onFrame);

	return (): void => {
		unregisterBridgeFrameJankSampleCallback(session, options.onJankSample);
		stopBridgeFrameJankProbeSession(session, cancelFrame);
	};
}

export function readBridgeFrameJankProbe(): BridgeFrameJankProbe | null {
	const probeWindow = bridgeFrameJankProbeWindow();
	if (probeWindow === null) {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return probeWindow.__bridgeFrameJankProbe ?? null;
}

export function resetBridgeFrameJankProbeForTesting(): void {
	const probeWindow = bridgeFrameJankProbeWindow();
	activeSession = null;
	if (probeWindow === null) {
		return;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	delete probeWindow.__bridgeFrameJankProbe;
}

function createBridgeFrameJankLongTaskObserver(props: {
	readonly getSampleCallbacks: () => ReadonlySet<(sample: BridgeFrameJankSample) => void>;
	readonly observerConstructor: BridgeFrameJankPerformanceObserverConstructor | undefined;
	readonly probe: BridgeFrameJankProbe;
}): PerformanceObserver | null {
	if (
		props.observerConstructor === undefined ||
		!bridgeFrameJankLongTaskObservationIsSupported(props.observerConstructor)
	) {
		return null;
	}
	const observer = new props.observerConstructor((entryList): void => {
		const entries = entryList.getEntries();
		for (const entry of entries) {
			recordBridgeFrameJankLongTaskEntry(props.probe, entry);
			emitBridgeFrameJankSample(props.getSampleCallbacks(), props.probe, {
				durationMilliseconds: entry.duration,
				kind: 'long_task',
			});
		}
	});
	try {
		observer.observe({ entryTypes: ['longtask'] });
	} catch {
		observer.disconnect();
		return null;
	}
	return observer;
}

function registerBridgeFrameJankSampleCallback(
	session: ActiveBridgeFrameJankProbeSession,
	onJankSample: ((sample: BridgeFrameJankSample) => void) | undefined,
): void {
	if (onJankSample === undefined) {
		return;
	}
	session.onJankSampleCallbacks.add(onJankSample);
}

function unregisterBridgeFrameJankSampleCallback(
	session: ActiveBridgeFrameJankProbeSession,
	onJankSample: ((sample: BridgeFrameJankSample) => void) | undefined,
): void {
	if (onJankSample === undefined) {
		return;
	}
	session.onJankSampleCallbacks.delete(onJankSample);
}

function emitBridgeFrameJankSample(
	callbacks: ReadonlySet<(sample: BridgeFrameJankSample) => void>,
	probe: BridgeFrameJankProbe,
	props: {
		readonly durationMilliseconds: number;
		readonly kind: BridgeFrameJankSample['kind'];
	},
): void {
	if (callbacks.size === 0) {
		return;
	}
	const sample: BridgeFrameJankSample = {
		droppedFrameCount: probe.dropped_frame.count,
		droppedFrameWorstGapMilliseconds: probe.dropped_frame.worst_gap_ms,
		durationMilliseconds: Math.max(0, props.durationMilliseconds),
		kind: props.kind,
		longTaskCount: probe.long_task.count,
		longTaskMaxMilliseconds: probe.long_task.max_ms,
		longTaskTotalMilliseconds: probe.long_task.total_ms,
	};
	for (const callback of callbacks) {
		callback(sample);
	}
}

function recordBridgeFrameJankLongTaskEntry(
	probe: BridgeFrameJankProbe,
	entry: PerformanceEntry,
): void {
	probe.long_task.count += 1;
	probe.long_task.total_ms += entry.duration;
	if (entry.duration > probe.long_task.max_ms) {
		probe.long_task.max_ms = entry.duration;
	}
	probe.last_long_task_at_ms = entry.startTime;
}

function stopBridgeFrameJankProbeSession(
	session: ActiveBridgeFrameJankProbeSession | null,
	cancelFrame: (frameId: number) => void,
): void {
	if (session === null || !session.isRunning) {
		return;
	}
	session.refCount -= 1;
	if (session.refCount > 0) {
		return;
	}
	session.isRunning = false;
	if (session.frameId !== null) {
		cancelFrame(session.frameId);
		session.frameId = null;
	}
	session.observer?.disconnect();
	session.observer = null;
	if (activeSession === session) {
		activeSession = null;
	}
}

function bridgeFrameJankLongTaskObservationIsSupported(
	observerConstructor: BridgeFrameJankPerformanceObserverConstructor,
): boolean {
	return (
		observerConstructor.supportedEntryTypes === undefined ||
		observerConstructor.supportedEntryTypes.includes('longtask')
	);
}

function ensureBridgeFrameJankProbe(probeWindow: Window): BridgeFrameJankProbe {
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeFrameJankProbe ??= {
		long_task: {
			count: 0,
			total_ms: 0,
			max_ms: 0,
		},
		dropped_frame: {
			count: 0,
			worst_gap_ms: 0,
		},
		last_long_task_at_ms: null,
	};
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return probeWindow.__bridgeFrameJankProbe;
}

function bridgeFrameJankProbeWindow(): Window | null {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return null;
	}
	return probeWindow;
}

function bridgeFrameJankProbePerformanceObserver(
	probeWindow: Window,
): BridgeFrameJankPerformanceObserverConstructor | undefined {
	return (
		probeWindow as Window & {
			readonly PerformanceObserver?: BridgeFrameJankPerformanceObserverConstructor;
		}
	).PerformanceObserver;
}
