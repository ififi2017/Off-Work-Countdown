import { ReactNode } from 'react';
import { locales } from '@/i18n-config';

export async function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default function Layout({
  children,
  params: { lang },
}: {
  children: ReactNode;
  params: { lang: string };
}) {
  return (
    <div className="min-h-screen" data-lang={lang}>
      {children}
    </div>
  );
} 