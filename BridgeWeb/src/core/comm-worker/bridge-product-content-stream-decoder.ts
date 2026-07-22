import type {
	BridgeProductContentFrame,
	BridgeProductContentFrameFor,
	BridgeProductContentKind,
	BridgeProductContentRequestFor,
	BridgeProductContentTerminal,
} from './bridge-product-content-contracts.js';
import { BridgeProductContentStreamValidator } from './bridge-product-content-frame-codec.js';
import { BridgeProductContentFrameDecoder } from './bridge-product-content-frame-decoder.js';

export type BridgeProductContentStreamDecoderState = 'open' | 'poisoned' | 'terminal';

export interface BridgeProductContentStreamDecodeResult<
	TContentKind extends BridgeProductContentKind,
> {
	readonly frames: readonly BridgeProductContentFrameFor<TContentKind>[];
	readonly terminal: BridgeProductContentTerminal<TContentKind> | null;
}

/**
 * Owns byte framing and request-correlated lifecycle validation for one content response.
 * A terminal or failed response releases both owners so no partial wire or content bytes remain.
 */
export class BridgeProductContentStreamDecoder<
	TContentKind extends BridgeProductContentKind = BridgeProductContentKind,
> {
	readonly #contentKind: TContentKind;
	#frameDecoder: BridgeProductContentFrameDecoder | null;
	#state: BridgeProductContentStreamDecoderState = 'open';
	#streamValidator: BridgeProductContentStreamValidator | null;

	constructor(expectedRequest: BridgeProductContentRequestFor<TContentKind>) {
		this.#contentKind = expectedRequest.contentKind;
		this.#frameDecoder = new BridgeProductContentFrameDecoder();
		this.#streamValidator = new BridgeProductContentStreamValidator(expectedRequest);
	}

	get retainedByteCount(): number {
		return this.#frameDecoder?.diagnostics.retainedByteCount ?? 0;
	}

	get state(): BridgeProductContentStreamDecoderState {
		return this.#state;
	}

	async push(chunk: Uint8Array): Promise<BridgeProductContentStreamDecodeResult<TContentKind>> {
		this.#throwIfUnavailableForPush();
		const frameDecoder = requireContentFrameDecoder(this.#frameDecoder);
		const streamValidator = requireContentStreamValidator(this.#streamValidator);
		try {
			const decodedFrames = frameDecoder.push(chunk);
			const correlatedFrames: BridgeProductContentFrameFor<TContentKind>[] = [];
			let terminal: BridgeProductContentTerminal<TContentKind> | null = null;
			for (const frame of decodedFrames) {
				// eslint-disable-next-line no-await-in-loop -- Stream lifecycle validation is ordered.
				const validatedTerminal = await streamValidator.accept(frame);
				correlatedFrames.push(correlateBridgeProductContentFrame(frame, this.#contentKind));
				if (validatedTerminal !== null) {
					terminal = correlateBridgeProductContentTerminal(validatedTerminal, this.#contentKind);
				}
			}

			if (terminal !== null) {
				frameDecoder.finish();
				this.#state = 'terminal';
				this.#releaseOwnedState();
			}
			return { frames: correlatedFrames, terminal };
		} catch (error) {
			this.#state = 'poisoned';
			this.#releaseOwnedState();
			throw error;
		}
	}

	finish(): void {
		if (this.#state === 'terminal') return;
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content stream decoder is poisoned.');
		}
		try {
			requireContentFrameDecoder(this.#frameDecoder).finish();
			requireContentStreamValidator(this.#streamValidator).finish();
		} catch (error) {
			this.#state = 'poisoned';
			this.#releaseOwnedState();
			throw error;
		}
	}

	#releaseOwnedState(): void {
		this.#frameDecoder = null;
		this.#streamValidator = null;
	}

	#throwIfUnavailableForPush(): void {
		if (this.#state === 'terminal') {
			throw new Error('Bridge product content stream decoder cannot receive post-terminal bytes.');
		}
		if (this.#state === 'poisoned') {
			throw new Error('Bridge product content stream decoder is poisoned.');
		}
	}
}

function correlateBridgeProductContentFrame<TContentKind extends BridgeProductContentKind>(
	frame: BridgeProductContentFrame,
	expectedContentKind: TContentKind,
): BridgeProductContentFrameFor<TContentKind> {
	if (frame.header.kind === 'content.accepted') {
		if (frame.header.identity.contentKind !== expectedContentKind) {
			throw new Error('Bridge product content acceptance failed content-kind correlation.');
		}
		return frame;
	}
	return frame;
}

function correlateBridgeProductContentTerminal<TContentKind extends BridgeProductContentKind>(
	terminal: BridgeProductContentTerminal<BridgeProductContentKind>,
	expectedContentKind: TContentKind,
): BridgeProductContentTerminal<TContentKind> {
	if (terminal.contentKind !== expectedContentKind) {
		throw new Error('Bridge product content terminal failed content-kind correlation.');
	}
	return terminal as BridgeProductContentTerminal<TContentKind>;
}

function requireContentFrameDecoder(
	frameDecoder: BridgeProductContentFrameDecoder | null,
): BridgeProductContentFrameDecoder {
	if (frameDecoder === null) {
		throw new Error('Bridge product content stream decoder released its frame owner.');
	}
	return frameDecoder;
}

function requireContentStreamValidator(
	streamValidator: BridgeProductContentStreamValidator | null,
): BridgeProductContentStreamValidator {
	if (streamValidator === null) {
		throw new Error('Bridge product content stream decoder released its validation owner.');
	}
	return streamValidator;
}
