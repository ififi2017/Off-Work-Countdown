import type { Metadata } from "next";
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
      </div>
    </ContentPage>
  );
}
