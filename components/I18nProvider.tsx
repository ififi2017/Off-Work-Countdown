"use client";

import { ReactNode, useEffect } from "react";
import i18n from "i18next";
import { initReactI18next, I18nextProvider } from "react-i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import Backend from "i18next-http-backend";

interface I18nProviderProps {
  children: ReactNode;
  lang: string;
}

i18n
  .use(Backend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    lng: "en",
    fallbackLng: "en",
    ns: ["translation", "seo"],
    defaultNS: "translation",
    backend: {
      loadPath: "/locales/{{lng}}/{{ns}}.json",
    },
    detection: {
      order: ["querystring", "cookie", "localStorage", "navigator"],
      lookupQuerystring: "lng",
      lookupCookie: "i18nextLng",
      lookupLocalStorage: "i18nextLng",
      caches: ["localStorage", "cookie"],
    },
  });

export function I18nProvider({ children, lang }: I18nProviderProps) {
  useEffect(() => {
    i18n.changeLanguage(lang);
    document.documentElement.lang = lang;
  }, [lang]);

  return <I18nextProvider i18n={i18n}>{children}</I18nextProvider>;
}
