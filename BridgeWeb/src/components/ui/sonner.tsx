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
	'--border-radius': 'var(--radius)',
	'--normal-bg': 'var(--bridge-surface-raised-bg)',
	'--normal-border': 'var(--bridge-border-opaque)',
	'--normal-text': 'var(--bridge-text-primary)',
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
						'border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)] text-[var(--bridge-text-secondary)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
					description: 'text-[10px] text-[var(--bridge-text-secondary)]',
					title: 'text-xs font-medium',
					toast: 'shadow-[var(--bridge-floating-panel-shadow)]',
				},
			}}
			{...props}
		/>
	);
}

export { Toaster };
