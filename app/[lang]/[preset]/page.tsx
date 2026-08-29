import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { siteConfig } from "@/config/site";
import { ContentPage } from "@/components/ContentPage";
import { getPresetCopy } from "@/lib/server/presets";
import { presets, getPreset } from "@/lib/presets";
import { getShiftLengthHours } from "@/lib/countdown";
import { encodeShift } from "@/lib/share";
import { localizedSocialMetadata } from "@/lib/server/metadata";
import {
  contentLocales,
  defaultContentLocale,
  type ContentLocale,
} from "@/lib/content-locales";
import { isContentSlug } from "@/lib/site-urls";

// 五页长文已迁到官网，本仓不再保留同名页面。Web 上旧 URL 由 next.config 301；
// 若落到这一段（例如桌面静态导出），直接 404，不要当成预设班次。
export const dynamicParams = false;

export function generateStaticParams() {
  return contentLocales.flatMap((lang) =>
    presets.map((p) => ({ lang, preset: p.slug }))
  );
}

function alternatesFor(slug: string) {
  return {
    ...Object.fromEntries(
      contentLocales.map((l) => [l, `${siteConfig.webAppUrl}/${l}/${slug}`])
    ),
    "x-default": `${siteConfig.webAppUrl}/${defaultContentLocale}/${slug}`,
  };
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string; preset: string }>;
}): Promise<Metadata> {
  const { lang, preset } = await params;
  if (isContentSlug(preset)) return {};
  const copy = await getPresetCopy(lang);
  const item = copy.items[preset];
  if (!item) return {};

  return {
    metadataBase: new URL(siteConfig.webAppUrl),
    title: item.metaTitle,
    description: item.metaDescription,
    alternates: {
      canonical: `${siteConfig.webAppUrl}/${lang}/${preset}`,
      languages: alternatesFor(preset),
    },
    ...localizedSocialMetadata({
      lang,
      path: preset,
      title: item.metaTitle,
      description: item.metaDescription,
      type: "article",
    }),
  };
}

// 小时数去掉多余的 .0，9.5 这类保留一位小数。
function formatHours(h: number): string {
  return Number.isInteger(h) ? String(h) : h.toFixed(1);
}

export default async function PresetPage({
  params,
}: {
  params: Promise<{ lang: string; preset: string }>;
}) {
  const { lang, preset } = await params;
  if (isContentSlug(preset)) notFound();
  const definition = getPreset(preset);
  const copy = await getPresetCopy(lang);
  const item = copy.items[preset];
  if (!definition || !item) notFound();

  const perDay = getShiftLengthHours(
    definition.shift.start,
    definition.shift.end
  );
  const perWeek = perDay * definition.daysPerWeek;

  const facts = [
    {
      label: copy.scheduleLabel,
      value: `${definition.shift.start} – ${definition.shift.end}`,
    },
    {
      label: copy.perDayLabel,
      value: `${formatHours(perDay)}${copy.hoursUnit}`,
    },
    {
      label: copy.perWeekLabel,
      value: `${formatHours(perWeek)}${copy.hoursUnit}`,
    },
  ];

  // 带上班次直接开始倒计时。不加 from=share —— 那是访问者自己选的作息，
  // 不该显示「有人分享给你」，也理应写入本地设置。
  const startHref = `/${lang}?s=${encodeShift(definition.shift)}`;

  return (
    <ContentPage
      lang={lang as ContentLocale}
      slug={preset}
      backLabel={copy.backToApp}
      heading={item.name}
      intro={item.intro}
    >
      <dl className="grid grid-cols-3 gap-3">
        {facts.map((f) => (
          <div
            key={f.label}
            className="rounded-xl bg-white/70 px-3 py-3 text-center dark:bg-black/20"
          >
            <dt className="text-xs text-gray-500 dark:text-gray-400">
              {f.label}
            </dt>
            <dd className="mt-1 text-sm font-semibold text-gray-900 dark:text-white">
              {f.value}
            </dd>
          </div>
        ))}
      </dl>

      <div className="mt-8 space-y-4">
        {item.body.map((para, i) => (
          <p
            key={i}
            className="text-base leading-7 text-gray-600 dark:text-gray-300"
          >
            {para}
          </p>
        ))}
      </div>

      <Link
        href={startHref}
        className="mt-8 inline-flex rounded-xl bg-gray-900 px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-gray-700 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-200"
      >
        {copy.startCta}
      </Link>

      {/* 预设页之间互链，爬虫才走得到。 */}
      <section className="mt-12 border-t border-gray-200 pt-6 dark:border-gray-700">
        <h2 className="text-sm font-semibold text-gray-800 dark:text-gray-200">
          {copy.otherPresetsHeading}
        </h2>
        <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-sm">
          {presets
            .filter((p) => p.slug !== preset)
            .map((p) => (
              <li key={p.slug}>
                <Link
                  href={`/${lang}/${p.slug}`}
                  className="text-gray-600 underline-offset-4 transition-colors hover:text-gray-900 hover:underline dark:text-gray-400 dark:hover:text-white"
                >
                  {copy.items[p.slug]?.name ?? p.slug}
                </Link>
              </li>
            ))}
        </ul>
      </section>
    </ContentPage>
  );
}
