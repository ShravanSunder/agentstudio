import { describe, expect, expectTypeOf, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerReviewContentMetadataSchema,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	bridgeWorkerSlicePatchEventSchema,
	parseBridgeWorkerMainToServerMessage,
	type BridgeWorkerMainToServerMessage,
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
});
