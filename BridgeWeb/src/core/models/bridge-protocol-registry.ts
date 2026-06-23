import type { BridgeProtocolId, BridgeResourceKind } from './bridge-core-models.js';

export interface BridgeProtocolRegistration {
	readonly protocol: BridgeProtocolId;
	readonly resourceKinds: readonly BridgeResourceKind[];
	readonly privilegedMethods: readonly string[];
}

export interface BridgeProtocolRegistryProps {
	readonly protocols: readonly BridgeProtocolRegistration[];
}

export interface BridgeAllowedResourceKindsByProtocol {
	readonly [protocol: string]: ReadonlySet<string>;
}

export interface BridgeProtocolRegistry {
	readonly allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol;
	isResourceKindAllowed(protocol: BridgeProtocolId, resourceKind: BridgeResourceKind): boolean;
	isPrivilegedMethodAllowed(protocol: BridgeProtocolId, method: string): boolean;
}

export function createBridgeProtocolRegistry(
	props: BridgeProtocolRegistryProps,
): BridgeProtocolRegistry {
	const resourceKindsByProtocol = new Map<BridgeProtocolId, Set<BridgeResourceKind>>();
	const privilegedMethodsByProtocol = new Map<BridgeProtocolId, Set<string>>();

	for (const registration of props.protocols) {
		if (resourceKindsByProtocol.has(registration.protocol)) {
			throw new Error(`Duplicate Bridge protocol registration: ${registration.protocol}`);
		}
		resourceKindsByProtocol.set(registration.protocol, new Set(registration.resourceKinds));
		privilegedMethodsByProtocol.set(registration.protocol, new Set(registration.privilegedMethods));
	}

	const allowedResourceKindsByProtocol = Object.fromEntries(
		Array.from(resourceKindsByProtocol.entries()).map(([protocol, resourceKinds]) => {
			return [protocol, new Set(resourceKinds)];
		}),
	) satisfies BridgeAllowedResourceKindsByProtocol;

	return {
		allowedResourceKindsByProtocol,
		isResourceKindAllowed(protocol: BridgeProtocolId, resourceKind: BridgeResourceKind): boolean {
			return resourceKindsByProtocol.get(protocol)?.has(resourceKind) ?? false;
		},
		isPrivilegedMethodAllowed(protocol: BridgeProtocolId, method: string): boolean {
			return privilegedMethodsByProtocol.get(protocol)?.has(method) ?? false;
		},
	};
}

export const bridgeDefaultProtocolRegistry = createBridgeProtocolRegistry({
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
