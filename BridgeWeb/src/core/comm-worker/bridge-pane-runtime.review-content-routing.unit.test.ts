import { afterEach, describe, expect, test, vi } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgePaneCommWorkerDispatcher } from './bridge-pane-comm-worker-session.js';
import { createBridgePaneRuntime, type BridgePaneSessionPort } from './bridge-pane-runtime.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	commitBridgeWorkerReviewContentReadyRenderPatch,
	prepareBridgeWorkerReviewContentRenderJobEvent,
} from './bridge-worker-review-content-ready.js';

describe('Bridge pane runtime Review content routing', () => {
	afterEach((): void => {
		vi.unstubAllGlobals();
	});

	test('delivers Review content-ready publications only to the Review surface client', () => {
		// Arrange
		vi.stubGlobal('cancelAnimationFrame', vi.fn());
		vi.stubGlobal(
			'requestAnimationFrame',
			vi.fn((): number => 1),
		);
		let publishWorkerMessages:
			| ((messages: readonly BridgeWorkerServerToMainMessage[]) => void)
			| undefined;
		const session: BridgePaneSessionPort = {
			createDispatcher: (props): BridgePaneCommWorkerDispatcher => {
				publishWorkerMessages = props.publishWorkerMessages;
				return { dispatch: vi.fn(), dispose: vi.fn() };
			},
			dispose: vi.fn(),
			installNativeBootstrap: vi.fn(),
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});
		const fileMessages: BridgeWorkerServerToMainMessage[] = [];
		const reviewMessages: BridgeWorkerServerToMainMessage[] = [];
		runtime.surfaceClient('fileView').subscribeMessages((message): void => {
			fileMessages.push(message);
		});
		runtime.surfaceClient('review').subscribeMessages((message): void => {
			reviewMessages.push(message);
		});
		const publications = makeReviewContentReadyPublications();

		// Act
		publishWorkerMessages?.(publications);

		// Assert
		expect(reviewMessages).toEqual(publications);
		expect(reviewMessages.map(({ kind }) => kind)).toEqual([
			'reviewPierreRenderJob',
			'reviewRenderPatch',
		]);
		expect(fileMessages).toEqual([]);
		runtime.dispose();
	});
});

function makeReviewContentReadyPublications(): readonly BridgeWorkerServerToMainMessage[] {
	const store = createBridgeCommWorkerStore({
		surface: 'review',
		contentItems: [makeWorkerReviewContentMetadata()],
		rows: [{ id: 'item-1', parentId: null, index: 0 }],
	});
	const preparedJobEvent = prepareBridgeWorkerReviewContentRenderJobEvent({
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: {
			className: 'interactive',
			maxBytes: 512 * 1024,
			maxWindowLines: 50,
		},
		publicationSequence: 11,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: 'item-1',
			publicationSequence: 11,
			surface: 'review',
			workerDerivationEpoch: 7,
		}),
		resources: [
			makeFetchedReviewContentResource({
				contentHash: 'sha256:item-1:base',
				role: 'base',
				text: 'base content\n',
			}),
			makeFetchedReviewContentResource({
				contentHash: 'sha256:item-1:head',
				role: 'head',
				text: 'head content\n',
			}),
		],
		semantics: makeRenderSemantics(),
		workerDerivationEpoch: 7,
	});
	if (preparedJobEvent === null) {
		throw new Error('Expected review render job event.');
	}
	const contentReadyCommit = commitBridgeWorkerReviewContentReadyRenderPatch({
		preparedJobEvent,
		publicationSequence: 11,
		store,
		workerDerivationEpoch: 7,
	});
	return [preparedJobEvent.message, contentReadyCommit.preparedMessage.message];
}

function makeWorkerReviewContentMetadata(): BridgeWorkerReviewContentMetadata {
	return {
		itemId: 'item-1',
		path: 'Sources/App/item-1.swift',
		language: 'swift',
		cacheKey: 'item-1:base|item-1:head',
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeRenderSemantics(): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/item-1.swift',
		basePath: 'Sources/App/item-1.swift',
		headPath: 'Sources/App/item-1.swift',
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeFetchedReviewContentResource(props: {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text: string;
}): BridgeWorkerFetchedReviewContentResource {
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		descriptorId: `descriptor-item-1-${props.role}`,
		language: 'swift',
		byteLength: textBytes.byteLength,
		observedSha256: props.role === 'base' ? 'a'.repeat(64) : 'b'.repeat(64),
		requestId: `content-request-item-1-${props.role}`,
		sourceGeneration: 7,
		sourceIdentity: 'review-source-1',
		sourcePosition: 'whole',
		text: props.text,
		textBytes,
	};
}
