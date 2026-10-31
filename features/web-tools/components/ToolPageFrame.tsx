import type { ReactNode } from "react";
import Link from "next/link";
import { siteConfig } from "@/config/site";
import { officialPageUrl } from "@/lib/site-urls";
import type { ToolPage } from "../catalog/pages";
import { getDirectoryPage } from "../catalog/pages";

export function ToolPageFrame({ page, children }: { page: ToolPage; children: ReactNode }) {
  const zh = page.lang === "zh-CN";
  const directory = getDirectoryPage(page.lang);
  return <div className="min-h-screen bg-gray-50 text-gray-900 dark:bg-gray-950 dark:text-gray-100">
    <header className="border-b border-gray-200 dark:border-gray-800">
      <nav aria-label={zh ? "品牌导航" : "Main navigation"} className="mx-auto flex max-w-4xl flex-wrap items-center gap-x-6 gap-y-3 px-5 py-5 sm:px-8">
        <Link href={`/${page.lang}`} className="mr-auto text-lg font-bold tracking-tight">{siteConfig.brandName}</Link>
        {directory && <Link href={directory.path} className="text-sm text-gray-600 hover:text-orange-600 dark:text-gray-300">{zh ? "工具库" : "Tools"}</Link>}
        <a href={officialPageUrl(page.lang, "download")} className="text-sm text-gray-600 hover:text-orange-600 dark:text-gray-300">{zh ? "下载客户端" : "Get the apps"}</a>
      </nav>
    </header>
    <main className="mx-auto max-w-4xl px-5 pb-16 pt-9 sm:px-8 sm:pt-12">
      {page.status !== "published" && <p className="mb-6 border-l-2 border-orange-500 pl-3 text-sm leading-6 text-gray-600 dark:text-gray-400">{zh ? "审核预览 · 本批内容仍待人工审核，未发布到公开工具库或搜索清单。" : "Review preview · This batch awaits human content review and is excluded from the public tool list and sitemap."}</p>}
      {page.kind === "salary" && <p className="mb-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">{zh ? "中国大陆 · 简体中文 · 税前换算" : "United States · English · Gross pay"}</p>}
      <h1 className="max-w-3xl text-3xl font-bold leading-tight tracking-tight sm:text-4xl">{page.title}</h1>
      {children}
    </main>
    <footer className="border-t border-gray-200 dark:border-gray-800"><div className="mx-auto flex max-w-4xl flex-wrap gap-x-6 gap-y-3 px-5 py-6 text-xs text-gray-500 sm:px-8 dark:text-gray-400"><span>© fi_niaR Studio</span><a href={officialPageUrl(page.lang, "privacy")} className="hover:underline">{zh ? "隐私" : "Privacy"}</a><a href={`mailto:${siteConfig.supportEmail}`} className="hover:underline">{zh ? "联系我们" : "Contact"}</a></div></footer>
  </div>;
}
