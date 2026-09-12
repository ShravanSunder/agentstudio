import { Button as ButtonPrimitive } from '@base-ui/react/button';
import { Plus } from 'lucide-react';
import type { PointerEvent, ReactElement } from 'react';

export interface AnnotationGutterRowProps {
	readonly startLine: number;
	readonly endLine: number;
	readonly top: number;
	readonly height: number;
	readonly firstLineCenter: number;
	readonly active: boolean;
	readonly hasComments: boolean;
	readonly endpoint: boolean;
	readonly disabled: boolean;
	readonly onSelect: (event: PointerEvent<HTMLButtonElement>) => void;
	readonly onKeyboardSelect: () => void;
	readonly onAnnotatePointerDown: (event: PointerEvent<HTMLButtonElement>) => void;
	readonly onAnnotate: () => void;
}

export function AnnotationGutterRow(props: AnnotationGutterRowProps): ReactElement {
	return (
		<div
			className="group/gutter absolute left-0 w-full data-[active=true]:bg-[var(--annotation-source-gutter-selection-background)] before:pointer-events-none before:absolute before:inset-y-0 before:left-0 before:hidden before:w-1 before:content-[''] data-[commented=true]:before:block before:bg-[linear-gradient(0deg,var(--background)_50%,var(--warning)_50%)] before:[background-size:2px_2px]"
			data-active={props.active}
			data-commented={props.hasComments}
			data-endpoint={props.endpoint}
			style={{ top: props.top, height: props.height }}
		>
			<ButtonPrimitive
				className="absolute left-0 h-5 w-[30px] -translate-y-1/2 pr-0.5 text-right font-mono text-sm text-muted-foreground outline-none group-data-[active=true]/gutter:text-warning focus-visible:ring-2 focus-visible:ring-ring disabled:text-faint-foreground"
				style={{ top: props.firstLineCenter }}
				disabled={props.disabled}
				aria-label={`Select source lines ${props.startLine}–${props.endLine}`}
				onPointerDown={props.onSelect}
				onClick={(event): void => {
					if (event.detail === 0) props.onKeyboardSelect();
				}}
			>
				{props.startLine}
			</ButtonPrimitive>
			<ButtonPrimitive
				className="absolute left-[30px] grid size-5 -translate-y-1/2 place-items-center rounded-sm bg-warning text-background opacity-0 outline-none group-hover/gutter:opacity-100 group-data-[endpoint=true]/gutter:opacity-100 focus-visible:opacity-100 focus-visible:ring-2 focus-visible:ring-ring disabled:bg-muted disabled:text-faint-foreground [&_svg]:pointer-events-none [&_svg]:size-3.5"
				style={{ top: props.firstLineCenter }}
				disabled={props.disabled}
				aria-label={`Annotate source lines ${props.startLine}–${props.endLine}`}
				onPointerDown={props.onAnnotatePointerDown}
				onClick={(event): void => {
					if (event.detail === 0) props.onAnnotate();
				}}
			>
				<Plus />
			</ButtonPrimitive>
		</div>
	);
}
