import { OffWorkCountdown } from '@/components/off-work-countdown';
import { DesktopDownloadInvite } from '@/components/DesktopDownloadInvite';
import { I18nProvider } from '@/components/I18nProvider';
import { getTranslations } from '@/lib/server/i18n';
import { buildWebAppJsonLd } from '@/lib/server/metadata';
import { IS_WEB_BUILD } from '@/lib/build-target';

type Props = {
  params: Promise<{ lang: string }>
};

export default async function Home({ params }: Props) {
  const { lang } = await params;
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
    </I18nProvider>
  );
}
