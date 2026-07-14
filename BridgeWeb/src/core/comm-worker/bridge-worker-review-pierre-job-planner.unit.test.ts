import { describe, expect, test } from 'vitest';

import type { BridgeWorkerReviewRenderSemantics } from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	planBridgeWorkerReviewPierreRenderJob,
	prepareBridgeWorkerReviewPierreRenderJobEvent,
} from './bridge-worker-review-pierre-job-planner.js';

describe('Bridge worker review Pierre job planner', () => {
	test('plans modified review diffs as worker-prepared CodeView items', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 2,
					role: 'base',
					text: 'export const before = 1;\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					language: 'typescript',
					lineCount: 2,
					role: 'head',
					text: 'export const after = 2;\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 2, head: 2 },
				itemKind: 'diff',
				language: 'typescript',
			}),
		});

		expect(job?.payload.kind).toBe('codeViewDiffItem');
		if (job?.payload.kind === 'codeViewDiffItem') {
			expect(job.payload.item).toMatchObject({
				id: 'item-1',
				type: 'diff',
				bridgeMetadata: {
					contentState: 'hydrated',
					contentRoles: ['base', 'head'],
					displayPath: 'Sources/App/View.swift',
				},
			});
			expect(job.payload.item.fileDiff.additionLines).toContain('export const after = 2;\n');
			expect(job.payload.item.fileDiff.deletionLines).toContain('export const before = 1;\n');
			expect(job.payload.item.fileDiff.cacheKey).toContain(
				'pierre-content:fixture-preview:sha256:item-1:head',
			);
		}
	});

	test('plans modified review diffs from base and head content windows', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 120,
					role: 'base',
					text: 'let before = 1;\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					language: 'typescript',
					lineCount: 80,
					role: 'head',
					text: 'let after = 2;\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 120, head: 80 },
				itemKind: 'diff',
			}),
		});

		expect(job).toMatchObject({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey:
				'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
			contentHash: 'sha256:item-1:base|sha256:item-1:head',
			language: 'typescript',
			window: {
				startLine: 1,
				endLine: 50,
				totalLineCount: 120,
			},
			windowLineCount: 50,
		});
		expect(job?.payload.kind).toBe('codeViewDiffItem');
		if (job?.payload.kind === 'codeViewDiffItem') {
			expect(job.payloadByteLength).toBeGreaterThan(0);
			expect(job.payload.item.fileDiff.additionLines).toContain('let after = 2;\n');
			expect(job.payload.item.fileDiff.deletionLines).toContain('let before = 1;\n');
		}
	});

	test('windows multiline review diffs before preparing CodeView payloads', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 2,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 4,
					role: 'base',
					text: 'line 1\nline 2\nline 3\nline 4\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					lineCount: 4,
					role: 'head',
					text: 'line 1\nline two\nline 3 changed\nline 4 changed\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 4, head: 4 },
				itemKind: 'diff',
			}),
		});

		expect(job?.window).toMatchObject({
			startLine: 1,
			endLine: 2,
			totalLineCount: 4,
		});
		expect(job?.payload.kind).toBe('codeViewDiffItem');
		if (job?.payload.kind === 'codeViewDiffItem') {
			expect(job.payload.item.bridgeMetadata.contentState).toBe('windowed');
			expect(job.payload.item.fileDiff.additionLines).toContain('line two\n');
			expect(job.payload.item.fileDiff.additionLines).not.toContain('line 3 changed\n');
			expect(job.payload.item.fileDiff.deletionLines).toContain('line 2\n');
			expect(job.payload.item.fileDiff.deletionLines).not.toContain('line 3\n');
		}
	});

	test('rejects oversized diff windows before preparing CodeView payloads', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 16,
				maxWindowLines: 2,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 2,
					role: 'base',
					text: 'base line with too many bytes\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					lineCount: 2,
					role: 'head',
					text: 'head line with too many bytes\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 2, head: 2 },
				itemKind: 'diff',
			}),
		});

		expect(job).toBeNull();
	});

	test('does not plan modified review diffs until both sides are fetched', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					role: 'base',
					textBytes: new ArrayBuffer(32),
				}),
			],
			semantics: makeRenderSemantics({
				itemKind: 'diff',
			}),
		});

		expect(job).toBeNull();
	});

	test('plans one-sided added review diffs from the head side only', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 100,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					lineCount: 33,
					role: 'head',
					text: 'let added = true;\n',
				}),
			],
			semantics: makeRenderSemantics({
				changeKind: 'added',
				contentLineCountsByRole: { head: 33 },
				itemKind: 'file',
			}),
		});

		expect(job).toMatchObject({
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:empty|pierre-content:fixture-preview:sha256:item-1:head',
			contentHash: 'empty|sha256:item-1:head',
			language: 'swift',
			windowLineCount: 33,
		});
		expect(job?.payload.kind).toBe('codeViewDiffItem');
		if (job?.payload.kind === 'codeViewDiffItem') {
			expect(job.payloadByteLength).toBeGreaterThan(0);
			expect(job.payload.item.fileDiff.additionLines).toContain('let added = true;\n');
			expect(job.payload.item.bridgeMetadata.contentRoles).toEqual(['head']);
		}
	});

	test('derives the bounded Review window from fetched text when metadata omits extent facts', () => {
		const fetchedText =
			[
				'---',
				'name: agentstudio-bridgeweb-react-ui',
				'description: BridgeWeb React UI guidance',
				'---',
				'',
				'# Agent Studio BridgeWeb React UI',
				'',
				'BridgeWeb React UI uses shared owned primitives.',
			].join('\n') + '\n';
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					text: fetchedText,
				}),
			],
			semantics: makeRenderSemantics({
				basePath: null,
				changeKind: 'added',
				contentLineCountsByRole: {},
				displayPath: '.codex/skills/agentstudio-bridgeweb-react-ui/SKILL.md',
				headPath: '.codex/skills/agentstudio-bridgeweb-react-ui/SKILL.md',
				itemKind: 'file',
				language: 'markdown',
			}),
		});

		expect(job?.window).toEqual({
			startLine: 1,
			endLine: 8,
			totalLineCount: 8,
		});
		expect(job?.payload.kind).toBe('codeViewDiffItem');
		if (job?.payload.kind === 'codeViewDiffItem') {
			expect(job.payload.item.fileDiff.additionLines.join('')).toContain(
				'# Agent Studio BridgeWeb React UI',
			);
			expect(job.payload.item.fileDiff.additionLines).toHaveLength(8);
		}
	});

	test('plans file text jobs from a single preferred resource and language fallback', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					language: null,
					lineCount: 45,
					role: 'file',
					text: 'plain file content\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { file: 45 },
				itemKind: 'file',
				language: null,
			}),
		});

		expect(job).toMatchObject({
			renderKind: 'fileText',
			contentCacheKey: 'pierre-content:fixture-preview:sha256:item-1:file',
			contentHash: 'sha256:item-1:file',
			language: 'text',
			windowLineCount: 45,
		});
		expect(job?.payload.kind).toBe('codeViewFileItem');
		if (job?.payload.kind === 'codeViewFileItem') {
			expect(job.payloadByteLength).toBe(
				new TextEncoder().encode('plain file content\n').byteLength,
			);
			expect(job.payload.item.file.contents).toBe('plain file content\n');
			expect(job.payload.item.bridgeMetadata.contentRoles).toEqual(['file']);
		}
	});

	test('windows multiline file text before preparing CodeView payloads', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 512 * 1024,
				maxWindowLines: 2,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					lineCount: 4,
					role: 'file',
					text: 'file line 1\nfile line 2\nfile line 3\nfile line 4\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { file: 4 },
				itemKind: 'file',
			}),
		});

		expect(job?.window).toMatchObject({
			startLine: 1,
			endLine: 2,
			totalLineCount: 4,
		});
		expect(job?.payload.kind).toBe('codeViewFileItem');
		if (job?.payload.kind === 'codeViewFileItem') {
			expect(job.payload.item.bridgeMetadata.contentState).toBe('windowed');
			expect(job.payload.item.bridgeMetadata.lineCount).toBe(4);
			expect(job.payload.item.file.contents).toBe('file line 1\nfile line 2\n');
		}
	});

	test('rejects oversized file windows before preparing CodeView payloads', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 16,
				maxWindowLines: 2,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					lineCount: 2,
					role: 'file',
					text: 'file line with too many bytes\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { file: 2 },
				itemKind: 'file',
			}),
		});

		expect(job).toBeNull();
	});

	test('prepares review diff render job events as structured CodeView payloads', () => {
		const prepared = prepareBridgeWorkerReviewPierreRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			publicationSequence: 11,
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 120,
					role: 'base',
					text: 'let before = 1;\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					language: 'typescript',
					lineCount: 80,
					role: 'head',
					text: 'let after = 2;\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 120, head: 80 },
				itemKind: 'diff',
			}),
			workerDerivationEpoch: 7,
		});

		expect(prepared?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'reviewPierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		expect(prepared?.message.transferDescriptors).toEqual([
			{
				messageKind: 'reviewPierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: prepared?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(prepared?.transferList).toEqual([]);
	});

	test('prepares one-sided review diff render job events with clone descriptors', () => {
		const prepared = prepareBridgeWorkerReviewPierreRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 100,
			},
			publicationSequence: 11,
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					lineCount: 33,
					role: 'head',
					text: 'let added = true;\n',
				}),
			],
			semantics: makeRenderSemantics({
				changeKind: 'added',
				contentLineCountsByRole: { head: 33 },
				itemKind: 'file',
			}),
			workerDerivationEpoch: 7,
		});

		expect(prepared?.message.job.payload.kind).toBe('codeViewDiffItem');
		expect(prepared?.message.transferDescriptors).toEqual([
			{
				messageKind: 'reviewPierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: prepared?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(prepared?.transferList).toEqual([]);
	});

	test('prepares file text render job events with clone descriptors', () => {
		const prepared = prepareBridgeWorkerReviewPierreRenderJobEvent({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			publicationSequence: 11,
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					language: null,
					lineCount: 45,
					role: 'file',
					text: 'plain file content\n',
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { file: 45 },
				itemKind: 'file',
				language: null,
			}),
			workerDerivationEpoch: 7,
		});

		expect(prepared?.message.job.payload.kind).toBe('codeViewFileItem');
		expect(prepared?.message.transferDescriptors).toEqual([
			{
				messageKind: 'reviewPierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: prepared?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(prepared?.transferList).toEqual([]);
	});

	test('does not prepare render job events when the planner has no complete job', () => {
		const prepared = prepareBridgeWorkerReviewPierreRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			publicationSequence: 11,
			resources: [
				makeFetchedReviewContentResource({
					role: 'base',
					textBytes: new ArrayBuffer(32),
				}),
			],
			semantics: makeRenderSemantics({
				itemKind: 'diff',
			}),
			workerDerivationEpoch: 7,
		});

		expect(prepared).toBeNull();
	});
});

function makeRenderSemantics(
	overrides: Partial<BridgeWorkerReviewRenderSemantics> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/View.swift',
		basePath: 'Sources/App/View.swift',
		headPath: 'Sources/App/View.swift',
		language: 'swift',
		contentLineCountsByRole: {},
		...overrides,
	};
}

function makeFetchedReviewContentResource(props: {
	readonly contentHash?: string;
	readonly language?: string | null;
	readonly lineCount?: number;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text?: string;
	readonly textBytes?: ArrayBuffer;
}): BridgeWorkerFetchedReviewContentResource {
	const text = props.text ?? '';
	const textBytes = props.textBytes ?? new TextEncoder().encode(text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash ?? `sha256:item-1:${props.role}`,
		contentHashAlgorithm: 'fixture-preview',
		language: props.language === undefined ? 'swift' : props.language,
		byteLength: textBytes.byteLength,
		text,
		textBytes,
	};
}
