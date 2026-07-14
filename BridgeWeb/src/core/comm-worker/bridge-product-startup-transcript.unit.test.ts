import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import {
	bridgeProductContentHeaderSchema,
	bridgeProductContentRequestSchema,
} from './bridge-product-content-contracts.js';
import { bridgeProductFrameAcknowledgementRequestSchema } from './bridge-product-frame-acknowledgement-contracts.js';
import {
	type BridgeProductControlMux,
	type BridgeProductSubscriptionOpenAccepted,
	type BridgeProductSubscriptionUpdateBatchAccepted,
} from './bridge-product-session-authority.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataFrameSchema,
	bridgeProductMetadataStreamRequestSchema,
} from './bridge-product-session-contracts.js';
import { type BridgeProductSubscriptionInterestDeltaWire } from './bridge-product-subscription-contracts.js';
import { BridgeProductSubscriptionState } from './bridge-product-subscription-state.js';

const transcriptCodecSchema = z.enum([
	'contentHeader',
	'contentRequest',
	'controlRequest',
	'controlResponse',
	'metadataFrame',
	'metadataStreamRequest',
]);
const observationDispositionSchema = z.enum([
	'accepted',
	'idempotentReplay',
	'rejectedChangedReuse',
	'rejectedForeignIdentity',
	'rejectedPostTerminal',
	'rejectedSequenceGap',
	'rejectedStaleWorker',
]);
const validStartupTranscriptSchema = z
	.object({
		lifecycleExpectations: z
			.object({
				cancel: z
					.object({
						requestId: z.string().min(1),
						subscriptionId: z.string().min(1),
						terminalFrameKind: z.literal('subscription.cancelled'),
					})
					.strict(),
				replacement: z
					.object({
						replacementWorkerInstanceId: z.string().min(1),
						retiredWorkerInstanceId: z.string().min(1),
						staleObservationCase: z.string().min(1),
					})
					.strict(),
				reset: z
					.object({
						reason: z.literal('interest_mismatch'),
						subscriptionId: z.string().min(1),
						terminalFrameKind: z.literal('subscription.reset'),
					})
					.strict(),
				zeroResidue: z
					.object({
						leases: z.literal(0),
						producers: z.literal(0),
						responses: z.literal(0),
						retainedBodies: z.literal(0),
						sessions: z.literal(0),
						subscriptions: z.literal(0),
						waiters: z.literal(0),
					})
					.strict(),
			})
			.strict(),
		observationCases: z.array(
			z
				.object({
					expectedDisposition: observationDispositionSchema,
					name: z.string().min(1),
					request: z.unknown(),
				})
				.strict(),
		),
		schemaVersion: z.literal(1),
		transcript: z.array(
			z
				.object({
					codec: transcriptCodecSchema,
					name: z.string().min(1),
					payloadBase64: z.string().optional(),
					value: z.unknown(),
				})
				.strict(),
		),
		wireVersion: z.literal(2),
	})
	.strict();
const invalidStartupTranscriptSchema = z
	.object({
		cases: z.array(
			z
				.object({
					name: z.string().min(1),
					request: z.unknown(),
				})
				.strict(),
		),
		schemaVersion: z.literal(1),
		wireVersion: z.literal(2),
	})
	.strict();

const frozenFixtureHashes = {
	invalid: '78da34fabc8fdfeb2316df0b21e819691ea2bb4e861a74cbee3270231d6494c8',
	valid: '9dbb1c5d33f832e0c76b09859fdc9aed6561256033b6acede000df4f2a774112',
} as const;

