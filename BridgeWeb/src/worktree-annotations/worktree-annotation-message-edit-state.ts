export function worktreeAnnotationMessageHasUnsavedChanges(
	body: string,
	savedBody: string | null,
): boolean {
	return body !== (savedBody ?? '');
}
