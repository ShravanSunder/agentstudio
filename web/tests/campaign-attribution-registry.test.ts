import { describe, expect, it } from "vitest";

import {
  campaignAttributionRegistry,
  campaignChannels,
  createCampaignAttributionRegistry,
  deriveCampaignCode,
  type CampaignCreativeDefinition,
} from "../src/campaign-attribution/campaign-attribution-registry";

const collisionDefinitions = [
  {
    campaignKey: "first-campaign",
    creativeKey: "first-creative",
    placements: [{ channel: "x", placementKey: "post" }],
    variantKey: "default",
  },
  {
    campaignKey: "second-campaign",
    creativeKey: "second-creative",
    placements: [{ channel: "yt", placementKey: "description" }],
    variantKey: "default",
  },
] as const satisfies readonly CampaignCreativeDefinition[];

describe("campaign attribution registry", () => {
  it("derives one stable four-character code for a creative across channels", (): void => {
    const campaignIdentity = {
      campaignKey: "launch-week",
      creativeKey: "launch-overview",
      variantKey: "default",
    } as const;

    expect(deriveCampaignCode(campaignIdentity)).toBe("73uz");

    const launchRoutes = campaignAttributionRegistry.routes.filter(
      (route) => route.campaignKey === campaignIdentity.campaignKey,
    );
    expect(launchRoutes.map((route) => route.channel)).toEqual(campaignChannels);
    expect(new Set(launchRoutes.map((route) => route.code))).toEqual(
      new Set([deriveCampaignCode(campaignIdentity)]),
    );
  });

  it("resolves every registered route back to bounded marketing dimensions", (): void => {
    for (const route of campaignAttributionRegistry.routes) {
      expect(campaignAttributionRegistry.resolve(route.channel, route.code)).toEqual(route);
      expect(route.path).toBe(`/${route.channel}/${route.code}`);
      expect(route.campaignKey).toBeTruthy();
      expect(route.creativeKey).toBeTruthy();
      expect(route.variantKey).toBeTruthy();
      expect(route.placementKey).toBeTruthy();
    }
  });

  it("rejects code collisions instead of merging unrelated creative identities", (): void => {
    expect(() =>
      createCampaignAttributionRegistry(collisionDefinitions, (): string => "same"),
    ).toThrow(/collision/i);
  });

  it("rejects duplicate creative identities", (): void => {
    expect(() =>
      createCampaignAttributionRegistry([
        collisionDefinitions[0],
        {
          ...collisionDefinitions[0],
          placements: [{ channel: "c", placementKey: "generic-share" }],
        },
      ]),
    ).toThrow(/duplicate campaign creative identity/i);
  });

  it("does not resolve an unknown short code", (): void => {
    expect(campaignAttributionRegistry.resolve("x", "zzzz")).toBeUndefined();
  });
});
