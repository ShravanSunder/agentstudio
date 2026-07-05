import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import { createBridgeWorkerRpcLifecycleStore } from './bridge-worker-rpc-lifecycle-store.js';

describe('Bridge worker RPC lifecycle store', () => {
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
