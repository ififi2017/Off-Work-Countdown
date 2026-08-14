import type { Metadata } from "next";
import {
  ArrowDown,
  Bell,
  Check,
  Clock3,
  Keyboard,
  Minus,
  PanelTop,
} from "lucide-react";
import { siteConfig } from "@/config/site";
import { ContentPage } from "@/components/ContentPage";
import { DesktopDownloads } from "@/components/DesktopDownloads";
import {
  getContent,
  type DownloadComparisonOption,
} from "@/lib/server/content";
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

function AvailabilityCell({
  option,
  labels,
}: {
  option: DownloadComparisonOption;
  labels: Record<DownloadComparisonOption["status"], string>;
}) {
  const Icon =
    option.status === "included"
      ? Check
      : option.status === "limited"
        ? Clock3
        : Minus;
  const color =
    option.status === "included"
      ? "text-emerald-600 dark:text-emerald-400"
      : option.status === "limited"
        ? "text-amber-600 dark:text-amber-400"
        : "text-gray-400 dark:text-gray-500";

  return (
    <div className="flex items-start gap-2.5">
      <Icon
        className={`mt-0.5 h-4 w-4 shrink-0 ${color}`}
        aria-hidden="true"
      />
      <span className="leading-6 text-gray-600 dark:text-gray-300">
        <span className="sr-only">{labels[option.status]}: </span>
        {option.detail}
      </span>
    </div>
  );
}

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

      {/* 首屏文案之后直接让用户看到真实客户端，再逐层展开价值与功能差异。
          明暗版本跟随站内主题类切换。 */}
      <section id="demo">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.demoHeading}
        </h2>
        <p className="mt-2 max-w-3xl leading-7 text-gray-600 dark:text-gray-300">
          {copy.demoIntro}
        </p>

        <div className="mt-7 grid gap-6 md:grid-cols-2">
          {[
            {
              kind: "app",
              width: 430,
              heading: copy.demoAppHeading,
              body: copy.demoAppBody,
              alt: copy.demoAppAlt,
            },
            {
              kind: "mini",
              width: 300,
              heading: copy.demoMiniHeading,
              body: copy.demoMiniBody,
              alt: copy.demoMiniAlt,
            },
          ].map(({ kind, width, heading, body, alt }) => (
            <article
              key={kind}
              className="flex h-full flex-col rounded-3xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5 dark:border-gray-700 dark:bg-gray-800"
            >
              <div className="flex h-72 items-center justify-center overflow-hidden rounded-2xl bg-gray-50 p-4 sm:h-80 sm:p-5 lg:h-[22rem] dark:bg-gray-900/60">
                {(["light", "dark"] as const).map((scheme) => (
                  <video
                    key={`${kind}-${scheme}`}
                    src={`/demo/${kind}-${videoLang}-${scheme}.mp4`}
                    poster={`/demo/${kind}-${videoLang}-${scheme}.jpg`}
                    width={width}
                    aria-label={alt}
                    autoPlay
                    muted
                    loop
                    playsInline
                    preload="metadata"
                    className={`h-auto max-h-full w-auto max-w-full rounded-2xl border border-gray-200 object-contain shadow-md dark:border-gray-700 ${
                      scheme === "dark"
                        ? "hidden dark:block"
                        : "block dark:hidden"
                    }`}
                    style={{ maxWidth: width }}
                  />
                ))}
              </div>

              <div className="flex flex-1 flex-col px-1 pb-1 pt-6 sm:px-0">
                <h3 className="text-xl font-semibold tracking-tight text-gray-950 dark:text-white">
                  {heading}
                </h3>
                <p className="mt-3 leading-7 text-gray-600 dark:text-gray-300">
                  {body}
                </p>
                <a
                  href="#comparison"
                  className="mt-5 inline-flex w-fit items-center gap-2 rounded-full bg-gray-950 px-5 py-2.5 text-sm font-medium text-white transition-colors hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 sm:mt-auto sm:translate-y-1 dark:bg-white dark:text-gray-950 dark:hover:bg-gray-100 dark:focus:ring-offset-gray-800"
                >
                  {copy.demoCtaLabel}
                  <ArrowDown className="h-4 w-4" aria-hidden="true" />
                </a>
              </div>
            </article>
          ))}
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

      <section id="comparison" className="mt-16 scroll-mt-8">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.comparisonHeading}
        </h2>
        <p className="mt-2 max-w-3xl leading-7 text-gray-600 dark:text-gray-300">
          {copy.comparisonIntro}
        </p>

        <div className="mt-6 overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] table-fixed text-left text-sm">
              <thead className="bg-gray-50 text-gray-500 dark:bg-gray-900/50 dark:text-gray-400">
                <tr>
                  <th className="w-[27%] px-5 py-3 font-medium" scope="col">
                    {copy.comparisonFeatureLabel}
                  </th>
                  <th className="w-[36.5%] px-5 py-3 font-medium" scope="col">
                    {copy.webLabel}
                  </th>
                  <th className="w-[36.5%] px-5 py-3 font-medium" scope="col">
                    {copy.desktopLabel}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                {copy.comparison.map((row) => (
                  <tr key={row.feature}>
                    <th
                      scope="row"
                      className="px-5 py-4 font-medium leading-6 text-gray-950 dark:text-white"
                    >
                      {row.feature}
                    </th>
                    <td className="px-5 py-4 align-top">
                      <AvailabilityCell
                        option={row.web}
                        labels={{
                          included: copy.featureIncludedLabel,
                          limited: copy.featureLimitedLabel,
                          unavailable: copy.featureUnavailableLabel,
                        }}
                      />
                    </td>
                    <td className="px-5 py-4 align-top">
                      <AvailabilityCell
                        option={row.desktop}
                        labels={{
                          included: copy.featureIncludedLabel,
                          limited: copy.featureLimitedLabel,
                          unavailable: copy.featureUnavailableLabel,
                        }}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="downloads" className="mt-16 scroll-mt-8">
        <h2 className="text-2xl font-semibold tracking-tight text-gray-950 dark:text-white">
          {copy.downloadsHeading}
        </h2>
        <p className="mt-2 text-gray-600 dark:text-gray-300">
          {copy.downloadsIntro}
        </p>
        <div className="mt-6">
          <DesktopDownloads
            copy={copy}
            releasesUrl={siteConfig.releases}
            storeUrl={siteConfig.microsoftStore}
          />
        </div>
      </section>
    </ContentPage>
  );
}
