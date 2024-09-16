'use client';

import { useEffect } from 'react';
import i18n from '../i18n';

export function I18nProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    const savedLanguage = localStorage.getItem('i18nextLng');
    const defaultLanguage = savedLanguage || (typeof window !== 'undefined' ? window.navigator.language : 'en');
    i18n.changeLanguage(defaultLanguage);
  }, []);

  return <>{children}</>;
}