describe('Bridge product startup transcript', () => {
	test('keeps the Swift source and TypeScript mirrors byte-identical', () => {
		// Arrange
		const fixtureKinds = ['invalid', 'valid'] as const;

		// Act
		const fixtureIdentities = fixtureKinds.map((fixtureKind) => {
			const sourceBytes = readFixtureBytes(
				`../../../../Tests/BridgeContractFixtures/${fixtureKind}/bridge-product-startup-transcript.json`,
			);
			const mirrorBytes = readFixtureBytes(
				`../../test-fixtures/bridge-contract-fixtures/${fixtureKind}/bridge-product-startup-transcript.json`,
			);
			return {
				fixtureKind,
				mirrorBytes,
				observedHash: createHash('sha256').update(sourceBytes).digest('hex'),
				sourceBytes,
			};
		});

		// Assert
		for (const fixtureIdentity of fixtureIdentities) {
			expect(fixtureIdentity.sourceBytes.equals(fixtureIdentity.mirrorBytes)).toBe(true);
			expect(fixtureIdentity.observedHash).toBe(frozenFixtureHashes[fixtureIdentity.fixtureKind]);
		}
	});

	test('decodes every already-supported startup and event structure', () => {
		// Arrange
		const fixture = loadValidFixture();

		// Act / Assert
		expect(fixture.transcript).toHaveLength(27);
		for (const entry of fixture.transcript) {
			switch (entry.codec) {
				case 'contentHeader':
					expect(bridgeProductContentHeaderSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
				case 'contentRequest':
					expect(bridgeProductContentRequestSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
				case 'controlRequest':
					expect(bridgeProductControlRequestSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
				case 'controlResponse':
					expect(bridgeProductControlResponseSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
				case 'metadataFrame':
					expect(bridgeProductMetadataFrameSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
				case 'metadataStreamRequest':
					expect(bridgeProductMetadataStreamRequestSchema.parse(entry.value), entry.name).toEqual(
						entry.value,
					);
					break;
			}
		}
	});

	test('derives every Review interest transition hash through production subscription state', async () => {
		// Arrange
		const fixture = loadValidFixture();
		const openRequest = transcriptValue(
			fixture,
			'review-subscription-open',
			bridgeProductControlRequestSchema,
		);
		const openResponse = transcriptValue(
			fixture,
			'review-subscription-open-accepted',
			bridgeProductControlResponseSchema,
		);
		const updateRequest = transcriptValue(
			fixture,
			'review-selection-demand',
			bridgeProductControlRequestSchema,
		);
		const updateResponse = transcriptValue(
			fixture,
			'review-selection-demand-accepted',
			bridgeProductControlResponseSchema,
		);
		const committedFrame = transcriptValue(
			fixture,
			'review-selection-demand-committed',
			bridgeProductMetadataFrameSchema,
		);
		const cancelledFrame = transcriptValue(
			fixture,
			'review-subscription-cancelled-frame',
			bridgeProductMetadataFrameSchema,
		);
		if (
			openRequest.kind !== 'subscription.open' ||
			openRequest.subscription.subscriptionKind !== 'review.metadata' ||
			openResponse.kind !== 'subscription.openAccepted' ||
			openResponse.subscriptionKind !== 'review.metadata' ||
			updateRequest.kind !== 'subscription.updateBatch' ||
			updateRequest.subscriptionKind !== 'review.metadata' ||
			updateResponse.kind !== 'subscription.updateBatchAccepted' ||
			updateResponse.subscriptionKind !== 'review.metadata' ||
			committedFrame.kind !== 'subscription.interestsCommitted' ||
			cancelledFrame.kind !== 'subscription.cancelled'
		) {
			throw new Error('Review startup transcript does not contain its required typed transitions.');
		}
		const typedOpenResponse = {
			...openResponse,
			subscriptionKind: 'review.metadata',
		} satisfies BridgeProductSubscriptionOpenAccepted<'review.metadata'>;
		const typedUpdateResponse = {
			...updateResponse,
			subscriptionKind: 'review.metadata',
		} satisfies BridgeProductSubscriptionUpdateBatchAccepted<'review.metadata'>;
		const controlHarness = createStartupTranscriptReviewControlHarness(
			typedOpenResponse,
			typedUpdateResponse,
		);
		const subscriptionState = new BridgeProductSubscriptionState({
			controlMux: controlHarness.controlMux,
			createIdentifier: (): string => updateRequest.updateId,
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: { interests: [] },
			onTerminal: (): void => {},
			subscriptionId: openRequest.subscriptionId,
			subscriptionKind: 'review.metadata',
			workerDerivationEpoch: openRequest.workerDerivationEpoch,
		});
		subscriptionState.start();

		// Act
		const updateCompletion = subscriptionState.publicSubscription.update({
			interests: updateRequest.delta.add.map((addition) => ({
				itemIds: [addition.itemId],
				lane: addition.lane,
			})),
		});
		try {
			const derivedUpdate = await controlHarness.capturedUpdate;

			// Assert
			expect(derivedUpdate).toMatchObject({
				baseInterestRevision: updateRequest.baseInterestRevision,
				baseInterestSha256: updateRequest.baseInterestSha256,
				delta: updateRequest.delta,
				subscriptionId: updateRequest.subscriptionId,
				targetInterestRevision: updateRequest.targetInterestRevision,
				updateId: updateRequest.updateId,
				workerDerivationEpoch: updateRequest.workerDerivationEpoch,
			});
			expect([
				updateRequest.targetInterestSha256,
				updateResponse.targetInterestSha256,
				committedFrame.interestSha256,
				cancelledFrame.interestSha256,
			]).toEqual(Array.from({ length: 4 }, () => derivedUpdate.targetInterestSha256));
		} finally {
			subscriptionState.fail(new Error('Review startup transcript test cleanup.'));
			await updateCompletion.catch((): undefined => undefined);
		}
	});

	test('freezes observation identities and lifecycle outcomes', () => {
		// Arrange
		const fixture = loadValidFixture();
		const metadataCase = fixture.observationCases.find(
			(observationCase) => observationStreamKind(observationCase.request) === 'metadata',
		);
		const contentCase = fixture.observationCases.find(
			(observationCase) => observationStreamKind(observationCase.request) === 'content',
		);

		// Act
		const metadataKeys = sortedObjectKeys(metadataCase?.request);
		const contentKeys = sortedObjectKeys(contentCase?.request);
		const dispositions = new Set(
			fixture.observationCases.map((observationCase) => observationCase.expectedDisposition),
		);

		// Assert
		expect(fixture.observationCases).toHaveLength(16);
		expect(metadataKeys).toEqual([
			'kind',
			'metadataStreamId',
			'paneSessionId',
			'streamKind',
			'streamSequence',
			'wireVersion',
			'workerInstanceId',
		]);
		expect(contentKeys).toEqual([
			'contentRequestId',
			'contentSequence',
			'kind',
			'leaseId',
			'paneSessionId',
			'streamKind',
			'wireVersion',
			'workerInstanceId',
		]);
		expect(dispositions).toEqual(new Set(observationDispositionSchema.options));
		expect(
			fixture.observationCases.find(({ name }) => name === 'metadata-exact-replay')?.request,
		).toEqual(
			fixture.observationCases.find(({ name }) => name === 'metadata-sequence-zero')?.request,
		);
		expect(
			fixture.observationCases.find(({ name }) => name === 'content-exact-replay')?.request,
		).toEqual(
			fixture.observationCases.find(({ name }) => name === 'content-end-sequence-two')?.request,
		);
		expect(Object.values(fixture.lifecycleExpectations.zeroResidue)).toEqual([0, 0, 0, 0, 0, 0, 0]);
	});

	test('accepts metadata and every independently paced content observation body', () => {
		// Arrange
		const fixture = loadValidFixture();

		// Act
		const parseResults = fixture.observationCases.map((observationCase) => ({
			name: observationCase.name,
			result: bridgeProductFrameAcknowledgementRequestSchema.safeParse(observationCase.request),
		}));

		// Assert
		for (const parseResult of parseResults) {
			expect(parseResult.result.success, parseResult.name).toBe(true);
		}
	});

	test('rejects every structurally hostile observation body', () => {
		// Arrange
		const fixture = loadInvalidFixture();

		// Act
		const parseResults = fixture.cases.map((fixtureCase) => ({
			name: fixtureCase.name,
			result: bridgeProductFrameAcknowledgementRequestSchema.safeParse(fixtureCase.request),
		}));

		// Assert
		expect(parseResults).toHaveLength(10);
		for (const parseResult of parseResults) {
			expect(parseResult.result.success, parseResult.name).toBe(false);
		}
	});
});

function loadValidFixture(): z.infer<typeof validStartupTranscriptSchema> {
	const bytes = readFixtureBytes(
		'../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-startup-transcript.json',
	);
	const parsedJSON: unknown = JSON.parse(bytes.toString('utf8'));
	return validStartupTranscriptSchema.parse(parsedJSON);
}

function loadInvalidFixture(): z.infer<typeof invalidStartupTranscriptSchema> {
	const bytes = readFixtureBytes(
		'../../test-fixtures/bridge-contract-fixtures/invalid/bridge-product-startup-transcript.json',
	);
	const parsedJSON: unknown = JSON.parse(bytes.toString('utf8'));
	return invalidStartupTranscriptSchema.parse(parsedJSON);
}

function readFixtureBytes(relativePath: string): Buffer {
	return readFileSync(new URL(relativePath, import.meta.url));
}

function observationStreamKind(value: unknown): string | undefined {
	if (typeof value !== 'object' || value === null || !('streamKind' in value)) {
		return undefined;
	}
	return typeof value.streamKind === 'string' ? value.streamKind : undefined;
}

function sortedObjectKeys(value: unknown): string[] {
	return typeof value === 'object' && value !== null ? Object.keys(value).toSorted() : [];
}

function transcriptValue<TSchema extends z.ZodType>(
	fixture: z.infer<typeof validStartupTranscriptSchema>,
	name: string,
	schema: TSchema,
): z.output<TSchema> {
	const entry = fixture.transcript.find((candidate) => candidate.name === name);
	if (entry === undefined) throw new Error(`Missing startup transcript entry: ${name}.`);
	return schema.parse(entry.value);
}

interface CapturedSubscriptionUpdate {
	readonly baseInterestRevision: number;
	readonly baseInterestSha256: string;
	readonly batchCount: number;
	readonly batchIndex: number;
	readonly delta: BridgeProductSubscriptionInterestDeltaWire;
	readonly subscriptionId: string;
	readonly targetInterestRevision: number;
	readonly targetInterestSha256: string;
	readonly totalDeltaItemCount: number;
	readonly updateId: string;
	readonly workerDerivationEpoch: number;
}

function createStartupTranscriptReviewControlHarness(
	openResponse: BridgeProductSubscriptionOpenAccepted<'review.metadata'>,
	updateResponse: BridgeProductSubscriptionUpdateBatchAccepted<'review.metadata'>,
): {
	readonly capturedUpdate: Promise<CapturedSubscriptionUpdate>;
	readonly controlMux: Pick<
		BridgeProductControlMux,
		'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	>;
} {
	let resolveCapturedUpdate: ((update: CapturedSubscriptionUpdate) => void) | null = null;
	const capturedUpdate = new Promise<CapturedSubscriptionUpdate>((resolve): void => {
		resolveCapturedUpdate = resolve;
	});
	const controlMux: Pick<
		BridgeProductControlMux,
		'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	> = {
		cancelSubscription: async (): Promise<never> => {
			throw new Error('Startup transcript harness does not cancel subscriptions.');
		},
		openSubscription: async (props) => {
			if (props.subscription.subscriptionKind !== 'review.metadata') {
				throw new Error('Startup transcript harness accepts only Review subscriptions.');
			}
			return { ...openResponse, subscriptionKind: props.subscription.subscriptionKind };
		},
		updateSubscriptionBatch: async (props) => {
			resolveCapturedUpdate?.(props);
			if (props.delta.subscriptionKind !== 'review.metadata') {
				throw new Error('Startup transcript harness accepts only Review subscription updates.');
			}
			return { ...updateResponse, subscriptionKind: props.delta.subscriptionKind };
		},
	};
	return { capturedUpdate, controlMux };
}
