import { describe, expect, test } from 'vitest';

import {
	type BridgeCommWorkerPort,
	createBridgeCommWorkerScopePortAdapter,
	postPreparedBridgeCommWorkerMessage,
	registerInertBridgeCommWorkerPortProtocol,
} from './bridge-comm-worker-entry.js';
import type {
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import { prepareBridgeWorkerReviewContentRenderJobEvent } from './bridge-worker-review-content-ready.js';

interface PostedBridgeWorkerMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

function assertPreparedEntryPostRejectsSyntheticMessages(port: BridgeCommWorkerPort): void {
	const syntheticPreparedMessage = {
		message: {
			kind: 'pierreRenderJob',
			transferDescriptors: [],
		},
		transferList: [],
	};
	// @ts-expect-error Entry posting accepts only schema-derived server-to-main worker DTOs.
	postPreparedBridgeCommWorkerMessage(port, syntheticPreparedMessage);
}

function assertBrowserMessagePortMatchesEntryPort(port: MessagePort): BridgeCommWorkerPort {
	return port;
}

describe('Bridge comm worker entry', () => {
	test('posts prepared review content-ready worker messages with transfer lists', () => {
		const postedMessages: PostedBridgeWorkerMessage[] = [];
		const port: BridgeCommWorkerPort = {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		};
		const baseTextBytes = new ArrayBuffer(40);
		const headTextBytes = new ArrayBuffer(64);
		const preparedMessage = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					textBytes: baseTextBytes,
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					textBytes: headTextBytes,
				}),
			],
			semantics: makeRenderSemantics(),
		});
		if (preparedMessage === null) {
			throw new Error('Expected review content-ready render job.');
		}

		postPreparedBridgeCommWorkerMessage(port, preparedMessage);

		expect(postedMessages).toEqual([
			{
				message: preparedMessage.message,
				transferList: [baseTextBytes, headTextBytes],
			},
		]);
		expect(postedMessages[0]?.transferList).not.toBe(preparedMessage.transferList);
		expect(typeof assertPreparedEntryPostRejectsSyntheticMessages).toBe('function');
		expect(typeof assertBrowserMessagePortMatchesEntryPort).toBe('function');
	});

	test('forwards prepared transfer lists through the worker scope adapter', () => {
		const postedMessages: PostedBridgeWorkerMessage[] = [];
		const scope = {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		};
		const textBytes = new ArrayBuffer(32);
		const preparedMessage = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					role: 'file',
					textBytes,
				}),
			],
			semantics: makeRenderSemantics({
				changeKind: 'modified',
				contentLineCountsByRole: { file: 80 },
				itemKind: 'file',
			}),
		});
		if (preparedMessage === null) {
			throw new Error('Expected review content-ready render job.');
		}

		postPreparedBridgeCommWorkerMessage(
			createBridgeCommWorkerScopePortAdapter(scope),
			preparedMessage,
		);

		expect(postedMessages).toEqual([
			{
				message: preparedMessage.message,
				transferList: [textBytes],
			},
		]);
	});

	test('preserves inert ready health replies on the one-argument post path', () => {
		const { dispatch, postedMessages, started } = createRecordingBridgeCommWorkerPort();
		registerInertBridgeCommWorkerPortProtocol(dispatch.port);

		dispatch.message({
			wireVersion: 1,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-1',
			epoch: 0,
			transferDescriptors: [],
			selectedItemId: 'item-1',
			selectedSource: 'user',
		});

		expect(started()).toBe(true);
		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-1',
					status: 'ready',
					transferDescriptors: [],
				},
				transferList: undefined,
			},
		]);
	});

	test('preserves inert degraded health replies for invalid messages', () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerInertBridgeCommWorkerPortProtocol(dispatch.port);

		dispatch.message({ kind: 'not-a-bridge-worker-message' });

		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					status: 'degraded',
					message: 'Bridge comm worker received invalid message.',
					transferDescriptors: [],
				},
				transferList: undefined,
			},
		]);
	});
});

function createRecordingBridgeCommWorkerPort(): {
	readonly dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: BridgeCommWorkerPort;
	};
	readonly postedMessages: PostedBridgeWorkerMessage[];
	readonly started: () => boolean;
} {
	const postedMessages: PostedBridgeWorkerMessage[] = [];
	let listener: ((event: MessageEvent<unknown>) => void) | null = null;
	let didStart = false;
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
				start: (): void => {
					didStart = true;
				},
			},
		},
		postedMessages,
		started: (): boolean => didStart,
	};
}

function makeRenderSemantics(
	overrides: Partial<BridgeWorkerReviewRenderSemantics> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/item-1.swift',
		basePath: 'Sources/App/item-1.swift',
		headPath: 'Sources/App/item-1.swift',
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
		...overrides,
	};
}

function makeFetchedReviewContentResource(props: {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly textBytes: ArrayBuffer;
}): BridgeWorkerFetchedReviewContentResource {
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		byteLength: props.textBytes.byteLength,
		textBytes: props.textBytes,
	};
}
