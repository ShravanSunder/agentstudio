import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import { bridgeProductFileMetadataSubscriptionDataSchema } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';

export interface FileRenewalWireEvent {
	readonly eventKind: string;
	readonly path: string | null;
	readonly descriptorSha256: string | null;
	readonly generation: number;
	readonly streamSequence: number;
}

// Diagnostic only: decode observed copies of real frames, never modify forwarding.
export class BridgeFileRenewalWireObserver {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #events: FileRenewalWireEvent[] = [];
	#decodeFailureCount = 0;

	observe(chunk: Uint8Array): void {
		try {
			for (const frame of this.#decoder.push(chunk)) {
				if (frame.kind !== 'subscription.data' || frame.subscriptionKind !== 'file.metadata')
					continue;
				const { event } = bridgeProductFileMetadataSubscriptionDataSchema.parse(frame.data);
				if (event.eventKind !== 'file.descriptorReady' && event.eventKind !== 'file.invalidated')
					continue;
				const availability =
					event.eventKind === 'file.descriptorReady'
						? event.availability
						: event.replacementDescriptor?.availability;
				if (this.#events.length < 256)
					this.#events.push({
						eventKind: event.eventKind,
						path: event.path,
						descriptorSha256:
							availability?.availabilityKind === 'available'
								? availability.contentDescriptor.expectedSha256
								: null,
						generation: event.source.subscriptionGeneration,
						streamSequence: frame.streamSequence,
					});
			}
		} catch {
			this.#decodeFailureCount += 1;
		}
	}

	snapshot(): {
		readonly events: readonly FileRenewalWireEvent[];
		readonly decodeFailureCount: number;
	} {
		return { events: [...this.#events], decodeFailureCount: this.#decodeFailureCount };
	}
}
