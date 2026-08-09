import path from "path";
import fs from "fs/promises";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";

// 内容页（FAQ / how-it-works / about）的文案。与 translation.json / seo.json 同目录，
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
  about: {
    metaTitle: string;
    metaDescription: string;
    heading: string;
    intro: string;
    sections: ContentSection[];
  };
}

export async function getContent(lang: string): Promise<ContentBundle> {
  const safeLang: ContentLocale = contentLocales.includes(lang as ContentLocale)
    ? (lang as ContentLocale)
    : defaultContentLocale;

  const filePath = path.join(
    process.cwd(),
    "public",
    "locales",
    safeLang,
    "content.json"
  );
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw) as ContentBundle;
}
