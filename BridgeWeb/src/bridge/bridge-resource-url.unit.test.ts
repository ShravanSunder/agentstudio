import { describe, expect, test } from 'vitest';

import {
	buildBridgeWorkerFetchProbeContentResourceUrl,
	parseBridgeContentResourceUrl,
	parseBridgeResourceUrl,
} from './bridge-resource-url.js';

describe('bridge resource URL', () => {
	test('parses content handle and generation', () => {
		const parsed = parseBridgeContentResourceUrl(
			'agentstudio://resource/review/content/handle-1?generation=7',
		);

		expect(parsed).toEqual({ handleId: 'handle-1', generation: 7 });
	});

	test('parses content handle with optional revision for worktree dev resources', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/handle-1?generation=7&revision=3',
		);

		expect(parsed).toEqual({
			kind: 'content',
			handleId: 'handle-1',
			generation: 7,
			revision: 3,
			range: { kind: 'whole' },
			canonicalUrl: 'agentstudio://resource/review/content/handle-1?generation=7&revision=3',
		});
	});

	test('builds worker fetch probe URL without raw filesystem path leakage', () => {
		const resourceUrl = buildBridgeWorkerFetchProbeContentResourceUrl({
			handleId: 'handle-worker-fetch-probe',
			generation: 7,
			revision: 3,
		});

		expect(resourceUrl).toBe(
			'agentstudio://resource/review/content/handle-worker-fetch-probe?generation=7&revision=3',
		);
		expect(resourceUrl).not.toContain('/Users/example/project');
		expect(parseBridgeResourceUrl(resourceUrl)?.canonicalUrl).toBe(resourceUrl);
	});

	test('returns null for malformed resource URL text', () => {
		const parsed = parseBridgeContentResourceUrl('not a valid URL');

		expect(parsed).toBeNull();
	});

	test('rejects old review package and item-window resources', () => {
		expect(
			parseBridgeResourceUrl(
				'agentstudio://resource/review/review-package/package-1?generation=7&revision=3',
			),
		).toBeNull();
		expect(
			parseBridgeResourceUrl(
				'agentstudio://resource/review/review-items/package-1?generation=7&revision=3&rangeKind=itemWindow&cursor=cursor-1&start=10&end=18',
			),
		).toBeNull();
	});

	test('rejects worktree metadata resources', () => {
		expect(
			parseBridgeResourceUrl(
				'agentstudio://resource/worktree-file/worktree.treeWindow/tree-window-1?generation=7&cursor=cursor-1',
			),
		).toBeNull();
		expect(
			parseBridgeResourceUrl(
				'agentstudio://resource/worktree-file/worktree.treeDeltaOperations/delta-1?generation=7&cursor=cursor-1',
			),
		).toBeNull();
		expect(
			parseBridgeResourceUrl(
				'agentstudio://resource/worktree-file/worktree.status/status-1?generation=7&cursor=cursor-1',
			),
		).toBeNull();
	});

	test('rejects old worktree tree cursor routes', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/worktree-file/tree/tree-1?generation=7&revision=3&cursor=cursor-1&depth=2',
		);

		expect(parsed).toBeNull();
	});

	test('rejects duplicate singleton query keys', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/handle-1?generation=7&generation=8&revision=3',
		);

		expect(parsed).toBeNull();
	});

	test('rejects unknown query keys', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/handle-1?generation=7&path=../../secret',
		);

		expect(parsed).toBeNull();
	});

	test('rejects mixed selector families', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/handle-1?generation=7&revision=3&rangeKind=window&start=0&end=10',
		);

		expect(parsed).toBeNull();
	});

	test('rejects non-canonical path-like resource identifiers', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/%2E%2E%2Fsecret?generation=7',
		);

		expect(parsed).toBeNull();
	});

	test('rejects double-encoded traversal resource identifiers', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/%252e%252e?generation=7',
		);

		expect(parsed).toBeNull();
	});

	test('rejects double-encoded slash resource identifiers', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/content%252F123?generation=7',
		);

		expect(parsed).toBeNull();
	});

	test('rejects malformed percent encoded resource paths without throwing', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/content/%E0%A4%A?generation=7',
		);

		expect(parsed).toBeNull();
	});
});
