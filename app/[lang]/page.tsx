import { notFound } from 'next/navigation';
import { OffWorkCountdown } from '@/components/off-work-countdown';
import { DesktopDownloadInvite } from '@/components/DesktopDownloadInvite';
import { AdFreeInvite } from '@/components/AdFreeInvite';
import { I18nProvider } from '@/components/I18nProvider';
import { locales, type Locale } from '@/i18n-config';
import { getTranslations } from '@/lib/server/i18n';
import { buildWebAppJsonLd } from '@/lib/server/metadata';
import { IS_WEB_BUILD } from '@/lib/build-target';

type Props = {
  params: Promise<{ lang: string }>
};

export default async function Home({ params }: Props) {
  const { lang } = await params;
  // dynamicParams 为 false 时未知语言本应直接 404。这里再挡一层：一旦页面
  // 仍被渲染，文件名 locale 会让 Intl.NumberFormat 抛错并变成 500。
  if (!locales.includes(lang as Locale)) notFound();
  const [translation, seo] = await Promise.all([
    getTranslations(lang, 'translation'),
    getTranslations(lang, 'seo'),
  ]);
  const jsonLd = buildWebAppJsonLd({
    lang,
    description: seo.description,
  });

  return (
    <I18nProvider lang={lang} resources={{ translation, seo }}>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c'),
        }}
      />
      <div className="min-h-screen">
        <OffWorkCountdown lang={lang} />
      </div>
      {IS_WEB_BUILD && <DesktopDownloadInvite />}
      {IS_WEB_BUILD && <AdFreeInvite />}
    </I18nProvider>
  );
}
