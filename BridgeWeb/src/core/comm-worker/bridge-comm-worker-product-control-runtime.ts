import { readBridgeCommWorkerRuntimeNowMilliseconds } from './bridge-comm-worker-runtime-support.js';
import {
	recordBridgeCommWorkerTaskTelemetry,
	type BridgeCommWorkerTelemetryRecorder,
} from './bridge-comm-worker-telemetry.js';
import type { BridgeProductCallResult } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

interface CallCurrentFileSourceWithTelemetryProps {
	readonly now?: () => number;
	readonly productTransport: BridgeProductTransportSession;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export async function callCurrentFileSourceWithTelemetry(
	props: CallCurrentFileSourceWithTelemetryProps,
): Promise<BridgeProductCallResult<'file.source.current'>> {
	const discoveryStartedAtMilliseconds = readBridgeCommWorkerRuntimeNowMilliseconds(props.now);
	try {
		const discovery = await props.productTransport.call('file.source.current', {});
		recordFileSourceDiscoveryTelemetry({
			durationMilliseconds:
				readBridgeCommWorkerRuntimeNowMilliseconds(props.now) - discoveryStartedAtMilliseconds,
			result: discovery.status === 'available' ? 'success' : 'unavailable',
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		return discovery;
	} catch (error) {
		recordFileSourceDiscoveryTelemetry({
			durationMilliseconds:
				readBridgeCommWorkerRuntimeNowMilliseconds(props.now) - discoveryStartedAtMilliseconds,
			result: 'failed',
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		throw error;
	}
}

export async function rejectUninstalledBridgeProductControl(
	command: BridgeProductControlCommand,
): Promise<never> {
	throw new Error(`Bridge product-control sender is not installed for ${command.method}.`);
}

export async function rejectUninstalledReviewMetadataInterestUpdate(): Promise<never> {
	throw new Error('Bridge Review metadata product subscription is not installed.');
}

export function rejectUninstalledBridgeFileContentOpen(): never {
	throw new Error('Bridge File content transport is not installed.');
}

export function bridgeCommWorkerProductControlFailureMessage(props: {
	readonly command: BridgeProductControlCommand;
}): string {
	return `Bridge comm worker failed to forward ${props.command.method}.`;
}

export function sendBridgeCommWorkerActionWithTimeout(props: {
	readonly send: () => Promise<unknown>;
	readonly timeoutMilliseconds: number;
}): Promise<unknown> {
	return new Promise<unknown>((resolve, reject): void => {
		let didSettle = false;
		const timeoutId = globalThis.setTimeout((): void => {
			if (didSettle) return;
			didSettle = true;
			reject(new Error('Bridge comm worker command action timed out.'));
		}, props.timeoutMilliseconds);
		void props.send().then(
			(actionResult: unknown): void => {
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

function recordFileSourceDiscoveryTelemetry(props: {
	readonly durationMilliseconds: number;
	readonly result: 'failed' | 'success' | 'unavailable';
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}): void {
	recordBridgeCommWorkerTaskTelemetry({
		command: 'fileSourceDiscovery',
		durationMilliseconds: props.durationMilliseconds,
		lane: 'background',
		result: props.result,
		taskKind: 'product_control',
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
	});
}
