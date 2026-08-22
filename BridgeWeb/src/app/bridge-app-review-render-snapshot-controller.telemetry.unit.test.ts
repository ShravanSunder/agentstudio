import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import { applyBridgeWorkerMessagesToMainRenderSnapshotStore } from './bridge-app-review-render-snapshot-controller.js';

const TEST_REVIEW_PUBLICATION_IDENTITY = {
	packageId: 'test-review-package',
	publicationId: '00000000-0000-7000-8000-000000000001',
	reviewGeneration: 1,
	revision: 1,
	sourceIdentity: 'test-review-source',
} as const;

describe('Bridge app Review render snapshot telemetry', () => {
	test('records settled panel chrome after applying it to the main render store', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = { submit: (): void => {} };

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'reviewRenderPatch',
					reviewPublicationIdentity: TEST_REVIEW_PUBLICATION_IDENTITY,
					publicationSequence: 17,
					surface: 'review',
					workerDerivationEpoch: 4,
					patches: [
						{
							slice: 'panelChrome',
							operation: 'upsert',
							payload: {
								reviewComparison: {
									activeTarget: { basis: 'commonCommit', kind: 'branch', name: 'base' },
									attempt: { reviewGeneration: 6, status: 'settled' },
									displayedSnapshot: {
										packageId: 'package-6',
										reviewGeneration: 6,
										revision: 3,
										status: 'current',
									},
									repositoryDefaultTarget: null,
								},
							},
						},
					],
				},
			],
			pierreCourier,
			renderFulfillmentCoordinator: createBridgeMainRenderFulfillmentCoordinator({
				cancelAnimationFrame: (): void => {},
				nowMilliseconds: (): number => 0,
				requestAnimationFrame: (): number => 0,
				sendDisposition: (): void => {},
			}),
			renderSnapshotStore,
			telemetryRecorder: {
				isEnabled: (): boolean => true,
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
				measure: (props) => props.operation(),
				flush: (): boolean => true,
			},
		});

		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.pane_presentation',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.comparison.attempt.status': 'settled',
					'agentstudio.bridge.phase': 'panel_chrome_applied',
					'agentstudio.bridge.result': 'success',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.presentation.publication_sequence': 17,
					'agentstudio.bridge.review.generation': 6,
					'agentstudio.bridge.worker.derivation_epoch': 4,
				}),
			}),
		);
	});
});
