import { act, useState, type ReactElement } from 'react';

import {
	BridgeReviewComparisonControl,
	type BridgeReviewComparisonControlProps,
} from './bridge-review-comparison-control.js';
import {
	BridgeViewerContextPanelProvider,
	BridgeViewerContextPanelViewport,
	requireBridgeViewerContextPanelPortalContainer,
} from './bridge-viewer-context-panel-host.js';

type BridgeReviewComparisonControlTestHostProps = Omit<
	BridgeReviewComparisonControlProps,
	'finalFocus' | 'onOpenChange' | 'open'
>;

export function BridgeReviewComparisonControlTestHost(
	props: BridgeReviewComparisonControlTestHostProps,
): ReactElement {
	return (
		<BridgeViewerContextPanelProvider>
			<BridgeReviewComparisonControlTestHostContent {...props} />
		</BridgeViewerContextPanelProvider>
	);
}

/** Flush each interaction before advancing the portaled Drawer's transition. */
export async function performComparisonAction(action: () => Promise<void> | void): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
	});
	for (let frame = 0; frame < 10; frame += 1) {
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
			const animations = [...document.querySelectorAll('[data-slot="drawer-popup"]')].flatMap(
				(panel) => panel.getAnimations(),
			);
			for (const animation of animations) animation.finish();
			await Promise.all(
				animations.map(async (animation) => {
					await animation.finished.catch(() => {});
				}),
			);
		});
		if (
			document.querySelector(
				'[data-slot="drawer-popup"][data-starting-style], [data-slot="drawer-popup"][data-ending-style]',
			) === null
		)
			return;
	}
	throw new Error('Comparison drawer motion did not settle.');
}

function BridgeReviewComparisonControlTestHostContent(
	props: BridgeReviewComparisonControlTestHostProps,
): ReactElement {
	const [open, setOpen] = useState(false);
	const viewportRef = requireBridgeViewerContextPanelPortalContainer();
	const isActive = props.isActive ?? true;
	return (
		<div className="grid h-[600px] w-[720px] grid-rows-[auto_minmax(0,1fr)]">
			<div>
				<BridgeReviewComparisonControl
					{...props}
					finalFocus={({ closeReason, trigger }): false | HTMLElement | null => {
						if (!isActive || closeReason === 'outside-press') return false;
						if (trigger?.disabled === false) return trigger;
						viewportRef.current?.focus({ preventScroll: true });
						return false;
					}}
					onOpenChange={(nextOpen): boolean => {
						setOpen(nextOpen);
						return true;
					}}
					open={open}
				/>
			</div>
			<BridgeViewerContextPanelViewport testId="bridge-review-comparison-test-viewport">
				<div>Comparison test canvas</div>
			</BridgeViewerContextPanelViewport>
		</div>
	);
}
