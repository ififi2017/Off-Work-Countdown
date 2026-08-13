import path from "path";
import fs from "fs/promises";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";

// 内容页（FAQ / how-it-works / about / download）的文案。与 translation.json / seo.json 同目录，
// 但只在服务端读取——内容页是纯服务端组件，不需要客户端 i18n。

export interface FaqItem {
  q: string;
  a: string;
}

export interface ContentSection {
  heading: string;
  body: string[];
}

/**
 * 隐私政策的小节。比 ContentSection 多一个可选的要点列表——「保存了哪些字段」
 * 「有哪些第三方」这类内容排成条目远比塞进段落好读，而读得懂正是一份隐私政策
 * 唯一的作用。
 */
export interface PrivacySection extends ContentSection {
  bullets?: string[];
}

export type DownloadFeatureAvailability =
  | "included"
  | "limited"
  | "unavailable";

export interface DownloadComparisonOption {
  status: DownloadFeatureAvailability;
  detail: string;
}

export interface DownloadComparisonRow {
  feature: string;
  web: DownloadComparisonOption;
  desktop: DownloadComparisonOption;
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
  privacy: {
    metaTitle: string;
    metaDescription: string;
    heading: string;
    intro: string;
    updatedLabel: string;
    updated: string;
    sections: PrivacySection[];
  };
  download: {
    metaTitle: string;
    metaDescription: string;
    heading: string;
    intro: string;
    benefits: ContentSection[];
    comparisonHeading: string;
    comparisonIntro: string;
    comparisonFeatureLabel: string;
    webLabel: string;
    desktopLabel: string;
    featureIncludedLabel: string;
    featureLimitedLabel: string;
    featureUnavailableLabel: string;
    comparison: DownloadComparisonRow[];
    downloadsHeading: string;
    downloadsIntro: string;
    demoHeading: string;
    demoIntro: string;
    demoAppHeading: string;
    demoAppBody: string;
    demoAppAlt: string;
    demoMiniHeading: string;
    demoMiniBody: string;
    demoMiniAlt: string;
    demoCtaLabel: string;
    latestVersionLabel: string;
    loadingLabel: string;
    unavailableLabel: string;
    mirrorLabel: string;
    mirrorHint: string;
    mirrorNotice: string;
    downloadLabel: string;
    windowsTitle: string;
    windowsDescription: string;
    windowsX64Label: string;
    windowsArmLabel: string;
    recommendedLabel: string;
    macosTitle: string;
    macosDescription: string;
    appleSiliconLabel: string;
    intelLabel: string;
    linuxTitle: string;
    linuxDescription: string;
    linuxX64Label: string;
    comingSoonLabel: string;
    githubLabel: string;
    githubDescription: string;
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
