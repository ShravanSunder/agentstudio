import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	recordBridgeMainFileQueryDiagnosticPhase,
	recordBridgeCommWorkerFileQueryDiagnosticPhase,
	recordBridgeCommWorkerTaskTelemetry,
} from './bridge-comm-worker-telemetry.js';

describe('Bridge comm worker telemetry', () => {
	test('records only the bounded semantic class for message admission', () => {
		const samples: Parameters<
			NonNullable<
				Parameters<typeof recordBridgeCommWorkerTaskTelemetry>[0]['telemetryClient']
			>['record']
		>[0][] = [];
		recordBridgeCommWorkerTaskTelemetry({
			command: 'annotationCommand',
			durationMilliseconds: 1,
			lane: 'selected',
			semanticClass: 'urgent_action',
			taskKind: 'message_handler',
			telemetryClient: {
				record: (sample): void => {
					samples.push(sample);
				},
			},
		});

		expect(samples).toHaveLength(1);
		expect(samples[0]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.worker.command': 'annotationCommand',
			'agentstudio.bridge.worker.semantic_class': 'urgent_action',
		});
		expect(JSON.stringify(samples[0])).not.toContain('exact durable body');
	});

	test('records path-free File query phase markers with bounded chunk counts', () => {
		const samples: BridgeTelemetrySample[] = [];
		const telemetryClient = {
			record: (sample: BridgeTelemetrySample): void => {
				samples.push(sample);
			},
		};

		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			phase: 'command_received',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			chunkIndex: 2,
			phase: 'chunk_started',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			chunkIndex: 2,
			evaluatedRowCount: 2,
			phase: 'chunk_completed',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			phase: 'projection_published',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			phase: 'outcome_published',
			telemetryClient,
		});

		expect(samples).toHaveLength(5);
		expect(
			samples.map(
				(sample) => sample.stringAttributes['agentstudio.bridge.worker.file_query.phase'],
			),
		).toEqual([
			'command_received',
			'chunk_started',
			'chunk_completed',
			'projection_published',
			'outcome_published',
		]);
		expect(samples[1]?.numericAttributes).toEqual({
			'agentstudio.bridge.worker.file_query.chunk.index': 2,
		});
		expect(samples[2]?.numericAttributes).toEqual({
			'agentstudio.bridge.worker.file_query.chunk.index': 2,
			'agentstudio.bridge.worker.file_query.evaluated_row.count': 2,
		});
		expect(JSON.stringify(samples)).not.toContain('tracked.txt');
	});

	test('records path-free page query diagnostics with bounded counts and visibility', () => {
		const samples: BridgeTelemetrySample[] = [];
		const telemetryClient = {
			record: (sample: BridgeTelemetrySample): void => {
				samples.push(sample);
			},
		};

		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'patch_received',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			displayItemCount: 1,
			pageHidden: true,
			phase: 'snapshot_published',
			telemetryClient,
			treeRowCount: 1,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			displayItemCount: 1,
			pageHidden: true,
			phase: 'render_consumer_committed',
			queryKeyMatchesInput: true,
			telemetryClient,
			treeRowCount: 1,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			mountedPathRowCount: 3,
			pageHidden: true,
			phase: 'tree_dom_commit',
			telemetryClient,
			viewportMeasured: false,
		});

		expect(samples).toHaveLength(4);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.file_query_diagnostic',
			stringAttributes: {
				'agentstudio.bridge.file_query.diagnostic.phase': 'patch_received',
			},
			booleanAttributes: {
				'agentstudio.bridge.file_query.diagnostic.page_hidden': true,
			},
			numericAttributes: {
				'agentstudio.bridge.file_query.diagnostic.batch.index': 1,
				'agentstudio.bridge.file_query.diagnostic.batch.count': 2,
			},
		});
		expect(samples[1]?.numericAttributes).toEqual({
			'agentstudio.bridge.file_query.diagnostic.display_item.count': 1,
			'agentstudio.bridge.file_query.diagnostic.tree_row.count': 1,
		});
		expect(samples[2]).toMatchObject({
			stringAttributes: {
				'agentstudio.bridge.file_query.diagnostic.phase': 'render_consumer_committed',
			},
			booleanAttributes: {
				'agentstudio.bridge.file_query.diagnostic.page_hidden': true,
				'agentstudio.bridge.file_query.diagnostic.query_key_matches_input': true,
			},
		});
		expect(samples[3]).toMatchObject({
			stringAttributes: {
				'agentstudio.bridge.file_query.diagnostic.phase': 'tree_dom_commit',
			},
			numericAttributes: {
				'agentstudio.bridge.file_query.diagnostic.mounted_path_row.count': 3,
			},
			booleanAttributes: {
				'agentstudio.bridge.file_query.diagnostic.page_hidden': true,
				'agentstudio.bridge.file_query.diagnostic.viewport_measured': false,
			},
		});
		expect(JSON.stringify(samples)).not.toContain('tracked.txt');
	});
});
