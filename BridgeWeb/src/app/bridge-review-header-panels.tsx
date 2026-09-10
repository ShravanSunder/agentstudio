import { useRef, useState, type ReactElement } from 'react';

import { WorktreeAnnotationSharePanelControl } from '../worktree-annotations/worktree-annotation-output-controls.js';
import { useWorktreeAnnotationOutputPendingController } from '../worktree-annotations/worktree-annotation-output-pending-controller.js';
import { useWorktreeAnnotationInteraction } from '../worktree-annotations/worktree-annotation-surface-provider.js';
import {
	BridgeReviewComparisonControl,
	type BridgeReviewComparisonControlProps,
} from './bridge-review-comparison-control.js';
import { requireBridgeViewerContextPanelPortalContainer } from './bridge-viewer-context-panel-host.js';

type BridgeReviewHeaderPanelsProps = Omit<
	BridgeReviewComparisonControlProps,
	'finalFocus' | 'onOpenChange' | 'open'
>;

export function BridgeReviewHeaderPanels(props: BridgeReviewHeaderPanelsProps): ReactElement {
	const interaction = useWorktreeAnnotationInteraction();
	const outputPendingController = useWorktreeAnnotationOutputPendingController();
	const viewportRef = requireBridgeViewerContextPanelPortalContainer();
	const [comparisonOpen, setComparisonOpen] = useState(false);
	const comparePeerCloseRef = useRef(false);
	const sharePeerCloseRef = useRef(false);
	const isActive = props.isActive ?? true;

	return (
		<>
			<WorktreeAnnotationSharePanelControl
				finalFocus={({ closeReason, trigger }): false | HTMLElement | null => {
					if (sharePeerCloseRef.current) {
						sharePeerCloseRef.current = false;
						return false;
					}
					if (!isActive || closeReason === 'outside-press') return false;
					return trigger;
				}}
				onOpenRequest={(): boolean => {
					if (comparisonOpen) {
						comparePeerCloseRef.current = true;
						setComparisonOpen(false);
					}
					return true;
				}}
				outputPendingController={outputPendingController}
			/>
			<BridgeReviewComparisonControl
				{...props}
				finalFocus={({ closeReason, trigger }): false | HTMLElement | null => {
					if (comparePeerCloseRef.current) {
						comparePeerCloseRef.current = false;
						return false;
					}
					if (!isActive || closeReason === 'outside-press') return false;
					if (trigger !== null && !trigger.disabled && trigger.isConnected) return trigger;
					const viewport = viewportRef.current;
					if (!isActive || viewport === null || !viewport.isConnected || viewport.inert)
						return false;
					viewport.focus({ preventScroll: true });
					return false;
				}}
				onOpenChange={(nextOpen): boolean => {
					if (nextOpen) {
						if (outputPendingController.isPending) return false;
						if (interaction.shareMode.kind === 'open') {
							sharePeerCloseRef.current = true;
							interaction.closeShareMode();
						}
					}
					setComparisonOpen(nextOpen);
					return true;
				}}
				open={comparisonOpen}
			/>
		</>
	);
}
