import { describe, expect, test } from 'vitest';

import bridgeReviewQueryTimeWindowFixture from '../../test-fixtures/bridge-contract-fixtures/edge/bridge-review-query-time-window.json' with { type: 'json' };
import bridgeReviewPackageMissingGenerationFixture from '../../test-fixtures/bridge-contract-fixtures/invalid/bridge-review-package-missing-generation.json' with { type: 'json' };
import bridgeReviewCheckpointFixture from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-review-checkpoint.json' with { type: 'json' };
import bridgeReviewDeltaFixture from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-review-delta.json' with { type: 'json' };
import bridgeReviewPackageFixture from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-review-package.json' with { type: 'json' };
import type { BridgeReviewQuery } from '../review-query/bridge-review-query.js';
import type { BridgeReviewDelta } from './bridge-review-delta.js';
import type { BridgeReviewCheckpoint, BridgeReviewPackage } from './bridge-review-package.js';

describe('bridge review contract fixtures', () => {
	test('keeps Swift fixture JSON assignable to BridgeWeb contract types', () => {
		const reviewPackage = decodeBridgeReviewPackageFixture(bridgeReviewPackageFixture);
		const checkpoint = decodeBridgeReviewCheckpointFixture(bridgeReviewCheckpointFixture);
		const delta = decodeBridgeReviewDeltaFixture(bridgeReviewDeltaFixture);
		const timeWindowQuery = decodeBridgeReviewQueryFixture(bridgeReviewQueryTimeWindowFixture);

		expect(reviewPackage.reviewGeneration).toBe(42);
		expect(checkpoint.checkpointKind).toBe('prompt');
		expect(delta.operations.invalidateContent).toEqual(['handle-generated-head']);
		expect(timeWindowQuery.grouping.kind).toBe('timeWindow');
	});

	test('keeps invalid fixture missing the branded review generation field', () => {
		expect(Object.hasOwn(bridgeReviewPackageMissingGenerationFixture, 'reviewGeneration')).toBe(
			false,
		);
		expect(Object.hasOwn(bridgeReviewPackageMissingGenerationFixture, 'epoch')).toBe(false);
	});
});

type JsonRecord = Readonly<Record<string, unknown>>;

function decodeBridgeReviewPackageFixture(value: unknown): BridgeReviewPackage {
	assertBridgeReviewPackageFixture(value);
	return value;
}

function decodeBridgeReviewCheckpointFixture(value: unknown): BridgeReviewCheckpoint {
	assertBridgeReviewCheckpointFixture(value);
	return value;
}

function decodeBridgeReviewDeltaFixture(value: unknown): BridgeReviewDelta {
	assertBridgeReviewDeltaFixture(value);
	return value;
}

function decodeBridgeReviewQueryFixture(value: unknown): BridgeReviewQuery {
	assertBridgeReviewQueryFixture(value, 'filterPackage');
	return value;
}

function assertBridgeReviewPackageFixture(value: unknown): asserts value is BridgeReviewPackage {
	assertJsonRecord(value);

	expect(value['schemaVersion']).toBe(1);
	expect(value['reviewGeneration']).toBe(42);
	assertBridgeReviewQueryFixture(value['query'], 'compare');
	assertJsonRecord(value['baseEndpoint']);
	assertJsonRecord(value['headEndpoint']);
	assertJsonRecord(value['itemsById']);
	expect(Array.isArray(value['orderedItemIds'])).toBe(true);
	expect(Array.isArray(value['groups'])).toBe(true);
}

function assertBridgeReviewCheckpointFixture(
	value: unknown,
): asserts value is BridgeReviewCheckpoint {
	assertJsonRecord(value);

	expect(value['checkpointKind']).toBe('prompt');
	expect(value['reviewGeneration']).toBe(42);
	expect(value['baseEndpointId']).toBe('endpoint-base-main');
	expect(value['headEndpointId']).toBe('endpoint-head-prompt');
}

function assertBridgeReviewDeltaFixture(value: unknown): asserts value is BridgeReviewDelta {
	assertJsonRecord(value);

	expect(value['packageId']).toBe('package-42');
	expect(value['reviewGeneration']).toBe(42);
	assertJsonRecord(value['operations']);
}

function assertBridgeReviewQueryFixture(
	value: unknown,
	expectedQueryKind: BridgeReviewQuery['queryKind'],
): asserts value is BridgeReviewQuery {
	assertJsonRecord(value);

	expect(value['queryKind']).toBe(expectedQueryKind);
	assertJsonRecord(value['grouping']);
	assertJsonRecord(value['viewFilter']);
	assertJsonRecord(value['provenanceFilter']);
}

function assertJsonRecord(value: unknown): asserts value is JsonRecord {
	expect(typeof value).toBe('object');
	expect(value).not.toBeNull();
}
