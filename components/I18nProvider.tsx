'use client';

import { I18nextProvider } from 'react-i18next';
import { useEffect, useState } from 'react';
import i18n from '@/i18n';

export function I18nProvider({ 
  children,
  lang
}: { 
  children: React.ReactNode;
  lang: string;
}) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const init = async () => {
      // 等待 i18n 初始化完成
      if (!i18n.isInitialized) {
        await new Promise(resolve => {
          i18n.on('initialized', resolve);
        });
      }
      
      // 切换语言
      await i18n.changeLanguage(lang);
      setMounted(true);
    };

    init();
  }, [lang]);

  // 在初始化完成前显示加载动画
  if (!mounted) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-r from-gray-50 to-gray-100">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-gray-200 border-t-primary rounded-full animate-spin mx-auto mb-4" />
          <span className="text-xl font-medium bg-gradient-to-r from-primary to-primary/60 bg-clip-text text-transparent animate-pulse">
            Loading...
          </span>
        </div>
      </div>
    );
  }

  return <I18nextProvider i18n={i18n}>{children}</I18nextProvider>;
}