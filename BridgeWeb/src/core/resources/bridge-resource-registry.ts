import {
	bridgeAttachedResourceDescriptorSchema,
	type BridgeAttachedResourceDescriptor,
	type BridgeDescriptorRef,
	type BridgeIdentity,
	type BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import {
	parseBridgeCoreResourceUrl,
	type BridgeAllowedResourceKindsByProtocol,
} from './bridge-resource-url.js';

export interface BridgeResourceDescriptorRegistryProps {
	readonly allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol;
}

export type BridgeResourceDescriptorRegisterResult =
	| { readonly ok: true }
	| {
			readonly ok: false;
			readonly reason:
				| 'descriptor_ref_mismatch'
				| 'descriptor_resource_url_mismatch'
				| 'descriptor_schema_invalid'
				| 'unregistered_protocol_or_kind';
	  };

export interface BridgeResourceRegistryResetIdentity {
	readonly paneId: string;
	readonly protocol: string;
	readonly sourceId?: string;
	readonly packageId?: string;
	readonly generation?: number;
	readonly revision?: number;
	readonly streamId?: string;
	readonly cursor?: string;
}

export interface BridgeResourceDescriptorRegistry {
	register(
		attachedDescriptor: BridgeAttachedResourceDescriptor,
	): BridgeResourceDescriptorRegisterResult;
	lookup(ref: BridgeDescriptorRef): BridgeResourceDescriptor | null;
	revoke(ref: BridgeDescriptorRef): void;
	resetIdentity(identity: BridgeResourceRegistryResetIdentity): void;
}

export function createBridgeResourceDescriptorRegistry(
	props: BridgeResourceDescriptorRegistryProps,
): BridgeResourceDescriptorRegistry {
	const descriptorsById = new Map<string, BridgeResourceDescriptor>();
	return {
		register(
			attachedDescriptor: BridgeAttachedResourceDescriptor,
		): BridgeResourceDescriptorRegisterResult {
			const parsedAttachedDescriptor =
				bridgeAttachedResourceDescriptorSchema.safeParse(attachedDescriptor);
			if (!parsedAttachedDescriptor.success) {
				return { ok: false, reason: 'descriptor_schema_invalid' };
			}
			const { ref, descriptor } = parsedAttachedDescriptor.data;
			if (!isRegisteredResourceKind(descriptor, props.allowedResourceKindsByProtocol)) {
				return { ok: false, reason: 'unregistered_protocol_or_kind' };
			}
			if (!descriptorMatchesRef(descriptor, ref)) {
				return { ok: false, reason: 'descriptor_ref_mismatch' };
			}
			if (!descriptorResourceURLMatches(descriptor, props.allowedResourceKindsByProtocol)) {
				return { ok: false, reason: 'descriptor_resource_url_mismatch' };
			}
			descriptorsById.set(descriptor.descriptorId, descriptor);
			return { ok: true };
		},
		lookup(ref: BridgeDescriptorRef): BridgeResourceDescriptor | null {
			const descriptor = descriptorsById.get(ref.descriptorId);
			if (descriptor === undefined || !descriptorMatchesRef(descriptor, ref)) {
				return null;
			}
			return descriptor;
		},
		revoke(ref: BridgeDescriptorRef): void {
			const descriptor = descriptorsById.get(ref.descriptorId);
			if (descriptor !== undefined && descriptorMatchesRef(descriptor, ref)) {
				descriptorsById.delete(ref.descriptorId);
			}
		},
		resetIdentity(identity: BridgeResourceRegistryResetIdentity): void {
			for (const [descriptorId, descriptor] of descriptorsById.entries()) {
				if (identityMatchesResetFilter(descriptor.identity, identity)) {
					descriptorsById.delete(descriptorId);
				}
			}
		},
	};
}

function isRegisteredResourceKind(
	descriptor: BridgeResourceDescriptor,
	allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol,
): boolean {
	return allowedResourceKindsByProtocol[descriptor.protocol]?.has(descriptor.resourceKind) ?? false;
}

function descriptorMatchesRef(
	descriptor: BridgeResourceDescriptor,
	ref: BridgeDescriptorRef,
): boolean {
	return (
		descriptor.descriptorId === ref.descriptorId &&
		descriptor.protocol === ref.expectedProtocol &&
		descriptor.resourceKind === ref.expectedResourceKind &&
		identityMatches(descriptor.identity, ref.expectedIdentity)
	);
}

function descriptorResourceURLMatches(
	descriptor: BridgeResourceDescriptor,
	allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol,
): boolean {
	const parsedResourceURL = parseBridgeCoreResourceUrl(descriptor.resourceUrl, {
		allowedResourceKindsByProtocol,
	});
	if (parsedResourceURL === null) {
		return false;
	}
	return (
		parsedResourceURL.protocol === descriptor.protocol &&
		parsedResourceURL.resourceKind === descriptor.resourceKind &&
		parsedResourceURL.generation === descriptor.identity.generation &&
		parsedResourceURL.revision === descriptor.identity.revision &&
		parsedResourceURL.cursor === descriptor.identity.cursor
	);
}

function identityMatches(left: BridgeIdentity, right: BridgeIdentity): boolean {
	return (
		left.paneId === right.paneId &&
		left.protocol === right.protocol &&
		left.sourceId === right.sourceId &&
		left.packageId === right.packageId &&
		left.generation === right.generation &&
		left.revision === right.revision &&
		left.streamId === right.streamId &&
		left.cursor === right.cursor
	);
}

function identityMatchesResetFilter(
	identity: BridgeIdentity,
	resetIdentity: BridgeResourceRegistryResetIdentity,
): boolean {
	return (
		identity.paneId === resetIdentity.paneId &&
		identity.protocol === resetIdentity.protocol &&
		(resetIdentity.sourceId === undefined || identity.sourceId === resetIdentity.sourceId) &&
		(resetIdentity.packageId === undefined || identity.packageId === resetIdentity.packageId) &&
		(resetIdentity.generation === undefined || identity.generation === resetIdentity.generation) &&
		(resetIdentity.revision === undefined || identity.revision === resetIdentity.revision) &&
		(resetIdentity.streamId === undefined || identity.streamId === resetIdentity.streamId) &&
		(resetIdentity.cursor === undefined || identity.cursor === resetIdentity.cursor)
	);
}
