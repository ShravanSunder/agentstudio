import { describe, expect, test } from 'vitest';

import {
	bridgePierreContentDescriptorFileSchema,
	createBridgePierreContentDescriptorFile,
	replaceBridgePierreContentDescriptorFileContents,
} from './bridge-pierre-worker-content-descriptor.js';

describe('Bridge Pierre worker content descriptor files', () => {
	test('round trips a descriptor-backed file request with only line skeleton content on the main side', () => {
		const file = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source:head',
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/Example.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=2',
		});

		const parsedFile = bridgePierreContentDescriptorFileSchema.parse(file);
		const hydratedFile = replaceBridgePierreContentDescriptorFileContents({
			file,
			text: 'struct Example {}\nlet value = 1\n',
		});

		expect(parsedFile.contents).toBe('\n\n\n');
		expect(parsedFile.bridgeContentDescriptor).toEqual({
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			maxBytes: 2048,
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=2',
		});
		expect(hydratedFile).toEqual({
			cacheKey: 'item-source:head',
			contents: 'struct Example {}\nlet value = 1\n',
			name: 'Sources/Example.swift',
		});
	});
});
