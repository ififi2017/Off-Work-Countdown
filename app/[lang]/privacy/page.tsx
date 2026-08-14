import type { Metadata } from "next";
import { ExternalLink, Github, Mail } from "lucide-react";
import { siteConfig } from "@/config/site";
import { getContent } from "@/lib/server/content";
import { ContentPage } from "@/components/ContentPage";
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
    contentLocales.map((lang) => [lang, `${siteConfig.baseUrl}/${lang}/privacy`])
  ),
  "x-default": `${siteConfig.baseUrl}/${defaultContentLocale}/privacy`,
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
    title: content.privacy.metaTitle,
    description: content.privacy.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/privacy`,
      languages: alternateLanguages,
    },
    ...localizedSocialMetadata({
      lang,
      path: "privacy",
      title: content.privacy.metaTitle,
      description: content.privacy.metaDescription,
    }),
  };
}

export default async function PrivacyPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const content = await getContent(lang);

  return (
    <ContentPage
      lang={lang as ContentLocale}
      slug="privacy"
      backLabel={content.backToApp}
      heading={content.privacy.heading}
      intro={content.privacy.intro}
    >
      <div className="space-y-10">
        {/* 生效日期放在正文之前：读隐私政策的人第一个想确认的就是这份是不是最新的。 */}
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {content.privacy.updatedLabel} {content.privacy.updated}
        </p>

        {content.privacy.sections.map((section) => (
          <section key={section.heading}>
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
              {section.heading}
            </h2>
            {section.body.map((paragraph) => (
              <p
                key={paragraph}
                className="mt-3 text-base leading-7 text-gray-600 dark:text-gray-300"
              >
                {paragraph}
              </p>
            ))}
            {section.bullets && (
              <ul className="mt-4 list-disc space-y-2 ps-5 text-base leading-7 text-gray-600 marker:text-gray-400 dark:text-gray-300 dark:marker:text-gray-500">
                {section.bullets.map((bullet) => (
                  <li key={bullet}>{bullet}</li>
                ))}
              </ul>
            )}
          </section>
        ))}

        {/* 邮箱与仓库地址从 siteConfig 取，不写进文案里：同一个地址还要填进
            Partner Center 的商店 listing，两处对不上就是个查起来很烦的问题。 */}
        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
            {content.privacy.contactHeading}
          </h2>
          {content.privacy.contactBody.map((paragraph) => (
            <p
              key={paragraph}
              className="mt-3 text-base leading-7 text-gray-600 dark:text-gray-300"
            >
              {paragraph}
            </p>
          ))}
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <a
              href={`mailto:${siteConfig.supportEmail}`}
              className="group flex min-h-32 flex-col rounded-2xl border border-gray-200 bg-white p-4 shadow-sm transition-[border-color,background-color,box-shadow] hover:border-gray-300 hover:bg-gray-50 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gray-500 focus-visible:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-gray-600 dark:hover:bg-gray-800/70 dark:focus-visible:ring-gray-400 dark:focus-visible:ring-offset-gray-900"
            >
              <span className="flex items-start justify-between gap-3">
                <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-200">
                  <Mail className="h-4.5 w-4.5" aria-hidden="true" />
                </span>
                <span className="text-sm font-medium text-gray-500 transition-colors group-hover:text-gray-700 dark:text-gray-400 dark:group-hover:text-gray-200">
                  {siteConfig.supportEmail}
                </span>
              </span>
              <span className="mt-4 block font-semibold text-gray-900 dark:text-white">
                {content.privacy.contactEmailLabel}
              </span>
              <span className="mt-1 block text-sm leading-5 text-gray-500 dark:text-gray-400">
                {content.privacy.contactEmailDescription}
              </span>
            </a>

            <a
              href={siteConfig.github}
              target="_blank"
              rel="noopener noreferrer"
              className="group flex min-h-32 flex-col rounded-2xl border border-gray-200 bg-white p-4 shadow-sm transition-[border-color,background-color,box-shadow] hover:border-gray-300 hover:bg-gray-50 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gray-500 focus-visible:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-gray-600 dark:hover:bg-gray-800/70 dark:focus-visible:ring-gray-400 dark:focus-visible:ring-offset-gray-900"
            >
              <span className="flex items-start justify-between gap-3">
                <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-200">
                  <Github className="h-4.5 w-4.5" aria-hidden="true" />
                </span>
                <ExternalLink
                  className="h-4 w-4 text-gray-400 transition-colors group-hover:text-gray-600 dark:group-hover:text-gray-200"
                  aria-hidden="true"
                />
              </span>
              <span className="mt-4 block font-semibold text-gray-900 dark:text-white">
                {content.privacy.contactGithubLabel}
              </span>
              <span className="mt-1 block text-sm leading-5 text-gray-500 dark:text-gray-400">
                {content.privacy.contactGithubDescription}
              </span>
            </a>
          </div>
        </section>
      </div>
    </ContentPage>
  );
}
