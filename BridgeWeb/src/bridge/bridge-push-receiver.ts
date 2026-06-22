import type { BridgePushEnvelope } from './bridge-push-envelope.js';
import { decodeBridgePushEnvelope } from './bridge-push-envelope.js';

export type BridgePushDropReason =
	| 'missing_push_nonce'
	| 'push_decode_failed'
	| 'push_nonce_mismatch'
	| 'stale_push';

export interface InstallBridgePushReceiverProps {
	readonly target?: EventTarget;
	readonly getPushNonce: () => string | null;
	readonly onEnvelope: (envelope: BridgePushEnvelope) => void;
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

		let envelope: BridgePushEnvelope;
		try {
			envelope = decodeBridgePushEnvelope(extractEnvelopeValue(detail));
		} catch (error) {
			props.onInvalidEnvelope?.(error instanceof Error ? error : new Error(String(error)));
			props.onDroppedEnvelope?.('push_decode_failed');
			return;
		}

		if (!shouldAcceptEnvelope(envelope, revisionsByStoreSlice)) {
			props.onDroppedEnvelope?.('stale_push');
			return;
		}
		props.onEnvelope(envelope);
	};

	target.addEventListener('__bridge_push', handlePush);
	target.addEventListener('__bridge_push_json', handlePush);
	return (): void => {
		target.removeEventListener('__bridge_push', handlePush);
		target.removeEventListener('__bridge_push_json', handlePush);
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
