import { locales } from '@/i18n-config'
import { NextResponse } from 'next/server'

export const GET = async () => {
  const baseUrl = 'https://off.rainif.com'

  // 生成 XML
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
            xmlns:xhtml="http://www.w3.org/1999/xhtml">
      <url>
        <loc>${baseUrl}</loc>
        ${locales.map((locale) => `
          <xhtml:link 
            rel="alternate" 
            hreflang="${locale}"
            href="${baseUrl}/${locale}"
          />`).join('')}
        <xhtml:link 
          rel="alternate" 
          hreflang="x-default"
          href="${baseUrl}"
        />
      </url>
      ${locales.map((locale) => `
        <url>
          <loc>${baseUrl}/${locale}</loc>
          ${locales.map((l) => `
            <xhtml:link 
              rel="alternate" 
              hreflang="${l}"
              href="${baseUrl}/${l}"
            />`).join('')}
          <xhtml:link 
            rel="alternate" 
            hreflang="x-default"
            href="${baseUrl}"
          />
        </url>
      `).join('')}
    </urlset>`

  return new NextResponse(xml, {
    headers: {
      'Content-Type': 'text/xml',
    },
  })
}

// 设置此路由不需要布局
export const dynamic = 'force-dynamic'
export const revalidate = 3600 // 每小时重新验证一次 