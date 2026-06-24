import type { BridgePushEnvelope } from './bridge-push-envelope.js';
import { decodeBridgePushEnvelope } from './bridge-push-envelope.js';

export type BridgePushAdmissionSource = 'page-event' | 'host-bridge-port';

export type BridgePushDropReason =
	| 'missing_push_nonce'
	| 'push_decode_failed'
	| 'host_port_message_invalid'
	| 'push_nonce_mismatch'
	| 'stale_push';

export interface InstallBridgePushReceiverProps {
	readonly target?: EventTarget;
	readonly getPushNonce: () => string | null;
	readonly onEnvelope: (
		envelope: BridgePushEnvelope,
		admissionSource: BridgePushAdmissionSource,
	) => void;
	readonly onInvalidEnvelope?: (error: Error) => void;
	readonly onDroppedEnvelope?: (reason: BridgePushDropReason) => void;
}

interface StoreRevisionState {
	epoch: number;
	revision: number;
}

export function installBridgePushReceiver(props: InstallBridgePushReceiverProps): () => void {
	const target = props.target ?? document;
	const revisionsByStoreSlice = new Map<string, StoreRevisionState>();
	const hostPorts = new Set<MessagePort>();

	const handlePush = (event: Event): void => {
		const pushNonce = props.getPushNonce();
		if (pushNonce === null) {
			props.onDroppedEnvelope?.('missing_push_nonce');
			return;
		}
		const detail = extractCustomEventDetail(event);
		if (!hasMatchingPushNonce(detail, pushNonce)) {
			props.onDroppedEnvelope?.('push_nonce_mismatch');
			return;
		}

		let envelopeValue: unknown;
		try {
			envelopeValue = extractEnvelopeValue(detail);
		} catch (error) {
			props.onInvalidEnvelope?.(error instanceof Error ? error : new Error(String(error)));
			props.onDroppedEnvelope?.('push_decode_failed');
			return;
		}
		handleEnvelopeValue(envelopeValue, 'page-event');
	};

	const handleEnvelopeValue = (
		value: unknown,
		admissionSource: BridgePushAdmissionSource,
	): void => {
		let envelope: BridgePushEnvelope;
		try {
			envelope = decodeBridgePushEnvelope(value);
		} catch (error) {
			props.onInvalidEnvelope?.(error instanceof Error ? error : new Error(String(error)));
			props.onDroppedEnvelope?.('push_decode_failed');
			return;
		}
		if (!shouldAcceptEnvelope(envelope, revisionsByStoreSlice)) {
			props.onDroppedEnvelope?.('stale_push');
			return;
		}
		props.onEnvelope(envelope, admissionSource);
	};

	const handleHostPortTransfer = (event: Event): void => {
		if (!(event instanceof MessageEvent) || !isBridgeHostPushPortMessage(event.data)) {
			return;
		}
		const port = event.ports[0];
		if (port === undefined) {
			props.onDroppedEnvelope?.('host_port_message_invalid');
			return;
		}
		hostPorts.add(port);
		port.addEventListener('message', handleHostPortEnvelope);
		port.start();
	};

	const handleHostPortEnvelope = (event: MessageEvent<unknown>): void => {
		if (!isBridgeHostPushEnvelopeMessage(event.data)) {
			props.onDroppedEnvelope?.('host_port_message_invalid');
			return;
		}
		try {
			handleEnvelopeValue(JSON.parse(event.data.json), 'host-bridge-port');
		} catch (error) {
			props.onInvalidEnvelope?.(error instanceof Error ? error : new Error(String(error)));
			props.onDroppedEnvelope?.('push_decode_failed');
		}
	};

	target.addEventListener('__bridge_push', handlePush);
	target.addEventListener('__bridge_push_json', handlePush);
	const messageTarget = messageEventTargetForBridgePushReceiver();
	messageTarget?.addEventListener('message', handleHostPortTransfer);
	target.dispatchEvent(new CustomEvent('__bridge_host_push_port_request'));
	return (): void => {
		target.removeEventListener('__bridge_push', handlePush);
		target.removeEventListener('__bridge_push_json', handlePush);
		messageTarget?.removeEventListener('message', handleHostPortTransfer);
		for (const port of hostPorts) {
			port.removeEventListener('message', handleHostPortEnvelope);
			port.close();
		}
		hostPorts.clear();
	};
}

function extractCustomEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}

function hasMatchingPushNonce(
	value: unknown,
	pushNonce: string,
): value is { readonly nonce: string } {
	if (typeof value !== 'object' || value === null || !('nonce' in value)) {
		return false;
	}
	return value.nonce === pushNonce;
}

function extractEnvelopeValue(detail: { readonly nonce: string }): unknown {
	if ('json' in detail && typeof detail.json === 'string') {
		return JSON.parse(detail.json);
	}
	return detail;
}

function messageEventTargetForBridgePushReceiver(): Window | null {
	return typeof window === 'undefined' ? null : window;
}

function isBridgeHostPushPortMessage(
	value: unknown,
): value is { readonly type: 'agentstudio.bridge.hostPushPort'; readonly version: 1 } {
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return (
		'type' in value &&
		value.type === 'agentstudio.bridge.hostPushPort' &&
		'version' in value &&
		value.version === 1
	);
}

function isBridgeHostPushEnvelopeMessage(value: unknown): value is {
	readonly json: string;
	readonly type: 'agentstudio.bridge.hostPushEnvelopeJSON';
	readonly version: 1;
} {
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return (
		'type' in value &&
		value.type === 'agentstudio.bridge.hostPushEnvelopeJSON' &&
		'version' in value &&
		value.version === 1 &&
		'json' in value &&
		typeof value.json === 'string'
	);
}

function shouldAcceptEnvelope(
	envelope: BridgePushEnvelope,
	revisionsByStoreSlice: Map<string, StoreRevisionState>,
): boolean {
	const revisionKey = `${envelope.store}:${envelope.slice}`;
	const previous = revisionsByStoreSlice.get(revisionKey);
	if (previous !== undefined) {
		if (envelope.epoch < previous.epoch) {
			return false;
		}
		if (envelope.epoch === previous.epoch && envelope.revision <= previous.revision) {
			return false;
		}
	}
	revisionsByStoreSlice.set(revisionKey, {
		epoch: envelope.epoch,
		revision: envelope.revision,
	});
	return true;
}
