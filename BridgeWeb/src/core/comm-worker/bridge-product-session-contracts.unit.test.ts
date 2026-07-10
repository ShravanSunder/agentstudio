import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import invalidProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/invalid/bridge-product-session-corpus.json' with { type: 'json' };
import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import {
	bridgeProductContentHeaderSchema,
	bridgeProductContentRequestSchema,
} from './bridge-product-content-contracts.js';
import { BridgeProductContentFrameEncoder } from './bridge-product-content-frame-codec.js';
import { BridgeProductContentFrameDecoder } from './bridge-product-content-frame-decoder.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
} from './bridge-product-contract-primitives.js';
import {
	BridgeProductMetadataFrameDecoder,
	encodeBridgeProductMetadataFrame,
} from './bridge-product-metadata-frame-codec.js';
import {
	bridgePaneCommWorkerInstallSchema,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataAcceptedStreamSequence,
	bridgeProductMetadataFrameSchema,
	bridgeProductMetadataStreamRequestSchema,
	bridgeProductSessionBootstrapSchema,
	encodeBridgeProductCapabilityHeader,
	postBridgePaneCommWorkerInstall,
} from './bridge-product-session-contracts.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';
import { bridgeProductSubscriptionInterestStateSchema } from './bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from './bridge-product-subscription-interest-state-codec.js';

