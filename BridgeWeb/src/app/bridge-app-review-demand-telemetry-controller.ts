import type { Dispatch, SetStateAction } from 'react';
import { useEffect } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-types.js';
import { reviewContentDemandTelemetryForPackage } from './bridge-app-review-selection-state.js';

export interface UseBridgeReviewDemandTelemetryControllerProps {
	readonly lastSelectedDemandTelemetry: ReviewContentDemandTelemetry | null;
	readonly lastVisibleDemandTelemetry: ReviewContentDemandTelemetry | null;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly setLastSelectedDemandTelemetry: Dispatch<
		SetStateAction<ReviewContentDemandTelemetry | null>
	>;
	readonly setLastVisibleDemandTelemetry: Dispatch<
		SetStateAction<ReviewContentDemandTelemetry | null>
	>;
}

export interface BridgeReviewDemandTelemetryController {
	readonly lastSelectedDemandTelemetryForCurrentPackage: ReviewContentDemandTelemetry | null;
	readonly lastVisibleDemandTelemetryForCurrentPackage: ReviewContentDemandTelemetry | null;
}

export function useBridgeReviewDemandTelemetryController(
	props: UseBridgeReviewDemandTelemetryControllerProps,
): BridgeReviewDemandTelemetryController {
	const {
		lastSelectedDemandTelemetry,
		lastVisibleDemandTelemetry,
		reviewPackage,
		setLastSelectedDemandTelemetry,
		setLastVisibleDemandTelemetry,
	} = props;
	useEffect((): void => {
		setLastSelectedDemandTelemetry((currentTelemetry) =>
			reviewContentDemandTelemetryForPackage({
				reviewPackage,
				telemetry: currentTelemetry,
			}),
		);
		setLastVisibleDemandTelemetry((currentTelemetry) =>
			reviewContentDemandTelemetryForPackage({
				reviewPackage,
				telemetry: currentTelemetry,
			}),
		);
	}, [reviewPackage, setLastSelectedDemandTelemetry, setLastVisibleDemandTelemetry]);

	return {
		lastSelectedDemandTelemetryForCurrentPackage: reviewContentDemandTelemetryForPackage({
			reviewPackage,
			telemetry: lastSelectedDemandTelemetry,
		}),
		lastVisibleDemandTelemetryForCurrentPackage: reviewContentDemandTelemetryForPackage({
			reviewPackage,
			telemetry: lastVisibleDemandTelemetry,
		}),
	};
}
