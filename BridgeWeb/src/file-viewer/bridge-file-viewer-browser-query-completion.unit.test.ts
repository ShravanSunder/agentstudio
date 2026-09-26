import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerFileQueryUpdateCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeWorkerFileQueryOutcomeEvent } from '../core/comm-worker/bridge-worker-contracts.js';
import { createBridgeFileViewerBrowserQueryCompletion } from './bridge-file-viewer-browser-test-comm-worker.js';

describe('Bridge File Viewer browser query completion', () => {
	test('keeps an exact projected request pending until its transaction is published', async () => {
		// Arrange
		const completion = createBridgeFileViewerBrowserQueryCompletion();
		const pending = completion.prepareNextQueryCompletion();
		completion.observeCommand(fileQueryCommand('query-projected'));
		completion.observeOutcome(
			fileQueryOutcome('query-projected', {
				kind: 'projected',
				transactionId: 'transaction-projected',
			}),
		);
		let didResolve = false;
		void pending.promise.then((): void => {
			didResolve = true;
		});

		// Act / Assert
		await Promise.resolve();
		expect(didResolve).toBe(false);
		completion.observePublishedTransaction('other-transaction');
		await Promise.resolve();
		expect(didResolve).toBe(false);
		completion.observePublishedTransaction('transaction-projected');
		await expect(pending.promise).resolves.toBeUndefined();
	});

	test('settles when the display transaction is published before its query outcome arrives', async () => {
		// Arrange
		const completion = createBridgeFileViewerBrowserQueryCompletion();
		const pending = completion.prepareNextQueryCompletion();
		completion.observeCommand(fileQueryCommand('query-published-first'));
		let didResolve = false;
		void pending.promise.then(
			(): void => {
				didResolve = true;
			},
			(): void => {},
		);

		// Act: the main-thread display snapshot can publish from the final batch
		// before the following fileQueryOutcome supplies its transaction ID.
		completion.observePublishedTransaction('unrelated-transaction');
		await Promise.resolve();
		expect(didResolve).toBe(false);
		completion.observePublishedTransaction('transaction-published-first');
		await Promise.resolve();
		expect(didResolve).toBe(false);
		completion.observeOutcome(
			fileQueryOutcome('query-published-first', {
				kind: 'projected',
				transactionId: 'transaction-published-first',
			}),
		);
		await Promise.resolve();
		const didResolveAfterMatchingOutcome = didResolve;
		if (!didResolveAfterMatchingOutcome) pending.cancel();

		// Assert
		expect(didResolveAfterMatchingOutcome).toBe(true);
	});

	test('settles unchanged and rejects superseded exact requests', async () => {
		// Arrange / Act: unchanged is terminal without a display transaction.
		const completion = createBridgeFileViewerBrowserQueryCompletion();
		const unchanged = completion.prepareNextQueryCompletion();
		completion.observeCommand(fileQueryCommand('query-unchanged'));
		completion.observeOutcome(fileQueryOutcome('query-unchanged', { kind: 'unchanged' }));

		// Assert
		await expect(unchanged.promise).resolves.toBeUndefined();

		// Arrange / Act: supersession rejects only its exact request.
		const superseded = completion.prepareNextQueryCompletion();
		completion.observeCommand(fileQueryCommand('query-superseded'));
		completion.observeOutcome(fileQueryOutcome('query-superseded', { kind: 'superseded' }));

		// Assert
		await expect(superseded.promise).rejects.toThrow(
			'File query request query-superseded was superseded.',
		);
	});

	test('rejects both observed and not-yet-observed waits on disposal', async () => {
		// Arrange
		const completion = createBridgeFileViewerBrowserQueryCompletion();
		const observed = completion.prepareNextQueryCompletion();
		completion.observeCommand(fileQueryCommand('query-disposed'));
		const notYetObserved = completion.prepareNextQueryCompletion();

		// Act
		completion.dispose();

		// Assert
		await expect(observed.promise).rejects.toThrow('File query completion disposed.');
		await expect(notYetObserved.promise).rejects.toThrow('File query completion disposed.');
	});
});

function fileQueryCommand(
	requestId: string,
): ReturnType<typeof encodeBridgeWorkerFileQueryUpdateCommand> {
	return encodeBridgeWorkerFileQueryUpdateCommand({
		epoch: 1,
		filterMode: 'source',
		requestId,
		searchMode: 'text',
		searchText: 'query',
	});
}

function fileQueryOutcome(
	requestId: string,
	outcome: BridgeWorkerFileQueryOutcomeEvent['outcome'],
): BridgeWorkerFileQueryOutcomeEvent {
	return {
		direction: 'serverWorkerToMain',
		kind: 'fileQueryOutcome',
		outcome,
		requestId,
		transferDescriptors: [],
		wireVersion: 1,
	};
}