describe('Bridge product session contracts', () => {
	test('dispatches top-level control and metadata envelopes by kind', () => {
		expect(bridgeProductControlRequestSchema).toBeInstanceOf(z.ZodDiscriminatedUnion);
		expect(bridgeProductMetadataFrameSchema).toBeInstanceOf(z.ZodDiscriminatedUnion);
	});

	test('keeps the Swift and TypeScript corpora byte-identical at frozen hashes', () => {
		const fixturePairs = [
			{
				expectedHash: '57ad606fe03071a6fc0a96bd76a3d7f10687d937cbed9ee61c5d3d811e0cc726',
				kind: 'valid',
			},
			{
				expectedHash: 'f547073f989681da76df3d5908bca638e442583d34608a181a44229ecc7d94bb',
				kind: 'invalid',
			},
		] as const;

		for (const fixturePair of fixturePairs) {
			const relativeFixturePath = `${fixturePair.kind}/bridge-product-session-corpus.json`;
			const typeScriptBytes = readFileSync(
				new URL(
					`../../test-fixtures/bridge-contract-fixtures/${relativeFixturePath}`,
					import.meta.url,
				),
			);
			const swiftBytes = readFileSync(
				new URL(`../../../../Tests/BridgeContractFixtures/${relativeFixturePath}`, import.meta.url),
			);

			expect(swiftBytes.equals(typeScriptBytes)).toBe(true);
			expect(createHash('sha256').update(typeScriptBytes).digest('hex')).toBe(
				fixturePair.expectedHash,
			);
		}
	});

	test('accepts the nonsecret bootstrap and canonical capability header', () => {
		expect(bridgeProductSessionBootstrapSchema.parse(validProductSessionCorpus.bootstrap)).toEqual(
			validProductSessionCorpus.bootstrap,
		);
		expect(validProductSessionCorpus.bootstrap).not.toHaveProperty('initialSurface');
		expect(validProductSessionCorpus.bootstrap).not.toHaveProperty('productCapabilityBytes');
		expect(validProductSessionCorpus.bootstrap).not.toHaveProperty('routes');
		expect(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES).toBe(256 * 1024);
		expect(validProductSessionCorpus.bootstrap.policy.maximumRequestBodyBytes).toBe(
			BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
		);
		for (const capabilityCase of validProductSessionCorpus.capabilityHeaderCases) {
			expect(encodeBridgeProductCapabilityHeader(capabilityCase.bytes)).toBe(
				capabilityCase.encoded,
			);
			expect(
				encodeBridgeProductCapabilityHeader(Uint8Array.from(capabilityCase.bytes).buffer),
			).toBe(capabilityCase.encoded);
			expect(capabilityCase.encoded).not.toMatch(/[+/=]/u);
		}
	});

	test('accepts every closed request, response, metadata, and content variant', () => {
		expect(
			new Set(validProductSessionCorpus.controlRequests.map((request) => request.kind)),
		).toEqual(
			new Set([
				'workerSession.open',
				'product.call',
				'subscription.open',
				'subscription.updateBatch',
				'subscription.cancel',
				'workerSession.resync',
			]),
		);
		expect(
			new Set(validProductSessionCorpus.controlResponses.map((response) => response.kind)),
		).toEqual(
			new Set([
				'workerSession.accepted',
				'call.completed',
				'subscription.openAccepted',
				'subscription.updateBatchAccepted',
				'subscription.cancelAccepted',
				'resync.accepted',
				'request.error',
			]),
		);
		expect(new Set(validProductSessionCorpus.metadataFrames.map((frame) => frame.kind))).toEqual(
			new Set([
				'metadataStream.accepted',
				'subscription.accepted',
				'subscription.interestsCommitted',
				'subscription.data',
				'subscription.reset',
				'subscription.end',
				'subscription.cancelled',
				'content.cancelled',
				'metadataStream.error',
			]),
		);
		expect(new Set(validProductSessionCorpus.contentHeaders.map((header) => header.kind))).toEqual(
			new Set([
				'content.accepted',
				'content.data',
				'content.end',
				'content.error',
				'content.reset',
			]),
		);
		for (const request of validProductSessionCorpus.controlRequests) {
			expect(bridgeProductControlRequestSchema.parse(request)).toEqual(request);
		}
		for (const response of validProductSessionCorpus.controlResponses) {
			expect(bridgeProductControlResponseSchema.parse(response)).toEqual(response);
		}
		for (const request of validProductSessionCorpus.metadataStreamRequests) {
			expect(bridgeProductMetadataStreamRequestSchema.parse(request)).toEqual(request);
		}
		for (const frame of validProductSessionCorpus.metadataFrames) {
			expect(bridgeProductMetadataFrameSchema.parse(frame)).toEqual(frame);
		}
		for (const request of validProductSessionCorpus.contentRequests) {
			expect(bridgeProductContentRequestSchema.parse(request)).toEqual(request);
		}
		for (const header of validProductSessionCorpus.contentHeaders) {
			expect(bridgeProductContentHeaderSchema.parse(header)).toEqual(header);
		}
	});

	test('keeps pane-session contracts free of every derivation epoch', () => {
		const workerSessionOpen = validProductSessionCorpus.controlRequests.find(
			(request) => request.kind === 'workerSession.open',
		);
		if (workerSessionOpen === undefined) {
			throw new Error('Shared corpus is missing workerSession.open.');
		}
		const paneScopedCases = [
			{
				name: 'product session bootstrap',
				schema: bridgeProductSessionBootstrapSchema,
				value: validProductSessionCorpus.bootstrap,
			},
			{
				name: 'worker session open',
				schema: bridgeProductControlRequestSchema,
				value: workerSessionOpen,
			},
			...validProductSessionCorpus.controlResponses.map((response) => ({
				name: response.kind,
				schema: bridgeProductControlResponseSchema,
				value: response,
			})),
			...validProductSessionCorpus.metadataStreamRequests.map((request) => ({
				name: request.kind,
				schema: bridgeProductMetadataStreamRequestSchema,
				value: request,
			})),
			...validProductSessionCorpus.metadataFrames
				.filter(
					(frame) =>
						frame.kind === 'metadataStream.accepted' || frame.kind === 'metadataStream.error',
				)
				.map((frame) => ({
					name: frame.kind,
					schema: bridgeProductMetadataFrameSchema,
					value: frame,
				})),
		];

		for (const paneScopedCase of paneScopedCases) {
			expect(
				paneScopedCase.schema.safeParse(paneScopedCase.value).success,
				paneScopedCase.name,
			).toBe(true);
			expect(
				paneScopedCase.schema.safeParse({ ...paneScopedCase.value, workerEpoch: 3 }).success,
				`${paneScopedCase.name} rejects workerEpoch`,
			).toBe(false);
			expect(
				paneScopedCase.schema.safeParse({
					...paneScopedCase.value,
					workerDerivationEpoch: 3,
				}).success,
				`${paneScopedCase.name} rejects workerDerivationEpoch`,
			).toBe(false);
		}
	});

	test('requires a derivation epoch only on surface-scoped admission and push variants', () => {
		const surfaceScopedCases = [
			...validProductSessionCorpus.controlRequests
				.filter(
					(request) =>
						request.kind !== 'workerSession.open' && request.kind !== 'workerSession.resync',
				)
				.map((request) => ({
					name: request.kind,
					schema: bridgeProductControlRequestSchema,
					value: request,
				})),
			...validProductSessionCorpus.metadataFrames
				.filter(
					(frame) =>
						frame.kind !== 'metadataStream.accepted' && frame.kind !== 'metadataStream.error',
				)
				.map((frame) => ({
					name: frame.kind,
					schema: bridgeProductMetadataFrameSchema,
					value: frame,
				})),
			...validProductSessionCorpus.contentRequests.map((request) => ({
				name: request.kind,
				schema: bridgeProductContentRequestSchema,
				value: request,
			})),
			...validProductSessionCorpus.contentHeaders
				.filter((header) => header.kind === 'content.accepted')
				.map((header) => ({
					name: header.kind,
					schema: bridgeProductContentHeaderSchema,
					value: header,
				})),
		];

		for (const surfaceScopedCase of surfaceScopedCases) {
			expect(
				surfaceScopedCase.schema.safeParse(surfaceScopedCase.value).success,
				surfaceScopedCase.name,
			).toBe(true);
			expect(
				surfaceScopedCase.schema.safeParse(withoutWorkerDerivationEpoch(surfaceScopedCase.value))
					.success,
				`${surfaceScopedCase.name} requires workerDerivationEpoch`,
			).toBe(false);
			expect(
				surfaceScopedCase.schema.safeParse({
					...withoutWorkerDerivationEpoch(surfaceScopedCase.value),
					workerEpoch: 3,
				}).success,
				`${surfaceScopedCase.name} rejects workerEpoch`,
			).toBe(false);
			expect(
				surfaceScopedCase.schema.safeParse({ ...surfaceScopedCase.value, surface: 'review' })
					.success,
				`${surfaceScopedCase.name} derives rather than repeats surface`,
			).toBe(false);
		}
	});

	test('resync carries independent epochs per active surface and rejects split same-surface epochs', () => {
		const resync = bridgeProductControlRequestSchema.parse(
			validProductSessionCorpus.controlRequests.find(
				(request) => request.kind === 'workerSession.resync',
			),
		);
		if (resync.kind !== 'workerSession.resync') {
			throw new Error('Shared corpus did not decode workerSession.resync.');
		}
		const reviewSubscription = resync.activeSubscriptions[0];
		if (reviewSubscription === undefined) {
			throw new Error('Shared corpus is missing the active resync subscription.');
		}
		const reviewEpochSeven = { ...reviewSubscription, workerDerivationEpoch: 7 };
		const fileEpochTwo = {
			interestRevision: 0,
			interestSha256: '51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b',
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
			workerDerivationEpoch: 2,
		} as const;
		const paneResync = {
			...resync,
			activeSubscriptions: [reviewEpochSeven, fileEpochTwo],
		};
		const { workerDerivationEpoch: _missingEpoch, ...reviewWithoutEpoch } = reviewEpochSeven;

		expect(bridgeProductControlRequestSchema.safeParse(paneResync).success).toBe(true);
		expect(
			bridgeProductControlRequestSchema.safeParse({ ...paneResync, workerEpoch: 7 }).success,
		).toBe(false);
		expect(
			bridgeProductControlRequestSchema.safeParse({
				...paneResync,
				workerDerivationEpoch: 7,
			}).success,
		).toBe(false);
		expect(
			bridgeProductControlRequestSchema.safeParse({
				...paneResync,
				activeSubscriptions: [reviewWithoutEpoch, fileEpochTwo],
			}).success,
		).toBe(false);
		expect(
			bridgeProductControlRequestSchema.safeParse({
				...paneResync,
				activeSubscriptions: [
					reviewEpochSeven,
					{
						...reviewEpochSeven,
						subscriptionId: 'review-subscription-2',
						workerDerivationEpoch: 8,
					},
				],
			}).success,
		).toBe(false);
	});

	test('resumed and snapshot-required acceptance consume the next physical sequence', () => {
		const freshAccepted = bridgeProductMetadataFrameSchema.parse(
			validProductSessionCorpus.metadataFrames.find(
				(frame) => frame.kind === 'metadataStream.accepted',
			),
		);
		if (freshAccepted.kind !== 'metadataStream.accepted') {
			throw new Error('Shared corpus did not decode metadataStream.accepted.');
		}
		const freshRequest = bridgeProductMetadataStreamRequestSchema.parse(
			validProductSessionCorpus.metadataStreamRequests.find(
				(request) => request.resumeFromStreamSequence === null,
			),
		);
		const resumedRequest = bridgeProductMetadataStreamRequestSchema.parse({
			...freshRequest,
			resumeFromStreamSequence: 6,
		});
		const resumedAccepted = {
			...freshAccepted,
			resumeDisposition: 'resumed',
			streamSequence: 7,
		} as const;
		const snapshotRequiredAccepted = {
			...freshAccepted,
			resumeDisposition: 'snapshot_required',
			streamSequence: 7,
		} as const;

		expect(bridgeProductMetadataFrameSchema.safeParse(freshAccepted).success).toBe(true);
		expect(bridgeProductMetadataFrameSchema.safeParse(resumedAccepted).success).toBe(true);
		expect(bridgeProductMetadataFrameSchema.safeParse(snapshotRequiredAccepted).success).toBe(true);
		expect(bridgeProductMetadataAcceptedStreamSequence(freshRequest)).toBe(0);
		expect(bridgeProductMetadataAcceptedStreamSequence(resumedRequest)).toBe(7);
	});

	test('matches canonical interest-state bytes and SHA-256 vectors', () => {
		for (const vector of validProductSessionCorpus.interestStateVectors) {
			const encodedState = encodeBridgeProductSubscriptionInterestState(
				bridgeProductSubscriptionInterestStateSchema.parse(vector.state),
			);

			expect(Buffer.from(encodedState).toString('base64'), vector.name).toBe(vector.encodedBase64);
			expect(createHash('sha256').update(encodedState).digest('hex'), vector.name).toBe(
				vector.sha256,
			);
		}

		expect(() =>
			encodeBridgeProductSubscriptionInterestState({
				interests: [
					{ itemIds: ['review-item-1'], lane: 'foreground' },
					{ itemIds: ['review-item-1'], lane: 'visible' },
				],
				subscriptionKind: 'review.metadata',
			}),
		).toThrow(/unique across demand lanes/iu);
	});

	test('stages bounded interest deltas and orders committed metadata by revision', () => {
		const legacyWholeOptionsUpdate = invalidProductSessionCorpus.cases.find(
			(hostileCase) => hostileCase.name === 'legacy subscription update carries whole options',
		)?.value;
		const baseInterestSha256 = '1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6';
		const targetInterestSha256 = '2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd';
		const updateBatch = {
			baseInterestRevision: 0,
			baseInterestSha256,
			batchCount: 1,
			batchIndex: 0,
			delta: {
				add: [
					{ itemId: 'review-item-1', lane: 'foreground' },
					{ itemId: 'review-item-2', lane: 'visible' },
				],
				removeItemIds: [],
				subscriptionKind: 'review.metadata',
			},
			kind: 'subscription.updateBatch',
			paneSessionId: 'pane-session-1',
			requestId: 'request-review-subscription-update-batch-1',
			requestSequence: 5,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			targetInterestRevision: 1,
			targetInterestSha256,
			totalDeltaItemCount: 2,
			updateId: 'review-interest-update-1',
			wireVersion: 2,
			workerDerivationEpoch: 7,
			workerInstanceId: 'worker-instance-1',
		};
		const committedFrame = {
			cursor: 'review-cursor-committed-1',
			interestRevision: 1,
			interestSha256: targetInterestSha256,
			kind: 'subscription.interestsCommitted',
			metadataStreamId: 'metadata-stream-1',
			paneSessionId: 'pane-session-1',
			sourceGeneration: 7,
			streamSequence: 2,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			subscriptionSequence: 1,
			updateId: 'review-interest-update-1',
			wireVersion: 2,
			workerDerivationEpoch: 7,
			workerInstanceId: 'worker-instance-1',
		};
		const revisionedDataFrame = validProductSessionCorpus.metadataFrames.find(
			(frame) => frame.kind === 'subscription.data',
		);
		if (revisionedDataFrame === undefined) {
			throw new Error('Shared corpus is missing a subscription.data frame.');
		}
		const unrevisionedDataFrame = {
			...revisionedDataFrame,
			interestRevision: undefined,
			interestSha256: undefined,
		};

		expect(bridgeProductControlRequestSchema.safeParse(legacyWholeOptionsUpdate).success).toBe(
			false,
		);
		expect(bridgeProductControlRequestSchema.safeParse(updateBatch).success).toBe(true);
		expect(bridgeProductMetadataFrameSchema.safeParse(committedFrame).success).toBe(true);
		expect(bridgeProductMetadataFrameSchema.safeParse(unrevisionedDataFrame).success).toBe(false);
	});

	test('rejects every hostile shared-corpus case at its receiving boundary', () => {
		for (const hostileCase of invalidProductSessionCorpus.cases) {
			expect(
				hostileContractRejects(hostileCase.contract, hostileCase.value),
				hostileCase.name,
			).toBe(true);
		}
	});

	test('rejects the obsolete generic payload and resource GET corridors', () => {
		expect(
			bridgeProductControlRequestSchema.safeParse({
				kind: 'product.command',
				wireVersion: 2,
				paneSessionId: 'pane-session-1',
				workerInstanceId: 'worker-instance-1',
				requestId: 'request-generic-1',
				requestSequence: 1,
				command: { name: 'review.refresh', payload: { arbitrary: true } },
			}).success,
		).toBe(false);
		expect(
			bridgeProductSessionBootstrapSchema.safeParse({
				...validProductSessionCorpus.bootstrap,
				routes: {
					command: { method: 'POST', url: 'agentstudio://rpc/command' },
					resource: { method: 'GET', urlPrefix: 'agentstudio://resource/' },
					stream: { method: 'POST', url: 'agentstudio://rpc/stream' },
				},
			}).success,
		).toBe(false);
	});

	test('rejects exact Kelvin-sign key lookalikes before typed handler admission', () => {
		const hostileRawBodies = [
			'{"\\u212Aind":"content.data","contentSequence":1,"offsetBytes":0}',
			'{"kind":"content.data","\\u212Aind":"content.data","contentSequence":1,"offsetBytes":0}',
		];

		for (const hostileRawBody of hostileRawBodies) {
			const parsedBody = parseBridgeProductStrictJSON(new TextEncoder().encode(hostileRawBody));
			expect(bridgeProductContentHeaderSchema.safeParse(parsedBody).success).toBe(false);
		}
	});

	test('requires one exact 32-byte product capability in the install message', () => {
		const productChannel = new MessageChannel();
		const validCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const shortCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH - 1);

		expect(
			bridgePaneCommWorkerInstallSchema.safeParse({
				bootstrap: validProductSessionCorpus.bootstrap,
				kind: 'bridgePaneCommWorker.install',
				productCapability: validCapability,
				productPort: productChannel.port1,
			}).success,
		).toBe(true);
		expect(
			bridgePaneCommWorkerInstallSchema.safeParse({
				bootstrap: validProductSessionCorpus.bootstrap,
				kind: 'bridgePaneCommWorker.install',
				productCapability: shortCapability,
				productPort: productChannel.port1,
			}).success,
		).toBe(false);

		productChannel.port1.close();
		productChannel.port2.close();
	});

	test('transfers the install port and capability and proves sender detachment', async () => {
		const bootstrapChannel = new MessageChannel();
		const productChannel = new MessageChannel();
		const productCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const receivedInstall = new Promise<unknown>((resolve) => {
			bootstrapChannel.port2.addEventListener(
				'message',
				(event): void => {
					resolve(event.data);
				},
				{ once: true },
			);
			bootstrapChannel.port2.start();
		});

		postBridgePaneCommWorkerInstall(bootstrapChannel.port1, {
			bootstrap: bridgeProductSessionBootstrapSchema.parse(validProductSessionCorpus.bootstrap),
			kind: 'bridgePaneCommWorker.install',
			productCapability,
			productPort: productChannel.port1,
		});

		expect(productCapability.byteLength).toBe(0);
		const install = bridgePaneCommWorkerInstallSchema.parse(await receivedInstall);
		expect(install.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);

		install.productPort.close();
		productChannel.port2.close();
		bootstrapChannel.port1.close();
		bootstrapChannel.port2.close();
	});

	test('incrementally decodes one physical metadata stream across Review and File', () => {
		const encodedFrames = validProductSessionCorpus.metadataFrames
			.slice(0, 5)
			.map((frame) =>
				encodeBridgeProductMetadataFrame(bridgeProductMetadataFrameSchema.parse(frame)),
			);
		const wireBytes = concatenateBytes(...encodedFrames);
		const decoder = new BridgeProductMetadataFrameDecoder();

		const first = decoder.push(wireBytes.subarray(0, 2));
		const middle = decoder.push(wireBytes.subarray(2, encodedFrames[0]?.byteLength ?? 2));
		const rest = decoder.push(wireBytes.subarray(encodedFrames[0]?.byteLength ?? 2));
		decoder.finish();
		const oneByteDecoder = new BridgeProductMetadataFrameDecoder();
		let oneByteDecodedFrameCount = 0;
		for (let offset = 0; offset < wireBytes.byteLength; offset += 1) {
			oneByteDecodedFrameCount += oneByteDecoder.push(
				wireBytes.subarray(offset, offset + 1),
			).length;
		}
		oneByteDecoder.finish();

		expect(first).toEqual([]);
		expect(middle.map((frame) => frame.kind)).toEqual(['metadataStream.accepted']);
		expect(rest.map((frame) => frame.kind)).toEqual([
			'subscription.accepted',
			'subscription.interestsCommitted',
			'subscription.data',
			'subscription.accepted',
		]);
		expect(rest.map((frame) => frame.streamSequence)).toEqual([1, 2, 3, 4]);
		expect(oneByteDecodedFrameCount).toBe(encodedFrames.length);
		expect(oneByteDecoder.diagnostics).toMatchObject({
			consumedByteCount: wireBytes.byteLength,
			copiedByteCount: wireBytes.byteLength,
			discardedTailByteCount: 0,
			emittedFrameCount: encodedFrames.length,
			failureCode: null,
			receivedByteCount: wireBytes.byteLength,
			retainedByteCount: 0,
			state: 'finished',
		});
	});

	test('poisons metadata framing after a fatal push or finish failure', () => {
		const validFrame = encodeBridgeProductMetadataFrame(
			bridgeProductMetadataFrameSchema.parse(validProductSessionCorpus.metadataFrames[0]),
		);
		const invalidLength = Uint8Array.of(0, 0, 0, 0);
		const invalidDecoder = new BridgeProductMetadataFrameDecoder();

		expect(() => invalidDecoder.push(invalidLength)).toThrow(/length/iu);
		expect(() => invalidDecoder.push(validFrame)).toThrow(/poisoned/iu);

		const truncatedDecoder = new BridgeProductMetadataFrameDecoder();
		truncatedDecoder.push(validFrame.subarray(0, validFrame.byteLength - 1));
		expect(() => truncatedDecoder.finish()).toThrow(/truncated/iu);
		expect(() => truncatedDecoder.push(validFrame)).toThrow(/poisoned/iu);
	});

	test('matches the shared literal metadata and binary content wire vectors', () => {
		const metadataFrame = bridgeProductMetadataFrameSchema.parse(
			validProductSessionCorpus.metadataFrames[0],
		);
		const encodedMetadata = encodeBridgeProductMetadataFrame(metadataFrame);
		expect(Buffer.from(encodedMetadata).toString('base64')).toBe(
			validProductSessionCorpus.wireVectors.metadataAccepted.encodedBase64,
		);
		const metadataDecoder = new BridgeProductMetadataFrameDecoder();
		expect(
			metadataDecoder.push(
				Uint8Array.from(
					Buffer.from(
						validProductSessionCorpus.wireVectors.metadataAccepted.encodedBase64,
						'base64',
					),
				),
			),
		).toEqual([metadataFrame]);
		metadataDecoder.finish();

		const contentRequest = bridgeProductContentRequestSchema.parse(
			validProductSessionCorpus.contentRequests[0],
		);
		const contentAcceptedHeader = bridgeProductContentHeaderSchema.parse(
			validProductSessionCorpus.contentHeaders.find((header) => header.kind === 'content.accepted'),
		);
		const contentHeader = bridgeProductContentHeaderSchema.parse(
			validProductSessionCorpus.contentHeaders.find((header) => header.kind === 'content.data'),
		);
		const contentEndHeader = bridgeProductContentHeaderSchema.parse(
			validProductSessionCorpus.contentHeaders.find((header) => header.kind === 'content.end'),
		);
		const contentPayload = Uint8Array.from(
			Buffer.from(validProductSessionCorpus.wireVectors.contentData.payloadBase64, 'base64'),
		);
		const contentEncoder = new BridgeProductContentFrameEncoder(contentRequest);
		const encodedAccepted = contentEncoder.encode({
			header: contentAcceptedHeader,
			payload: new Uint8Array(),
		});
		const encodedContent = contentEncoder.encode({
			header: contentHeader,
			payload: contentPayload,
		});
		const encodedEnd = contentEncoder.encode({
			header: contentEndHeader,
			payload: new Uint8Array(),
		});
		contentEncoder.finish();
		expect(Buffer.from(encodedContent).toString('base64')).toBe(
			validProductSessionCorpus.wireVectors.contentData.encodedBase64,
		);
		expect(Buffer.from(encodedContent).toString('hex')).toBe(
			validProductSessionCorpus.wireVectors.contentData.encodedHex,
		);
		expect(new TextDecoder().decode(encodedAccepted.subarray(9))).toBe(
			validProductSessionCorpus.wireVectors.contentStream.acceptedBodyJSON,
		);
		expect(new TextDecoder().decode(encodedEnd.subarray(9))).toBe(
			validProductSessionCorpus.wireVectors.contentStream.endBodyJSON,
		);
		const encodedContentStream = Buffer.concat([encodedAccepted, encodedContent, encodedEnd]);
		expect(encodedContentStream.byteLength).toBe(
			validProductSessionCorpus.wireVectors.contentStream.encodedByteLength,
		);
		expect(encodedContentStream.toString('base64')).toBe(
			validProductSessionCorpus.wireVectors.contentStream.encodedBase64,
		);
		const contentDecoder = new BridgeProductContentFrameDecoder();
		const decodedContentFrames = contentDecoder.push(
			Uint8Array.from(
				Buffer.from(validProductSessionCorpus.wireVectors.contentStream.encodedBase64, 'base64'),
			),
		);
		expect(decodedContentFrames).toEqual([
			{ header: contentAcceptedHeader, payload: new Uint8Array() },
			{ header: contentHeader, payload: contentPayload },
			{ header: contentEndHeader, payload: new Uint8Array() },
		]);
		expect(decodedContentFrames).toHaveLength(
			validProductSessionCorpus.wireVectors.contentStream.frameCount,
		);
		contentDecoder.finish();
	});
});

