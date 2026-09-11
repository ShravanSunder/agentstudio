import {
	CircleCheckIcon,
	InfoIcon,
	Loader2Icon,
	OctagonXIcon,
	TriangleAlertIcon,
} from 'lucide-react';
import type { CSSProperties, ReactElement } from 'react';
import { Toaster as Sonner, type ToasterProps } from 'sonner';

const toasterStyle: CSSProperties & Record<`--${string}`, string> = {
	'--border-radius': 'var(--radius-lg)',
	'--normal-bg': 'var(--popover)',
	'--normal-border': 'var(--popover-border)',
	'--normal-text': 'var(--popover-foreground)',
	'--width': '20rem',
};

function Toaster({ ...props }: ToasterProps): ReactElement {
	return (
		<Sonner
			theme="dark"
			className="toaster group"
			closeButton
			icons={{
				error: <OctagonXIcon className="size-3.5" />,
				info: <InfoIcon className="size-3.5" />,
				loading: <Loader2Icon className="size-3.5 animate-spin" />,
				success: <CircleCheckIcon className="size-3.5" />,
				warning: <TriangleAlertIcon className="size-3.5" />,
			}}
			position="bottom-right"
			style={toasterStyle}
			toastOptions={{
				classNames: {
					closeButton:
						'border-input bg-surface text-muted-foreground hover:bg-accent hover:text-accent-foreground disabled:text-faint-foreground disabled:opacity-100',
					// Sonner injects unlayered rules; these owned recipes must outrank them.
					description: 'text-2xs! text-muted-foreground!',
					title: 'text-xs! font-medium',
					toast:
						'rounded-lg border-popover-border bg-popover text-popover-foreground shadow-popover! focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring',
				},
			}}
			{...props}
		/>
	);
}

export { Toaster };
