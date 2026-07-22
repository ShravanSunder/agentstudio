import { z } from 'zod';

const sha256DigestSchema = z
	.object({
		algorithm: z.literal('sha256'),
		digest: z.string().regex(/^[a-f0-9]{64}$/u),
	})
	.strict();
const semanticContentRoleSchema = z.enum(['base', 'head', 'diff', 'file']);

const semanticWindowIdentityInputSchema = z
	.object({
		documentKind: z.enum(['file', 'diff', 'markdown']),
		orderedContentDigests: z
			.array(
				z
					.object({
						role: semanticContentRoleSchema,
						algorithm: z.literal('sha256'),
						digest: z.string().regex(/^[a-f0-9]{64}$/u),
					})
					.strict(),
			)
			.min(1)
			.max(4)
			.refine((digests) => new Set(digests.map((digest) => digest.role)).size === digests.length)
			.readonly(),
		partitionId: z.string().min(1).max(128),
		windowId: z.string().min(1).max(128),
		startLine: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
		endLineExclusive: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
		windowDigest: sha256DigestSchema,
	})
	.strict()
	.refine((identity) => identity.endLineExclusive > identity.startLine, {
		message: 'Bridge semantic window end must follow its start.',
	});

export type BridgeWorkerSemanticWindowIdentityInput = z.input<
	typeof semanticWindowIdentityInputSchema
>;

export interface BridgeWorkerSemanticWindowIdentity {
	readonly semanticDocumentRevision: string;
	readonly documentKind: 'file' | 'diff' | 'markdown';
	readonly partitionId: string;
	readonly windowId: string;
	readonly startLine: number;
	readonly endLineExclusive: number;
	readonly windowDigest: {
		readonly algorithm: 'sha256';
		readonly digest: string;
	};
	readonly windowKey: string;
}

export function createBridgeWorkerSemanticWindowIdentity(
	input: BridgeWorkerSemanticWindowIdentityInput,
): BridgeWorkerSemanticWindowIdentity {
	const identity = semanticWindowIdentityInputSchema.parse(input);
	const semanticDocumentRevision = JSON.stringify([
		'bridge-semantic-document-v1',
		identity.documentKind,
		identity.orderedContentDigests.map((digest) => [digest.role, digest.algorithm, digest.digest]),
	]);
	const windowKey = JSON.stringify([
		'bridge-semantic-window-v1',
		semanticDocumentRevision,
		identity.partitionId,
		identity.windowId,
		identity.startLine,
		identity.endLineExclusive,
		identity.windowDigest.algorithm,
		identity.windowDigest.digest,
	]);

	return Object.freeze({
		semanticDocumentRevision,
		documentKind: identity.documentKind,
		partitionId: identity.partitionId,
		windowId: identity.windowId,
		startLine: identity.startLine,
		endLineExclusive: identity.endLineExclusive,
		windowDigest: Object.freeze({ ...identity.windowDigest }),
		windowKey,
	});
}
