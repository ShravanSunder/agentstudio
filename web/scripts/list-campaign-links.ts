import {
  campaignAttributionRegistry,
  campaignChannels,
} from "../src/campaign-attribution/campaign-attribution-registry.ts";
import { siteMetadata } from "../src/site-metadata.ts";

for (const channel of campaignChannels) {
  console.log(new URL(`/${channel}`, siteMetadata.canonicalOrigin).href);
}

for (const route of campaignAttributionRegistry.routes) {
  const campaignUrl = new URL(route.path, siteMetadata.canonicalOrigin).href;
  console.log(
    [
      campaignUrl,
      `campaign=${route.campaignKey}`,
      `creative=${route.creativeKey}`,
      `variant=${route.variantKey}`,
      `placement=${route.placementKey}`,
    ].join("\t"),
  );
}
