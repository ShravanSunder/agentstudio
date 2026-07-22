import { describe, expect, test } from 'vitest';

import { createInertBridgeCommWorkerClient } from './bridge-comm-worker-client.js';
import {
	createBridgeCommWorkerHostileServerTransport,
	createDeferredBridgeWorkerReply,
} from './bridge-comm-worker-hostile-test-support.js';

describe('Bridge comm worker hostile server test support', () => {
	test('drops duplicate reorder stale and never resolving replies without FE protocol ownership', async () => {
		const staleReply = createDeferredBridgeWorkerReply();
		const activeReply = createDeferredBridgeWorkerReply();
		const neverResolvingReply = createDeferredBridgeWorkerReply();
		const transport = createBridgeCommWorkerHostileServerTransport({
			replyPlan: [staleReply, activeReply, activeReply, neverResolvingReply],
		});
		let nextRequestId = 0;
		const client = createInertBridgeCommWorkerClient({
			postMessage: transport.postMessage,
			waitForHealth: transport.waitForHealth,
			createRequestId: (): string => {
				nextRequestId += 1;
				return `request-${nextRequestId}`;
			},
		});

		const firstTask = client.select({
			epoch: 1,
			selectedItemId: 'item-1',
			selectedSource: 'user',
			surface: 'fileView',
		});
		const secondTask = client.select({
			epoch: 2,
			selectedItemId: 'item-2',
			selectedSource: 'user',
			surface: 'fileView',
		});

		activeReply.resolve({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-2',
			status: 'ready',
		});
		staleReply.resolve({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-1',
			status: 'ready',
		});

		await expect(secondTask).resolves.toMatchObject({
			kind: 'health',
			requestId: 'request-2',
			status: 'ready',
		});
		await expect(firstTask).resolves.toEqual({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-1',
			status: 'ready',
		});
		expect(transport.postedMessages.map((message) => message.requestId)).toEqual([
			'request-1',
			'request-2',
		]);
		expect(transport.droppedReplyCount).toBe(1);
		expect(neverResolvingReply.settled).toBe(false);
	});
});
