import { describe, expect, test } from 'vitest';

import { bridgeWorkerMainToServerMessageSchema } from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeFileViewerHeaderStatusText } from './bridge-file-viewer-shell.js';

describe('Bridge File viewer refresh retry', () => {
	test('shows retained unavailable status from a typed File refresh failure', () => {
		const status = bridgeFileViewerHeaderStatusText(true, {
			fileRefreshFailure: { failureKind: 'fileSourceUnavailable', retryable: true },
			message: 'Files unavailable',
		});

		expect(status).toBe('Files unavailable');
	});

	test('accepts the exact File refresh retry worker command', () => {
		expect(
			bridgeWorkerMainToServerMessageSchema.parse({
				command: 'fileRefreshRetry',
				direction: 'mainToServerWorker',
				epoch: 8,
				issuedAtMilliseconds: 1_775_000_000_000,
				kind: 'command',
				requestId: 'file-refresh-retry-1',
				transferDescriptors: [],
				wireVersion: 1,
			}),
		).toMatchObject({ command: 'fileRefreshRetry', epoch: 8 });
	});
});
