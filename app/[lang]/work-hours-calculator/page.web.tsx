import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { siteConfig } from "@/config/site";
import { locales, type Locale } from "@/i18n-config";
import {
  WorkHoursCalculator,
  type WorkHoursCalculatorCopy,
} from "@/components/WorkHoursCalculator";
import { contentLocales, type ContentLocale } from "@/lib/content-locales";
import { presets } from "@/lib/presets";
import { getTranslations } from "@/lib/server/i18n";
import { localizedSocialMetadata } from "@/lib/server/metadata";
import { getPresetCopy } from "@/lib/server/presets";
import { webAppAlternates, webAppPageUrl } from "@/lib/site-urls";
import { WORK_HOURS_CALCULATOR_SLUG } from "@/lib/work-hours";

// 工时计算器：独立于倒计时的 Web 小工具（仅 Web 构建；`.web.tsx` 不进桌面导出）。
// 界面文案短，19 种语言都有；预设页长文仍只有中英两版，只在这两种语言下互链。
// 计算器本体是客户端组件，但默认输入的结果、标题、说明都在首屏 HTML 里。

export const dynamicParams = false;

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

interface CalculatorPageCopy extends WorkHoursCalculatorCopy {
  metaTitle: string;
  metaDescription: string;
  heading: string;
  intro: string;
  backToApp: string;
  howHeading: string;
  howBody: string[];
  presetsHeading: string;
}

async function getCalculatorCopy(lang: string): Promise<CalculatorPageCopy> {
  return getTranslations(lang, "calculator");
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string }>;
}): Promise<Metadata> {
  const { lang } = await params;
  if (!locales.includes(lang as Locale)) return {};
  const copy = await getCalculatorCopy(lang);

  return {
    metadataBase: new URL(siteConfig.webAppUrl),
    title: copy.metaTitle,
    description: copy.metaDescription,
    alternates: {
      canonical: webAppPageUrl(lang, WORK_HOURS_CALCULATOR_SLUG),
      languages: webAppAlternates(locales, WORK_HOURS_CALCULATOR_SLUG),
    },
    ...localizedSocialMetadata({
      lang,
      path: WORK_HOURS_CALCULATOR_SLUG,
      title: copy.metaTitle,
      description: copy.metaDescription,
    }),
  };
}

export default async function WorkHoursCalculatorPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  if (!locales.includes(lang as Locale)) notFound();
  const copy = await getCalculatorCopy(lang);

  const hasPresets = contentLocales.includes(lang as ContentLocale);
  const presetCopy = hasPresets ? await getPresetCopy(lang) : null;
  const pageUrl = webAppPageUrl(lang, WORK_HOURS_CALCULATOR_SLUG);

  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebApplication",
        name: copy.heading,
        url: pageUrl,
        description: copy.metaDescription,
        inLanguage: lang,
        applicationCategory: "UtilitiesApplication",
        operatingSystem: "Any",
        browserRequirements: "Requires JavaScript",
        isAccessibleForFree: true,
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        publisher: { "@id": `${siteConfig.officialSiteUrl}/#organization` },
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          {
            "@type": "ListItem",
            position: 1,
            name: siteConfig.brandName,
            item: webAppPageUrl(lang),
          },
          {
            "@type": "ListItem",
            position: 2,
            name: copy.heading,
            item: pageUrl,
          },
        ],
      },
    ],
  };

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-gray-900">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c"),
        }}
      />
      <div className="mx-auto max-w-xl px-4 py-10 sm:px-5 sm:py-14">
        <Link
          href={`/${lang}`}
          className="inline-flex items-center gap-2 text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
        >
          <ArrowLeft size={16} className="rtl:rotate-180" aria-hidden="true" />
          {siteConfig.brandName} · {copy.backToApp}
        </Link>

        <h1 className="mt-8 text-3xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-4xl">
          {copy.heading}
        </h1>
        <p className="mt-3 text-base leading-7 text-gray-600 dark:text-gray-300">
          {copy.intro}
        </p>

        <div className="mt-8">
          <WorkHoursCalculator lang={lang} copy={copy} />
        </div>

        <section className="mt-12">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            {copy.howHeading}
          </h2>
          <div className="mt-3 space-y-3">
            {copy.howBody.map((paragraph, index) => (
              <p
                key={index}
                className="text-sm leading-6 text-gray-600 dark:text-gray-400"
              >
                {paragraph}
              </p>
            ))}
          </div>
        </section>

        {presetCopy && (
          <section className="mt-10 border-t border-gray-200 pt-6 dark:border-gray-800">
            <h2 className="text-sm font-semibold text-gray-800 dark:text-gray-200">
              {copy.presetsHeading}
            </h2>
            <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-sm">
              {presets.map((preset) => (
                <li key={preset.slug}>
                  <Link
                    href={`/${lang}/${preset.slug}`}
                    className="text-gray-600 underline-offset-4 transition-colors hover:text-gray-900 hover:underline dark:text-gray-400 dark:hover:text-white"
                  >
                    {presetCopy.items[preset.slug]?.name ?? preset.slug}
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </div>
  );
}
