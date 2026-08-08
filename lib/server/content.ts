import path from "path";
import fs from "fs/promises";
import { locales, defaultLocale, type Locale } from "@/i18n-config";

// 内容页（FAQ / how-it-works）的文案。与 translation.json / seo.json 同目录，
// 但只在服务端读取——内容页是纯服务端组件，不需要客户端 i18n。

export interface FaqItem {
  q: string;
  a: string;
}

export interface ContentSection {
  heading: string;
  body: string[];
}

export interface ContentBundle {
  backToApp: string;
  faq: {
    metaTitle: string;
    metaDescription: string;
    heading: string;
    intro: string;
    items: FaqItem[];
  };
  howItWorks: {
    metaTitle: string;
    metaDescription: string;
    heading: string;
    intro: string;
    sections: ContentSection[];
  };
}

function contentPath(lang: string) {
  return path.join(process.cwd(), "public", "locales", lang, "content.json");
}

/**
 * 已备好内容文案的语言。内容页的路由、sitemap 条目都由它驱动，因此在文案
 * 尚未译全的阶段，未就绪的语言直接 404，而不是在该语言的 URL 下渲染英文——
 * 后者会让搜索引擎收录到语言与内容不符的页面。
 * 补齐 content.json 后无需改代码，路由与 sitemap 自动扩展。
 */
export async function getContentLocales(): Promise<Locale[]> {
  const checks = await Promise.all(
    locales.map(async (lang) => {
      try {
        await fs.access(contentPath(lang));
        return lang;
      } catch {
        return null;
      }
    })
  );
  return checks.filter((l): l is Locale => l !== null);
}

export async function getContent(lang: string): Promise<ContentBundle> {
  const safeLang = locales.includes(lang as Locale) ? lang : defaultLocale;
  const raw = await fs.readFile(contentPath(safeLang), "utf8");
  return JSON.parse(raw) as ContentBundle;
}
