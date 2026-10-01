import { TriangleAlert } from 'lucide-react';
import { useState, useSyncExternalStore, type ReactElement } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';

import { BridgeRegionPresentation } from '../app/bridge-region-presentation.js';
import { BridgeViewerRecoveryRetryButton } from '../app/bridge-viewer-recovery-retry-button.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export function WorktreeAnnotationRecoveryWarning(): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const viewRecoveryStatus = useSyncExternalStore(
		annotationClient.subscribeViewRecoveryStatus,
		annotationClient.getViewRecoveryStatus,
		annotationClient.getViewRecoveryStatus,
	);
	const [failureMessage, setFailureMessage] = useState<string | null>(null);
	const [isAcknowledging, setIsAcknowledging] = useState(false);
	const isViewRecoveryFailed = viewRecoveryStatus?.status === 'failedRetryable';
	const isLocallyRecoveredDegraded = projection.recoveryStatus === 'recovered_degraded';

	if (!isLocallyRecoveredDegraded && !isViewRecoveryFailed) return null;
	if (isViewRecoveryFailed && !isLocallyRecoveredDegraded)
		return (
			<BridgeRegionPresentation
				region="comments-recovery"
				shape="comments"
				state={{
					kind: 'failed',
					retainsContent: false,
					failure: { kind: 'retryable', scope: 'surface', message: 'Comments unavailable' },
				}}
				retry={
					<BridgeViewerRecoveryRetryButton
						surface="comments"
						onClick={(): void => {
							annotationClient.retryViewRecovery();
							annotationClient.retryProjection();
						}}
					/>
				}
			/>
		);

	const acknowledgeRecovery = async (): Promise<void> => {
		if (isAcknowledging) return;
		setIsAcknowledging(true);
		setFailureMessage(null);
		try {
			const outcome = await annotationClient.execute({ kind: 'recovery.acknowledge' });
			if (outcome.status.kind !== 'committed') {
				throw new Error(
					outcome.status.kind === 'failed'
						? outcome.status.code
						: 'Recovery acknowledgement was not committed.',
				);
			}
		} catch (error: unknown) {
			setFailureMessage(
				error instanceof Error ? error.message : 'Recovery acknowledgement failed.',
			);
		} finally {
			setIsAcknowledging(false);
		}
	};

	return (
		<Alert layout="banner" variant="warning">
			<TriangleAlert />
			<AlertTitle>
				{isViewRecoveryFailed
					? 'Comments unavailable'
					: 'Comments recovered with missing local history'}
			</AlertTitle>
			<AlertDescription>
				{failureMessage ??
					(isViewRecoveryFailed
						? 'Showing the last available comments while this view recovers.'
						: 'Review the recovery notice before creating or changing inline comments.')}
			</AlertDescription>
			<AlertAction>
				{isViewRecoveryFailed ? (
					<BridgeViewerRecoveryRetryButton
						onClick={(): void => {
							annotationClient.retryViewRecovery();
							annotationClient.retryProjection();
						}}
						surface="comments"
					/>
				) : null}
				{isLocallyRecoveredDegraded ? (
					<Button
						disabled={isAcknowledging}
						onClick={() => void acknowledgeRecovery()}
						size="xs"
						variant="outline"
					>
						Acknowledge
					</Button>
				) : null}
			</AlertAction>
		</Alert>
	);
}
