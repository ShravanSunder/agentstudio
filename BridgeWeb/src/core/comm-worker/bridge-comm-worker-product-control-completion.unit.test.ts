import { describe, expect, test } from 'vitest';

import { publishBridgeCommWorkerProductControlCompletion } from './bridge-comm-worker-product-control-completion.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

const publicationA = '00000000-0000-7000-8000-000000000011';
const publicationB = '00000000-0000-7000-8000-000000000012';

describe('Bridge comm worker product control completion', () => {
	test('replaces install admission ready with its correlated admission event', () => {
		const postedMessages: BridgeWorkerServerToMainMessage[] = [];
		const readyMessage = makeReadyMessage('review-install-admit-1');

		publishBridgeCommWorkerProductControlCompletion({
			actionResult: { status: 'admitted' },
			command: {
				method: 'review.publication.install.admit',
				params: {
					candidatePublicationId: publicationB,
					expectedDisplayedPublicationId: publicationA,
				},
			},
			messages: [readyMessage],
			publish: (message): void => {
				postedMessages.push(message);
			},
			requestId: 'review-install-admit-1',
		});

		expect(postedMessages).toEqual([
			expect.objectContaining({
				candidatePublicationId: publicationB,
				kind: 'reviewPublicationInstallAdmission',
				requestId: 'review-install-admit-1',
				status: 'admitted',
			}),
		]);
	});

	test('keeps generic ready completion after the installed applied call', () => {
		const postedMessages: BridgeWorkerServerToMainMessage[] = [];
		const readyMessage = makeReadyMessage('review-installed-1');

		publishBridgeCommWorkerProductControlCompletion({
			actionResult: undefined,
			command: {
				method: 'review.publication.applied',
				params: { publicationId: publicationB },
			},
			messages: [readyMessage],
			publish: (message): void => {
				postedMessages.push(message);
			},
			requestId: 'review-installed-1',
		});

		expect(postedMessages).toEqual([readyMessage]);
	});
});

function makeReadyMessage(requestId: string): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'health',
		message: 'Bridge comm worker ready.',
		requestId,
		status: 'ready',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}
