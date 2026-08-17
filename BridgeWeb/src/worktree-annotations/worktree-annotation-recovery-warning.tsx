import { TriangleAlert } from 'lucide-react';
import { useState, type ReactElement } from 'react';

import { Alert, AlertAction, AlertDescription, AlertTitle } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';

import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export function WorktreeAnnotationRecoveryWarning(): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const [failureMessage, setFailureMessage] = useState<string | null>(null);
	const [isAcknowledging, setIsAcknowledging] = useState(false);

	if (projection.recoveryStatus !== 'recovered_degraded') return null;

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
		<Alert className="rounded-none border-x-0 border-warning/35 bg-warning/10 pr-28">
			<TriangleAlert className="text-warning" />
			<AlertTitle>Comments recovered with missing local history</AlertTitle>
			<AlertDescription>
				{failureMessage ??
					'Review the recovery notice before creating or changing inline comments.'}
			</AlertDescription>
			<AlertAction>
				<Button
					disabled={isAcknowledging}
					onClick={() => void acknowledgeRecovery()}
					size="xs"
					variant="outline"
				>
					Acknowledge
				</Button>
			</AlertAction>
		</Alert>
	);
}
