import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	readBridgeReviewSelectionDiagnostic,
	recordBridgeFileModeSendAttempt,
	recordBridgeFileModeSendSynchronousFailure,
	recordBridgePageReadyState,
	recordBridgeReviewSelectionDiagnosticStage,
	recordBridgeSelectionLifecycleSnapshot,
	resetBridgeReviewSelectionDiagnosticForTesting,
} from './bridge-review-selection-diagnostic.js';

afterEach(() => {
	resetBridgeReviewSelectionDiagnosticForTesting();
	vi.unstubAllGlobals();
});

describe('Bridge Review selection diagnostic', () => {
	test('records only scrub-safe cumulative selection boundary counts', () => {
		// Arrange
		ensureTestWindow();
		resetBridgeReviewSelectionDiagnosticForTesting();

		// Act
		recordBridgeReviewSelectionDiagnosticStage('initial_selection_requested');
		recordBridgeReviewSelectionDiagnosticStage('initial_selection_scheduling_accepted');
		recordBridgeReviewSelectionDiagnosticStage('selection_scheduled');
		recordBridgeReviewSelectionDiagnosticStage('selection_first_frame_reached');
		recordBridgeReviewSelectionDiagnosticStage('selection_second_frame_reached');
		recordBridgeReviewSelectionDiagnosticStage('selection_submitted');
		recordBridgeReviewSelectionDiagnosticStage('selection_dropped');
		recordBridgeReviewSelectionDiagnosticStage('selection_scheduled');

		// Assert
		expect(readBridgeReviewSelectionDiagnostic()).toEqual({
			initialSelectionRequestedCount: 1,
			initialSelectionSchedulingAcceptedCount: 1,
			selectionDroppedCount: 1,
			selectionFirstFrameReachedCount: 1,
			selectionSecondFrameReachedCount: 1,
			selectionScheduledCount: 2,
			selectionSubmittedCount: 1,
		});
	});

	test('does not create a diagnostic outside a browser window', () => {
		// Arrange
		vi.stubGlobal('window', undefined);

		// Act
		recordBridgeReviewSelectionDiagnosticStage('initial_selection_requested');

		// Assert
		expect(readBridgeReviewSelectionDiagnostic()).toBeNull();
	});

	test('retains scrub-safe page readiness, File mode send, and selection lifecycle state', () => {
		// Arrange
		ensureTestWindow();
		resetBridgeReviewSelectionDiagnosticForTesting();
		const lifecycleStates = ['pending', 'acked', 'failed', 'timed_out', 'superseded'] as const;

		// Act / Assert
		recordBridgePageReadyState('awaiting');
		recordBridgePageReadyState('ready');
		recordBridgeFileModeSendAttempt();
		recordBridgeFileModeSendAttempt();
		recordBridgeFileModeSendSynchronousFailure();
		recordBridgeSelectionLifecycleSnapshot({
			requestId: null,
			snapshot: { requestsById: {} },
			surface: 'review',
		});
		recordBridgeSelectionLifecycleSnapshot({
			requestId: null,
			snapshot: { requestsById: {} },
			surface: 'fileView',
		});
		expect(readBridgeReviewSelectionDiagnostic()).toMatchObject({
			fileModeSendAttemptCount: 2,
			fileModeSendSynchronousFailureCount: 1,
			latestFileSelectLifecycleState: 'not_sent',
			latestReviewSelectLifecycleState: 'not_sent',
			pageReadyState: 'ready',
		});
		for (const lifecycleState of lifecycleStates) {
			const privateRequestId = `private-review-select-${lifecycleState}`;
			recordBridgeSelectionLifecycleSnapshot({
				requestId: privateRequestId,
				snapshot: {
					requestsById: {
						[privateRequestId]: {
							command: 'select',
							state: lifecycleState,
							surface: 'review',
						},
					},
				},
				surface: 'review',
			});
			const diagnostic = readBridgeReviewSelectionDiagnostic();
			expect(diagnostic).toMatchObject({ latestReviewSelectLifecycleState: lifecycleState });
			expect(JSON.stringify(diagnostic)).not.toContain(privateRequestId);
		}
		for (const lifecycleState of lifecycleStates) {
			const privateRequestId = `private-file-select-${lifecycleState}`;
			recordBridgeSelectionLifecycleSnapshot({
				requestId: privateRequestId,
				snapshot: {
					requestsById: {
						[privateRequestId]: {
							command: 'select',
							state: lifecycleState,
							surface: 'fileView',
						},
					},
				},
				surface: 'fileView',
			});
			const diagnostic = readBridgeReviewSelectionDiagnostic();
			expect(diagnostic).toMatchObject({ latestFileSelectLifecycleState: lifecycleState });
			expect(JSON.stringify(diagnostic)).not.toContain(privateRequestId);
		}
		recordBridgePageReadyState('failed');
		expect(readBridgeReviewSelectionDiagnostic()).toMatchObject({ pageReadyState: 'failed' });
	});
});

function ensureTestWindow(): void {
	if (typeof window === 'undefined') {
		vi.stubGlobal('window', {});
	}
}
