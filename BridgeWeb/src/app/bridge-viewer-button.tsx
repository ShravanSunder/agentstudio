import type { ComponentProps, ReactElement, ReactNode, Ref } from 'react';

import { Button } from '../components/ui/button.js';

export interface BridgeViewerButtonProps extends Omit<
	ComponentProps<typeof Button>,
	'children' | 'className' | 'ref' | 'style'
> {
	readonly children?: ReactNode;
	readonly buttonRef?: Ref<HTMLButtonElement>;
	readonly ariaLabel?: string;
	readonly ariaPressed?: boolean;
	readonly 'data-bridge-viewer-context-selected'?: string;
	readonly 'data-bridge-viewer-context-target'?: string;
	readonly 'data-testid'?: string;
	readonly testId?: string;
}

export function BridgeViewerButton(props: BridgeViewerButtonProps): ReactElement {
	const {
		ariaLabel,
		ariaPressed,
		buttonRef,
		children,
		testId,
		size = 'sm',
		variant = 'ghost',
		...buttonProps
	} = props;
	return (
		<Button
			{...buttonProps}
			ref={buttonRef}
			aria-label={ariaLabel ?? buttonProps['aria-label']}
			aria-pressed={ariaPressed ?? buttonProps['aria-pressed']}
			data-bridge-viewer-context-selected={props['data-bridge-viewer-context-selected']}
			data-bridge-viewer-context-target={props['data-bridge-viewer-context-target']}
			data-testid={testId ?? props['data-testid']}
			size={size}
			type="button"
			variant={variant}
		>
			{children}
		</Button>
	);
}

export interface BridgeViewerIconProps {
	readonly children: ReactNode;
}

export function BridgeViewerIcon(props: BridgeViewerIconProps): ReactElement {
	return <span aria-hidden="true">{props.children}</span>;
}
