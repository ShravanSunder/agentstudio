import { z } from 'zod';

import {
	bridgeProductDisplayPathSchema,
	bridgeProductDocumentLocationSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductFileSourceIdentitySchema } from './bridge-product-file-contracts.js';

export const BRIDGE_PRODUCT_MAXIMUM_FILE_COLLECTION_MEMBER_GROUP_COUNT = 256;
export const BRIDGE_PRODUCT_MAXIMUM_FILE_COLLECTION_OPENED_DOCUMENT_COUNT = 4096;

/**
 * One member worktree of a receiver's Files collection and the group path its
 * files are listed under. A member-relative path inside one of
 * `nestedMemberRelativeRoots` belongs to that deeper member's group instead.
 * `identityPrefix` namespaces the member's descriptor identities in the
 * collection.
 */
export const bridgeProductFileMemberGroupSchema = z
	.object({
		groupPath: bridgeProductDisplayPathSchema,
		identityPrefix: bridgeProductIdentifierSchema,
		nestedMemberRelativeRoots: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_FILE_COLLECTION_MEMBER_GROUP_COUNT)
			.readonly(),
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict();

export type BridgeProductFileMemberGroup = z.infer<typeof bridgeProductFileMemberGroupSchema>;

export const bridgeProductFileMemberGroupListSchema = z
	.array(bridgeProductFileMemberGroupSchema)
	.max(BRIDGE_PRODUCT_MAXIMUM_FILE_COLLECTION_MEMBER_GROUP_COUNT)
	.readonly()
	.superRefine((groups, context): void => {
		if (
			new Set(groups.map((group) => group.worktreeId)).size !== groups.length ||
			new Set(groups.map((group) => group.groupPath)).size !== groups.length
		) {
			context.addIssue({
				code: 'custom',
				message: 'File member groups must name each worktree and group path once.',
			});
		}
	});

/**
 * One opened document outside every member worktree. `documentLocation` is the
 * identity its local annotations are recorded under; `displayPath` is the key
 * the collection lists it by.
 */
export const bridgeProductFileOpenedDocumentEntrySchema = z
	.object({
		displayPath: bridgeProductDisplayPathSchema,
		documentLocation: bridgeProductDocumentLocationSchema,
		identityPrefix: bridgeProductIdentifierSchema,
	})
	.strict();

export type BridgeProductFileOpenedDocumentEntry = z.infer<
	typeof bridgeProductFileOpenedDocumentEntrySchema
>;

export const bridgeProductFileOpenedDocumentListSchema = z
	.array(bridgeProductFileOpenedDocumentEntrySchema)
	.max(BRIDGE_PRODUCT_MAXIMUM_FILE_COLLECTION_OPENED_DOCUMENT_COUNT)
	.readonly()
	.superRefine((documents, context): void => {
		if (
			new Set(documents.map((document) => document.documentLocation)).size !== documents.length ||
			new Set(documents.map((document) => document.displayPath)).size !== documents.length
		) {
			context.addIssue({
				code: 'custom',
				message: 'File opened documents must name each location and display path once.',
			});
		}
	});

/**
 * The complete member-group list; it replaces the previous list. The opened
 * documents outside every member ride along so local-file annotations can be
 * placed under their document's key. `source` and
 * `membershipRevision` order the lists, so a list from a superseded source or
 * an older membership never replaces a newer one.
 */
export const bridgeProductFileMemberGroupsEventSchema = z
	.object({
		eventKind: z.literal('file.memberGroups'),
		groups: bridgeProductFileMemberGroupListSchema,
		membershipRevision: bridgeProductNonnegativeSequenceSchema,
		openedDocuments: bridgeProductFileOpenedDocumentListSchema,
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict();
