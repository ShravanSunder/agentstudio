import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import strictJSONCorpus from '../../test-fixtures/bridge-contract-fixtures/edge/bridge-product-strict-json-corpus.json' with { type: 'json' };
import {
	BridgeProductStrictJSONError,
	parseBridgeProductStrictJSON,
} from './bridge-product-strict-json.js';

const textEncoder = new TextEncoder();

describe('Bridge product strict JSON', () => {
	test('keeps the raw Swift and TypeScript corpus byte-identical at its frozen hash', () => {
		const typeScriptBytes = readFileSync(
			new URL(
				'../../test-fixtures/bridge-contract-fixtures/edge/bridge-product-strict-json-corpus.json',
				import.meta.url,
			),
		);
		const swiftBytes = readFileSync(
			new URL(
				'../../../../Tests/BridgeContractFixtures/edge/bridge-product-strict-json-corpus.json',
				import.meta.url,
			),
		);

		expect(swiftBytes.equals(typeScriptBytes)).toBe(true);
		expect(createHash('sha256').update(typeScriptBytes).digest('hex')).toBe(
			'5f42825787d62d912a5061aefc9c4d3b9e5754b80a1730ee4ea931547c433397',
		);
	});

	test('accepts unique, sibling, escaped, and structurally hostile string cases', () => {
		for (const fixtureCase of strictJSONCorpus.valid) {
			expect(parseBridgeProductStrictJSON(textEncoder.encode(fixtureCase.rawJSON))).toEqual(
				JSON.parse(fixtureCase.rawJSON),
			);
		}
	});

	test('rejects top-level, nested, array-nested, and escaped-equivalent duplicates', () => {
		for (const fixtureCase of strictJSONCorpus.invalid) {
			expect(() => parseBridgeProductStrictJSON(textEncoder.encode(fixtureCase.rawJSON))).toThrow(
				expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
					failureCode: 'duplicate_object_member',
				}),
			);
		}
	});

	test('bounds nesting, members, input bytes, UTF-8, and semantic JSON decoding', () => {
		const maximumDepthJSON = `${'['.repeat(64)}0${']'.repeat(64)}`;
		const oversizedDepthJSON = `${'['.repeat(65)}0${']'.repeat(65)}`;
		const maximumMembersJSON = `{${Array.from(
			{ length: 64 },
			(_, index) => `"member${index}":${index}`,
		).join(',')}}`;
		const oversizedMembersJSON = `{${Array.from(
			{ length: 65 },
			(_, index) => `"member${index}":${index}`,
		).join(',')}}`;

		expect(parseBridgeProductStrictJSON(textEncoder.encode(maximumDepthJSON))).toBeDefined();
		expect(parseBridgeProductStrictJSON(textEncoder.encode(maximumMembersJSON))).toBeDefined();
		expect(() => parseBridgeProductStrictJSON(textEncoder.encode(oversizedDepthJSON))).toThrow(
			expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
				failureCode: 'nesting_exceeds_ceiling',
			}),
		);
		expect(() => parseBridgeProductStrictJSON(textEncoder.encode(oversizedMembersJSON))).toThrow(
			expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
				failureCode: 'object_member_count_exceeds_ceiling',
			}),
		);
		expect(() => parseBridgeProductStrictJSON(new Uint8Array(256 * 1024 + 1))).toThrow(
			expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
				failureCode: 'input_exceeds_ceiling',
			}),
		);
		expect(() => parseBridgeProductStrictJSON(Uint8Array.of(0xff))).toThrow(
			expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
				failureCode: 'invalid_utf8',
			}),
		);
		expect(() => parseBridgeProductStrictJSON(textEncoder.encode('{"kind":'))).toThrow(
			expect.objectContaining<Partial<BridgeProductStrictJSONError>>({
				failureCode: 'invalid_json',
			}),
		);
	});

	test('preserves exact ASCII and Kelvin-sign member names for semantic validation', () => {
		const exactMember = parseBridgeProductStrictJSON(
			textEncoder.encode('{"subscriptionKind":"review.metadata"}'),
		);
		const kelvinSpoof = parseBridgeProductStrictJSON(
			textEncoder.encode('{"subscription\\u212Aind":"review.metadata"}'),
		);
		const exactAndKelvinSpellings = parseBridgeProductStrictJSON(
			textEncoder.encode(
				'{"subscriptionKind":"review.metadata","subscription\\u212Aind":"file.metadata"}',
			),
		);

		expect(bridgeProductJSONObjectKeys(exactMember)).toEqual(['subscriptionKind']);
		expect(bridgeProductJSONObjectKeys(kelvinSpoof)).toEqual(['subscription\u212Aind']);
		expect(bridgeProductJSONObjectKeys(exactAndKelvinSpellings)).toEqual([
			'subscriptionKind',
			'subscription\u212Aind',
		]);
	});
});

function bridgeProductJSONObjectKeys(value: unknown): readonly string[] {
	if (typeof value !== 'object' || value === null || Array.isArray(value)) {
		throw new Error('Expected Bridge product strict JSON to produce an object.');
	}
	return Object.keys(value);
}
