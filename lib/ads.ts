// Google AdSense for the browser site only. The installed PWA, the Desktop
// shell, the Chrome extension and the native apps never load it: the loader
// lives behind IS_WEB_BUILD and bails out when the page runs as an installed
// app. Auto ads are configured in the AdSense console; the EEA/UK/CH consent
// message is Google's own (Privacy & messaging), served by the same script.
export const ADSENSE_CLIENT_ID = "ca-pub-9912554861143289";
export const ADSENSE_SRC = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT_ID}`;

/**
 * Ads belong on content pages (`/{lang}/{preset|tool|salary|...}`), never on
 * the timer itself (`/{lang}`) or the floating mini timer (`/{lang}/mini`).
 */
export function isAdEligiblePath(pathname: string): boolean {
  const segments = pathname.split("/").filter(Boolean);
  return segments.length >= 2 && segments[1] !== "mini";
}

export interface AdContext {
  pathname: string;
  hostname: string;
  /** Hostname of siteConfig.webAppUrl; previews and localhost never show ads. */
  productionHostname: string;
  installedApp: boolean;
}

export function shouldLoadAds(ctx: AdContext): boolean {
  return (
    !ctx.installedApp &&
    ctx.hostname === ctx.productionHostname &&
    isAdEligiblePath(ctx.pathname)
  );
}
