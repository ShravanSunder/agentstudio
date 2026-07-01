import { describe, expect, test } from 'vitest';

import {
	bridgeAttachedResourceDescriptorSchema,
	type BridgeAttachedResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from './bridge-resource-registry.js';
import type { BridgeAllowedResourceKindsByProtocol } from './bridge-resource-url.js';

describe('bridge resource descriptor registry', () => {
	const allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol = {
		review: new Set(['content']),
		'worktree-file': new Set(['worktree.fileContent', 'worktree.fileRange']),
	};

	test('registers attached descriptors before demand lookup by descriptor ref', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor();

		const registerResult = registry.register(attachedDescriptor);
		const lookupResult = registry.lookup(attachedDescriptor.ref);

		expect(registerResult).toEqual({ ok: true });
		expect(lookupResult?.descriptorId).toBe('descriptor-1');
	});

	test('rejects unregistered protocol and resource kind pairs', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor({
			protocol: 'comments',
			resourceKind: 'comment-thread',
		});

		const registerResult = registry.register(attachedDescriptor);

		expect(registerResult).toEqual({
			ok: false,
			reason: 'unregistered_protocol_or_kind',
		});
		expect(registry.lookup(attachedDescriptor.ref)).toBeNull();
	});

	test('rejects descriptor resource URLs that do not match the attached ref identity', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor({
			resourceUrl:
				'agentstudio://resource/review/content/descriptor-1?generation=2&revision=5&cursor=cursor_abc-1',
		});

		const registerResult = registry.register(attachedDescriptor);

		expect(registerResult).toEqual({
			ok: false,
			reason: 'descriptor_resource_url_mismatch',
		});
		expect(registry.lookup(attachedDescriptor.ref)).toBeNull();
	});

	test('rejects descriptor resource URLs that use a different opaque resource id', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor({
			resourceUrl:
				'agentstudio://resource/review/content/content-123?generation=2&revision=4&cursor=cursor_abc-1',
		});

		const registerResult = registry.register(attachedDescriptor);

		expect(registerResult).toEqual({
			ok: false,
			reason: 'descriptor_resource_url_mismatch',
		});
		expect(registry.lookup(attachedDescriptor.ref)).toBeNull();
	});

	test('rejects lookup refs whose identity does not match the registered descriptor', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor();
		registry.register(attachedDescriptor);

		const lookupResult = registry.lookup({
			...attachedDescriptor.ref,
			expectedIdentity: {
				...attachedDescriptor.ref.expectedIdentity,
				revision: 5,
			},
		});

		expect(lookupResult).toBeNull();
	});

	test('revokes descriptor refs after explicit cancellation', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor();
		expect(registry.register(attachedDescriptor)).toEqual({ ok: true });

		registry.revoke(attachedDescriptor.ref);

		expect(registry.lookup(attachedDescriptor.ref)).toBeNull();
	});

	test('resets descriptors for a stale stream lineage', () => {
		const registry = createBridgeResourceDescriptorRegistry({ allowedResourceKindsByProtocol });
		const attachedDescriptor = makeAttachedDescriptor();
		expect(registry.register(attachedDescriptor)).toEqual({ ok: true });

		registry.resetIdentity({
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			streamId: 'stream-1',
		});

		expect(registry.lookup(attachedDescriptor.ref)).toBeNull();
	});
});

interface MakeAttachedDescriptorProps {
	readonly protocol?: string;
	readonly resourceKind?: string;
	readonly resourceUrl?: string;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps = {},
): BridgeAttachedResourceDescriptor {
	const protocol = props.protocol ?? 'review';
	const resourceKind = props.resourceKind ?? 'content';
	const identity = {
		paneId: 'pane-1',
		protocol,
		sourceId: 'source-1',
		packageId: 'package-1',
		generation: 2,
		revision: 4,
		streamId: 'stream-1',
		cursor: 'cursor_abc-1',
	};
	const descriptor = {
		descriptorId: 'descriptor-1',
		protocol,
		resourceKind,
		resourceUrl:
			props.resourceUrl ??
			'agentstudio://resource/review/content/descriptor-1?generation=2&revision=4&cursor=cursor_abc-1',
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
		},
	};
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
}
