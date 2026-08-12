import { TriangleAlertIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '../components/ui/alert.js';
import { Button } from '../components/ui/button.js';
import { Progress } from '../components/ui/progress.js';
import type { BridgeReviewComparisonPaneState } from './bridge-review-comparison-pane-state.js';
import type { BridgeReviewComparisonTarget } from './bridge-review-comparison-target.js';

export function BridgeReviewComparisonStatusBanner(props: {
	readonly onRetry: (target: BridgeReviewComparisonTarget) => void;
	readonly state: BridgeReviewComparisonPaneState;
}): ReactElement | null {
	switch (props.state.kind) {
		case 'settled':
			return null;
		case 'loadingInitial':
		case 'loadingPrevious':
			return (
				<Alert
					aria-live="polite"
					className="rounded-none border-x-0 border-t-0"
					data-testid="bridge-review-comparison-status-banner"
					role="status"
				>
					<AlertTitle>Loading comparison with {props.state.requestedTargetLabel}…</AlertTitle>
					<Progress aria-label="Loading comparison" className="col-span-full mt-1" value={null} />
				</Alert>
			);
		case 'failedPrevious':
			return (
				<ComparisonFailureAlert
					description={`Couldn’t load ${props.state.requestedTargetLabel}. Showing the previous comparison with ${props.state.displayedTargetLabel}.`}
					onRetry={props.onRetry}
					retryTarget={props.state.retryTarget}
				/>
			);
		case 'failedInitial':
			return (
				<ComparisonFailureAlert
					description={`Couldn’t load ${props.state.requestedTargetLabel}.`}
					onRetry={props.onRetry}
					retryTarget={props.state.retryTarget}
				/>
			);
		default:
			return assertNeverComparisonStatusBannerState(props.state);
	}
}

function ComparisonFailureAlert(props: {
	readonly description: string;
	readonly onRetry: (target: BridgeReviewComparisonTarget) => void;
	readonly retryTarget: BridgeReviewComparisonTarget | null;
}): ReactElement {
	const retryTarget = props.retryTarget;
	return (
		<Alert
			className="rounded-none border-x-0 border-t-0"
			data-testid="bridge-review-comparison-status-banner"
			variant="destructive"
		>
			<TriangleAlertIcon aria-hidden="true" />
			<AlertTitle>Comparison unavailable</AlertTitle>
			<AlertDescription>{props.description}</AlertDescription>
			{retryTarget === null ? null : (
				<AlertAction>
					<Button
						onClick={(): void => props.onRetry(retryTarget)}
						size="xs"
						type="button"
						variant="outline"
					>
						Retry
					</Button>
				</AlertAction>
			)}
		</Alert>
	);
}

function assertNeverComparisonStatusBannerState(state: never): never {
	throw new Error(`Unexpected Review comparison banner state: ${JSON.stringify(state)}`);
}
