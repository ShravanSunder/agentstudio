import { describe, expect, test } from 'vitest';

import { contentRequest } from '../src/core/comm-worker/bridge-product-content-frame-test-support.js';
import {
	bridgeWorktreeDevFileContentRouteMatchesDescriptor,
	bridgeWorktreeDevFileContentRouteUsesOrigin,
	parseBridgeWorktreeDevFileContentRouteRequest,
	parseBridgeWorktreeDevReloadIntegerList,
	parseBridgeWorktreeDevReloadIntegerToken,
} from './bridge-worktree-dev-reload-diagnostics.js';

describe('bridge worktree dev reload diagnostics', () => {
	test('parses strict nonnegative integer lists', () => {
		expect(parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text: '' })).toEqual([]);
		expect(parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text: '1,2,3' })).toEqual([
			1, 2, 3,
		]);
	});

	test('rejects malformed integer tokens and comma lists', () => {
		for (const text of ['2x', '1e3', '2 ', '2,,3', '2,', ',2']) {
			expect(() => parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text })).toThrow(
				/strict nonnegative integer/u,
			);
		}
		expect(() => parseBridgeWorktreeDevReloadIntegerToken({ label: 'count', token: '-1' })).toThrow(
			/strict nonnegative integer/u,
		);
	});

	test('correlates typed File content POST bodies only on the product endpoint and origin', () => {
		const expectedOrigin = 'http://127.0.0.1:5173';
		const expectedUrl = 'http://127.0.0.1:5173/__bridge-product/content?scenario=current-worktree';
		const request = contentRequest();
		const postData = JSON.stringify(request);

		expect(
			bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin,
				url: expectedUrl,
			}),
		).toBe(true);
		expect(
			bridgeWorktreeDevFileContentRouteMatchesDescriptor({
				expectedDescriptorId: request.descriptor.descriptorId,
				expectedOrigin,
				method: 'POST',
				postData,
				url: expectedUrl,
			}),
		).toBe(true);
		expect(
			parseBridgeWorktreeDevFileContentRouteRequest({
				expectedOrigin,
				method: 'POST',
				postData,
				url: expectedUrl,
			}),
		).toMatchObject({
			contentRequestId: request.contentRequestId,
			descriptorId: request.descriptor.descriptorId,
			leaseId: request.leaseId,
		});

		for (const invalidRequest of [
			{ method: 'GET', postData, url: expectedUrl },
			{ method: 'POST', postData: null, url: expectedUrl },
			{ method: 'POST', postData: '{', url: expectedUrl },
			{
				method: 'POST',
				postData,
				url: 'http://localhost:5173/__bridge-product/content',
			},
			{
				method: 'POST',
				postData,
				url: 'http://127.0.0.1:5173/__bridge-worktree/file-content/dev-file-1',
			},
		]) {
			expect(
				parseBridgeWorktreeDevFileContentRouteRequest({ expectedOrigin, ...invalidRequest }),
			).toBeNull();
		}
		expect(
			bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin,
				url: 'http://localhost:5173/__bridge-product/content',
			}),
		).toBe(false);
	});
});
