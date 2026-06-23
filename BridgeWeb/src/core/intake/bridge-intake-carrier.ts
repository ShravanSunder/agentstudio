import { bridgeIntakeFrameSchema } from '../models/bridge-intake-frame.js';
import type { BridgeIntakeReceiver } from './bridge-intake-receiver.js';

export type BridgeIntakeCarrierDropReason =
	| 'carrier_nonce_mismatch'
	| 'frame_decode_failed'
	| 'frame_too_large'
	| 'missing_carrier_nonce'
	| 'receiver_rejected_frame';

export type BridgeIntakeCarrierDrop =
	| {
			readonly reason: 'frame_too_large';
			readonly byteLength: number;
	  }
	| {
			readonly reason: Exclude<BridgeIntakeCarrierDropReason, 'frame_too_large'>;
	  };

export interface InstallBridgeIntakeEventCarrierProps {
	readonly target?: EventTarget;
	readonly eventName: string;
	readonly getNonce: () => string | null;
	readonly receiver: BridgeIntakeReceiver;
	readonly maxFrameBytes: number;
	readonly onDroppedFrame?: (drop: BridgeIntakeCarrierDrop) => void;
}

export function installBridgeIntakeEventCarrier(
	props: InstallBridgeIntakeEventCarrierProps,
): () => void {
	const target = props.target ?? document;

	const handleFrame = (event: Event): void => {
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
		const byteLength = utf8ByteLength(detail.json);
		if (byteLength > props.maxFrameBytes) {
			props.onDroppedFrame?.({ reason: 'frame_too_large', byteLength });
			return;
		}
		const frame = parseFrame(detail.json);
		if (frame === null) {
			props.onDroppedFrame?.({ reason: 'frame_decode_failed' });
			return;
		}
		const result = props.receiver.receive(frame);
		if (!result.ok) {
			props.onDroppedFrame?.({ reason: 'receiver_rejected_frame' });
		}
	};

	target.addEventListener(props.eventName, handleFrame);
	return (): void => {
		target.removeEventListener(props.eventName, handleFrame);
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
