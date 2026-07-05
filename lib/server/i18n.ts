import path from "path";
import fs from "fs/promises";
import { defaultLocale, locales, Locale } from "@/i18n-config";

export async function getTranslations(lang: string, ns: string) {
  // 白名单校验，防止路径遍历
  if (!locales.includes(lang as Locale)) {
    lang = defaultLocale;
  }

  try {
    const filePath = path.join(
      process.cwd(),
      "public",
      "locales",
      lang,
      `${ns}.json`
    );
    const content = await fs.readFile(filePath, "utf8");
    return JSON.parse(content);
  } catch (error) {
    console.error(`Failed to load translations for ${lang}/${ns}:`, error);
    // 如果找不到翻译文件，返回英文翻译
    const enFilePath = path.join(
      process.cwd(),
      "public",
      "locales",
      "en",
      `${ns}.json`
    );
    const enContent = await fs.readFile(enFilePath, "utf8");
    return JSON.parse(enContent);
  }
}
