import type { BridgeIntegrityDescriptor } from '../models/bridge-resource-descriptor.js';
import { verifyBridgeResourceIntegrity } from './bridge-integrity.js';

export interface BridgeTextResourceStreamResult {
	readonly authoritative: boolean;
	readonly byteLength: number;
	readText(): string;
}

export interface BridgeTextResourceStreamChunk {
	readonly byteLength: number;
	readonly text: string;
	readonly totalBytesRead: number;
}

export async function readBridgeTextResourceStream(
	response: Response,
	props: {
		readonly integrity?: BridgeIntegrityDescriptor | undefined;
		readonly maxBytes?: number | undefined;
		readonly onTextChunk?: ((chunk: BridgeTextResourceStreamChunk) => void) | undefined;
		readonly signal?: AbortSignal | undefined;
	} = {},
): Promise<BridgeTextResourceStreamResult> {
	if (response.body === null) {
		throw new Error('Bridge text resource response did not expose a body stream.');
	}
	const reader = response.body.getReader();
	const chunkDecoder = new TextDecoder();
	const chunks: Uint8Array[] = [];
	let byteLength = 0;
	try {
		while (true) {
			if (props.signal?.aborted === true) {
				throw new DOMException('Bridge text resource stream aborted', 'AbortError');
			}
			const chunk = await reader.read();
			if (chunk.done) {
				break;
			}
			byteLength += chunk.value.byteLength;
			if (props.maxBytes !== undefined && byteLength > props.maxBytes) {
				throw new Error('Bridge text resource stream exceeded issued max bytes');
			}
			chunks.push(chunk.value);
			if (props.onTextChunk !== undefined) {
				const decodedText = chunkDecoder.decode(chunk.value, { stream: true });
				props.onTextChunk({
					byteLength: chunk.value.byteLength,
					text: decodedText,
					totalBytesRead: byteLength,
				});
			}
		}
		if (props.onTextChunk !== undefined) {
			const finalText = chunkDecoder.decode();
			if (finalText.length > 0) {
				props.onTextChunk({
					byteLength: 0,
					text: finalText,
					totalBytesRead: byteLength,
				});
			}
		}
		const data = concatenateChunks({ byteLength, chunks });
		const integrityResult = await verifyBridgeResourceIntegrity({
			data,
			integrity: props.integrity,
		});
		if (!integrityResult.ok) {
			throw new Error('Bridge text resource stream failed whole-body integrity validation');
		}
		let memoizedText: string | null = null;
		return {
			authoritative: integrityResult.authoritative,
			byteLength,
			readText: (): string => {
				memoizedText ??= new TextDecoder().decode(data);
				return memoizedText;
			},
		};
	} finally {
		reader.releaseLock();
	}
}

function concatenateChunks(props: {
	readonly byteLength: number;
	readonly chunks: readonly Uint8Array[];
}): Uint8Array {
	const data = new Uint8Array(props.byteLength);
	let offset = 0;
	for (const chunk of props.chunks) {
		data.set(chunk, offset);
		offset += chunk.byteLength;
	}
	return data;
}
