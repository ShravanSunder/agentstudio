import { FileClockIcon, RefreshCwIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { Alert, AlertAction, AlertTitle } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';

export interface BridgeViewerFileChangedAlertProps {
	/** The latest Update attempt could not prepare the open annotation editors. */
	readonly installationFailed: boolean;
	readonly installationPending: boolean;
	readonly onUpdate: () => void;
	/** Accessible name of the Update action, naming what it loads. */
	readonly updateActionLabel: string;
}

/**
 * The explicit exit from a viewer that keeps showing an older file revision: it names
 * the change and loads the latest file on request. The feature owns placement and the
 * installation behavior behind `onUpdate`.
 */
export function BridgeViewerFileChangedAlert(
	props: BridgeViewerFileChangedAlertProps,
): ReactElement {
	const title = props.installationFailed ? 'Update failed' : 'File changed';
	return (
		<Alert
			aria-label={title}
			className="pointer-events-auto items-center"
			layout="floating"
			role="status"
			variant="floating"
		>
			<FileClockIcon aria-hidden="true" />
			<AlertTitle>{title}</AlertTitle>
			<AlertAction className="self-center">
				<Tooltip>
					<TooltipTrigger
						render={
							<Button
								aria-label={props.updateActionLabel}
								disabled={props.installationPending}
								size="sm"
								type="button"
								variant="outline"
							/>
						}
						onClick={props.onUpdate}
					>
						<RefreshCwIcon
							aria-hidden="true"
							data-busy={props.installationPending}
							data-icon="inline-start"
						/>
						Update
					</TooltipTrigger>
					<TooltipContent side="bottom">
						{props.installationFailed
							? 'Finish or cancel the open annotation, then retry.'
							: 'Keep the draft and load the latest file.'}
					</TooltipContent>
				</Tooltip>
			</AlertAction>
		</Alert>
	);
}
