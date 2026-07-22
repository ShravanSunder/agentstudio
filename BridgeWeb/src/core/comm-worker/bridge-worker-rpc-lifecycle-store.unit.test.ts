import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import type { BridgeWorkerMainToServerCommand } from './bridge-worker-contracts.js';
import {
	createBridgeWorkerRpcLifecycleStore,
	type StartBridgeWorkerRpcRequestProps,
} from './bridge-worker-rpc-lifecycle-store.js';

type AssertExactCommandUnion<TValue extends true> = TValue;
type LifecycleCommandMatchesContract =
	BridgeWorkerMainToServerCommand['command'] extends StartBridgeWorkerRpcRequestProps['command']
		? StartBridgeWorkerRpcRequestProps['command'] extends BridgeWorkerMainToServerCommand['command']
			? true
			: false
		: false;

describe('Bridge worker RPC lifecycle store', () => {
	test('derives request command names from the worker contract command surface', () => {
		const commandContractMatches: AssertExactCommandUnion<LifecycleCommandMatchesContract> = true;

		expect(commandContractMatches).toBe(true);
	});

	test('tracks pending ack fail timeout and rollback metadata without caching rows content windows or byte buffers', () => {
		const store = createBridgeWorkerRpcLifecycleStore();
		const snapshots: readonly unknown[] = [];
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		store.startRequest({
			requestId: 'request-1',
			command: 'select',
			optimisticIntentId: 'intent-1',
			rollbackMetadata: {
				kind: 'selection',
				previousSelectedItemId: 'item-old',
			},
		});
		store.ackRequest({
			requestId: 'request-1',
			acknowledgedAtSequence: 7,
		});
		store.startRequest({ requestId: 'request-2', command: 'viewport' });
		store.failRequest({ requestId: 'request-2', reason: 'stale_epoch' });
		store.startRequest({ requestId: 'request-3', command: 'hover' });
		store.timeoutRequest({ requestId: 'request-3' });

		const snapshot = store.getSnapshot();
		snapshots.concat(snapshot);

		expect(snapshot.requestsById['request-1']).toMatchObject({
			state: 'acked',
			rollbackMetadata: {
				kind: 'selection',
				previousSelectedItemId: 'item-old',
			},
		});
		expect(snapshot.requestsById['request-2']).toMatchObject({
			state: 'failed',
			reason: 'stale_epoch',
		});
		expect(snapshot.requestsById['request-3']).toMatchObject({
			state: 'timed_out',
		});
		expect(JSON.stringify(snapshot)).not.toMatch(
			/rowById|contentWindow|byteBuffer|demandMembership|canonicalCache|refetch/i,
		);
		expect(publishCount).toBe(6);

		unsubscribe();
	});

	test('keeps raw request ids distinct instead of normalizing them into one slot', () => {
		const store = createBridgeWorkerRpcLifecycleStore();

		store.startRequest({ requestId: 'request-1', command: 'select' });
		store.startRequest({ requestId: 'request_1', command: 'hover' });

		expect(store.getSnapshot().requestsById['request-1']).toMatchObject({
			requestId: 'request-1',
			command: 'select',
		});
		expect(store.getSnapshot().requestsById['request_1']).toMatchObject({
			requestId: 'request_1',
			command: 'hover',
		});
	});

	test('preserves duplicate request id and missing request read errors', () => {
		const store = createBridgeWorkerRpcLifecycleStore();

		store.startRequest({ requestId: 'tracked', command: 'select' });

		expect(() => store.startRequest({ requestId: 'tracked', command: 'hover' })).toThrow(
			'Bridge worker RPC request tracked is already tracked.',
		);
		expect(() => store.ackRequest({ requestId: 'missing', acknowledgedAtSequence: 1 })).toThrow(
			'Bridge worker RPC request missing is not tracked.',
		);
	});

	test.each([0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN])(
		'rejects invalid terminal history capacity %s',
		(terminalHistoryCapacityPerSurface) => {
			expect(() =>
				createBridgeWorkerRpcLifecycleStore({ terminalHistoryCapacityPerSurface }),
			).toThrow(
				'Bridge worker RPC lifecycle store requires a positive safe terminal history capacity.',
			);
		},
	);

	test('evicts the oldest terminal request on the same surface by settlement order', () => {
		const store = createBridgeWorkerRpcLifecycleStore({ terminalHistoryCapacityPerSurface: 2 });

		store.startRequest({ requestId: 'settles-late', command: 'select', surface: 'review' });
		store.startRequest({ requestId: 'settles-first', command: 'hover', surface: 'review' });
		store.ackRequest({ requestId: 'settles-first', acknowledgedAtSequence: 1 });
		store.startRequest({ requestId: 'settles-second', command: 'viewport', surface: 'review' });
		store.ackRequest({ requestId: 'settles-second', acknowledgedAtSequence: 2 });
		store.ackRequest({ requestId: 'settles-late', acknowledgedAtSequence: 3 });

		const requestsById = store.getSnapshot().requestsById;
		expect(requestsById['settles-first']).toBeUndefined();
		expect(requestsById['settles-second']).toMatchObject({ state: 'acked' });
		expect(requestsById['settles-late']).toMatchObject({
			state: 'acked',
			acknowledgedAtSequence: 3,
		});
	});

	test('never evicts pending requests when terminal history reaches capacity', () => {
		const store = createBridgeWorkerRpcLifecycleStore({ terminalHistoryCapacityPerSurface: 1 });
		let publishCount = 0;
		store.subscribe(() => {
			publishCount += 1;
		});

		store.startRequest({ requestId: 'pending-review', command: 'select', surface: 'review' });
		store.startRequest({ requestId: 'terminal-old', command: 'hover', surface: 'review' });
		store.ackRequest({ requestId: 'terminal-old', acknowledgedAtSequence: 1 });
		store.startRequest({ requestId: 'terminal-latest', command: 'viewport', surface: 'review' });
		store.ackRequest({ requestId: 'terminal-latest', acknowledgedAtSequence: 2 });

		const requestsById = store.getSnapshot().requestsById;
		expect(requestsById['pending-review']).toMatchObject({ state: 'pending' });
		expect(requestsById['terminal-old']).toBeUndefined();
		expect(requestsById['terminal-latest']).toMatchObject({ state: 'acked' });
		expect(publishCount).toBe(5);
	});

	test('bounds terminal history independently for each surface', () => {
		const store = createBridgeWorkerRpcLifecycleStore({ terminalHistoryCapacityPerSurface: 1 });

		for (const surface of ['fileView', 'pane', 'review'] as const) {
			store.startRequest({ requestId: `${surface}-old`, command: 'select', surface });
			store.ackRequest({ requestId: `${surface}-old`, acknowledgedAtSequence: 1 });
		}
		store.startRequest({ requestId: 'review-latest', command: 'hover', surface: 'review' });
		store.ackRequest({ requestId: 'review-latest', acknowledgedAtSequence: 2 });

		const requestsById = store.getSnapshot().requestsById;
		expect(requestsById['fileView-old']).toMatchObject({ state: 'acked' });
		expect(requestsById['pane-old']).toMatchObject({ state: 'acked' });
		expect(requestsById['review-old']).toBeUndefined();
		expect(requestsById['review-latest']).toMatchObject({ state: 'acked' });
	});

	test('retains failed and timed out settlements until each is genuinely oldest', () => {
		const store = createBridgeWorkerRpcLifecycleStore({ terminalHistoryCapacityPerSurface: 2 });

		store.startRequest({ requestId: 'failed', command: 'select', surface: 'fileView' });
		store.failRequest({ requestId: 'failed', reason: 'rejected' });
		store.startRequest({ requestId: 'timed-out', command: 'hover', surface: 'fileView' });
		store.timeoutRequest({ requestId: 'timed-out' });

		expect(store.getSnapshot().requestsById['failed']).toMatchObject({
			state: 'failed',
			reason: 'rejected',
		});
		expect(store.getSnapshot().requestsById['timed-out']).toMatchObject({ state: 'timed_out' });

		store.startRequest({ requestId: 'latest', command: 'viewport', surface: 'fileView' });
		store.ackRequest({ requestId: 'latest', acknowledgedAtSequence: 3 });

		const requestsById = store.getSnapshot().requestsById;
		expect(requestsById['failed']).toBeUndefined();
		expect(requestsById['timed-out']).toMatchObject({ state: 'timed_out' });
		expect(requestsById['latest']).toMatchObject({ state: 'acked' });
	});

	test('converted Bridge worker surfaces do not import async cache primitives', () => {
		const root = join(process.cwd(), 'src', 'core', 'comm-worker');
		const forbiddenPatterns = [
			/useQuery\s*\(/,
			/useMutation\s*\(/,
			/QueryClient/,
			/@tanstack\/react-query/,
			/from ['"]swr/,
			/from ['"]@apollo/,
			/ApolloClient/,
			/invalidateQueries/,
			/refetchOnWindowFocus/,
			/refetchOnReconnect/,
			/refetchOnMount/,
		];
		const matches: string[] = [];

		for (const filePath of listTypeScriptFiles(root)) {
			const source = readFileSync(filePath, 'utf8');
			for (const pattern of forbiddenPatterns) {
				if (pattern.test(source)) {
					matches.push(`${filePath}:${pattern.source}`);
				}
			}
		}

		expect(matches).toEqual([]);
	});
});

function listTypeScriptFiles(root: string): readonly string[] {
	const entries = readdirSync(root).map((entry) => join(root, entry));
	const files: string[] = [];
	for (const entry of entries) {
		const stat = statSync(entry);
		if (stat.isDirectory()) {
			files.push(...listTypeScriptFiles(entry));
			continue;
		}
		if (entry.endsWith('.ts') && !entry.endsWith('.unit.test.ts')) {
			files.push(entry);
		}
	}
	return files;
}
