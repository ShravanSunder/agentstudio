import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { buildReviewSnapshotFrame } from '../features/review/protocol/review-snapshot-frame-builder.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { BridgeApp } from './bridge-app.js';

describe('BridgeApp native review intake Browser Mode', () => {
	afterEach(() => {
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		vi.restoreAllMocks();
	});

	test('marks review intake ready after the command nonce arrives', async () => {
		const commands: unknown[] = [];
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		document.addEventListener('__bridge_command', handleBridgeCommand);

		await render(<BridgeApp />);
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);
		await Promise.resolve();
		expect(commands).toEqual([]);

		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		await waitForBridgeViewerAnimationFrame();

		expect(commands).toEqual([
			{
				__nonce: 'bridge-nonce',
				jsonrpc: '2.0',
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					streamId: 'review:bridge-app-test-pane',
				},
			},
		]);
		document.removeEventListener('__bridge_command', handleBridgeCommand);
	});

	test('renders package failure when native review intake publishes an error frame', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		await render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId: 'review:bridge-app-test-pane',
			generation: 1,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId: 'review:bridge-app-test-pane',
				generation: 1,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'query-startup',
				packageId: 'package-startup',
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'error',
			streamId: 'review:bridge-app-test-pane',
			generation: 1,
			sequence: 1,
			message: 'loadFailed',
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-package-failed-shell"]'),
		);
		expect(document.body.textContent).toContain('Review package unavailable');
		expect(document.body.textContent).toContain('loadFailed');
		expect(document.body.textContent).not.toContain('Waiting for review package');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
	});

	test('renders the review shell when native review intake publishes a streamed package descriptor', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
		});
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl = String(resource);
			if (resourceUrl !== snapshotFrame.package.rootDescriptor.descriptor.resourceUrl) {
				return chunkedTextResponse(['struct FixtureView {}\n']);
			}
			return chunkedTextResponse([
				JSON.stringify(reviewPackage).slice(0, 64),
				JSON.stringify(reviewPackage).slice(64),
			]);
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		await render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: reviewPackage.query.queryId,
				packageId: reviewPackage.packageId,
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: snapshotFrame.sequence,
			payload: snapshotFrame,
		});

		await expect
			.poll(() => document.querySelector('[data-testid="review-viewer-shell"]') !== null)
			.toBe(true);
		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(document.body.textContent).not.toContain('Waiting for review package');
	});

	test('emits accepted review intake telemetry when web telemetry is enabled', async () => {
		const commands: unknown[] = [];
		const handleBridgeCommand = (event: Event): void => {
			commands.push('detail' in event ? event.detail : null);
		};
		document.addEventListener('__bridge_command', handleBridgeCommand);
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		await render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame(
			{
				kind: 'reset',
				streamId: 'review:bridge-app-test-pane',
				generation: 1,
				sequence: 0,
				payload: {
					kind: 'reset',
					streamId: 'review:bridge-app-test-pane',
					generation: 1,
					sequence: 0,
					frameKind: 'review.reset',
					reason: 'authorityChanged',
					sourceIdentity: 'query-startup',
					packageId: 'package-startup',
				},
			},
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					maxSamplesPerBatch: 16,
					maxEncodedBatchBytes: 65_536,
					minimumFlushIntervalMilliseconds: 0,
					rpcMethodName: 'system.bridgeTelemetry',
					scenario: 'package_apply_content_fetch_v1',
				},
			},
		);

		const telemetryCommand = commands.find(isBridgeTelemetryCommand);
		expect(telemetryCommand?.params.samples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.intake_frame',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.intake.frame_kind': 'review.reset',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.result_reason': 'none',
					'agentstudio.bridge.transport': 'intake',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.intake.generation': 1,
					'agentstudio.bridge.intake.sequence': 0,
				}),
			}),
		);
		document.removeEventListener('__bridge_command', handleBridgeCommand);
	});
});

interface DispatchHostAdmittedReviewIntakeFrameOptions {
	readonly telemetryConfig?: unknown;
}

async function dispatchHostAdmittedReviewIntakeFrame(
	frame: BridgeIntakeFrame,
	options: DispatchHostAdmittedReviewIntakeFrameOptions = {},
): Promise<void> {
	document.dispatchEvent(
		new CustomEvent('__bridge_handshake', {
			detail: { pushNonce: 'push-nonce', telemetryConfig: options.telemetryConfig },
		}),
	);
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(frame),
				nonce: 'push-nonce',
			},
		}),
	);
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
}

function isBridgeTelemetryCommand(value: unknown): value is {
	readonly method: 'system.bridgeTelemetry';
	readonly params: {
		readonly samples: readonly {
			readonly name: string;
			readonly numericAttributes: Readonly<Record<string, number>>;
			readonly stringAttributes: Readonly<Record<string, string>>;
		}[];
	};
} {
	return (
		typeof value === 'object' &&
		value !== null &&
		'method' in value &&
		value.method === 'system.bridgeTelemetry' &&
		'params' in value &&
		typeof value.params === 'object' &&
		value.params !== null &&
		'samples' in value.params &&
		Array.isArray(value.params.samples)
	);
}

function chunkedTextResponse(chunks: readonly string[]): Response {
	return new Response(
		new ReadableStream<Uint8Array>({
			start(controller): void {
				const encoder = new TextEncoder();
				for (const chunk of chunks) {
					controller.enqueue(encoder.encode(chunk));
				}
				controller.close();
			},
		}),
		{
			headers: {
				'content-type': 'text/plain; charset=utf-8',
			},
		},
	);
}
