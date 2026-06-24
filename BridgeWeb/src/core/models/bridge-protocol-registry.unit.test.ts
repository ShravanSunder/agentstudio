import { describe, expect, test } from 'vitest';

import { createBridgeProtocolRegistry } from './bridge-protocol-registry.js';

describe('bridge protocol registry', () => {
	test('registers protocol-owned resource kinds and privileged methods', () => {
		const registry = createBridgeProtocolRegistry({
			protocols: [
				{
					protocol: 'review',
					resourceKinds: ['content', 'review-package'],
					privilegedMethods: ['review.openStream'],
				},
			],
		});

		expect(registry.isResourceKindAllowed('review', 'content')).toBe(true);
		expect(registry.isPrivilegedMethodAllowed('review', 'review.openStream')).toBe(true);
		expect(registry.allowedResourceKindsByProtocol['review']).toEqual(
			new Set(['content', 'review-package']),
		);
	});

	test('rejects duplicate protocol registrations before runtime use', () => {
		expect(() =>
			createBridgeProtocolRegistry({
				protocols: [
					{
						protocol: 'review',
						resourceKinds: ['content'],
						privilegedMethods: [],
					},
					{
						protocol: 'review',
						resourceKinds: ['review-package'],
						privilegedMethods: [],
					},
				],
			}),
		).toThrow('Duplicate Bridge protocol registration: review');
	});

	test('keeps disabled comments and comms resource kinds unregistered by default', () => {
		const registry = createBridgeProtocolRegistry({
			protocols: [
				{
					protocol: 'review',
					resourceKinds: ['content', 'review-package'],
					privilegedMethods: ['review.openStream'],
				},
				{
					protocol: 'worktree-file',
					resourceKinds: ['tree', 'file-content'],
					privilegedMethods: ['worktree-file.openStream'],
				},
			],
		});

		expect(registry.isResourceKindAllowed('review', 'comment-thread')).toBe(false);
		expect(registry.isResourceKindAllowed('comments', 'thread')).toBe(false);
		expect(registry.isResourceKindAllowed('comms', 'message')).toBe(false);
		expect(registry.isPrivilegedMethodAllowed('comments', 'comments.openStream')).toBe(false);
	});
});
