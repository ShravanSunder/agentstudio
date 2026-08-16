import type { RefinementCtx } from 'zod';

export function validateBridgeWorkerSelectCommand(
	command: {
		readonly reviewPresentation?: 'diff' | 'file' | undefined;
		readonly selectedItemId: string | null;
		readonly selectedSource: 'keyboard' | 'programmatic' | 'user' | null;
		readonly surface: 'fileView' | 'review';
	},
	context: RefinementCtx,
): void {
	if ((command.selectedItemId === null) !== (command.selectedSource === null)) {
		context.addIssue({
			code: 'custom',
			message: 'Selection identity and source must both be present or both be null.',
		});
	}
	if (command.reviewPresentation !== undefined && command.surface !== 'review') {
		context.addIssue({
			code: 'custom',
			message: 'Review presentation is valid only for Review selection.',
		});
	}
}
