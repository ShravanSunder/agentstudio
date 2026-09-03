import { readBridgeCommWorkerAbsoluteNowMilliseconds } from './bridge-comm-worker-clock.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeWorkerHealthEvent } from './bridge-worker-contracts.js';

export function readBridgeCommWorkerRuntimeNowMilliseconds(
	now: (() => number) | undefined,
): number {
	if (now !== undefined) {
		return now();
	}
	return readBridgeCommWorkerAbsoluteNowMilliseconds();
}

export function createBridgeWorkerRuntimeSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

export function scheduleDefaultBridgeCommWorkerPreparationDrain(
	drain: () => Promise<unknown>,
): void {
	queueMicrotask(() => {
		void drain();
	});
}

export function sendBridgeCommWorkerActionWithTimeout<TResult>(props: {
	readonly send: () => Promise<TResult>;
	readonly timeoutMilliseconds: number;
}): Promise<TResult> {
	return new Promise<TResult>((resolve, reject): void => {
		let didSettle = false;
		const timeoutId = globalThis.setTimeout((): void => {
			if (didSettle) return;
			didSettle = true;
			reject(new Error('Bridge comm worker command action timed out.'));
		}, props.timeoutMilliseconds);
		void props.send().then(
			(actionResult: TResult): void => {
				if (didSettle) return;
				didSettle = true;
				globalThis.clearTimeout(timeoutId);
				resolve(actionResult);
			},
			(error: unknown): void => {
				if (didSettle) return;
				didSettle = true;
				globalThis.clearTimeout(timeoutId);
				reject(error);
			},
		);
	});
}

export function bridgeProductMetadataStreamHealthDiagnostic(
	transport: BridgeProductTransportSession,
): BridgeWorkerHealthEvent['diagnostic'] | undefined {
	const readDiagnostics = (
		transport as Partial<Pick<BridgeProductTransportSession, 'metadataStreamDiagnostics'>>
	).metadataStreamDiagnostics;
	if (typeof readDiagnostics !== 'function') return undefined;
	return {
		kind: 'productMetadataStream',
		...readDiagnostics.call(transport),
	};
}
