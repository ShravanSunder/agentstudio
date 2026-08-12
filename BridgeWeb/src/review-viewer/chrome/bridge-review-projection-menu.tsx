import { BotIcon, FileTextIcon, ListChecksIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentIconButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from '../../app/bridge-viewer-chrome.js';
import { cn } from '../../app/class-name.js';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group.js';
import type { BridgeReviewProjectionMode } from '../models/review-projection-models.js';

export function BridgeReviewProjectionMenu(props: {
	readonly disabled?: boolean;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
}): ReactElement {
	const activeProjectionKind =
		props.projectionMode.kind === 'normalReview' ? props.projectionMode.kind : 'normalReview';
	return (
		<ToggleGroup
			aria-label="Review mode"
			className={bridgeViewerChromeSegmentedControlClassName}
			data-bridge-segmented-control="review-mode"
			data-testid="bridge-review-mode-segmented-control"
			role="radiogroup"
			size="sm"
			value={[activeProjectionKind]}
		>
			{projectionButtonSpecs.map((spec) => {
				const isSelected = spec.mode.kind === activeProjectionKind;
				const isEnabled = spec.mode.kind === 'normalReview' && props.disabled !== true;
				return (
					<ToggleGroupItem
						aria-checked={isSelected ? 'true' : 'false'}
						aria-label={spec.label}
						className={cn(
							bridgeViewerChromeSegmentIconButtonClassName,
							isSelected ? 'shadow-none' : undefined,
						)}
						data-testid="bridge-review-mode-segment"
						disabled={!isEnabled}
						key={spec.value}
						onPressedChange={(pressed): void => {
							if (pressed && isEnabled && !isSelected) {
								props.onProjectionModeChange?.(spec.mode);
							}
						}}
						role="radio"
						size="sm"
						title={spec.label}
						value={spec.value}
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
