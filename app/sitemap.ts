import { MetadataRoute } from 'next'
import { locales } from '@/i18n-config'

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = 'https://off.rainif.com'
  
  // 为每个语言版本创建 URL 条目
  const routes = locales.map((locale) => ({
    url: `${baseUrl}/${locale}`,
    lastModified: new Date(),
    changeFrequency: 'daily' as const,
    priority: 1,
  }))

  // 添加根路径
  routes.push({
    url: baseUrl,
    lastModified: new Date(),
    changeFrequency: 'daily' as const,
    priority: 1,
  })

  return routes
} 