import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeReviewRefreshLifecycleTelemetry } from './bridge-review-refresh-lifecycle-telemetry.js';

describe('Bridge Review refresh lifecycle telemetry', () => {
	test('records controlled candidate and cleanup facts without source identity', () => {
		// Arrange
		const record = vi.fn<BridgeTelemetryRecorder['record']>();
		const recorder = {
			flush: (): boolean => true,
			isEnabled: (): boolean => true,
			measure: <TResult>(props: { readonly operation: () => TResult }): TResult =>
				props.operation(),
			record,
		} satisfies BridgeTelemetryRecorder;

		// Act
		recordBridgeReviewRefreshLifecycleTelemetry({
			event: {
				affectedStableFileCount: 3,
				generation: 7,
				phase: 'installTerminal',
				presentationClass: { kind: 'promoted', reason: 'files' },
				result: 'success',
				resultReason: 'none',
				trigger: 'applyNow',
			},
			recorder,
		});
		recordBridgeReviewRefreshLifecycleTelemetry({
			event: {
				activeBankCount: 0,
				candidateBankCount: 0,
				phase: 'cleanup',
				reason: 'workerReplacement',
			},
			recorder,
		});

		// Assert
		expect(record).toHaveBeenNthCalledWith(
			1,
			expect.objectContaining({
				name: 'performance.bridge.web.review_refresh_lifecycle',
				numericAttributes: {
					'agentstudio.bridge.review.generation': 7,
					'agentstudio.bridge.review.refresh.affected_stable_file.count': 3,
				},
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'review_refresh_install_terminal',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.result_reason': 'none',
					'agentstudio.bridge.review.refresh.install_trigger': 'apply_now',
					'agentstudio.bridge.review.refresh.presentation_class': 'promoted',
					'agentstudio.bridge.review.refresh.promotion_reason': 'files',
				}),
			}),
		);
		expect(record).toHaveBeenNthCalledWith(
			2,
			expect.objectContaining({
				numericAttributes: {
					'agentstudio.bridge.review.refresh.active_bank.count': 0,
					'agentstudio.bridge.review.refresh.candidate_bank.count': 0,
				},
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'review_refresh_cleanup_terminal',
					'agentstudio.bridge.result_reason': 'worker_replacement',
				}),
			}),
		);
		expect(JSON.stringify(record.mock.calls)).not.toMatch(
			/publication|package|sourceIdentity|stableFileIdentities/u,
		);
	});
});
