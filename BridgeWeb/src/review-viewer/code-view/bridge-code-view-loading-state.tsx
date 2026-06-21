import type { ReactElement } from 'react';

import { Skeleton } from '../../components/ui/skeleton.js';

export function BridgeCodeViewLoadingState(): ReactElement {
	return <BridgeCodeViewSkeletonPanel dataTestId="bridge-code-view-loading-state" />;
}

export function BridgeCodeViewVisibleLoadingState(): ReactElement {
	return <BridgeCodeViewSkeletonPanel dataTestId="bridge-code-view-visible-loading-state" />;
}

interface BridgeCodeViewSkeletonPanelProps {
	readonly dataTestId: string;
}

function BridgeCodeViewSkeletonPanel(props: BridgeCodeViewSkeletonPanelProps): ReactElement {
	return (
		<div
			aria-hidden="true"
			className="pointer-events-none absolute left-8 top-12 z-10 flex w-[min(28rem,calc(100%-4rem))] flex-col gap-2 rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)]/75 p-3 shadow-[0_18px_48px_rgb(0_0_0_/_0.45)] backdrop-blur"
			data-testid={props.dataTestId}
		>
			<Skeleton className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]" />
			<Skeleton className="h-3 w-3/4 bg-[var(--bridge-surface-raised-bg)]" />
		</div>
	);
}
