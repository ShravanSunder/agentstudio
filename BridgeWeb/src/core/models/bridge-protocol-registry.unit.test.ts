import { describe, expect, test } from 'vitest';

import {
	bridgeDefaultProtocolRegistry,
	createBridgeProtocolRegistry,
} from './bridge-protocol-registry.js';

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
		expect(bridgeDefaultProtocolRegistry.isResourceKindAllowed('review', 'comment-thread')).toBe(
			false,
		);
		expect(bridgeDefaultProtocolRegistry.isResourceKindAllowed('comments', 'thread')).toBe(false);
		expect(bridgeDefaultProtocolRegistry.isResourceKindAllowed('comms', 'message')).toBe(false);
		expect(
			bridgeDefaultProtocolRegistry.isPrivilegedMethodAllowed('comments', 'comments.openStream'),
		).toBe(false);
	});
});
