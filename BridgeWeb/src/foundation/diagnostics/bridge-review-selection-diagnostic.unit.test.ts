import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	readBridgeReviewSelectionDiagnostic,
	recordBridgeReviewSelectionDiagnosticStage,
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
});

function ensureTestWindow(): void {
	if (typeof window === 'undefined') {
		vi.stubGlobal('window', {});
	}
}
