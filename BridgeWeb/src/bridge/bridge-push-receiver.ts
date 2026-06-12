import type { BridgePushEnvelope, BridgePushStore } from './bridge-push-envelope.js';
import { decodeBridgePushEnvelope } from './bridge-push-envelope.js';

export interface InstallBridgePushReceiverProps {
	readonly target?: EventTarget;
	readonly getPushNonce: () => string | null;
	readonly onEnvelope: (envelope: BridgePushEnvelope) => void;
	readonly onInvalidEnvelope?: (error: Error) => void;
}

interface StoreRevisionState {
	epoch: number;
	revision: number;
}

export function installBridgePushReceiver(props: InstallBridgePushReceiverProps): () => void {
	const target = props.target ?? document;
	const revisionsByStore = new Map<BridgePushStore, StoreRevisionState>();

	const handlePush = (event: Event): void => {
		const pushNonce = props.getPushNonce();
		if (pushNonce === null) {
			return;
		}
		const detail = extractCustomEventDetail(event);
		if (!hasMatchingPushNonce(detail, pushNonce)) {
			return;
		}

		let envelope: BridgePushEnvelope;
		try {
			envelope = decodeBridgePushEnvelope(detail);
		} catch (error) {
			props.onInvalidEnvelope?.(error instanceof Error ? error : new Error(String(error)));
			return;
		}

		if (!shouldAcceptEnvelope(envelope, revisionsByStore)) {
			return;
		}
		props.onEnvelope(envelope);
	};

	target.addEventListener('__bridge_push', handlePush);
	return (): void => {
		target.removeEventListener('__bridge_push', handlePush);
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

function shouldAcceptEnvelope(
	envelope: BridgePushEnvelope,
	revisionsByStore: Map<BridgePushStore, StoreRevisionState>,
): boolean {
	const previous = revisionsByStore.get(envelope.store);
	if (previous !== undefined) {
		if (envelope.epoch < previous.epoch) {
			return false;
		}
		if (envelope.epoch === previous.epoch && envelope.revision <= previous.revision) {
			return false;
		}
	}
	revisionsByStore.set(envelope.store, {
		epoch: envelope.epoch,
		revision: envelope.revision,
	});
	return true;
}
