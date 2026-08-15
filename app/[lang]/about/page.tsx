import type { Metadata } from "next";
import Link from "next/link";
import { Github } from "lucide-react";
import { siteConfig } from "@/config/site";
import { getContent } from "@/lib/server/content";
import { ContentPage } from "@/components/ContentPage";
import { MicrosoftStoreBadge } from "@/components/MicrosoftStoreBadge";
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
    contentLocales.map((lang) => [lang, `${siteConfig.baseUrl}/${lang}/about`])
  ),
  "x-default": `${siteConfig.baseUrl}/${defaultContentLocale}/about`,
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
    title: content.about.metaTitle,
    description: content.about.metaDescription,
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}/about`,
      languages: alternateLanguages,
    },
    ...localizedSocialMetadata({
      lang,
      path: "about",
      title: content.about.metaTitle,
      description: content.about.metaDescription,
    }),
  };
}

export default async function AboutPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const content = await getContent(lang);

  return (
    <ContentPage
      lang={lang as ContentLocale}
      slug="about"
      backLabel={content.backToApp}
      heading={content.about.heading}
      intro={content.about.intro}
    >
      <div className="space-y-10">
        {content.about.sections.map((section) => (
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
          </section>
        ))}

        <div className="flex flex-wrap items-center gap-3">
          <Link
            href={siteConfig.github}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-gray-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-gray-700 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-200"
          >
            <Github className="h-4 w-4" />
            GitHub
          </Link>
          <MicrosoftStoreBadge className="flex min-h-11 items-center" />
        </div>
      </div>
    </ContentPage>
  );
}
