import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import {
	createBridgePaneRuntime,
	type BridgePaneRuntime,
} from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeFileCollectionSearchWireCriteria } from '../core/comm-worker/bridge-worker-file-collection-search-contracts.js';
import { createBridgeFileViewerCollectionSearchRequests } from './bridge-file-viewer-collection-search-requests.js';

const searchCriteria: BridgeFileCollectionSearchWireCriteria = {
	limit: 20,
	scope: { kind: 'all' },
	searchMode: 'text',
	searchText: 'plan',
};

interface SearchTestPane {
	readonly dispatchedSearches: BridgeWorkerMainToServerMessage[];
	readonly publish: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	readonly runtime: BridgePaneRuntime;
	answerDuringDispatch: ((message: BridgeWorkerMainToServerMessage) => void) | null;
}

let pane: SearchTestPane;

beforeEach((): void => {
	vi.stubGlobal('cancelAnimationFrame', vi.fn());
	vi.stubGlobal(
		'requestAnimationFrame',
		vi.fn((): number => 1),
	);
	pane = makeSearchTestPane();
});

afterEach((): void => {
	pane.runtime.dispose();
	vi.unstubAllGlobals();
});

describe('File viewer collection search requests', () => {
	test('settles with the worker answer for its request id', async () => {
		// Arrange
		const requests = createBridgeFileViewerCollectionSearchRequests({
			client: pane.runtime.surfaceClient('fileView'),
		});
		const answer = requests.search(searchCriteria);
		const requestId = onlyDispatchedRequestId();

		// Act
		pane.publish([searchAnswer(requestId)]);

		// Assert
		await expect(answer).resolves.toEqual({ kind: 'noSource' });
		requests.dispose();
	});

	test('settles an answer the worker delivers while the command is still dispatching', async () => {
		// Arrange
		pane.answerDuringDispatch = (message): void => {
			pane.publish([searchAnswer(message.requestId)]);
		};
		const requests = createBridgeFileViewerCollectionSearchRequests({
			client: pane.runtime.surfaceClient('fileView'),
		});

		// Act
		const answer = requests.search(searchCriteria);

		// Assert
		await expect(answer).resolves.toEqual({ kind: 'noSource' });
		requests.dispose();
	});

	test('a refused command is unavailable, not pending', async () => {
		// Arrange
		const requests = createBridgeFileViewerCollectionSearchRequests({
			client: pane.runtime.surfaceClient('fileView'),
		});
		const answer = requests.search(searchCriteria);

		// Act
		pane.publish([
			{
				direction: 'serverWorkerToMain',
				kind: 'health',
				message: 'Bridge comm worker rejected the search.',
				requestId: onlyDispatchedRequestId(),
				status: 'degraded',
				transferDescriptors: [],
				wireVersion: 1,
			},
		]);

		// Assert
		await expect(answer).resolves.toEqual({ kind: 'unavailable', reason: 'refused' });
		requests.dispose();
	});

	test('worker replacement and unmount settle every open search as unavailable', async () => {
		// Arrange
		const client = pane.runtime.surfaceClient('fileView');
		const requests = createBridgeFileViewerCollectionSearchRequests({ client });
		const beforeReplacement = requests.search(searchCriteria);

		// Act
		client.requestWorkerReplacement();
		const beforeUnmount = requests.search(searchCriteria);
		requests.dispose();

		// Assert
		await expect(beforeReplacement).resolves.toEqual({
			kind: 'unavailable',
			reason: 'refused',
		});
		await expect(beforeUnmount).resolves.toEqual({ kind: 'unavailable', reason: 'disposed' });
		await expect(requests.search(searchCriteria)).resolves.toEqual({
			kind: 'unavailable',
			reason: 'disposed',
		});
	});
});

function makeSearchTestPane(): SearchTestPane {
	let publishWorkerMessages: (
		messages: readonly BridgeWorkerServerToMainMessage[],
	) => void = (): void => {};
	const testPane: SearchTestPane = {
		answerDuringDispatch: null,
		dispatchedSearches: [],
		publish: (messages): void => {
			publishWorkerMessages(messages);
		},
		runtime: createBridgePaneRuntime({
			recordDiagnosticSnapshot: (): void => {},
			sessionFactory: () => ({
				createDispatcher: (dispatcherProps) => {
					publishWorkerMessages = dispatcherProps.publishWorkerMessages;
					return {
						dispatch: (message): void => {
							if (message.command !== 'fileCollectionSearch') return;
							testPane.dispatchedSearches.push(message);
							testPane.answerDuringDispatch?.(message);
						},
						dispose: (): void => {},
					};
				},
				dispose: (): void => {},
				installNativeBootstrap: (): void => {},
				requestWorkerReplacement: (): void => {},
			}),
		}),
	};
	return testPane;
}

function onlyDispatchedRequestId(): string {
	const [search] = pane.dispatchedSearches;
	if (search === undefined || pane.dispatchedSearches.length !== 1) {
		throw new Error('Expected exactly one dispatched File collection search.');
	}
	return search.requestId;
}

function searchAnswer(requestId: string): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'fileCollectionSearch',
		outcome: { kind: 'noSource' },
		requestId,
		transferDescriptors: [],
		wireVersion: 1,
	};
}
