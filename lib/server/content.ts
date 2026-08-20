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
    // 联系方式不放进 sections：页面要在它下面渲染邮箱和仓库链接，
    // 靠「最后一个小节」来定位，加一节就会错位。
    contactHeading: string;
    contactBody: string[];
    contactEmailLabel: string;
    contactEmailDescription: string;
    contactGithubLabel: string;
    contactGithubDescription: string;
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
    storeCtaLabel: string;
    demoHeading: string;
    demoIntro: string;
    demoAppHeading: string;
    demoAppBody: string;
    demoAppAlt: string;
    demoMiniHeading: string;
    demoMiniBody: string;
    demoMiniAlt: string;
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
    windowsX64ShortLabel: string;
    windowsArmShortLabel: string;
    recommendedLabel: string;
    macosTitle: string;
    macosDescription: string;
    macAppStoreCtaLabel: string;
    macAppStoreDialogTitle: string;
    macAppStoreDialogIntro: string;
    macAppStoreWidgetHeading: string;
    macAppStoreWidgetBody: string;
    macAppStoreWidgetAlt: string;
    macAppStoreWidgetImageLight: string;
    macAppStoreWidgetImageDark: string;
    macAppStorePerk1: string;
    macAppStorePerk2: string;
    macAppStorePerk3: string;
    macAppStorePriceLabel: string;
    macAppStoreSupportNote: string;
    macAppStoreDialogPrimary: string;
    macAppStoreDialogSecondary: string;
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

export type MacAppStoreDialogCopy = Pick<
  ContentBundle["download"],
  | "macAppStoreCtaLabel"
  | "macAppStoreDialogTitle"
  | "macAppStoreDialogIntro"
  | "macAppStoreWidgetHeading"
  | "macAppStoreWidgetBody"
  | "macAppStoreWidgetAlt"
  | "macAppStoreWidgetImageLight"
  | "macAppStoreWidgetImageDark"
  | "macAppStorePerk1"
  | "macAppStorePerk2"
  | "macAppStorePerk3"
  | "macAppStorePriceLabel"
  | "macAppStoreSupportNote"
  | "macAppStoreDialogPrimary"
  | "macAppStoreDialogSecondary"
>;

/**
 * 首页只需要付费说明弹窗这组文案。显式挑字段，避免把下载页的比较表、FAQ 和
 * 下载状态文案全部序列化进客户端 payload。
 */
export function pickMacAppStoreDialogCopy(
  download: ContentBundle["download"]
): MacAppStoreDialogCopy {
  return {
    macAppStoreCtaLabel: download.macAppStoreCtaLabel,
    macAppStoreDialogTitle: download.macAppStoreDialogTitle,
    macAppStoreDialogIntro: download.macAppStoreDialogIntro,
    macAppStoreWidgetHeading: download.macAppStoreWidgetHeading,
    macAppStoreWidgetBody: download.macAppStoreWidgetBody,
    macAppStoreWidgetAlt: download.macAppStoreWidgetAlt,
    macAppStoreWidgetImageLight: download.macAppStoreWidgetImageLight,
    macAppStoreWidgetImageDark: download.macAppStoreWidgetImageDark,
    macAppStorePerk1: download.macAppStorePerk1,
    macAppStorePerk2: download.macAppStorePerk2,
    macAppStorePerk3: download.macAppStorePerk3,
    macAppStorePriceLabel: download.macAppStorePriceLabel,
    macAppStoreSupportNote: download.macAppStoreSupportNote,
    macAppStoreDialogPrimary: download.macAppStoreDialogPrimary,
    macAppStoreDialogSecondary: download.macAppStoreDialogSecondary,
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
