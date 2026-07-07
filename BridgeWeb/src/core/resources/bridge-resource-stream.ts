import type { BridgeIntegrityDescriptor } from '../models/bridge-resource-descriptor.js';
import { verifyBridgeResourceIntegrity } from './bridge-integrity.js';

export interface BridgeTextResourceStreamResult {
	readonly authoritative: boolean;
	readonly byteLength: number;
	copyBytes(): ArrayBuffer;
	readText(): string;
}

export interface BridgeTextResourceLoadTiming {
	readonly firstChunkWaitMilliseconds: number | null;
	readonly responseWaitMilliseconds: number;
	readonly streamReadMilliseconds: number;
}

export interface BridgeTextResourceLoadTimingResult extends BridgeTextResourceStreamResult {
	readonly timing?: BridgeTextResourceLoadTiming | undefined;
}

export interface BridgeTextResourceLoadTimingProbe {
	isEnabled(): boolean;
	now(): number;
}

export interface BridgeTextResourceStreamChunk {
	readonly byteLength: number;
	readonly text: string;
	readonly totalBytesRead: number;
}

export type BridgeTextResourceLoadFailureKind =
	| 'http_error'
	| 'missing_body'
	| 'byte_limit_exceeded'
	| 'integrity_mismatch'
	| 'chunk_manifest_unsupported';

export class BridgeTextResourceLoadError extends Error {
	readonly kind: BridgeTextResourceLoadFailureKind;

	constructor(kind: BridgeTextResourceLoadFailureKind, message: string) {
		super(message);
		this.name = 'BridgeTextResourceLoadError';
		this.kind = kind;
	}
}

export function bridgeTextResourceLoadErrorKind(
	error: unknown,
): BridgeTextResourceLoadFailureKind | null {
	return error instanceof BridgeTextResourceLoadError ? error.kind : null;
}

export async function loadBridgeTextResourceWithTiming(props: {
	readonly integrity?: BridgeIntegrityDescriptor | undefined;
	readonly maxBytes?: number | undefined;
	readonly onTextChunk?: ((chunk: BridgeTextResourceStreamChunk) => void) | undefined;
	readonly performFetch: () => Promise<Response>;
	readonly probe?: BridgeTextResourceLoadTimingProbe | undefined;
	readonly signal?: AbortSignal | undefined;
}): Promise<BridgeTextResourceLoadTimingResult> {
	if (props.probe === undefined || !props.probe.isEnabled()) {
		const response = await props.performFetch();
		if (!response.ok) {
			throw new BridgeTextResourceLoadError(
				'http_error',
				`Bridge text resource request failed: ${response.status}`,
			);
		}
		return await readBridgeTextResourceStream(response, {
			integrity: props.integrity,
			maxBytes: props.maxBytes,
			onTextChunk: props.onTextChunk,
			signal: props.signal,
		});
	}
	const requestStartedAtMilliseconds = props.probe.now();
	const response = await props.performFetch();
	const responseReceivedAtMilliseconds = props.probe.now();
	if (!response.ok) {
		throw new BridgeTextResourceLoadError(
			'http_error',
			`Bridge text resource request failed: ${response.status}`,
		);
	}
	const streamReadStartedAtMilliseconds = props.probe.now();
	let firstChunkAtMilliseconds: number | null = null;
	const streamedResource = await readBridgeTextResourceStream(response, {
		integrity: props.integrity,
		maxBytes: props.maxBytes,
		onTextChunk: (chunk): void => {
			firstChunkAtMilliseconds ??= props.probe?.now() ?? null;
			props.onTextChunk?.(chunk);
		},
		signal: props.signal,
	});
	const streamReadFinishedAtMilliseconds = props.probe.now();
	return {
		...streamedResource,
		timing: {
			firstChunkWaitMilliseconds:
				firstChunkAtMilliseconds === null
					? null
					: Math.max(0, firstChunkAtMilliseconds - streamReadStartedAtMilliseconds),
			responseWaitMilliseconds: Math.max(
				0,
				responseReceivedAtMilliseconds - requestStartedAtMilliseconds,
			),
			streamReadMilliseconds: Math.max(
				0,
				streamReadFinishedAtMilliseconds - streamReadStartedAtMilliseconds,
			),
		},
	};
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
		throw new BridgeTextResourceLoadError(
			'missing_body',
			'Bridge text resource response did not expose a body stream.',
		);
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
			// oxlint-disable-next-line no-await-in-loop -- ReadableStream chunks must be consumed in order.
			const chunk = await reader.read();
			if (chunk.done) {
				break;
			}
			byteLength += chunk.value.byteLength;
			if (props.maxBytes !== undefined && byteLength > props.maxBytes) {
				throw new BridgeTextResourceLoadError(
					'byte_limit_exceeded',
					'Bridge text resource stream exceeded issued max bytes',
				);
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
			throw new BridgeTextResourceLoadError(
				integrityResult.reason,
				'Bridge text resource stream failed whole-body integrity validation',
			);
		}
		let memoizedText: string | null = null;
		return {
			authoritative: integrityResult.authoritative,
			byteLength,
			copyBytes: (): ArrayBuffer => copyBytesToArrayBuffer(data),
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

function copyBytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
	const copiedBytes = new Uint8Array(bytes.byteLength);
	copiedBytes.set(bytes);
	return copiedBytes.buffer;
}
