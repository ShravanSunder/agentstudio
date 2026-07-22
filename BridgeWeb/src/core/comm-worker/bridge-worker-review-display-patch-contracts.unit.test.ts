import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import {
	BRIDGE_WORKER_REVIEW_DISPLAY_PATCH_LIMIT,
	bridgeWorkerReviewDisplayPatchEventSchema,
	type BridgeWorkerReviewDisplayPatchEvent,
} from './bridge-worker-contracts.js';

describe('Bridge worker Review display patch contracts', () => {
	test('rejects product and source authority instead of treating it as display state', () => {
		// Arrange
		const event = AUTHORITY_BEARING_REVIEW_DISPLAY_EVENT;
		const sourcePatch = event.patches[0];
		const itemPatch = event.patches[1];
		if (
			sourcePatch?.slice !== 'reviewSource' ||
			sourcePatch.operation !== 'upsert' ||
			itemPatch?.slice !== 'reviewItem' ||
			itemPatch.operation !== 'batch'
		) {
			throw new Error('Expected Review source and item display patch fixtures.');
		}
		const authorityCases: ReadonlyArray<{ readonly label: string; readonly value: unknown }> = [
			{
				label: 'package identifier',
				value: event,
			},
			{
				label: 'source endpoint descriptor',
				value: {
					...event,
					patches: [
						{
							...sourcePatch,
							payload: {
								...sourcePatch.payload,
								baseEndpoint: {
									createdAtUnixMilliseconds: 1,
									endpointId: 'base',
									kind: 'gitRef',
									label: 'base',
									providerIdentity: 'provider-1',
									repoId: 'repo-1',
									worktreeId: 'worktree-1',
								},
							},
						},
						itemPatch,
					],
				},
			},
			{
				label: 'product content source descriptor',
				value: {
					...event,
					patches: [
						sourcePatch,
						{
							...itemPatch,
							payload: {
								...itemPatch.payload,
								items: [
									{
										...itemPatch.payload.items[0],
										contentSources: [makeProductReviewContentSourceDescriptor()],
									},
								],
							},
						},
					],
				},
			},
			...['capability', 'resourceUrl', 'contentBody', 'sourceBytes'].map(
				(authorityField): { readonly label: string; readonly value: unknown } => ({
					label: authorityField,
					value: {
						...event,
						patches: [
							{
								...sourcePatch,
								payload: { ...sourcePatch.payload, [authorityField]: 'forbidden-authority' },
							},
							itemPatch,
						],
					},
				}),
			),
			{
				label: 'raw failure',
				value: {
					...event,
					patches: [
						{
							operation: 'failed',
							payload: {
								error: 'metadataUnavailable',
								rawError: 'private failure detail',
								status: 'failed',
							},
							slice: 'reviewSource',
						},
					],
				},
			},
		];

		// Act
		const acceptedAuthorityLabels = authorityCases.flatMap(({ label, value }) =>
			bridgeWorkerReviewDisplayPatchEventSchema.safeParse(value).success ? [label] : [],
		);

		// Assert
		expect(acceptedAuthorityLabels).toEqual([]);
	});

	test('requires worker-issued metadata and semantic content-window identity', () => {
		const contractSource = readFileSync(
			new URL('./bridge-worker-review-display-patch-contracts.ts', import.meta.url),
			'utf8',
		);

		expect(contractSource).toContain('metadataWindowIdentity');
		expect(contractSource).toContain('semanticDocumentRevision');
		expect(contractSource).toContain('windowKey');
	});

	test('rejects every nonempty Review display transfer declaration', () => {
		const event = makeReviewDisplayFailureEvent();

		expect(
			bridgeWorkerReviewDisplayPatchEventSchema.safeParse({
				...event,
				transferDescriptors: [
					{
						byteLength: 8,
						fieldPath: ['patches'],
						messageKind: 'reviewDisplayPatch',
						mode: 'clone',
					},
				],
			}).success,
		).toBe(false);
	});

	test('accepts bounded display metadata and rejects legacy carriers or raw failure details', () => {
		const event = makeReviewDisplayFailureEvent();
		const sourcePatch = event.patches[0];
		if (sourcePatch?.slice !== 'reviewSource' || sourcePatch.operation !== 'failed') {
			throw new Error('Expected Review source failure display patch fixture.');
		}

		expect(bridgeWorkerReviewDisplayPatchEventSchema.parse(event)).toEqual(event);
		expect(JSON.stringify(event)).not.toMatch(
			/"(?:capability|resourceUrl|contents|contentBody|sourceBytes)"|private failure/i,
		);
		expect(
			bridgeWorkerReviewDisplayPatchEventSchema.safeParse({
				...event,
				patches: [
					{
						operation: 'failed',
						payload: {
							error: 'metadataUnavailable',
							rawError: 'private failure detail',
							status: 'failed',
						},
						slice: 'reviewSource',
					},
				],
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerReviewDisplayPatchEventSchema.safeParse({
				...event,
				patches: [
					{
						...sourcePatch,
						payload: {
							...sourcePatch.payload,
							resourceUrl: 'agentstudio://resource/review/legacy',
						},
					},
				],
			}).success,
		).toBe(false);
	});

	test('enforces the bounded patch envelope', () => {
		const event = makeReviewDisplayFailureEvent();
		const failedPatch = {
			operation: 'failed',
			payload: { error: 'metadataUnavailable', status: 'failed' },
			slice: 'reviewSource',
		} as const;

		expect(
			bridgeWorkerReviewDisplayPatchEventSchema.safeParse({
				...event,
				patches: Array.from(
					{ length: BRIDGE_WORKER_REVIEW_DISPLAY_PATCH_LIMIT + 1 },
					() => failedPatch,
				),
			}).success,
		).toBe(false);
	});
});

const AUTHORITY_BEARING_REVIEW_DISPLAY_EVENT = {
	direction: 'serverWorkerToMain',
	epoch: 1,
	kind: 'reviewDisplayPatch',
	patches: [
		{
			operation: 'upsert',
			payload: {
				baseEndpoint: null,
				generation: 7,
				headEndpoint: null,
				packageId: 'package-1',
				query: null,
				revision: 11,
				sourceIdentity: 'source-1',
				status: 'loading',
				summary: null,
				totalItemCount: 1,
				totalTreeRowCount: 1,
			},
			slice: 'reviewSource',
		},
		{
			operation: 'batch',
			payload: {
				items: [
					{
						contentSources: [],
						extentFacts: [],
						metadata: {
							basePath: 'Sources/App.swift',
							changeKind: 'modified',
							contentDescriptorIdsByRole: {},
							contentHashesByRole: {},
							contentRoles: [],
							extension: 'swift',
							fileClass: 'source',
							headPath: 'Sources/App.swift',
							isHiddenByDefault: false,
							itemId: 'item-1',
							language: 'swift',
							mimeTypes: ['text/plain'],
							provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
							reviewPriority: 'normal',
							reviewState: 'unreviewed',
						},
					},
				],
				removedItemIds: [],
				replacementOrder: null,
				reset: true,
				startIndex: 0,
			},
			slice: 'reviewItem',
		},
	],
	projectionRevision: 1,
	sequence: 1,
	surface: 'review',
	transferDescriptors: [],
	wireVersion: 1,
} as const;

function makeReviewDisplayFailureEvent(): BridgeWorkerReviewDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'failed',
				payload: { error: 'metadataUnavailable', status: 'failed' },
				slice: 'reviewSource',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeProductReviewContentSourceDescriptor(): Readonly<Record<string, unknown>> {
	return {
		contentDigest: { algorithm: 'sha256', authority: 'authoritative', value: 'a'.repeat(64) },
		contentKind: 'review.content',
		descriptorId: 'descriptor-1',
		encoding: 'utf-8',
		endpointId: 'head',
		handleId: 'handle-1',
		isBinary: false,
		itemId: 'item-1',
		language: 'swift',
		mimeType: 'text/plain',
		packageId: 'package-1',
		reviewGeneration: 7,
		role: 'head',
		sourceIdentity: 'source-1',
		wholeByteLength: 128,
	};
}
