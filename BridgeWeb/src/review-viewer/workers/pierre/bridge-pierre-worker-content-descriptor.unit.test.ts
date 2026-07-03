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

	test('normalizes unsupported descriptor languages to plaintext before Pierre highlighting', () => {
		const file = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-gitignore:head',
			contentHash: 'sha256:def456',
			contentHashAlgorithm: 'sha256',
			generation: 9,
			lang: 'gitignore',
			lineCount: 2,
			maxBytes: 1024,
			name: '.gitignore',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-gitignore-head?generation=9&revision=1',
		});

		expect(file.lang).toBe('text');
	});

	test('preserves supported descriptor languages used by modified review files', () => {
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-package-json:head',
				contentHash: 'sha256:json',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'json',
				lineCount: 1,
				maxBytes: 1024,
				name: 'package.json',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-package-json-head?generation=1',
			}).lang,
		).toBe('json');
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-release-yml:head',
				contentHash: 'sha256:yml',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'yml',
				lineCount: 1,
				maxBytes: 1024,
				name: '.github/workflows/release.yml',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-release-yml-head?generation=1',
			}).lang,
		).toBe('yml');
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-mise-toml:head',
				contentHash: 'sha256:toml',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'toml',
				lineCount: 1,
				maxBytes: 1024,
				name: '.mise.toml',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-mise-toml-head?generation=1',
			}).lang,
		).toBe('toml');
	});
});
