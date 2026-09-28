import { TriangleAlert } from 'lucide-react';
import type { ReactElement } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '../components/ui/alert.js';
import type { BridgeMainViewRecoveryStatus } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeViewerRecoveryRetryButton } from './bridge-viewer-recovery-retry-button.js';

export function BridgeReviewMetadataRecoveryWarning(props: {
	readonly onRetry: () => void;
	readonly status: BridgeMainViewRecoveryStatus | null;
}): ReactElement | null {
	if (props.status?.status !== 'failedRetryable') return null;
	return (
		<Alert layout="banner" variant="warning" data-testid="bridge-review-metadata-recovery-warning">
			<TriangleAlert />
			<AlertTitle>Review metadata unavailable</AlertTitle>
			<AlertDescription>
				Showing the last available Review while metadata recovers.
			</AlertDescription>
			<AlertAction>
				<BridgeViewerRecoveryRetryButton onClick={props.onRetry} surface="review" />
			</AlertAction>
		</Alert>
	);
}
