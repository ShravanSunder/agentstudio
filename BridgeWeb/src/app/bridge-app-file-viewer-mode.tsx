import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	BridgeFileViewerApp,
	type BridgeFileViewerAppProps,
} from '../file-viewer/bridge-file-viewer-app.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { useBridgeFileViewerFrameControllerProps } from './bridge-file-viewer-frame-controller.js';
import { bridgeReviewNavigationCommandForWorktreeDescriptor } from './bridge-review-navigation.js';
import type {
	BridgeViewerNavigationCommand,
	BridgeViewerSource,
} from './bridge-viewer-navigation-models.js';

export interface BridgeFileViewerModeProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fileViewerProps?: BridgeFileViewerAppProps;
	readonly isActive: boolean;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onActivateNavigationCommand: (navigationCommand: BridgeViewerNavigationCommand) => void;
	readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
	readonly reviewNavigationSource?: Extract<
		BridgeViewerSource,
		{ readonly sourceKind: 'reviewComparison' }
	>;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly viewerHeaderControls: ReactElement;
}

export function BridgeFileViewerMode(props: BridgeFileViewerModeProps): ReactElement {
	const existingOpenReviewComparison = props.fileViewerProps?.onOpenReviewComparison;
	const onActivateNavigationCommand = props.onActivateNavigationCommand;
	const reviewNavigationSource = props.reviewNavigationSource;
	const [hasActivatedFileViewerShell, setHasActivatedFileViewerShell] = useState(props.isActive);
	// The WebView never remounts on a mode switch, so re-running the file
	// surface open announce requires an explicit signal. Bump it when the file
	// shell transitions back to active AND the surface has not yet resolved a
	// healthy open — a live healthy stream is reused (no re-open spam), while a
	// wedged/hung surface re-opens exactly like a fresh mount to recover.
	const [fileSurfaceReopenSignal, setFileSurfaceReopenSignal] = useState(0);
	const wasFileViewerActiveRef = useRef(props.isActive);
	const fileSurfaceOpenResolvedRef = useRef(false);
	const handleFileSurfaceOpenResolved = useCallback((): void => {
		fileSurfaceOpenResolvedRef.current = true;
	}, []);
	const hasFileViewerFrameSource = props.fileViewerProps !== undefined;
	const hasActivatedFileViewerController =
		props.isActive || hasActivatedFileViewerShell || hasFileViewerFrameSource;
	const controlledFileViewerProps = useBridgeFileViewerFrameControllerProps({
		enabled: hasActivatedFileViewerController,
		fileViewerProps: props.fileViewerProps,
		onSurfaceOpenResolved: handleFileSurfaceOpenResolved,
		reopenSignal: fileSurfaceReopenSignal,
		waitForBridgeReady: props.registerBridgeReadyCallback,
	});
	useEffect((): void => {
		if (props.isActive) {
			setHasActivatedFileViewerShell(true);
			if (!wasFileViewerActiveRef.current && !fileSurfaceOpenResolvedRef.current) {
				// The prior open never resolved (wedged/hung): re-issue it. If the
				// re-open also fails to resolve, the ref stays false and the next
				// activation retries — recovery. A resolved (healthy) stream is
				// reused instead, so healthy toggles never re-open.
				setFileSurfaceReopenSignal((signal) => signal + 1);
			}
		}
		wasFileViewerActiveRef.current = props.isActive;
	}, [props.isActive]);
	const openReviewComparison = useCallback(
		(descriptor: WorktreeFileDescriptor): void => {
			existingOpenReviewComparison?.(descriptor);
			onActivateNavigationCommand(
				bridgeReviewNavigationCommandForWorktreeDescriptor({
					descriptor,
					...(reviewNavigationSource === undefined ? {} : { reviewSource: reviewNavigationSource }),
				}),
			);
		},
		[existingOpenReviewComparison, onActivateNavigationCommand, reviewNavigationSource],
	);
	if (!props.isActive && !hasActivatedFileViewerShell) {
		return <BridgeFileViewerHeadlessController />;
	}
	return (
		<BridgeFileViewerApp
			{...(props.codeViewWorkerFactory === undefined
				? {}
				: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
			{...(props.codeViewWorkerPoolEnabled === undefined
				? {}
				: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
			{...controlledFileViewerProps}
			isActive={props.isActive}
			{...(props.navigationCommand === undefined
				? {}
				: { navigationCommand: props.navigationCommand })}
			onOpenReviewComparison={openReviewComparison}
			telemetryRecorder={props.telemetryRecorder}
			telemetryTraceContext={null}
			viewerHeaderControls={props.viewerHeaderControls}
			waitForBridgeReady={props.registerBridgeReadyCallback}
		/>
	);
}

function BridgeFileViewerHeadlessController(): ReactElement {
	return <div data-testid="bridge-file-viewer-headless-controller" />;
}
