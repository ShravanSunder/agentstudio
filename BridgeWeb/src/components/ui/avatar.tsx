import { Avatar as AvatarPrimitive } from '@base-ui/react/avatar';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

function Avatar({ className, ...props }: AvatarPrimitive.Root.Props): ReactElement {
	return (
		<AvatarPrimitive.Root
			data-slot="avatar"
			className={cn(
				'inline-flex size-6 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-secondary align-middle text-xs/none font-medium text-secondary-foreground select-none',
				className,
			)}
			{...props}
		/>
	);
}

function AvatarImage({ className, ...props }: AvatarPrimitive.Image.Props): ReactElement {
	return (
		<AvatarPrimitive.Image
			data-slot="avatar-image"
			className={cn('size-full object-cover', className)}
			{...props}
		/>
	);
}

function AvatarFallback({ className, ...props }: AvatarPrimitive.Fallback.Props): ReactElement {
	return (
		<AvatarPrimitive.Fallback
			data-slot="avatar-fallback"
			className={cn('flex size-full items-center justify-center', className)}
			{...props}
		/>
	);
}

export { Avatar, AvatarFallback, AvatarImage };