function hostileContractRejects(contract: string, value: unknown): boolean {
	switch (contract) {
		case 'bootstrap':
			return !bridgeProductSessionBootstrapSchema.safeParse(value).success;
		case 'contentHeader':
			return !bridgeProductContentHeaderSchema.safeParse(value).success;
		case 'contentRequest':
			return !bridgeProductContentRequestSchema.safeParse(value).success;
		case 'controlRequest':
			return !bridgeProductControlRequestSchema.safeParse(value).success;
		case 'controlResponse':
			return !bridgeProductControlResponseSchema.safeParse(value).success;
		case 'metadataFrame':
			return !bridgeProductMetadataFrameSchema.safeParse(value).success;
		case 'metadataStreamRequest':
			return !bridgeProductMetadataStreamRequestSchema.safeParse(value).success;
		default:
			throw new Error(`Unknown hostile Bridge product contract: ${contract}`);
	}
}

function concatenateBytes(...parts: readonly Uint8Array[]): Uint8Array {
	const result = new Uint8Array(parts.reduce((total, part) => total + part.byteLength, 0));
	let offset = 0;
	for (const part of parts) {
		result.set(part, offset);
		offset += part.byteLength;
	}
	return result;
}

function withoutWorkerDerivationEpoch<TValue extends { readonly workerDerivationEpoch?: number }>(
	value: TValue,
): Omit<TValue, 'workerDerivationEpoch'> {
	const { workerDerivationEpoch: _workerDerivationEpoch, ...withoutEpoch } = value;
	return withoutEpoch;
}
