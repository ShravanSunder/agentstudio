import { describe, expect, expectTypeOf, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerReviewRenderSemanticsSchema,
	bridgeWorkerFileViewContentMetadataSchema,
	bridgeWorkerFileViewContentRequestDescriptorSchema,
	bridgeWorkerFileViewSourceUpdateCommandSchema,
	bridgeWorkerReviewContentRequestDescriptorSchema,
	bridgeWorkerReviewContentMetadataSchema,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	bridgeWorkerSlicePatchEventSchema,
	parseBridgeWorkerMainToServerMessage,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerFileViewContentMetadata,
	type BridgeWorkerFileViewContentRequestDescriptor,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';

describe('BridgeWorkerContracts', () => {
	test('rejects untyped main to server worker messages at schema boundary', () => {
		const selectCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-select',
			epoch: 3,
			transferDescriptors: [],
			selectedItemId: 'item-1',
			selectedSource: 'user',
		} satisfies BridgeWorkerMainToServerMessage;

		expect(parseBridgeWorkerMainToServerMessage(selectCommand)).toEqual(selectCommand);
		expect(bridgeWorkerMainToServerMessageSchema.safeParse(selectCommand).success).toBe(true);
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

	test('requires every worker message to declare transfer descriptors explicitly', () => {
		const selectCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-select',
			epoch: 1,
			transferDescriptors: [],
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
		const handle = item.contentRoles.head;
		expect(handle).not.toBeNull();
		const descriptor = {
			itemId: item.itemId,
			role: 'head',
			handleId: handle?.handleId ?? 'missing',
			reviewGeneration: handle?.reviewGeneration ?? 0,
			resourceUrl: handle?.resourceUrl ?? 'agentstudio://resource/review/content/missing',
			contentHash: handle?.contentHash ?? 'sha256:missing',
			contentHashAlgorithm: handle?.contentHashAlgorithm ?? 'fixture-preview',
			language: handle?.language ?? null,
			sizeBytes: handle?.sizeBytes ?? 0,
			isBinary: handle?.isBinary ?? false,
		} satisfies BridgeWorkerReviewContentRequestDescriptor;

		expect(bridgeWorkerReviewContentRequestDescriptorSchema.parse(descriptor)).toEqual(descriptor);
		expect(JSON.stringify(descriptor)).not.toMatch(
			/"contentRoles"|endpointId|itemsById|"cacheKey"|mimeType/i,
		);
		expect(descriptor.resourceUrl).toMatch(/^agentstudio:\/\//);
		expect(
			bridgeWorkerReviewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				endpointId: 'endpoint-head',
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

	test('defines strict worker File View metadata separate from content request descriptors', () => {
		const metadata = {
			itemId: 'file-1',
			path: 'Sources/App/FileView.swift',
			language: 'swift',
			cacheKey: 'file-view:sha256:file-1',
			sizeBytes: 128,
			contentHandle: 'handle-file-1',
			descriptorId: 'descriptor-file-1',
			contentHash: 'sha256:file-1',
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 7,
			isBinary: false,
			canFetchContent: true,
		} satisfies BridgeWorkerFileViewContentMetadata;
		const descriptor = {
			itemId: metadata.itemId,
			path: metadata.path,
			handleId: metadata.contentHandle,
			descriptorId: metadata.descriptorId,
			resourceKind: 'worktree.fileContent',
			resourceUrl:
				'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=3',
			contentHash: metadata.contentHash,
			contentHashAlgorithm: 'sha256',
			language: metadata.language,
			sizeBytes: metadata.sizeBytes,
			maxBytes: 4096,
			isBinary: metadata.isBinary,
		} satisfies BridgeWorkerFileViewContentRequestDescriptor;

		expect(bridgeWorkerFileViewContentMetadataSchema.parse(metadata)).toEqual(metadata);
		expect(bridgeWorkerFileViewContentRequestDescriptorSchema.parse(descriptor)).toEqual(
			descriptor,
		);
		expect(JSON.stringify(metadata)).not.toMatch(/resourceUrl|contents|text|body/i);
		expect(descriptor.resourceUrl).toMatch(/^agentstudio:\/\//);
		expect(
			bridgeWorkerFileViewContentMetadataSchema.safeParse({
				...metadata,
				resourceUrl: descriptor.resourceUrl,
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				contents: 'print("main must not receive this")',
			}).success,
		).toBe(false);
	});

	test('requires File View request descriptors to use canonical worktree-file content resource urls', () => {
		const descriptor = makeBridgeWorkerFileViewSourceUpdateCommand().contentRequestDescriptors[0];
		if (descriptor === undefined) {
			throw new Error('expected test descriptor');
		}
		expect(bridgeWorkerFileViewContentRequestDescriptorSchema.parse(descriptor)).toEqual(
			descriptor,
		);

		expect(
			bridgeWorkerFileViewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?generation=3',
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&extra=1&generation=3',
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewContentRequestDescriptorSchema.safeParse({
				...descriptor,
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/other-descriptor?cursor=cursor-1&generation=3',
			}).success,
		).toBe(false);
		const rangeDescriptor: BridgeWorkerFileViewContentRequestDescriptor = {
			...descriptor,
			// @ts-expect-error File View content request descriptors do not admit range resources.
			resourceKind: 'worktree.fileRange',
			resourceUrl:
				'agentstudio://resource/worktree-file/worktree.fileRange/descriptor-file-1?cursor=cursor-1&generation=3',
		};
		expect(
			bridgeWorkerFileViewContentRequestDescriptorSchema.safeParse(rangeDescriptor).success,
		).toBe(false);
	});

	test('encodes File View source updates without raw tree snapshots or content bytes', () => {
		const command = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'fileViewSourceUpdate',
			requestId: 'request-file-view-source',
			epoch: 6,
			transferDescriptors: [],
			contentItems: [
				{
					itemId: 'file-1',
					path: 'Sources/App/FileView.swift',
					language: 'swift',
					cacheKey: 'file-view:sha256:file-1',
					sizeBytes: 128,
					contentHandle: 'handle-file-1',
					descriptorId: 'descriptor-file-1',
					contentHash: 'sha256:file-1',
					virtualizedExtentKind: 'exactLineCount',
					lineCount: 7,
					isBinary: false,
					canFetchContent: true,
				},
			],
			contentRequestDescriptors: [
				{
					itemId: 'file-1',
					path: 'Sources/App/FileView.swift',
					handleId: 'handle-file-1',
					descriptorId: 'descriptor-file-1',
					resourceKind: 'worktree.fileContent',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=3',
					contentHash: 'sha256:file-1',
					contentHashAlgorithm: 'sha256',
					language: 'swift',
					sizeBytes: 128,
					maxBytes: 4096,
					isBinary: false,
				},
			],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		};

		expect(bridgeWorkerFileViewSourceUpdateCommandSchema.parse(command)).toEqual(command);
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
		expect(JSON.stringify(command.contentItems)).not.toMatch(/resourceUrl|contents|body/i);
		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				rootSnapshot: { allRows: [] },
			}).success,
		).toBe(false);
	});

	test('rejects File View source updates with unsafe or mismatched request descriptors', () => {
		const command = makeBridgeWorkerFileViewSourceUpdateCommand();

		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				contentRequestDescriptors: [
					{
						...command.contentRequestDescriptors[0],
						resourceUrl: 'https://example.test/file.swift',
					},
				],
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				contentRequestDescriptors: [
					{
						...command.contentRequestDescriptors[0],
						path: 'Sources/App/Other.swift',
					},
				],
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				contentRequestDescriptors: [
					{
						...command.contentRequestDescriptors[0],
						resourceUrl:
							'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-other?cursor=cursor-1&generation=3',
					},
				],
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				contentRequestDescriptors: [],
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerFileViewSourceUpdateCommandSchema.safeParse({
				...command,
				contentRequestDescriptors: [
					command.contentRequestDescriptors[0],
					{
						...command.contentRequestDescriptors[0],
						descriptorId: 'descriptor-file-1-copy',
						resourceUrl:
							'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1-copy?cursor=cursor-1&generation=3',
					},
				],
			}).success,
		).toBe(false);
	});
});

function makeBridgeWorkerFileViewSourceUpdateCommand(): {
	readonly wireVersion: typeof BRIDGE_WORKER_WIRE_VERSION;
	readonly direction: 'mainToServerWorker';
	readonly kind: 'command';
	readonly command: 'fileViewSourceUpdate';
	readonly requestId: string;
	readonly epoch: number;
	readonly transferDescriptors: readonly [];
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly rows: readonly [{ readonly id: string; readonly parentId: null; readonly index: 0 }];
} {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'mainToServerWorker',
		kind: 'command',
		command: 'fileViewSourceUpdate',
		requestId: 'request-file-view-source',
		epoch: 6,
		transferDescriptors: [],
		contentItems: [
			{
				itemId: 'file-1',
				path: 'Sources/App/FileView.swift',
				language: 'swift',
				cacheKey: 'file-view:sha256:file-1',
				sizeBytes: 128,
				contentHandle: 'handle-file-1',
				descriptorId: 'descriptor-file-1',
				contentHash: 'sha256:file-1',
				virtualizedExtentKind: 'exactLineCount',
				lineCount: 7,
				isBinary: false,
				canFetchContent: true,
			},
		],
		contentRequestDescriptors: [
			{
				itemId: 'file-1',
				path: 'Sources/App/FileView.swift',
				handleId: 'handle-file-1',
				descriptorId: 'descriptor-file-1',
				resourceKind: 'worktree.fileContent',
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=3',
				contentHash: 'sha256:file-1',
				contentHashAlgorithm: 'sha256',
				language: 'swift',
				sizeBytes: 128,
				maxBytes: 4096,
				isBinary: false,
			},
		],
		rows: [{ id: 'file-1', parentId: null, index: 0 }],
	};
}
