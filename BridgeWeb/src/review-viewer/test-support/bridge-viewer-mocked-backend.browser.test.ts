import { afterEach, describe, expect, test } from 'vitest';

import { makeBridgeReviewProjectionRequest } from '../navigation/review-projection-request.js';
import { makeBridgeReviewProjectionInput } from '../navigation/review-projection.js';
import { makeBridgeViewerDescriptorRetouchFixture } from './bridge-viewer-mocked-backend-retouch-fixtures.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

describe('bridge viewer mocked backend', () => {
	afterEach(() => {
		disposeBridgeViewerMockedBackends();
		document.body.replaceChildren();
	});

	test('builds distinct small medium and large fixtures with metadata ledgers', () => {
		const smallFixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'small-mixed' });
		const mediumFixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'medium-agentstudio' });
		const largeFixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });

		expect(smallFixture.metadata.fixtureClass).toBe('small-mixed');
		expect(mediumFixture.metadata.fixtureClass).toBe('medium-agentstudio');
		expect(largeFixture.metadata.fixtureClass).toBe('large-diffshub');
		expect(smallFixture.metadata.itemCount).toBeGreaterThan(0);
		expect(mediumFixture.metadata.itemCount).toBeGreaterThan(smallFixture.metadata.itemCount);
		expect(largeFixture.metadata.itemCount).toBeGreaterThan(mediumFixture.metadata.itemCount);
		expect(largeFixture.metadata.packageBytes).toBeGreaterThan(mediumFixture.metadata.packageBytes);
		expect(largeFixture.contentByHandleId.size).toBeGreaterThan(
			smallFixture.contentByHandleId.size,
		);
	});

	test('can keep the huge diff outside the cold baseline rendered window', () => {
		const fixture = makeBridgeViewerBrowserFixture({
			fixtureClass: 'small-mixed',
			largeItemPlacement: 'after-fillers',
		});

		expect(fixture.reviewPackage.orderedItemIds.at(-1)).toBe('browser-large-diff');
		expect(fixture.metadata.diffLineCount).toBeGreaterThanOrEqual(100_000);
	});

	test('large fixture meets scale and distribution targets for large-diff proof', () => {
		const largeFixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const changeKindCounts = requireMetadataRecord(largeFixture.metadata, 'changeKindCounts');
		const fileClassCounts = requireMetadataRecord(largeFixture.metadata, 'fileClassCounts');

		expect(largeFixture.metadata.itemCount).toBeGreaterThanOrEqual(3_420);
		expect(largeFixture.metadata.diffLineCount).toBeGreaterThanOrEqual(100_000);
		expect(requireMetadataNumber(largeFixture.metadata, 'selectedLargeFileLineCount')).toBe(
			100_000,
		);
		expect(largeFixture.reviewPackage.itemsById['browser-large-diff']?.itemKind).toBe('file');
		expect(
			requireMetadataNumber(largeFixture.metadata, 'addedFullContentTargetCount'),
		).toBeGreaterThanOrEqual(1);
		expect(changeKindCounts['added']).toBeGreaterThan(0);
		expect(changeKindCounts['deleted']).toBeGreaterThan(0);
		expect(changeKindCounts['modified']).toBeGreaterThan(0);
		expect(changeKindCounts['renamed']).toBeGreaterThan(0);
		expect(fileClassCounts['config']).toBeGreaterThan(0);
		expect(fileClassCounts['docs']).toBeGreaterThan(0);
		expect(fileClassCounts['source']).toBeGreaterThan(0);
		expect(fileClassCounts['test']).toBeGreaterThan(0);
	});

	test('emits review metadata through intake frames and bodies through resources', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);
		const pageEventDetails: unknown[] = [];
		const intakeFrames: unknown[] = [];
		document.addEventListener('__bridge_push', (event: Event): void => {
			pageEventDetails.push('detail' in event ? event.detail : null);
		});
		document.addEventListener('__bridge_intake_json', (event: Event): void => {
			if (!('detail' in event) || typeof event.detail !== 'object' || event.detail === null) {
				return;
			}
			if (!('json' in event.detail) || typeof event.detail.json !== 'string') {
				return;
			}
			intakeFrames.push(JSON.parse(event.detail.json));
		});

		document.dispatchEvent(new CustomEvent('__bridge_handshake_request'));
		await backend.pushMetadata();
		await backend.pushDelta();
		await Promise.resolve();
		await Promise.resolve();

		expect(backend.pushRecords).toEqual([
			{
				op: 'replace',
				revision: fixture.reviewPackage.revision,
				reviewGeneration: fixture.reviewPackage.reviewGeneration,
				payloadKind: 'metadata',
			},
			{
				op: 'replace',
				revision: fixture.reviewPackage.revision,
				reviewGeneration: fixture.reviewPackage.reviewGeneration,
				payloadKind: 'metadataWindow',
			},
			{
				op: 'merge',
				revision: fixture.streamingAppendDelta.revision,
				reviewGeneration: fixture.streamingAppendDelta.reviewGeneration,
				payloadKind: 'metadataDelta',
			},
		]);
		expect(pageEventDetails).toEqual([]);
		expect(intakeFrames).toHaveLength(3);
		expect(intakeFrames).toEqual([
			expect.objectContaining({
				kind: 'snapshot',
				payload: expect.objectContaining({
					frameKind: 'review.metadataSnapshot',
					itemMetadata: expect.arrayContaining([
						expect.objectContaining({
							itemId: fixture.reviewPackage.orderedItemIds[0],
						}),
					]),
					treeRows: expect.any(Array),
					extentFacts: expect.any(Array),
				}),
			}),
			expect.objectContaining({
				kind: 'delta',
				payload: expect.objectContaining({
					frameKind: 'review.metadataWindow',
					itemMetadata: expect.any(Array),
					treeRows: expect.any(Array),
					extentFacts: expect.any(Array),
				}),
			}),
			expect.objectContaining({
				kind: 'delta',
				payload: expect.objectContaining({
					frameKind: 'review.metadataDelta',
					operations: expect.arrayContaining([
						expect.objectContaining({
							kind: 'appendItems',
						}),
						expect.objectContaining({
							kind: 'upsertTreeRows',
						}),
						expect.objectContaining({
							kind: 'upsertExtentFacts',
						}),
						expect.objectContaining({
							kind: 'replaceItemOrder',
						}),
					]),
				}),
			}),
		]);
		const snapshotFrame = intakeFrames[0];
		expect(JSON.stringify(snapshotFrame)).not.toContain('"itemsById"');
		expect(JSON.stringify(snapshotFrame)).not.toContain('"orderedItemIds"');
		const snapshotPayload =
			typeof snapshotFrame === 'object' && snapshotFrame !== null && 'payload' in snapshotFrame
				? snapshotFrame.payload
				: null;
		expect(snapshotPayload).toEqual(
			expect.objectContaining({
				frameKind: 'review.metadataSnapshot',
				itemMetadata: expect.any(Array),
				treeRows: expect.any(Array),
			}),
		);
	});

	test('records semantic command payloads sent through the Bridge scheme RPC endpoint', async () => {
		const backend = installBridgeViewerMockedBackend();
		const commandDetail = {
			__commandId: 'mock-command-1',
			id: 'mock-command-1',
			jsonrpc: '2.0',
			method: 'review.markFileViewed',
			params: { fileId: 'browser-source-a' },
		};

		const response = await fetch('agentstudio://rpc/command', {
			body: JSON.stringify(commandDetail),
			headers: { 'Content-Type': 'application/json' },
			method: 'POST',
		});

		expect(response.status).toBe(200);
		await expect(response.json()).resolves.toEqual({
			jsonrpc: '2.0',
			id: 'mock-command-1',
			result: null,
		});
		expect(backend.commandDetails).toEqual([commandDetail]);
	});

	test('supports content request success failure and deferred resolution ledgers', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const failedBackend = installBridgeViewerMockedBackend(fixture, {
			contentFailures: [fixture.expected.secondHeadHandleId],
		});
		const failedResponse = await failedBackend.fetchContent(
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338`,
		);
		expect(failedResponse.status).toBe(503);
		expect(failedBackend.requestedUrls).toEqual([
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338`,
		]);
		failedBackend.dispose();

		const unsafeBackend = installBridgeViewerMockedBackend(fixture);
		const unsafeResponse = await unsafeBackend.fetchContent(
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338&unsafe=1`,
		);
		expect(unsafeResponse.status).toBe(400);
		expect(unsafeBackend.requestedUrls).toEqual([
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338&unsafe=1`,
		]);
		unsafeBackend.dispose();

		const deferredBackend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.secondHeadHandleId],
		});
		const deferredResponsePromise = deferredBackend.fetchContent(
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338`,
		);
		await flushMockedBackendMicrotasks();
		expect(deferredBackend.pendingContentResponses).toHaveLength(1);
		deferredBackend.pendingContentResponses[0]?.resolve();
		await expect(
			deferredResponsePromise.then((response): Promise<string> => response.text()),
		).resolves.toContain(fixture.expected.secondText);
	});

	test('removes deferred content responses when their fetch is aborted', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.secondHeadHandleId],
		});
		const abortController = new AbortController();

		const deferredResponsePromise = backend.fetchContent(
			`agentstudio://resource/review/content/${fixture.expected.secondHeadHandleId}?generation=338`,
			{ signal: abortController.signal },
		);
		await flushMockedBackendMicrotasks();
		expect(backend.pendingContentResponses).toHaveLength(1);

		abortController.abort();
		await flushMockedBackendMicrotasks();

		expect(backend.pendingContentResponses).toHaveLength(0);
		await expect(deferredResponsePromise).resolves.toMatchObject({ status: 499 });
	});

	test('records deferred projection worker requests and resolves them through the mock transport', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferProjectionResponses: true,
		});
		const projectionInput = makeBridgeReviewProjectionInput(fixture.reviewPackage);
		const projectionRequest = makeBridgeReviewProjectionRequest({
			projectionMode: { kind: 'normalReview' },
			gitStatusFilter: 'all',
			fileClassFilter: 'source',
		});

		const task = backend.projectionWorkerClient.startProjection({
			projectionInput,
			projectionRequest,
			visibleItemIds: fixture.reviewPackage.orderedItemIds.slice(0, 3),
			workloadId: 'interactive',
			abortKey: 'mocked-backend-unit',
		});

		await flushMockedBackendMicrotasks();
		expect(backend.projectionRequests).toHaveLength(1);
		expect(backend.pendingProjectionResponses).toHaveLength(1);
		backend.pendingProjectionResponses[0]?.resolve();

		await expect(task.completed).resolves.toEqual(
			expect.objectContaining({
				status: 'success',
				identity: task.identity,
			}),
		);
	});

	test('records projection aborts and removes deferred projection responses', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferProjectionResponses: true,
		});
		const projectionInput = makeBridgeReviewProjectionInput(fixture.reviewPackage);
		const projectionRequest = makeBridgeReviewProjectionRequest({
			projectionMode: { kind: 'normalReview' },
			gitStatusFilter: 'all',
			fileClassFilter: 'source',
		});

		const task = backend.projectionWorkerClient.startProjection({
			projectionInput,
			projectionRequest,
			visibleItemIds: fixture.reviewPackage.orderedItemIds.slice(0, 3),
			workloadId: 'interactive',
			abortKey: 'mocked-backend-abort-unit',
		});

		await flushMockedBackendMicrotasks();
		expect(backend.pendingProjectionResponses).toHaveLength(1);
		task.abort();
		await flushMockedBackendMicrotasks();

		expect(backend.projectionAbortKeys).toEqual(['mocked-backend-abort-unit']);
		expect(backend.pendingProjectionResponses).toHaveLength(0);
		await expect(task.completed).resolves.toEqual(
			expect.objectContaining({
				status: 'stale',
				reason: 'superseded',
				identity: task.identity,
			}),
		);
	});

	test('can force projection worker failures for negative browser scenarios', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			projectionFailure: true,
		});
		const projectionInput = makeBridgeReviewProjectionInput(fixture.reviewPackage);
		const projectionRequest = makeBridgeReviewProjectionRequest({
			projectionMode: { kind: 'normalReview' },
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
		});

		const task = backend.projectionWorkerClient.startProjection({
			projectionInput,
			projectionRequest,
			visibleItemIds: fixture.reviewPackage.orderedItemIds.slice(0, 3),
			workloadId: 'interactive',
			abortKey: 'mocked-backend-failure-unit',
		});

		await expect(task.completed).resolves.toEqual(
			expect.objectContaining({
				status: 'failure',
				identity: task.identity,
			}),
		);
	});

	test('builds descriptor-bearing retouch fixtures for metadata-only and changed-hash churn', () => {
		const fixture = makeBridgeViewerDescriptorRetouchFixture();
		const sourceItemId = fixture.reviewPackage.orderedItemIds[0];
		if (sourceItemId === undefined) {
			throw new Error('expected descriptor retouch source item');
		}
		const sourceItem = fixture.reviewPackage.itemsById[sourceItemId];
		const metadataOnlyUpdateItem = fixture.metadataOnlyRetouchDelta.operations.updateItems[0];
		const changedHashUpdateItem = fixture.changedHashRetouchDelta.operations.updateItems[0];

		expect(metadataOnlyUpdateItem?.itemId).toBe(sourceItemId);
		expect(changedHashUpdateItem?.itemId).toBe(sourceItemId);
		expect(fixture.metadataOnlyRetouchDelta.revision).toBe(fixture.reviewPackage.revision + 1);
		expect(fixture.changedHashRetouchDelta.revision).toBe(fixture.reviewPackage.revision + 2);
		expect(metadataOnlyUpdateItem?.contentRoles.head?.handleId).toBe(
			sourceItem?.contentRoles.head?.handleId,
		);
		expect(metadataOnlyUpdateItem?.contentRoles.head?.contentHash).toBe(
			sourceItem?.contentRoles.head?.contentHash,
		);
		expect(changedHashUpdateItem?.contentRoles.head?.handleId).not.toBe(
			sourceItem?.contentRoles.head?.handleId,
		);
		expect(changedHashUpdateItem?.contentRoles.head?.contentHash).toBe(
			fixture.changedHeadContentHash,
		);
		expect(fixture.contentByHandleId.get(fixture.changedHeadHandleId)).toContain(
			fixture.changedHeadText,
		);
	});
});

async function flushMockedBackendMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

function requireMetadataRecord(
	metadata: Record<string, unknown>,
	key: string,
): Record<string, number> {
	const value = metadata[key];
	if (typeof value !== 'object' || value === null || Array.isArray(value)) {
		throw new Error(`Expected metadata record for ${key}`);
	}
	return Object.fromEntries(
		Object.entries(value).map(([entryKey, entryValue]: [string, unknown]): [string, number] => {
			if (typeof entryValue !== 'number') {
				throw new Error(`Expected numeric metadata value for ${key}.${entryKey}`);
			}
			return [entryKey, entryValue];
		}),
	);
}

function requireMetadataNumber(metadata: Record<string, unknown>, key: string): number {
	const value = metadata[key];
	if (typeof value !== 'number') {
		throw new Error(`Expected metadata number for ${key}`);
	}
	return value;
}
