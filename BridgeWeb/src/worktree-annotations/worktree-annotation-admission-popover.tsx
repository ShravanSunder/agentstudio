import type { RefObject } from 'react';
import { type ReactElement } from 'react';

import { Button } from '@/components/ui/button.js';
import {
	Popover,
	PopoverContent,
	PopoverDescription,
	PopoverHeader,
	PopoverTitle,
} from '@/components/ui/popover.js';

import type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationSessionSummary,
} from './worktree-annotation-surface-client.js';

export type WorktreeAnnotationAdmissionRequirement = Extract<
	WorktreeAnnotationCommandOutcome['status'],
	{ readonly kind: 'admission_required' }
>;

export interface WorktreeAnnotationAdmissionPopoverProps {
	readonly anchor: RefObject<HTMLElement | null>;
	readonly onContinue: (sessionId: string) => void;
	readonly onDismiss: () => void;
	readonly onLeavePaused: () => void;
	readonly onStartAnother: () => void;
	readonly requirement: WorktreeAnnotationAdmissionRequirement;
	readonly sessions: readonly WorktreeAnnotationSessionSummary[];
}

export function WorktreeAnnotationAdmissionPopover(
	props: WorktreeAnnotationAdmissionPopoverProps,
): ReactElement {
	const candidates = props.requirement.candidateSessionIds.flatMap(
		(sessionId): readonly WorktreeAnnotationSessionSummary[] => {
			const session = props.sessions.find((candidate) => candidate.sessionId === sessionId);
			return session === undefined ? [] : [session];
		},
	);
	const continuityIsUncertain = props.requirement.reason === 'uncertain_continuity_choice';
	return (
		<Popover
			onOpenChange={(isOpen): void => {
				if (!isOpen) props.onDismiss();
			}}
			open
		>
			<PopoverContent anchor={props.anchor} className="gap-2" side="bottom" align="end">
				<PopoverHeader>
					<PopoverTitle>
						{continuityIsUncertain ? 'Review continuity is uncertain' : 'Choose a review session'}
					</PopoverTitle>
					<PopoverDescription>
						{continuityIsUncertain
							? 'Choose how this inline comment should continue.'
							: 'Several sessions apply. Choose one for this inline comment.'}
					</PopoverDescription>
				</PopoverHeader>
				<div className="flex flex-col gap-1">
					{candidates.map((session, index) => (
						<Button
							key={session.sessionId}
							onClick={() => props.onContinue(session.sessionId)}
							size="xs"
							variant={continuityIsUncertain ? 'secondary' : 'outline'}
						>
							{continuityIsUncertain ? 'Continue' : `Continue session ${index + 1}`}
						</Button>
					))}
					{continuityIsUncertain ? (
						<Button onClick={props.onLeavePaused} size="xs" variant="ghost">
							Leave Paused
						</Button>
					) : null}
					{continuityIsUncertain ? (
						<Button onClick={props.onStartAnother} size="xs" variant="ghost">
							Start Another
						</Button>
					) : null}
				</div>
			</PopoverContent>
		</Popover>
	);
}
