import type { Shift } from "@/lib/share";

// 常见班次的预设。这里只放数据（班次时间、每周天数），本地化文案在
// public/locales/{lang}/presets.json —— 时间是事实，不需要翻译。
//
// 预设页支持全部 19 种 UI 语言（见 lib/content-locales.ts 的 presetLocales）。
// 每种语言都有经过人工校对的翻译，每个预设配一段真实的说明文案。

export interface Preset {
  slug: string;
  shift: Shift;
  /** 每周工作天数，用于推算周工时。 */
  daysPerWeek: number;
}

export const presets: Preset[] = [
  { slug: "996", shift: { start: "09:00", end: "21:00" }, daysPerWeek: 6 },
  { slug: "9-to-5", shift: { start: "09:00", end: "17:00" }, daysPerWeek: 5 },
  { slug: "9-to-6", shift: { start: "09:00", end: "18:00" }, daysPerWeek: 5 },
  { slug: "night-shift", shift: { start: "22:00", end: "06:00" }, daysPerWeek: 5 },
];

export const presetSlugs = presets.map((p) => p.slug);

export function getPreset(slug: string): Preset | undefined {
  return presets.find((p) => p.slug === slug);
}
