'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';

export function ManifestLink() {
  const pathname = usePathname();
  const [lang, setLang] = useState('');

  useEffect(() => {
    if (pathname) {
      const pathParts = pathname.split('/');
      if (pathParts.length > 1 && pathParts[1]) {
        setLang(pathParts[1]);
      }
    }
  }, [pathname]);

  if (!lang) return null;

  return (
    <>
      <link 
        rel="manifest" 
        href={`/manifest.json?lang=${lang}`}
        crossOrigin="use-credentials"
      />
    </>
  );
} 