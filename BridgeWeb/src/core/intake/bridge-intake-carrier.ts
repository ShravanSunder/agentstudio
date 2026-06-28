import { bridgeIntakeFrameSchema } from '../models/bridge-intake-frame.js';
import type { BridgeIntakeFrame } from '../models/bridge-intake-frame.js';
import {
	summarizeIntakeFrame,
	type BridgeIntakeFrameSummary,
	type BridgeIntakeReceiver,
	type BridgeIntakeReceiveResult,
} from './bridge-intake-receiver.js';

export type BridgeIntakeCarrierDropReason =
	| 'carrier_nonce_mismatch'
	| 'frame_decode_failed'
	| 'frame_too_large'
	| 'host_port_message_invalid'
	| 'missing_carrier_nonce'
	| 'receiver_rejected_frame';

export type BridgeIntakeCarrierDrop =
	| {
			readonly reason: 'frame_too_large';
			readonly byteLength: number;
	  }
	| {
			readonly reason: 'receiver_rejected_frame';
			readonly frame: BridgeIntakeFrameSummary;
			readonly receiverReason: Extract<BridgeIntakeReceiveResult, { readonly ok: false }>['reason'];
			readonly receiverStatus: Extract<BridgeIntakeReceiveResult, { readonly ok: false }>['status'];
	  }
	| {
			readonly reason: Exclude<
				BridgeIntakeCarrierDropReason,
				'frame_too_large' | 'receiver_rejected_frame'
			>;
	  };

export interface InstallBridgeIntakeEventCarrierProps {
	readonly target?: EventTarget;
	readonly eventName: string;
	readonly getNonce: () => string | null;
	readonly receiver: BridgeIntakeReceiver;
	readonly maxFrameBytes: number;
	readonly requestReplayOnInstall?: boolean;
	readonly onAcceptedFrame?: (
		frame: BridgeIntakeFrame,
		result: Extract<BridgeIntakeReceiveResult, { readonly ok: true }>,
	) => void;
	readonly onDroppedFrame?: (drop: BridgeIntakeCarrierDrop) => void;
}

export function installBridgeIntakeEventCarrier(
	props: InstallBridgeIntakeEventCarrierProps,
): () => void {
	const target = props.target ?? document;
	const hostPorts = new Set<MessagePort>();

	const handlePageFrame = (event: Event): void => {
		const expectedNonce = props.getNonce();
		if (expectedNonce === null) {
			props.onDroppedFrame?.({ reason: 'missing_carrier_nonce' });
			return;
		}
		const detail = extractCustomEventDetail(event);
		if (!hasMatchingNonce(detail, expectedNonce)) {
			props.onDroppedFrame?.({ reason: 'carrier_nonce_mismatch' });
			return;
		}
		if (!hasJsonFrame(detail)) {
			props.onDroppedFrame?.({ reason: 'frame_decode_failed' });
			return;
		}
		handleFrameJSON(detail.json);
	};

	const handleFrameJSON = (json: string): void => {
		const byteLength = utf8ByteLength(json);
		if (byteLength > props.maxFrameBytes) {
			props.onDroppedFrame?.({ reason: 'frame_too_large', byteLength });
			return;
		}
		const frame = parseFrame(json);
		if (frame === null) {
			props.onDroppedFrame?.({ reason: 'frame_decode_failed' });
			return;
		}
		const result = props.receiver.receive(frame);
		if (!result.ok) {
			props.onDroppedFrame?.({
				reason: 'receiver_rejected_frame',
				frame: summarizeIntakeFrame(frame),
				receiverReason: result.reason,
				receiverStatus: result.status,
			});
			return;
		}
		props.onAcceptedFrame?.(frame, result);
	};

	const handleHostPortTransfer = (event: Event): void => {
		if (!(event instanceof MessageEvent) || !isBridgeHostIntakePortMessage(event.data)) {
			return;
		}
		const port = event.ports[0];
		if (port === undefined) {
			props.onDroppedFrame?.({ reason: 'host_port_message_invalid' });
			return;
		}
		hostPorts.add(port);
		port.addEventListener('message', handleHostPortFrame);
		port.start();
	};

	const handleHostPortFrame = (event: MessageEvent<unknown>): void => {
		if (!isBridgeHostIntakeFrameMessage(event.data)) {
			props.onDroppedFrame?.({ reason: 'host_port_message_invalid' });
			return;
		}
		handleFrameJSON(event.data.json);
	};

	target.addEventListener(props.eventName, handlePageFrame);
	const messageTarget = messageEventTargetForBridgeIntakeCarrier();
	messageTarget?.addEventListener('message', handleHostPortTransfer);
	target.dispatchEvent(new CustomEvent('__bridge_host_intake_port_request'));
	if (props.requestReplayOnInstall !== false) {
		target.dispatchEvent(new CustomEvent('__bridge_intake_replay_request'));
	}
	return (): void => {
		target.removeEventListener(props.eventName, handlePageFrame);
		messageTarget?.removeEventListener('message', handleHostPortTransfer);
		for (const port of hostPorts) {
			port.removeEventListener('message', handleHostPortFrame);
			port.close();
		}
		hostPorts.clear();
	};
}

function utf8ByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

function extractCustomEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}

function hasMatchingNonce(value: unknown, nonce: string): value is { readonly nonce: string } {
	if (typeof value !== 'object' || value === null || !('nonce' in value)) {
		return false;
	}
	return value.nonce === nonce;
}

function hasJsonFrame(value: { readonly nonce: string }): value is {
	readonly nonce: string;
	readonly json: string;
} {
	return 'json' in value && typeof value.json === 'string';
}

function parseFrame(json: string): ReturnType<typeof bridgeIntakeFrameSchema.parse> | null {
	try {
		return bridgeIntakeFrameSchema.parse(JSON.parse(json));
	} catch {
		return null;
	}
}

function messageEventTargetForBridgeIntakeCarrier(): Window | null {
	return typeof window === 'undefined' ? null : window;
}

function isBridgeHostIntakePortMessage(
	value: unknown,
): value is { readonly type: 'agentstudio.bridge.hostIntakePort'; readonly version: 1 } {
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return (
		'type' in value &&
		value.type === 'agentstudio.bridge.hostIntakePort' &&
		'version' in value &&
		value.version === 1
	);
}

function isBridgeHostIntakeFrameMessage(value: unknown): value is {
	readonly json: string;
	readonly type: 'agentstudio.bridge.hostIntakeFrameJSON';
	readonly version: 1;
} {
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return (
		'type' in value &&
		value.type === 'agentstudio.bridge.hostIntakeFrameJSON' &&
		'version' in value &&
		value.version === 1 &&
		'json' in value &&
		typeof value.json === 'string'
	);
}
