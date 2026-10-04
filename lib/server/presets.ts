import path from "path";
import fs from "fs/promises";
import {
  presetLocales,
  defaultPresetLocale,
  type PresetLocale,
} from "@/lib/content-locales";

// 预设页文案。支持所有 19 种 UI 语言，只在服务端读取。

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
  iosCta: string;
  webBoundary: string;
  scheduleLabel: string;
  perDayLabel: string;
  perWeekLabel: string;
  hoursUnit: string;
  otherPresetsHeading: string;
  breakTableHeading: string;
  breakTableBreak: string;
  breakNone: string;
  breakMinutes: string;
  calculatorLink: string;
  items: Record<string, PresetCopy>;
}

export async function getPresetCopy(lang: string): Promise<PresetBundle> {
  const safeLang: PresetLocale = presetLocales.includes(lang as PresetLocale)
    ? (lang as PresetLocale)
    : defaultPresetLocale;

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
