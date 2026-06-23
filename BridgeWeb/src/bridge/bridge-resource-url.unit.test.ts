import { describe, expect, test } from 'vitest';

import { parseBridgeContentResourceUrl, parseBridgeResourceUrl } from './bridge-resource-url.js';

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

	test('returns null for malformed resource URL text', () => {
		const parsed = parseBridgeContentResourceUrl('not a valid URL');

		expect(parsed).toBeNull();
	});

	test('parses canonical review package resources', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-package/package-1?generation=7&revision=3',
		);

		expect(parsed).toEqual({
			kind: 'reviewPackage',
			packageId: 'package-1',
			generation: 7,
			revision: 3,
			canonicalUrl:
				'agentstudio://resource/review/review-package/package-1?generation=7&revision=3',
		});
	});

	test('parses review item cursor windows', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-items/package-1?generation=7&revision=3&rangeKind=itemWindow&cursor=cursor-1&start=10&end=18',
		);

		expect(parsed).toEqual({
			kind: 'reviewItems',
			packageId: 'package-1',
			generation: 7,
			revision: 3,
			range: {
				kind: 'itemWindow',
				cursor: 'cursor-1',
				start: 10,
				end: 18,
			},
			canonicalUrl:
				'agentstudio://resource/review/review-items/package-1?cursor=cursor-1&end=18&generation=7&rangeKind=itemWindow&revision=3&start=10',
		});
	});

	test('parses explicit review item lists without sorting item ids', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-items/package-1?revision=3&generation=7&rangeKind=list&itemIds=item-b,item-a',
		);

		expect(parsed).toEqual({
			kind: 'reviewItems',
			packageId: 'package-1',
			generation: 7,
			revision: 3,
			range: {
				kind: 'list',
				itemIds: ['item-b', 'item-a'],
			},
			canonicalUrl:
				'agentstudio://resource/review/review-items/package-1?generation=7&itemIds=item-b%2Citem-a&rangeKind=list&revision=3',
		});
	});

	test('rejects review item lists that exceed the explicit item budget', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-items/package-1?revision=3&generation=7&rangeKind=list&itemIds=item-a,item-b,item-c',
			{ reviewItemsBudget: { maxExplicitItemIds: 2, maxCursorWindowItems: 8 } },
		);

		expect(parsed).toBeNull();
	});

	test('rejects review item cursor windows that exceed the cursor budget', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-items/package-1?generation=7&revision=3&rangeKind=itemWindow&cursor=cursor-1&start=10&end=19',
			{ reviewItemsBudget: { maxExplicitItemIds: 2, maxCursorWindowItems: 8 } },
		);

		expect(parsed).toBeNull();
	});

	test('parses tree cursor resources', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/worktree-file/tree/tree-1?generation=7&revision=3&cursor=cursor-1&depth=2',
		);

		expect(parsed).toEqual({
			kind: 'tree',
			treeId: 'tree-1',
			generation: 7,
			revision: 3,
			range: {
				kind: 'cursor',
				cursor: 'cursor-1',
				depth: 2,
			},
			canonicalUrl:
				'agentstudio://resource/worktree-file/tree/tree-1?cursor=cursor-1&depth=2&generation=7&revision=3',
		});
	});

	test('rejects duplicate singleton query keys', () => {
		const parsed = parseBridgeResourceUrl(
			'agentstudio://resource/review/review-package/package-1?generation=7&generation=8&revision=3',
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
			'agentstudio://resource/review/review-items/package-1?generation=7&revision=3&rangeKind=itemWindow&cursor=cursor-1&start=0&end=10&itemIds=item-a',
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
