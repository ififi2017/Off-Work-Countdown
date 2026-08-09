import { MiniCountdown } from "@/components/MiniCountdown";
import { I18nProvider } from "@/components/I18nProvider";
import { getTranslations } from "@/lib/server/i18n";

export default async function MiniPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const [translation, seo] = await Promise.all([
    getTranslations(lang, "translation"),
    getTranslations(lang, "seo"),
  ]);

  return (
    <I18nProvider lang={lang} resources={{ translation, seo }}>
      <MiniCountdown />
    </I18nProvider>
  );
}
