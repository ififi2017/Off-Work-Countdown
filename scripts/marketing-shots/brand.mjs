// DoneAt store-art tokens. Same numbers as doneat-site/site.json —
// keep them here so the shot pipeline does not reach across repos.

import { readFileSync } from "node:fs";

export const BRAND = {
  name: "DoneAt",
  orange: "#F45A1E",
  orangeBright: "#FF9A45",
  orangeDeep: "#F05218",
  orangeInk: "#C2410C",
  cream: "#FFF1D8",
  plum: "#2B1935",
  eveningStart: "#3B2048",
  eveningEnd: "#1D1329",
};

const MARK_PATH = new URL("../../assets/brand/off-work-countdown-mark.svg", import.meta.url);

export function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function fontStack(language) {
  const cjk = language === "zh-CN" || language === "zh" ? '"PingFang SC", ' : "";
  return `${cjk}-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif`;
}

/** Official Open Day mark from assets/brand. Only the hands swap for dark canvases. */
export function brandMark(hands = BRAND.plum) {
  let svg = readFileSync(MARK_PATH, "utf8");
  if (hands.toUpperCase() !== BRAND.plum.toUpperCase()) {
    svg = svg.replaceAll(BRAND.plum, hands);
  }
  return svg.replace("<svg", '<svg class="mark" aria-hidden="true"');
}
