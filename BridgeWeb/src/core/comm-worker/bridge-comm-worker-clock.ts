export interface BridgeCommWorkerPerformanceClock {
	readonly timeOrigin: number;
	readonly now: () => number;
}

export function readBridgeCommWorkerAbsoluteNowMilliseconds(
	clock: BridgeCommWorkerPerformanceClock = performance,
): number {
	return clock.timeOrigin + clock.now();
}
