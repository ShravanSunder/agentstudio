import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';

describe('createWorktreeAnnotationEditToken', () => {
	test('uses a UUIDv7 identity', () => {
		const token = createWorktreeAnnotationEditToken();

		expect(z.uuidv7().parse(token.replace('annotation-edit-', ''))).toBeTruthy();
	});
});
