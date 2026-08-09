import { describe, expect, test } from 'vitest';

import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';

describe('Bridge product session Review comparison contract', () => {
	test('accepts the exact comparison-aware pane presentation and rejects the activity-only shape', () => {
		const frame = {
			kind: 'pane.presentation',
			metadataStreamId: 'metadata-stream-comparison-presentation',
			nativeActivity: 'foreground',
			paneSessionId: 'pane-session-1',
			presentationRevision: 5,
			refreshingLanes: ['review'],
			reviewComparison: {
				activeTarget: { kind: 'branch', name: 'feature/review' },
				attempt: { reviewGeneration: 8, status: 'pending' },
				displayedSnapshot: {
					packageId: 'package-predecessor',
					reviewGeneration: 7,
					revision: 3,
					status: 'stale',
				},
				targetCatalog: {
					branches: [
						{ branchName: 'feature/review', kind: 'local', oid: 'a'.repeat(40) },
						{
							branchName: 'main',
							kind: 'remoteTracking',
							oid: 'b'.repeat(40),
							remoteName: 'origin',
						},
					],
					defaultTarget: {
						branchName: 'main',
						kind: 'remoteTracking',
						oid: 'b'.repeat(40),
						remoteName: 'origin',
					},
				},
			},
			streamSequence: 5,
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;

		expect(bridgeProductMetadataFrameSchema.parse(frame)).toEqual(frame);
		expect(
			bridgeProductMetadataFrameSchema.safeParse({
				...frame,
				presentationRevision: undefined,
			}).success,
		).toBe(false);
		expect(
			bridgeProductMetadataFrameSchema.safeParse({ ...frame, reviewComparison: undefined }).success,
		).toBe(false);
	});

	test('rejects ambiguous or incomplete target catalog entries', () => {
		const comparisonPresentation = {
			activeTarget: null,
			attempt: { status: 'selectionRequired' },
			displayedSnapshot: { status: 'none' },
			targetCatalog: {
				branches: [{ branchName: 'main', kind: 'remoteTracking', oid: 'a'.repeat(40) }],
				defaultTarget: null,
			},
		};
		const frame = {
			kind: 'pane.presentation',
			metadataStreamId: 'metadata-stream-invalid-target-catalog',
			nativeActivity: 'foreground',
			paneSessionId: 'pane-session-1',
			presentationRevision: 5,
			refreshingLanes: ['review'],
			reviewComparison: comparisonPresentation,
			streamSequence: 5,
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		} as const;

		expect(bridgeProductMetadataFrameSchema.safeParse(frame).success).toBe(false);
	});
});
