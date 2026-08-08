import path from "path";
import fs from "fs/promises";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";

// 预设页文案。与内容页同样只做中英两版，只在服务端读取。

export interface PresetCopy {
  name: string;
  metaTitle: string;
  metaDescription: string;
  intro: string;
  body: string[];
}

export interface PresetBundle {
  backToApp: string;
  startCta: string;
  scheduleLabel: string;
  perDayLabel: string;
  perWeekLabel: string;
  hoursUnit: string;
  otherPresetsHeading: string;
  items: Record<string, PresetCopy>;
}

export async function getPresetCopy(lang: string): Promise<PresetBundle> {
  const safeLang: ContentLocale = contentLocales.includes(lang as ContentLocale)
    ? (lang as ContentLocale)
    : defaultContentLocale;

  const filePath = path.join(
    process.cwd(),
    "public",
    "locales",
    safeLang,
    "presets.json"
  );
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as PresetBundle;
}
