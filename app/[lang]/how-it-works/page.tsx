import type { Metadata } from "next";
import Link from "next/link";
import { siteConfig } from "@/config/site";
import { getContent } from "@/lib/server/content";
import { getPresetCopy } from "@/lib/server/presets";
import { presets } from "@/lib/presets";
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
    contentLocales.map((l) => [l, `${siteConfig.baseUrl}/${l}/how-it-works`])
  ),
  "x-default": `${siteConfig.baseUrl}/${defaultContentLocale}/how-it-works`,
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
    title: content.howItWorks.metaTitle,
    description: content.howItWorks.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/how-it-works`,
      languages: alternateLanguages,
    },
    ...localizedSocialMetadata({
      lang,
      path: "how-it-works",
      title: content.howItWorks.metaTitle,
      description: content.howItWorks.metaDescription,
      type: "article",
    }),
  };
}

export default async function HowItWorksPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const [content, presetCopy] = await Promise.all([
    getContent(lang),
    getPresetCopy(lang),
  ]);

  return (
    <ContentPage
      lang={lang as ContentLocale}
      slug="how-it-works"
      backLabel={content.backToApp}
      heading={content.howItWorks.heading}
      intro={content.howItWorks.intro}
    >
      <div className="space-y-10">
        {content.howItWorks.sections.map((section) => (
          <section key={section.heading}>
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
              {section.heading}
            </h2>
            {section.body.map((para, i) => (
              <p
                key={i}
                className="mt-3 text-base leading-7 text-gray-600 dark:text-gray-300"
              >
                {para}
              </p>
            ))}
          </section>
        ))}

        {/* 预设页的入口。它们需要来自已收录页面的内链，否则会变成孤儿页；
            放在这里也符合上下文——上面刚讲完班次是怎么算的。 */}
        <section className="border-t border-gray-200 pt-8 dark:border-gray-700">
          <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
            {presetCopy.otherPresetsHeading}
          </h2>
          <ul className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-base">
            {presets.map((p) => (
              <li key={p.slug}>
                <Link
                  href={`/${lang}/${p.slug}`}
                  className="text-gray-600 underline-offset-4 transition-colors hover:text-gray-900 hover:underline dark:text-gray-400 dark:hover:text-white"
                >
                  {presetCopy.items[p.slug]?.name ?? p.slug}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </ContentPage>
  );
}
