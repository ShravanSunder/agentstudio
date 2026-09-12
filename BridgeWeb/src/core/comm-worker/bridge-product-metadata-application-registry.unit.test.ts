import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import {
	defineBridgeProductMetadataApplicationProtocol,
	BridgeProductMetadataApplicationRegistry,
	registerBridgeProductMetadataApplicationProtocol,
} from './bridge-product-metadata-application-protocol.js';
import {
	bridgeProductFileAnnotationMetadataApplicationProtocol,
	bridgeProductFileMetadataApplicationProtocol,
	bridgeProductMetadataApplicationRegistry,
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';

const fixtureProtocol = defineBridgeProductMetadataApplicationProtocol({
	dataSchema: z
		.object({
			event: z.object({ generation: z.number().int().nonnegative(), value: z.string() }).strict(),
			subscriptionKind: z.literal('fixture.metadata'),
		})
		.strict(),
	emptyInterestState: () => ({ subscriptionKind: 'fixture.metadata' }),
	encodeInterestState: () => new Uint8Array([1, 9, 0, 0, 0, 0]),
	initialOpen: () => ({ subscriptionKind: 'fixture.metadata' }),
	initialUpdateOptions: (options) => options,
	interestDelta: () => ({ subscriptionKind: 'fixture.metadata' }),
	interestDeltaItemCount: () => 0,
	interestDeltaSchema: z.object({ subscriptionKind: z.literal('fixture.metadata') }).strict(),
	interestStatePreflightSchema: z
		.object({ subscriptionKind: z.literal('fixture.metadata') })
		.strict(),
	interestStateForUpdate: () => ({ subscriptionKind: 'fixture.metadata' }),
	interestStateSchema: z.object({ subscriptionKind: z.literal('fixture.metadata') }).strict(),
	kind: 'fixture.metadata',
	openSchema: z.object({ subscriptionKind: z.literal('fixture.metadata') }).strict(),
	optionsSchema: z.object({}).strict(),
	preflightInterestState: () => ({
		canonicalByteLength: 6,
		status: 'accepted',
		visitedTextValueCount: 0,
	}),
	readEventSourceGeneration: (event) => event.generation,
	surface: 'file',
	updateOptionsSchema: z.object({}).strict(),
});

describe('Bridge product metadata application registry', () => {
	test('registers a fixture application with empty interests without product switches', () => {
		const registry = new BridgeProductMetadataApplicationRegistry([
			registerBridgeProductMetadataApplicationProtocol(fixtureProtocol),
		]);

		expect(registry.lookup('fixture.metadata')).toBe(fixtureProtocol);
		expect(fixtureProtocol.emptyInterestState()).toEqual({
			subscriptionKind: 'fixture.metadata',
		});
		expect(
			fixtureProtocol.interestDeltaItemCount(
				fixtureProtocol.interestDelta(
					fixtureProtocol.emptyInterestState(),
					fixtureProtocol.emptyInterestState(),
				),
			),
		).toBe(0);
	});

	test('rejects duplicate registration and unknown or mismatched protocol lookup', () => {
		expect(
			() =>
				new BridgeProductMetadataApplicationRegistry([
					registerBridgeProductMetadataApplicationProtocol(fixtureProtocol),
					registerBridgeProductMetadataApplicationProtocol(fixtureProtocol),
				]),
		).toThrow(/[Dd]uplicate/u);

		const registry = new BridgeProductMetadataApplicationRegistry([
			registerBridgeProductMetadataApplicationProtocol(fixtureProtocol),
		]);
		expect(() => registry.lookup('unknown.metadata')).toThrow(/unknown/u);
		expect(() => registry.requireProtocol(bridgeProductFileMetadataApplicationProtocol)).toThrow(
			/[Uu]nregistered/u,
		);
	});

	test('installs exactly the four current File and Review application protocols', () => {
		expect(bridgeProductMetadataApplicationRegistry.registeredKinds).toEqual([
			'file.annotations',
			'file.metadata',
			'review.annotations',
			'review.metadata',
		]);
		expect(bridgeProductMetadataApplicationRegistry.lookup('file.annotations')).toBe(
			bridgeProductFileAnnotationMetadataApplicationProtocol,
		);
		expect(bridgeProductMetadataApplicationRegistry.lookup('file.metadata')).toBe(
			bridgeProductFileMetadataApplicationProtocol,
		);
		expect(bridgeProductMetadataApplicationRegistry.lookup('review.annotations')).toBe(
			bridgeProductReviewAnnotationMetadataApplicationProtocol,
		);
		expect(bridgeProductMetadataApplicationRegistry.lookup('review.metadata')).toBe(
			bridgeProductReviewMetadataApplicationProtocol,
		);
		expect(
			bridgeProductFileAnnotationMetadataApplicationProtocol.encodeInterestState(
				bridgeProductFileAnnotationMetadataApplicationProtocol.emptyInterestState(),
			),
		).toEqual(new Uint8Array([1, 3, 0, 0, 0, 0]));
		expect(
			bridgeProductFileMetadataApplicationProtocol.encodeInterestState(
				bridgeProductFileMetadataApplicationProtocol.emptyInterestState(),
			),
		).toEqual(new Uint8Array([1, 2, 0, 0, 0, 0, 0, 0, 0, 0]));
		expect(
			bridgeProductReviewAnnotationMetadataApplicationProtocol.encodeInterestState(
				bridgeProductReviewAnnotationMetadataApplicationProtocol.emptyInterestState(),
			),
		).toEqual(new Uint8Array([1, 4, 0, 0, 0, 0]));
		expect(
			bridgeProductReviewMetadataApplicationProtocol.encodeInterestState(
				bridgeProductReviewMetadataApplicationProtocol.emptyInterestState(),
			),
		).toEqual(new Uint8Array([1, 1, 0, 0, 0, 0]));
	});

	test('validates raw data only through the selected strict application protocol', () => {
		const validData = {
			event: { generation: 4, value: 'accepted' },
			subscriptionKind: 'fixture.metadata',
		};
		expect(fixtureProtocol.dataSchema.parse(validData)).toEqual(validData);
		expect(
			fixtureProtocol.dataSchema.safeParse({
				event: { generation: 4, value: 'cross-kind' },
				subscriptionKind: 'file.metadata',
			}).success,
		).toBe(false);
		expect(
			fixtureProtocol.dataSchema.safeParse({
				event: { generation: '4', value: 'malformed' },
				subscriptionKind: 'fixture.metadata',
			}).success,
		).toBe(false);
	});
});
