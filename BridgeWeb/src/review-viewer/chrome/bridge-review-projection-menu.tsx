import { BotIcon, FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from '../../app/bridge-viewer-chrome.js';
import { cn } from '../../app/class-name.js';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group.js';
import type { BridgeReviewProjectionMode } from '../models/review-projection-models.js';

export function BridgeReviewProjectionMenu(props: {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
}): ReactElement {
	const activeProjectionKind =
		props.projectionMode.kind === 'normalReview' ? props.projectionMode.kind : 'normalReview';
	return (
		<ToggleGroup
			aria-label="Review mode"
			data-bridge-segmented-control="review-mode"
			data-testid="bridge-review-mode-segmented-control"
			role="radiogroup"
			size="sm"
		>
			{projectionButtonSpecs.map((spec) => {
				const isSelected = spec.mode.kind === activeProjectionKind;
				const isEnabled = spec.mode.kind === 'normalReview';
				return (
					<ToggleGroupItem
						aria-checked={isSelected ? 'true' : 'false'}
						aria-label={spec.label}
						className={cn(
							bridgeViewerChromeIconButtonClassName,
							isSelected ? 'shadow-none' : undefined,
						)}
						data-testid="bridge-review-mode-segment"
						disabled={!isEnabled}
						key={spec.value}
						onClick={(): void => {
							if (isEnabled && !isSelected) {
								props.onProjectionModeChange?.(spec.mode);
							}
						}}
						pressed={isSelected}
						role="radio"
						size="sm"
						title={spec.label}
					>
						<spec.Icon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
					</ToggleGroupItem>
				);
			})}
		</ToggleGroup>
	);
}

const projectionButtonSpecs: readonly {
	readonly label: string;
	readonly mode: BridgeReviewProjectionMode;
	readonly value: string;
	readonly Icon: typeof ListChecksIcon;
}[] = [
	{
		label: 'Normal review',
		mode: { kind: 'normalReview' },
		value: 'normalReview',
		Icon: ListChecksIcon,
	},
	{
		label: 'Guided review',
		mode: { kind: 'guidedReview' },
		value: 'guidedReview',
		Icon: BotIcon,
	},
	{
		label: 'Plans/specs',
		mode: { kind: 'plansAndSpecs' },
		value: 'plansAndSpecs',
		Icon: FileTextIcon,
	},
];
