import { useCallback, useEffect, useRef, useState, type ReactElement } from 'react';

import type { BridgeActiveViewerSource } from '../bridge/bridge-rpc-client.js';
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
	readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
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
	const onActiveSourceChange = props.onActiveSourceChange;
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
	const pendingFileSurfaceReopenRef = useRef(false);
	const handleFileSurfaceOpenResolved = useCallback((): void => {
		fileSurfaceOpenResolvedRef.current = true;
		pendingFileSurfaceReopenRef.current = false;
	}, []);
	const handleFileSurfaceStreamResetRequired = useCallback((): void => {
		if (!fileSurfaceOpenResolvedRef.current) {
			return;
		}
		fileSurfaceOpenResolvedRef.current = false;
		onActiveSourceChange(null);
		if (!wasFileViewerActiveRef.current) {
			pendingFileSurfaceReopenRef.current = true;
			return;
		}
		setFileSurfaceReopenSignal((signal) => signal + 1);
	}, [onActiveSourceChange]);
	const hasFileViewerFrameSource = props.fileViewerProps !== undefined;
	const hasActivatedFileViewerController =
		props.isActive || hasActivatedFileViewerShell || hasFileViewerFrameSource;
	const controlledFileViewerProps = useBridgeFileViewerFrameControllerProps({
		enabled: hasActivatedFileViewerController,
		fileViewerProps: props.fileViewerProps,
		onSurfaceSourceResolved: onActiveSourceChange,
		onSurfaceOpenResolved: handleFileSurfaceOpenResolved,
		reopenSignal: fileSurfaceReopenSignal,
		waitForBridgeReady: props.registerBridgeReadyCallback,
	});
	useEffect((): void => {
		if (props.isActive) {
			setHasActivatedFileViewerShell(true);
			if (pendingFileSurfaceReopenRef.current) {
				pendingFileSurfaceReopenRef.current = false;
				setFileSurfaceReopenSignal((signal) => signal + 1);
			} else if (!wasFileViewerActiveRef.current && !fileSurfaceOpenResolvedRef.current) {
				// The prior open never resolved (wedged/hung): re-issue it. If the
				// re-open also fails to resolve, the ref stays false and the next
				// activation retries — recovery. A resolved (healthy) stream is
				// reused instead, so healthy toggles never re-open.
				setFileSurfaceReopenSignal((signal) => signal + 1);
			}
		}
		wasFileViewerActiveRef.current = props.isActive;
	}, [props.isActive]);
	useEffect((): (() => void) => {
		return (
			props.fileViewerProps?.registerSurfaceStreamResetRequiredCallback?.(
				handleFileSurfaceStreamResetRequired,
			) ?? ((): void => {})
		);
	}, [handleFileSurfaceStreamResetRequired, props.fileViewerProps]);
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
