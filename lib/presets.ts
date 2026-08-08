import type { Shift } from "@/lib/share";

// 常见班次的预设。这里只放数据（班次时间、每周天数），本地化文案在
// public/locales/{lang}/presets.json —— 时间是事实，不需要翻译。
//
// 预设页与内容页一样只做中英两版（见 lib/content-locales.ts）。若把这些页面
// 铺到 19 种语言，每页又只是同一个应用换个默认时间，就会产生大量近似重复的
// 页面，容易被判定为为搜索引擎批量生成的门页。控制在两种语言、每页配一段
// 真实的说明，才站得住。

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
