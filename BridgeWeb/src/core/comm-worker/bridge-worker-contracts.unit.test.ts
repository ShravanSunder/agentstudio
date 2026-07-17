import { describe, expect, expectTypeOf, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { makeContentRequestDescriptor } from './bridge-comm-worker-runtime-protocol.test-support.js';
import { parseBridgeWorkerMainToServerMessage } from './bridge-worker-contract-parsers.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerReviewRenderSemanticsSchema,
	bridgeWorkerFileViewContentMetadataSchema,
	bridgeWorkerReviewContentRequestDescriptorSchema,
	bridgeWorkerReviewContentMetadataSchema,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	bridgeWorkerSlicePatchEventSchema,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerFileViewContentMetadata,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';

describe('BridgeWorkerContracts', () => {
	test('accepts policy-only session bootstrap and rejects every legacy runtime carrier', () => {
		// Arrange
		const policyOnlyBootstrap = {
			schemaVersion: BRIDGE_WORKER_WIRE_VERSION,
			method: 'bridgeCommWorker.bootstrap',
			requestId: 'policy-only-bootstrap',
			runtime: {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 400,
				},
			},
		};

		// Act
		const parsedBootstrap = bridgeCommWorkerBootstrapRequestSchema.safeParse(policyOnlyBootstrap);

		// Assert
		expect(parsedBootstrap.success).toBe(true);
		if (!parsedBootstrap.success) return;
		expect(parsedBootstrap.data).toEqual(policyOnlyBootstrap);
		for (const legacyRuntimeField of [
			'contentItems',
			'contentRequestDescriptors',
			'renderSemantics',
			'rows',
		] as const) {
			expect(
				bridgeCommWorkerBootstrapRequestSchema.safeParse({
					...policyOnlyBootstrap,
					runtime: {
						...policyOnlyBootstrap.runtime,
						[legacyRuntimeField]: [],
					},
				}).success,
				`expected strict bootstrap rejection for legacy runtime.${legacyRuntimeField}`,
			).toBe(false);
		}
	});

	test('rejects main-seeded Review source payloads from the worker command boundary', () => {
		// Arrange
		const mainSeededReviewSourceUpdate = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'reviewSourceUpdate',
			requestId: 'request-main-seeded-review-source',
			epoch: 3,
			transferDescriptors: [],
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
		};

		// Act
		const parsedMainSeededReviewSourceUpdate = bridgeWorkerMainToServerMessageSchema.safeParse(
			mainSeededReviewSourceUpdate,
		);

		// Assert
		expect(
			parsedMainSeededReviewSourceUpdate.success,
			'MAIN_SEEDED_REVIEW_SOURCE_UPDATE_ACCEPTED',
		).toBe(false);
		type ReviewSourceUpdateCommand = Extract<
			BridgeWorkerMainToServerMessage,
			{ readonly command: 'reviewSourceUpdate' }
		>;
		expectTypeOf<ReviewSourceUpdateCommand>().toEqualTypeOf<never>();
	});

	test('accepts strict Review projection intent and rejects extra projection authority', () => {
		// Arrange
		const reviewProjectionUpdate = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'reviewProjectionUpdate',
			requestId: 'request-review-projection',
			epoch: 8,
			transferDescriptors: [],
			query: {
				fileClassFilter: 'source',
				gitStatusFilter: 'added',
			},
		};

		// Act
		const parsedReviewProjectionUpdate =
			bridgeWorkerMainToServerMessageSchema.safeParse(reviewProjectionUpdate);
		const parsedReviewProjectionUpdateWithExtra = bridgeWorkerMainToServerMessageSchema.safeParse({
			...reviewProjectionUpdate,
			query: {
				...reviewProjectionUpdate.query,
				orderedItemIds: ['main-owned-item'],
			},
		});

		// Assert
		expect(parsedReviewProjectionUpdate.success).toBe(true);
		expect(parsedReviewProjectionUpdateWithExtra.success).toBe(false);
	});

	test('rejects untyped main to server worker messages at schema boundary', () => {
		const selectCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-select',
			epoch: 3,
			transferDescriptors: [],
			surface: 'review',
			selectedItemId: 'item-1',
			selectedSource: 'user',
		} satisfies BridgeWorkerMainToServerMessage;

		expect(parseBridgeWorkerMainToServerMessage(selectCommand)).toEqual(selectCommand);
		expect(bridgeWorkerMainToServerMessageSchema.safeParse(selectCommand).success).toBe(true);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...selectCommand,
				surface: undefined,
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...selectCommand,
				surface: 'all',
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...selectCommand,
				wireVersion: BRIDGE_WORKER_WIRE_VERSION + 1,
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				direction: 'mainToServerWorker',
				kind: 'command',
				command: 'startFetch',
				requestId: 'request-fetch',
				epoch: 3,
				transferDescriptors: [],
			}).success,
		).toBe(false);

		const healthEvent = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-select',
			status: 'ready',
		};
		expect(bridgeWorkerServerToMainMessageSchema.safeParse(healthEvent).success).toBe(true);
		expect(
			bridgeWorkerServerToMainMessageSchema.safeParse({
				...healthEvent,
				status: 'degraded',
				diagnostic: {
					kind: 'productMetadataStream',
					acknowledgedFrameCount: 1,
					activeSubscriptionCount: 1,
					committedFrameCount: 1,
					decoderState: 'poisoned',
					expectedNextStreamSequence: 1,
					failureStage: 'decode',
					failureCode: 'stream_identity_mismatch',
					identityMismatchField: 'metadataStreamId',
					lastChunkByteCount: 128,
					lastAcknowledgedStreamSequence: 0,
					lastCommittedFrameKind: 'metadataStream.accepted',
					lastRoutedFrameKind: 'metadataStream.accepted',
					lifecycleState: 'failed',
					peakRetainedByteCount: 512,
					pushCount: 2,
					readFulfilledCount: 2,
					readPending: false,
					readRequestCount: 2,
					receivedByteCount: 256,
					retainedByteCount: 0,
					routeFailureCode: null,
					routedFrameCount: 1,
					streamOpenCount: 1,
				},
			}).success,
		).toBe(true);

		const invalidCommand: BridgeWorkerMainToServerMessage = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			// @ts-expect-error Unknown command shapes must be rejected before runtime.
			command: 'startFetch',
			requestId: 'request-fetch',
			epoch: 3,
			transferDescriptors: [],
		};
		expectTypeOf(invalidCommand).toMatchTypeOf<BridgeWorkerMainToServerMessage>();
	});

	test('accepts only a closed identity-bound render disposition command', () => {
		// Arrange
		const renderDispositionCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'renderDisposition',
			requestId: 'request-render-disposition',
			epoch: 4,
			transferDescriptors: [],
			receipt: {
				kind: 'render.disposition',
				disposition: 'painted',
				receivedAtMilliseconds: 125,
				attemptId: 'render-attempt-review-4-11',
				itemId: 'item-11',
				paneSessionId: 'pane-session-1',
				publicationId: 'render-publication-review-4-11',
				publicationSequence: 11,
				submissionId: 'render-submission-review-4-11',
				surface: 'review',
				windowKey: 'review-cache-key-11',
				workerDerivationEpoch: 4,
				workerInstanceId: 'worker-instance-1',
			},
		};

		// Act
		const parsedCommand = bridgeWorkerMainToServerMessageSchema.safeParse(renderDispositionCommand);

		// Assert
		expect(parsedCommand.success, 'RENDER_DISPOSITION_COMMAND_UNREACHABLE').toBe(true);
		for (const requiredIdentityField of [
			'attemptId',
			'itemId',
			'paneSessionId',
			'publicationId',
			'publicationSequence',
			'submissionId',
			'surface',
			'windowKey',
			'workerDerivationEpoch',
			'workerInstanceId',
		] as const) {
			const receiptWithoutIdentityField = { ...renderDispositionCommand.receipt };
			Reflect.deleteProperty(receiptWithoutIdentityField, requiredIdentityField);
			expect(
				bridgeWorkerMainToServerMessageSchema.safeParse({
					...renderDispositionCommand,
					receipt: receiptWithoutIdentityField,
				}).success,
				`expected ${requiredIdentityField} to be required`,
			).toBe(false);
		}
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...renderDispositionCommand,
				receipt: { ...renderDispositionCommand.receipt, undeclaredIdentity: true },
			}).success,
		).toBe(false);
	});

	test('requires complete receipt identity on Pierre publications and rejects cross-field drift', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			bridgeDemandRank: { lane: 'visible', priority: 1 },
			budget: { className: 'visible', maxBytes: 1024, maxWindowLines: 4 },
			contentCacheKey: 'cache-item-11',
			contentHash: 'a'.repeat(64),
			itemId: 'item-11',
			language: 'text',
			payload: {
				kind: 'codeViewFileItem',
				item: {
					bridgeMetadata: {
						cacheKey: 'cache-item-11',
						contentRoles: ['file'],
						contentState: 'hydrated',
						displayPath: 'item-11.txt',
						itemId: 'item-11',
						lineCount: 1,
					},
					file: { cacheKey: 'cache-item-11', contents: 'content', name: 'item-11.txt' },
					id: 'item-11',
					type: 'file',
				},
			},
			renderKind: 'fileText',
			window: { endLine: 1, startLine: 1, totalLineCount: 1 },
		});
		const receiptIdentity = {
			attemptId: 'render-attempt-review-4-11',
			itemId: 'item-11',
			paneSessionId: 'pane-session-1',
			publicationId: 'render-publication-review-4-11',
			publicationSequence: 11,
			submissionId: 'render-submission-review-4-11',
			surface: 'review',
			windowKey: 'review-window-11',
			workerDerivationEpoch: 4,
			workerInstanceId: 'worker-instance-1',
		} as const;
		const publication = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'reviewPierreRenderJob',
			job,
			publicationSequence: 11,
			renderReceiptIdentity: receiptIdentity,
			surface: 'review',
			workerDerivationEpoch: 4,
		};

		expect(
			bridgeWorkerServerToMainMessageSchema.safeParse(publication).success,
			'RENDER_PUBLICATION_RECEIPT_IDENTITY_UNREACHABLE',
		).toBe(true);
		expect(
			bridgeWorkerServerToMainMessageSchema.safeParse({
				...publication,
				renderReceiptIdentity: undefined,
			}).success,
		).toBe(false);
		for (const renderReceiptIdentity of [
			{ ...receiptIdentity, itemId: 'item-foreign' },
			{ ...receiptIdentity, publicationSequence: 12 },
			{ ...receiptIdentity, surface: 'file' },
			{ ...receiptIdentity, workerDerivationEpoch: 5 },
		] as const) {
			expect(
				bridgeWorkerServerToMainMessageSchema.safeParse({
					...publication,
					renderReceiptIdentity,
				}).success,
			).toBe(false);
		}
	});

	test('requires every worker message to declare transfer descriptors explicitly', () => {
		const selectCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-select',
			epoch: 1,
			transferDescriptors: [],
			surface: 'fileView',
			selectedItemId: 'item-1',
			selectedSource: 'user',
		};
		const slicePatchEvent = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 1,
			sequence: 2,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { label: 'README.md' },
				},
			],
		};

		expect(bridgeWorkerMainToServerMessageSchema.parse(selectCommand)).toEqual(selectCommand);
		expect(bridgeWorkerSlicePatchEventSchema.parse(slicePatchEvent)).toEqual(slicePatchEvent);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...selectCommand,
				transferDescriptors: undefined,
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerSlicePatchEventSchema.safeParse({
				...slicePatchEvent,
				transferDescriptors: undefined,
			}).success,
		).toBe(false);
	});

	test('rejects boundary-visible unknown slice patch payloads', () => {
		const slicePatchEvent = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 1,
			sequence: 2,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
					payload: {
						metadata: {
							nestedUnknownRecord: true,
						},
					},
				},
			],
		};

		expect(bridgeWorkerSlicePatchEventSchema.safeParse(slicePatchEvent).success).toBe(false);
	});

	test('defines strict worker review content metadata without package snapshots', () => {
		const item = makeBridgeReviewItem({
			itemId: 'item-worker-metadata',
			path: 'Sources/App/WorkerMetadata.swift',
		});
		const metadata = {
			itemId: item.itemId,
			path: item.headPath ?? item.basePath ?? item.itemId,
			language: item.language ?? null,
			cacheKey: item.cacheKey,
			sizeBytes: item.sizeBytes,
			availableContentRoles: ['base', 'head'],
			contentLineCountsByRole: item.contentLineCountsByRole ?? {},
		} satisfies BridgeWorkerReviewContentMetadata;

		expect(bridgeWorkerReviewContentMetadataSchema.parse(metadata)).toEqual(metadata);
		expect(JSON.stringify(metadata)).not.toMatch(/"contentRoles"|resourceUrl|endpointId/i);
		expect(
			bridgeWorkerReviewContentMetadataSchema.safeParse({
				...metadata,
				itemsById: {},
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerReviewContentMetadataSchema.safeParse({
				...metadata,
				contentRoles: item.contentRoles,
			}).success,
		).toBe(false);
	});

	test('defines strict worker review content request descriptors separate from metadata', () => {
		const item = makeBridgeReviewItem({
			itemId: 'item-worker-content-request',
			path: 'Sources/App/WorkerContentRequest.swift',
		});
		const descriptor = makeContentRequestDescriptor({
			itemId: item.itemId,
			role: 'head',
			text: 'let workerContent = true;\n',
		});

		expect(bridgeWorkerReviewContentRequestDescriptorSchema.parse(descriptor)).toEqual(descriptor);
		expect(JSON.stringify(descriptor)).not.toMatch(
			/"contentRoles"|itemsById|"cacheKey"|resourceUrl/i,
		);
		expect(descriptor.contentKind).toBe('review.content');
		expect(descriptor.descriptorId).toContain(item.itemId);
		const inexactDescriptor = {
			...descriptor,
			declaredByteLength: null,
			maximumBytes: 64,
			wholeByteLength: null,
			window: { ...descriptor.window, maximumBytes: 64 },
		} satisfies BridgeWorkerReviewContentRequestDescriptor;
		expect(bridgeWorkerReviewContentRequestDescriptorSchema.parse(inexactDescriptor)).toEqual(
			inexactDescriptor,
		);
		expect(
			bridgeWorkerReviewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				resourceUrl: 'agentstudio://resource/review/content/legacy',
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerReviewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				maximumBytes: 0,
				window: { ...descriptor.window, maximumBytes: 0 },
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerReviewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				window: { ...descriptor.window, maximumBytes: descriptor.maximumBytes + 1 },
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerReviewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				declaredByteLength: descriptor.maximumBytes + 1,
			}).success,
		).toBe(false);
	});

	test('defines strict worker review render semantics without content handles', () => {
		const item = makeBridgeReviewItem({
			itemId: 'item-render-semantics',
			path: 'Sources/App/RenderSemantics.swift',
		});
		const semantics = {
			itemId: item.itemId,
			itemKind: item.itemKind,
			changeKind: item.changeKind,
			displayPath: item.headPath ?? item.basePath ?? item.itemId,
			basePath: item.basePath ?? null,
			headPath: item.headPath ?? null,
			language: item.language ?? null,
			contentLineCountsByRole: item.contentLineCountsByRole ?? {},
		} satisfies BridgeWorkerReviewRenderSemantics;

		expect(bridgeWorkerReviewRenderSemanticsSchema.parse(semantics)).toEqual(semantics);
		expect(JSON.stringify(semantics)).not.toMatch(
			/"contentRoles"|resourceUrl|handleId|contentHash|endpointId/i,
		);
		expect(
			bridgeWorkerReviewRenderSemanticsSchema.safeParse({
				...semantics,
				contentRoles: item.contentRoles,
			}).success,
		).toBe(false);
	});

	test('defines strict worker File View prefix metadata without resource carriers', () => {
		const metadata = {
			metadataKind: 'fileView',
			itemId: 'file-1',
			path: 'Sources/App/FileView.swift',
			language: 'swift',
			cacheKey: 'file-view:sha256:file-1',
			sizeBytes: 128,
			descriptorId: 'descriptor-file-1',
			contentHash: 'sha256:file-1',
			encoding: 'utf-8',
			endsMidLine: false,
			endsWithNewline: true,
			virtualizedExtentKind: 'exactLineCount',
			payloadByteCount: 128,
			payloadLineCount: 7,
			totalLineCount: 7,
			truncationKind: 'none',
			isBinary: false,
			canFetchContent: true,
		} satisfies BridgeWorkerFileViewContentMetadata;

		expect(bridgeWorkerFileViewContentMetadataSchema.parse(metadata)).toEqual(metadata);
		expect(JSON.stringify(metadata)).not.toMatch(
			/contentHandle|resourceUrl|worktree\.fileContent|contents|text|body/i,
		);
		for (const invalidMetadata of [
			{ ...metadata, contentHandle: 'legacy-handle' },
			{ ...metadata, lineCount: 7 },
			{ ...metadata, resourceUrl: 'agentstudio://resource/legacy' },
		]) {
			expect(bridgeWorkerFileViewContentMetadataSchema.safeParse(invalidMetadata).success).toBe(
				false,
			);
		}
	});
});
