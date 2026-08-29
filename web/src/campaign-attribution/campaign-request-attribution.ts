import {
  campaignAttributionRegistry,
  campaignChannels,
  type CampaignAttributionRoute,
  type CampaignChannel,
} from "./campaign-attribution-registry.ts";

export const campaignRequestDatasetName = "agent_studio_campaign_requests";
export const aggregateCampaignDimension = "__channel_aggregate__";

export type CampaignRequestRoute =
  | { readonly kind: "creative"; readonly route: CampaignAttributionRoute }
  | { readonly kind: "channel-aggregate"; readonly channel: CampaignChannel; readonly path: string }
  | { readonly kind: "unknown" };

export interface CampaignRequestDataPoint {
  readonly indexes: [string];
  readonly blobs: [
    "creative" | "channel-aggregate",
    CampaignChannel,
    string,
    string,
    string,
    string,
  ];
  readonly doubles: [1];
}

const aggregatePathSet = new Set<string>(campaignChannels.map((channel) => `/${channel}`));

export const resolveCampaignRequestRoute = (pathname: string): CampaignRequestRoute => {
  const creativeRoute = campaignAttributionRegistry.routes.find((route) => route.path === pathname);
  if (creativeRoute !== undefined) {
    return { kind: "creative", route: creativeRoute };
  }

  if (aggregatePathSet.has(pathname)) {
    const channel = campaignChannels.find((candidate) => `/${candidate}` === pathname);
    if (channel !== undefined) {
      return { channel, kind: "channel-aggregate", path: pathname };
    }
  }

  return { kind: "unknown" };
};

export const createCampaignRequestDataPoint = (
  route: Exclude<CampaignRequestRoute, { readonly kind: "unknown" }>,
): CampaignRequestDataPoint => {
  if (route.kind === "creative") {
    return {
      blobs: [
        "creative",
        route.route.channel,
        route.route.campaignKey,
        route.route.creativeKey,
        route.route.variantKey,
        route.route.placementKey,
      ],
      doubles: [1],
      indexes: [route.route.path],
    };
  }

  return {
    blobs: [
      "channel-aggregate",
      route.channel,
      aggregateCampaignDimension,
      aggregateCampaignDimension,
      aggregateCampaignDimension,
      aggregateCampaignDimension,
    ],
    doubles: [1],
    indexes: [route.path],
  };
};

export const isCampaignRequestEligible = (
  request: Request,
  route: CampaignRequestRoute,
  response: Response,
): route is Exclude<CampaignRequestRoute, { readonly kind: "unknown" }> =>
  request.method === "GET" && route.kind !== "unknown" && response.status === 200;
