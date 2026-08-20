import { uuidv7 } from 'uuidv7';

export function createWorktreeAnnotationEditToken(): string {
	return `annotation-edit-${uuidv7()}`;
}
