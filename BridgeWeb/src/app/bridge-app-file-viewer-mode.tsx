import { useCallback, useEffect, useState, type ReactElement } from 'react';

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
	const hasFileViewerFrameSource = props.fileViewerProps !== undefined;
	const hasActivatedFileViewerController =
		props.isActive || hasActivatedFileViewerShell || hasFileViewerFrameSource;
	const controlledFileViewerProps = useBridgeFileViewerFrameControllerProps({
		enabled: hasActivatedFileViewerController,
		fileViewerProps: props.fileViewerProps,
		waitForBridgeReady: props.registerBridgeReadyCallback,
	});
	useEffect((): void => {
		if (props.isActive) {
			setHasActivatedFileViewerShell(true);
		}
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
