import { describe, expect, test } from 'vitest';

import {
	bridgeProductFrameAcknowledgementRejectedStatusSchema,
	bridgeProductFrameAcknowledgementRequestSchema,
} from './bridge-product-frame-acknowledgement-contracts.js';

describe('Bridge product frame acknowledgement contracts', () => {
	test('accepts strict metadata and content observation requests', () => {
		const metadataRequest = {
			kind: 'stream.frameObserved',
			metadataStreamId: 'metadata-stream-1',
			paneSessionId: 'pane-session-1',
			streamSequence: 7,
			streamKind: 'metadata',
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;
		const contentRequest = {
			contentRequestId: 'content-request-1',
			contentSequence: 0,
			kind: 'stream.frameObserved',
			leaseId: 'lease-1',
			paneSessionId: 'pane-session-1',
			streamKind: 'content',
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;

		expect(bridgeProductFrameAcknowledgementRequestSchema.parse(metadataRequest)).toEqual(
			metadataRequest,
		);
		expect(bridgeProductFrameAcknowledgementRequestSchema.parse(contentRequest)).toEqual(
			contentRequest,
		);
	});

	test('rejects cross-wired, unknown, and structurally invalid observation requests', () => {
		const metadataRequest = {
			kind: 'stream.frameObserved',
			metadataStreamId: 'metadata-stream-1',
			paneSessionId: 'pane-session-1',
			streamKind: 'metadata',
			streamSequence: 7,
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;
		const contentRequest = {
			contentRequestId: 'content-request-1',
			contentSequence: 0,
			kind: 'stream.frameObserved',
			leaseId: 'lease-1',
			paneSessionId: 'pane-session-1',
			streamKind: 'content',
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;

		for (const invalidRequest of [
			{ ...metadataRequest, metadataStreamId: '' },
			{ ...metadataRequest, paneSessionId: 'pane/invalid' },
			{ ...metadataRequest, workerInstanceId: 'worker/invalid' },
			{ ...metadataRequest, streamSequence: -1 },
			{ ...metadataRequest, unknown: true },
			{
				...metadataRequest,
				contentRequestId: 'content-request-1',
				contentSequence: 0,
				leaseId: 'lease-1',
			},
			{ ...contentRequest, contentRequestId: '' },
			{ ...contentRequest, leaseId: 'lease/invalid' },
			{ ...contentRequest, paneSessionId: 'pane/invalid' },
			{ ...contentRequest, workerInstanceId: 'worker/invalid' },
			{ ...contentRequest, contentSequence: -1 },
			{ ...contentRequest, unknown: true },
			{
				...contentRequest,
				metadataStreamId: 'metadata-stream-1',
				streamSequence: 0,
			},
			{ ...contentRequest, kind: 'stream.frameIgnored' },
			{ ...contentRequest, streamKind: 'telemetry' },
			{ ...contentRequest, wireVersion: 1 },
		]) {
			expect(bridgeProductFrameAcknowledgementRequestSchema.safeParse(invalidRequest).success).toBe(
				false,
			);
		}
	});

	test('defines closed rejection statuses', () => {
		for (const rejectionStatus of [400, 401, 403, 404, 405, 409, 413, 415]) {
			expect(bridgeProductFrameAcknowledgementRejectedStatusSchema.parse(rejectionStatus)).toBe(
				rejectionStatus,
			);
		}
		for (const unsupportedStatus of [200, 201, 204, 418, 500]) {
			expect(
				bridgeProductFrameAcknowledgementRejectedStatusSchema.safeParse(unsupportedStatus).success,
			).toBe(false);
		}
	});
});
