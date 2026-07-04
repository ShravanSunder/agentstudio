import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import transportResourceUrlCorpusFixture from '../../test-fixtures/bridge-contract-fixtures/valid/transport-resource-url-corpus.json' with { type: 'json' };
import {
	bridgeResourceUrlWithContentInterest,
	parseBridgeCoreResourceUrl,
	type BridgeAllowedResourceKindsByProtocol,
} from './bridge-resource-url.js';

describe('bridge core resource URL parser', () => {
	const corpus = transportResourceUrlCorpusSchema.parse(transportResourceUrlCorpusFixture);
	const allowedResourceKindsByProtocol = allowedResourceKindsByProtocolFromFixture(
		corpus.allowedResourceKindsByProtocol,
	);

	test('accepts canonical protocol-scoped resource URLs', () => {
		for (const fixtureCase of corpus.valid) {
			expect(
				parseBridgeCoreResourceUrl(fixtureCase.url, { allowedResourceKindsByProtocol }),
				fixtureCase.name,
			).toEqual(fixtureCase.expected);
		}
	});

	test('rejects invalid protocol-scoped resource URLs', () => {
		for (const fixtureCase of corpus.invalid) {
			expect(
				parseBridgeCoreResourceUrl(fixtureCase.url, { allowedResourceKindsByProtocol }),
				fixtureCase.name,
			).toBeNull();
		}
	});

	test('accepts content interest as non-identity demand metadata', () => {
		expect(
			parseBridgeCoreResourceUrl(
				'agentstudio://resource/review/content/content-123?generation=2&revision=4&interest=visible',
				{ allowedResourceKindsByProtocol },
			),
		).toEqual({
			protocol: 'review',
			resourceKind: 'content',
			opaqueId: 'content-123',
			generation: 2,
			revision: 4,
			canonicalUrl:
				'agentstudio://resource/review/content/content-123?generation=2&revision=4',
		});
	});

	test('adds content interest to fetch URLs without changing canonical resource identity', () => {
		const resourceUrl =
			'agentstudio://resource/review/content/content-123?generation=2&revision=4';

		expect(bridgeResourceUrlWithContentInterest(resourceUrl, 'selected')).toBe(
			'agentstudio://resource/review/content/content-123?generation=2&revision=4&interest=selected',
		);
		expect(
			parseBridgeCoreResourceUrl(
				bridgeResourceUrlWithContentInterest(resourceUrl, 'background'),
				{ allowedResourceKindsByProtocol },
			)?.canonicalUrl,
		).toBe(resourceUrl);
	});
});

const transportResourceUrlExpectedSchema = z
	.object({
		protocol: z.string().min(1),
		resourceKind: z.string().min(1),
		opaqueId: z.string().min(1),
		generation: z.number().int().nonnegative().optional(),
		revision: z.number().int().nonnegative().optional(),
		cursor: z.string().min(1).optional(),
		canonicalUrl: z.string().min(1),
	})
	.strict();

const transportResourceUrlCorpusSchema = z
	.object({
		allowedResourceKindsByProtocol: z.record(z.string().min(1), z.array(z.string().min(1))),
		valid: z.array(
			z
				.object({
					name: z.string().min(1),
					url: z.string().min(1),
					expected: transportResourceUrlExpectedSchema,
				})
				.strict(),
		),
		invalid: z.array(
			z
				.object({
					name: z.string().min(1),
					url: z.string().min(1),
				})
				.strict(),
		),
	})
	.strict();

function allowedResourceKindsByProtocolFromFixture(
	fixture: Readonly<Record<string, readonly string[]>>,
): BridgeAllowedResourceKindsByProtocol {
	return Object.fromEntries(
		Object.entries(fixture).map(
			([protocol, resourceKinds]: readonly [string, readonly string[]]) => {
				return [protocol, new Set(resourceKinds)];
			},
		),
	);
}
