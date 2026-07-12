import { expect } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export interface PostedBridgeWorkerRuntimeMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

export const descriptorByUrl = new Map<
	string,
	{ readonly itemId: string; readonly text: string }
>();

export function createRecordingBridgeCommWorkerPort(): {
	readonly dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: BridgeCommWorkerPort;
	};
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
} {
	const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
	let listener: ((event: MessageEvent<unknown>) => void) | null = null;
	return {
		dispatch: {
			message: (data: unknown): void => {
				if (listener === null) {
					throw new Error('Bridge comm worker port listener was not registered.');
				}
				listener(new MessageEvent('message', { data }));
			},
			port: {
				postMessage: (
					message: BridgeWorkerServerToMainMessage,
					transferList?: Transferable[],
				): void => {
					postedMessages.push({ message, transferList });
				},
				addEventListener: (
					type: 'message',
					nextListener: (event: MessageEvent<unknown>) => void,
				): void => {
					expect(type).toBe('message');
					listener = nextListener;
				},
				start: (): void => {},
			},
		},
		postedMessages,
	};
}

export function createBridgeWorkerSequenceCounter(firstSequence: number): () => number {
	let nextSequence = firstSequence;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

export function assertBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain | undefined,
): BridgeCommWorkerPreparationDrain {
	if (drain === undefined) {
		throw new Error('Expected scheduled bridge comm worker preparation drain.');
	}
	return drain;
}

export async function flushBridgeWorkerRuntimeContinuations(): Promise<void> {
	await Array.from({ length: 50 }).reduce<Promise<void>>(
		(previousFlush) => previousFlush.then(() => Promise.resolve()),
		Promise.resolve(),
	);
}

export function makeImmediateTextResponse(text: string): Response {
	const encodedText = new TextEncoder().encode(text);
	return new Response(
		new ReadableStream({
			start: (controller): void => {
				controller.enqueue(encodedText);
				controller.close();
			},
		}),
	);
}

export interface DeferredTextResponse {
	readonly promise: Promise<Response>;
	readonly resolve: (text: string) => void;
}

export function createDeferredTextResponse(): DeferredTextResponse {
	let resolveResponse: ((response: Response) => void) | null = null;
	const promise = new Promise<Response>((resolve) => {
		resolveResponse = resolve;
	});
	return {
		promise,
		resolve: (text: string): void => {
			if (resolveResponse === null) {
				throw new Error('Deferred response resolver was not initialized.');
			}
			resolveResponse(makeImmediateTextResponse(text));
		},
	};
}

export function makeWorkerReviewContentMetadata(
	props: { readonly itemId?: string } = {},
): BridgeWorkerReviewContentMetadata {
	const itemId = props.itemId ?? 'item-1';
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `${itemId}:base|${itemId}:head`,
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

export function makeWorkerFileViewContentMetadata(): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId: 'file-1',
		path: 'Sources/App/file-1.swift',
		language: 'swift',
		cacheKey: 'file-view:metadata-cache:file-1',
		sizeBytes: 128,
		descriptorId: 'descriptor-file-1',
		contentHash: 'sha256:file-1',
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount: 128,
		payloadLineCount: 1,
		totalLineCount: 1,
		truncationKind: 'none',
		isBinary: false,
		canFetchContent: true,
	};
}

export function makeRenderSemantics(
	props: { readonly itemId?: string } = {},
): BridgeWorkerReviewRenderSemantics {
	const itemId = props.itemId ?? 'item-1';
	return {
		itemId,
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: `Sources/App/${itemId}.swift`,
		basePath: `Sources/App/${itemId}.swift`,
		headPath: `Sources/App/${itemId}.swift`,
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

export function makeContentRequestDescriptor(props: {
	readonly generation?: number;
	readonly itemId?: string;
	readonly role: BridgeWorkerReviewContentRequestDescriptor['role'];
	readonly text: string;
}): BridgeWorkerReviewContentRequestDescriptor {
	const generation = props.generation ?? 4;
	const itemId = props.itemId ?? 'item-1';
	const textByteLength = new TextEncoder().encode(props.text).byteLength;
	const descriptor: BridgeWorkerReviewContentRequestDescriptor = {
		itemId,
		role: props.role,
		handleId: `handle-${itemId}-${props.role}`,
		reviewGeneration: generation,
		resourceUrl: `agentstudio://resource/review/content/handle-${itemId}-${props.role}?generation=${generation}`,
		contentHash: `sha256:${itemId}:${props.role}:generation-${generation}`,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		sizeBytes: textByteLength,
		expectedBytes: textByteLength,
		maxBytes: Math.max(textByteLength, 1),
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { itemId, text: props.text });
	return descriptor;
}
