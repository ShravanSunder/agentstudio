import { encodeBridgeProductMetadataFrame } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	writeBridgeProductDevResponseChunk,
	type BridgeProductDevWritableResponse,
} from './bridge-product-dev-http.js';

type BridgeProductMetadataFrameIdentityKey =
	| 'metadataStreamId'
	| 'paneSessionId'
	| 'streamSequence'
	| 'wireVersion'
	| 'workerInstanceId';

type BridgeProductSubscriptionFrameIdentityKey =
	| 'cursor'
	| 'interestRevision'
	| 'interestSha256'
	| 'sourceGeneration'
	| 'subscriptionId'
	| 'subscriptionKind'
	| 'subscriptionSequence'
	| 'workerDerivationEpoch';

type OmitBridgeProductMetadataFrameIdentity<TFrame> = TFrame extends BridgeProductMetadataFrame
	? Omit<TFrame, BridgeProductMetadataFrameIdentityKey>
	: never;

export type BridgeProductDevMetadataFramePayload =
	OmitBridgeProductMetadataFrameIdentity<BridgeProductMetadataFrame>;

type BridgeProductSubscriptionFrame = Extract<
	BridgeProductMetadataFrame,
	{
		readonly kind:
			| 'subscription.accepted'
			| 'subscription.cancelled'
			| 'subscription.data'
			| 'subscription.interestsCommitted';
	}
>;

type OmitBridgeProductSubscriptionFrameIdentity<TFrame> =
	TFrame extends BridgeProductSubscriptionFrame
		? Omit<
				OmitBridgeProductMetadataFrameIdentity<TFrame>,
				BridgeProductSubscriptionFrameIdentityKey
			>
		: never;

export type BridgeProductDevSubscriptionFramePayload =
	OmitBridgeProductSubscriptionFrameIdentity<BridgeProductSubscriptionFrame>;

export type BridgeProductDevSubscriptionFrameIdentity = Pick<
	Extract<BridgeProductMetadataFrame, { readonly kind: 'subscription.data' }>,
	Exclude<BridgeProductSubscriptionFrameIdentityKey, 'subscriptionSequence'>
>;

export interface BridgeProductDevSubscriptionSequenceState {
	sequence: number;
}

export interface BridgeProductDevMetadataWriterProps {
	readonly initialStreamSequence?: number;
	readonly metadataStreamId: string;
	readonly paneSessionId: string;
	readonly response: BridgeProductDevWritableResponse;
	readonly workerInstanceId: string;
}

interface BridgeProductDevPendingFrame {
	readonly frame: BridgeProductMetadataFrame;
	readonly onWritten?: () => void;
}

export class BridgeProductDevMetadataWriter {
	readonly #metadataStreamId: string;
	readonly #paneSessionId: string;
	#pendingWrite: Promise<void> = Promise.resolve();
	readonly #response: BridgeProductDevWritableResponse;
	#streamSequence: number;
	readonly #workerInstanceId: string;

	constructor(props: BridgeProductDevMetadataWriterProps) {
		const initialStreamSequence = props.initialStreamSequence ?? 0;
		if (!Number.isSafeInteger(initialStreamSequence) || initialStreamSequence < 0) {
			throw new Error('Bridge product dev metadata initial sequence must be nonnegative.');
		}
		this.#metadataStreamId = props.metadataStreamId;
		this.#paneSessionId = props.paneSessionId;
		this.#response = props.response;
		this.#streamSequence = initialStreamSequence - 1;
		this.#workerInstanceId = props.workerInstanceId;
	}

	get response(): BridgeProductDevWritableResponse {
		return this.#response;
	}

	get streamSequence(): number {
		return this.#streamSequence;
	}

	writeMetadataFrame(payload: BridgeProductDevMetadataFramePayload): Promise<void> {
		return this.#enqueue((nextStreamSequence) => ({
			frame: bridgeProductMetadataFrameSchema.parse({
				...this.#metadataIdentity(nextStreamSequence),
				...payload,
			}),
		}));
	}

	writeSubscriptionFrame(
		subscription: BridgeProductDevSubscriptionFrameIdentity,
		sequenceState: BridgeProductDevSubscriptionSequenceState,
		payload: BridgeProductDevSubscriptionFramePayload,
	): Promise<void> {
		return this.#enqueue((nextStreamSequence) => {
			const nextSubscriptionSequence =
				payload.kind === 'subscription.accepted'
					? sequenceState.sequence
					: sequenceState.sequence + 1;
			return {
				frame: bridgeProductMetadataFrameSchema.parse({
					...this.#metadataIdentity(nextStreamSequence),
					...subscription,
					...payload,
					subscriptionSequence: nextSubscriptionSequence,
				}),
				onWritten: (): void => {
					sequenceState.sequence = nextSubscriptionSequence;
				},
			};
		});
	}

	end(): void {
		this.#response.end();
	}

	#enqueue(
		buildFrame: (nextStreamSequence: number) => BridgeProductDevPendingFrame,
	): Promise<void> {
		const write = this.#pendingWrite.then(async (): Promise<void> => {
			if (this.#response.destroyed) {
				throw new Error('Bridge product dev metadata response is closed.');
			}
			const pendingFrame = buildFrame(this.#streamSequence + 1);
			await writeBridgeProductDevResponseChunk(
				this.#response,
				encodeBridgeProductMetadataFrame(pendingFrame.frame),
			);
			this.#streamSequence = pendingFrame.frame.streamSequence;
			pendingFrame.onWritten?.();
		});
		this.#pendingWrite = write;
		void write.catch((): void => {});
		return write;
	}

	#metadataIdentity(streamSequence: number): {
		readonly metadataStreamId: string;
		readonly paneSessionId: string;
		readonly streamSequence: number;
		readonly wireVersion: 2;
		readonly workerInstanceId: string;
	} {
		return {
			metadataStreamId: this.#metadataStreamId,
			paneSessionId: this.#paneSessionId,
			streamSequence,
			wireVersion: 2,
			workerInstanceId: this.#workerInstanceId,
		};
	}
}
