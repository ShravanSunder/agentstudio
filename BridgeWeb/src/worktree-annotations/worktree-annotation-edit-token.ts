export function createWorktreeAnnotationEditToken(): string {
	return `annotation-edit-${crypto.randomUUID()}`;
}
