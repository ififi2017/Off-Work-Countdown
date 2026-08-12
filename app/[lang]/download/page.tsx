import type { Metadata } from "next";
import { Bell, Keyboard, PanelTop } from "lucide-react";
import { siteConfig } from "@/config/site";
import { ContentPage } from "@/components/ContentPage";
import { DesktopDownloads } from "@/components/DesktopDownloads";
import { getContent } from "@/lib/server/content";
import { localizedSocialMetadata } from "@/lib/server/metadata";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";

export const dynamicParams = false;

export function generateStaticParams() {
  return contentLocales.map((lang) => ({ lang }));
}

const alternateLanguages = {
  ...Object.fromEntries(
    contentLocales.map((lang) => [lang, `${siteConfig.baseUrl}/${lang}/download`])
  ),
  "x-default": `${siteConfig.baseUrl}/${defaultContentLocale}/download`,
};

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string }>;
}): Promise<Metadata> {
  const { lang } = await params;
  const content = await getContent(lang);

  return {
    metadataBase: new URL(siteConfig.baseUrl),
    title: content.download.metaTitle,
    description: content.download.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/download`,
      languages: alternateLanguages,
    },
    ...localizedSocialMetadata({
      lang,
      path: "download",
      title: content.download.metaTitle,
      description: content.download.metaDescription,
    }),
  };
}

const benefitIcons = [PanelTop, Bell, Keyboard];

export default async function DownloadPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const content = await getContent(lang);
  const copy = content.download;
  // 演示片段按语种各录了一份；内容页只有中英两种语言。
  const videoLang = lang === "zh-CN" ? "zh" : "en";
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: siteConfig.name,
    description: copy.metaDescription,
    url: `${siteConfig.baseUrl}/${lang}/download`,
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "macOS, Windows",
    isAccessibleForFree: true,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    downloadUrl: `${siteConfig.baseUrl}/${lang}/download`,
    codeRepository: siteConfig.github,
  };

  return (
    <ContentPage
      lang={lang as ContentLocale}
      slug="download"
      backLabel={content.backToApp}
      heading={copy.heading}
      intro={copy.intro}
      wide
    >
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c"),
        }}
      />

      {/* 演示片段。明暗两版用 dark: 变体切换而不是 prefers-color-scheme：
          主题类打在 <html> 上，这样手动切主题也跟得上，不只是跟系统。
          语言不用切——下载页本身就是分语种路由。 */}
      <section id="demo" className="mb-16">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.demoHeading}
        </h2>
        <p className="mt-2 max-w-2xl text-gray-600 dark:text-gray-300">
          {copy.demoIntro}
        </p>
        <div className="mt-6 flex flex-wrap items-start justify-center gap-6">
          {[
            { kind: "app", width: 430, alt: copy.demoAppAlt },
            { kind: "mini", width: 300, alt: copy.demoMiniAlt },
          ].map(({ kind, width, alt }) =>
            (["light", "dark"] as const).map((scheme) => (
              <video
                key={`${kind}-${scheme}`}
                src={`/demo/${kind}-${videoLang}-${scheme}.mp4`}
                // 隐藏的那一个不会自动播；切主题后若浏览器没接着播，
                // 有海报至少是一帧真实画面而不是空白框。
                poster={`/demo/${kind}-${videoLang}-${scheme}.jpg`}
                width={width}
                aria-label={alt}
                autoPlay
                muted
                loop
                playsInline
                preload="metadata"
                // 宽度上限走行内 style：Tailwind 的 JIT 扫的是字面量，
                // 模板字符串拼出来的 max-w-[430px] 根本不会被生成。
                className={`w-full rounded-2xl border border-gray-200 shadow-sm dark:border-gray-700 ${
                  scheme === "dark" ? "hidden dark:block" : "block dark:hidden"
                }`}
                style={{ maxWidth: width }}
              />
            ))
          )}
        </div>
      </section>

      <section id="downloads">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.downloadsHeading}
        </h2>
        <p className="mt-2 max-w-2xl text-gray-600 dark:text-gray-300">
          {copy.downloadsIntro}
        </p>
        <div className="mt-6">
          <DesktopDownloads copy={copy} releasesUrl={siteConfig.releases} />
        </div>
      </section>

      <div className="mt-16 grid gap-4 md:grid-cols-3">
        {copy.benefits.map((benefit, index) => {
          const Icon = benefitIcons[index] ?? PanelTop;
          return (
            <section
              key={benefit.heading}
              className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800"
            >
              <span className="mb-4 grid h-10 w-10 place-items-center rounded-xl bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-100">
                <Icon className="h-5 w-5" aria-hidden="true" />
              </span>
              <h2 className="font-semibold text-gray-950 dark:text-white">
                {benefit.heading}
              </h2>
              {benefit.body.map((paragraph) => (
                <p
                  key={paragraph}
                  className="mt-2 text-sm leading-6 text-gray-600 dark:text-gray-300"
                >
                  {paragraph}
                </p>
              ))}
            </section>
          );
        })}
      </div>

      <section className="mt-16">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.comparisonHeading}
        </h2>
        <p className="mt-2 max-w-2xl text-gray-600 dark:text-gray-300">
          {copy.comparisonIntro}
        </p>

        <div className="mt-6 overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="bg-gray-50 text-gray-500 dark:bg-gray-900/50 dark:text-gray-400">
                <tr>
                  <th className="px-5 py-3 font-medium" scope="col" />
                  <th className="px-5 py-3 font-medium" scope="col">
                    {copy.webLabel}
                  </th>
                  <th className="px-5 py-3 font-medium" scope="col">
                    {copy.desktopLabel}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                {copy.comparison.map((row) => (
                  <tr key={row.feature}>
                    <th
                      scope="row"
                      className="px-5 py-4 font-medium text-gray-950 dark:text-white"
                    >
                      {row.feature}
                    </th>
                    <td className="px-5 py-4 text-gray-600 dark:text-gray-300">
                      {row.web}
                    </td>
                    <td className="px-5 py-4 text-gray-600 dark:text-gray-300">
                      {row.desktop}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </ContentPage>
  );
}
