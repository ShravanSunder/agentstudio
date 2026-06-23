import { describe, expect, test } from 'vitest';

import {
	bridgeAttachedResourceDescriptorSchema,
	bridgeDescriptorRefSchema,
	bridgeResourceDescriptorSchema,
} from '../models/bridge-resource-descriptor.js';

describe('bridge resource descriptor models', () => {
	test('parses descriptor refs and attached resource descriptors', () => {
		const descriptor = bridgeResourceDescriptorSchema.parse(makeDescriptor());
		const ref = bridgeDescriptorRefSchema.parse({
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		});
		const attachedDescriptor = bridgeAttachedResourceDescriptorSchema.parse({
			ref,
			descriptor,
		});

		expect(attachedDescriptor.ref.descriptorId).toBe('descriptor-1');
		expect(attachedDescriptor.descriptor.content.integrity).toEqual({
			algorithm: 'sha256',
			value: 'sha256:abc123',
		});
	});

	test('rejects malformed descriptors before registry insertion', () => {
		const invalidDescriptor = {
			...makeDescriptor(),
			content: {
				mediaType: 'text/plain',
				maxBytes: 0,
			},
		};

		expect(bridgeResourceDescriptorSchema.safeParse(invalidDescriptor).success).toBe(false);
	});
});

type JsonRecord = Readonly<Record<string, unknown>>;

function makeDescriptor(): JsonRecord {
	return {
		descriptorId: 'descriptor-1',
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl:
			'agentstudio://resource/review/content/content-123?generation=2&revision=4&cursor=cursor_abc-1',
		identity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 2,
			revision: 4,
			streamId: 'stream-1',
			cursor: 'cursor_abc-1',
		},
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
			integrity: {
				algorithm: 'sha256',
				value: 'sha256:abc123',
			},
		},
		window: {
			start: 0,
			count: 10,
			maxCount: 100,
		},
	};
}
