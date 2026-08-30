import { createHash } from "node:crypto";

export const campaignChannels = ["x", "yt", "c"] as const;

export type CampaignChannel = (typeof campaignChannels)[number];

export interface CampaignIdentity {
  readonly campaignKey: string;
  readonly creativeKey: string;
  readonly variantKey: string;
}

export interface CampaignPlacementDefinition {
  readonly channel: CampaignChannel;
  readonly placementKey: string;
}

export interface CampaignCreativeDefinition extends CampaignIdentity {
  readonly placements: readonly CampaignPlacementDefinition[];
}

export interface CampaignAttributionRoute extends CampaignIdentity {
  readonly channel: CampaignChannel;
  readonly code: string;
  readonly path: string;
  readonly placementKey: string;
}

export interface CampaignAttributionRegistry {
  readonly routes: readonly CampaignAttributionRoute[];
  readonly resolve: (
    channel: CampaignChannel,
    code: string,
  ) => CampaignAttributionRoute | undefined;
}

type CampaignCodeDeriver = (identity: CampaignIdentity) => string;

const campaignCodeLength = 4;
const campaignCodeRadix = 36;
const campaignCodeSpace = campaignCodeRadix ** campaignCodeLength;
const campaignKeyPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

const serializeCampaignIdentity = (identity: CampaignIdentity): string =>
  [identity.campaignKey, identity.creativeKey, identity.variantKey].join("\u001f");

const assertValidRegistryKey = (label: string, key: string): void => {
  if (!campaignKeyPattern.test(key)) {
    throw new Error(`${label} must be a lowercase kebab-case registry key; received ${key}`);
  }
};

export const deriveCampaignCode = (identity: CampaignIdentity): string => {
  const digestPrefix = createHash("sha256")
    .update(serializeCampaignIdentity(identity))
    .digest()
    .readUInt32BE(0);

  return (digestPrefix % campaignCodeSpace)
    .toString(campaignCodeRadix)
    .padStart(campaignCodeLength, "0");
};

export const createCampaignAttributionRegistry = (
  creativeDefinitions: readonly CampaignCreativeDefinition[],
  deriveCode: CampaignCodeDeriver = deriveCampaignCode,
): CampaignAttributionRegistry => {
  const routes: CampaignAttributionRoute[] = [];
  const identityByCode = new Map<string, string>();
  const routeByPath = new Map<string, CampaignAttributionRoute>();
  const creativeIdentities = new Set<string>();

  for (const creativeDefinition of creativeDefinitions) {
    assertValidRegistryKey("campaignKey", creativeDefinition.campaignKey);
    assertValidRegistryKey("creativeKey", creativeDefinition.creativeKey);
    assertValidRegistryKey("variantKey", creativeDefinition.variantKey);

    const serializedIdentity = serializeCampaignIdentity(creativeDefinition);
    if (creativeIdentities.has(serializedIdentity)) {
      throw new Error(`Duplicate campaign creative identity: ${serializedIdentity}`);
    }
    creativeIdentities.add(serializedIdentity);

    const code = deriveCode(creativeDefinition);
    if (!/^[a-z0-9]{4}$/.test(code)) {
      throw new Error(
        `Campaign code must contain exactly four lowercase base36 characters: ${code}`,
      );
    }

    const existingIdentity = identityByCode.get(code);
    if (existingIdentity !== undefined && existingIdentity !== serializedIdentity) {
      throw new Error(
        `Campaign code collision for ${code}: ${existingIdentity} and ${serializedIdentity}`,
      );
    }
    identityByCode.set(code, serializedIdentity);

    const placementChannels = new Set<CampaignChannel>();
    for (const placement of creativeDefinition.placements) {
      assertValidRegistryKey("placementKey", placement.placementKey);
      if (placementChannels.has(placement.channel)) {
        throw new Error(
          `Duplicate ${placement.channel} placement for campaign creative ${serializedIdentity}`,
        );
      }
      placementChannels.add(placement.channel);

      const path = `/${placement.channel}/${code}`;
      const route = Object.freeze({
        campaignKey: creativeDefinition.campaignKey,
        channel: placement.channel,
        code,
        creativeKey: creativeDefinition.creativeKey,
        path,
        placementKey: placement.placementKey,
        variantKey: creativeDefinition.variantKey,
      });
      routes.push(route);
      routeByPath.set(path, route);
    }
  }

  return Object.freeze({
    resolve: (channel: CampaignChannel, code: string): CampaignAttributionRoute | undefined =>
      routeByPath.get(`/${channel}/${code}`),
    routes: Object.freeze(routes),
  });
};

const campaignCreativeDefinitions = [
  {
    campaignKey: "launch-week",
    creativeKey: "launch-overview",
    placements: [
      { channel: "x", placementKey: "post" },
      { channel: "yt", placementKey: "description" },
      { channel: "c", placementKey: "generic-share" },
    ],
    variantKey: "default",
  },
] as const satisfies readonly CampaignCreativeDefinition[];

export const campaignAttributionRegistry = createCampaignAttributionRegistry(
  campaignCreativeDefinitions,
);
