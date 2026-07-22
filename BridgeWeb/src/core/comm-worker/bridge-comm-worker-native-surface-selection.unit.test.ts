import { describe, expect, test } from 'vitest';

import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerActiveViewerModeUpdateCommandSchema,
	bridgeWorkerNativeSurfaceSelectionRequestSchema,
	bridgeWorkerServerToMainMessageSchema,
} from './bridge-worker-contracts.js';

const nativeSurfaceSelectionMetadataFrame = {
	kind: 'pane.surfaceSelectionRequested',
	metadataStreamId: 'metadata-stream-1',
	paneSessionId: 'pane-session-1',
	requestId: 'native-selection-request-1',
	selectionRevision: 1,
	streamSequence: 2,
	surface: 'review',
	wireVersion: 2,
	workerInstanceId: 'worker-instance-1',
} as const;

describe('native surface-selection transport contracts', () => {
	test('decodes the closed pane metadata request with full stream identity', () => {
		// Arrange / Act
		const frame = bridgeProductMetadataFrameSchema.parse(nativeSurfaceSelectionMetadataFrame);

		// Assert
		expect(frame).toEqual(nativeSurfaceSelectionMetadataFrame);
	});

	test.each([
		['zero selection revision', { selectionRevision: 0 }],
		['empty request id', { requestId: '' }],
		['unknown surface', { surface: 'terminal' }],
		['missing pane session identity', { paneSessionId: undefined }],
		['missing worker identity', { workerInstanceId: undefined }],
		['missing metadata stream identity', { metadataStreamId: undefined }],
		['unknown key', { unexpected: true }],
	])('rejects %s on the pane metadata request', (_name, replacement) => {
		// Arrange
		const candidate = { ...nativeSurfaceSelectionMetadataFrame, ...replacement };

		// Act / Assert
		expect(bridgeProductMetadataFrameSchema.safeParse(candidate).success).toBe(false);
	});

	test('publishes one typed worker-to-main request without losing native correlation', async () => {
		// Arrange
		const frame = bridgeProductMetadataFrameSchema.parse(nativeSurfaceSelectionMetadataFrame);
		const { bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame } =
			await import('./bridge-comm-worker-native-surface-selection.js');

		// Act
		const message = bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame(frame);

		// Assert
		expect(bridgeWorkerNativeSurfaceSelectionRequestSchema.parse(message)).toEqual({
			direction: 'serverWorkerToMain',
			kind: 'nativeSurfaceSelectionRequest',
			metadataStreamId: 'metadata-stream-1',
			nativeSelectionRequestId: 'native-selection-request-1',
			paneSessionId: 'pane-session-1',
			selectionRevision: 1,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			workerInstanceId: 'worker-instance-1',
		});
		expect(bridgeWorkerServerToMainMessageSchema.parse(message)).toEqual(message);
	});

	test.each(['file', 'review'] as const)(
		'activeViewerModeUpdate returns the exact native request id for %s',
		(mode) => {
			// Arrange
			const command = {
				command: 'activeViewerModeUpdate',
				direction: 'mainToServerWorker',
				epoch: 4,
				kind: 'command',
				requestId: `active-viewer-${mode}`,
				transferDescriptors: [],
				update: {
					activeSource: null,
					mode,
					nativeSelectionRequestId: 'native-selection-request-1',
					sequence: 8,
					sessionId: 'viewer-session-1',
				},
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			};

			// Act / Assert
			expect(bridgeWorkerActiveViewerModeUpdateCommandSchema.parse(command)).toEqual(command);
		},
	);

	test('activeViewerModeUpdate requires an explicit nullable native request id', () => {
		// Arrange
		const update = {
			activeSource: null,
			mode: 'file',
			nativeSelectionRequestId: null,
			sequence: 9,
			sessionId: 'viewer-session-1',
		} as const;
		const command = {
			command: 'activeViewerModeUpdate',
			direction: 'mainToServerWorker',
			epoch: 4,
			kind: 'command',
			requestId: 'active-viewer-file',
			transferDescriptors: [],
			update,
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		};

		// Act / Assert
		expect(bridgeWorkerActiveViewerModeUpdateCommandSchema.parse(command)).toEqual(command);
		expect(
			bridgeWorkerActiveViewerModeUpdateCommandSchema.safeParse({
				...command,
				update: { activeSource: null, mode: 'file', sequence: 9, sessionId: 'viewer-session-1' },
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerActiveViewerModeUpdateCommandSchema.safeParse({
				...command,
				update: { ...update, nativeSelectionRequestId: '' },
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerActiveViewerModeUpdateCommandSchema.safeParse({
				...command,
				update: { ...update, unexpected: true },
			}).success,
		).toBe(false);
	});
});
