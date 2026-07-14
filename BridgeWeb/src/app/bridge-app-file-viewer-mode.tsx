import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';

import type { BridgeActiveViewerSource } from '../bridge/bridge-rpc-client.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import {
	BridgeFileViewerApp,
	type BridgeFileViewerAppProps,
} from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeFileViewerDisplaySource } from '../file-viewer/bridge-file-viewer-display-model.js';
import { BridgeFileViewerSurfaceClientProvider } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { startBridgeFrameJankProbe } from '../foundation/diagnostics/bridge-frame-jank-probe.js';
import { startBridgeFrameLivenessProbe } from '../foundation/diagnostics/bridge-frame-liveness-probe.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeFrameJankTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

export interface BridgeFileViewerModeProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fileViewClient: BridgePaneSurfaceClient;
	readonly fileViewerProps?: BridgeFileViewerAppProps;
	readonly isActive: boolean;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly viewerHeaderControls: ReactElement;
}

export function BridgeFileViewerMode(props: BridgeFileViewerModeProps): ReactElement {
	const { onActiveSourceChange } = props;
	const [hasActivatedFileViewerShell, setHasActivatedFileViewerShell] = useState(props.isActive);
	const isActiveRef = useRef(props.isActive);
	isActiveRef.current = props.isActive;
	useEffect((): (() => void) => startBridgeFrameLivenessProbe(), []);
	useEffect(
		(): (() => void) =>
			startBridgeFrameJankProbe({
				onJankSample: (sample): void => {
					recordBridgeFrameJankTelemetrySample({
						...sample,
						telemetryRecorder: props.telemetryRecorder,
						traceContext: null,
						viewer: 'file',
						viewerIsActive: isActiveRef.current,
					});
				},
			}),
		[props.telemetryRecorder],
	);
	useEffect((): void => {
		if (props.isActive) {
			setHasActivatedFileViewerShell(true);
		}
	}, [props.isActive]);
	const reportDisplaySource = useCallback(
		(source: BridgeFileViewerDisplaySource | null): void => {
			onActiveSourceChange(
				source === null
					? null
					: {
							generation: source.generation,
							protocol: 'worktree-file',
							streamId: source.sourceId,
						},
			);
		},
		[onActiveSourceChange],
	);

	if (!props.isActive && !hasActivatedFileViewerShell) {
		return <BridgeFileViewerHeadlessController />;
	}
	return (
		<BridgeFileViewerSurfaceClientProvider surfaceClient={props.fileViewClient}>
			<BridgeFileViewerApp
				{...props.fileViewerProps}
				{...(props.codeViewWorkerFactory === undefined
					? {}
					: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
				{...(props.codeViewWorkerPoolEnabled === undefined
					? {}
					: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
				isActive={props.isActive}
				{...(props.navigationCommand === undefined
					? {}
					: { navigationCommand: props.navigationCommand })}
				onDisplaySourceChange={reportDisplaySource}
				telemetryRecorder={props.telemetryRecorder}
				telemetryTraceContext={null}
				viewerHeaderControls={props.viewerHeaderControls}
			/>
		</BridgeFileViewerSurfaceClientProvider>
	);
}

function BridgeFileViewerHeadlessController(): ReactElement {
	return <div data-testid="bridge-file-viewer-headless-controller" />;
}
