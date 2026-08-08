import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import type { ReactNode } from "react";

// 内容页外壳。刻意做成服务端组件：这些页面没有交互，全部内容随首屏 HTML
// 一起产出，是它们能被收录的前提。
interface ContentPageProps {
  lang: string;
  backLabel: string;
  heading: string;
  intro: string;
  children: ReactNode;
}

export function ContentPage({
  lang,
  backLabel,
  heading,
  intro,
  children,
}: ContentPageProps) {
  return (
    <div className="min-h-screen bg-gray-100 dark:bg-gray-900">
      <div className="mx-auto max-w-2xl px-5 py-12 sm:py-16">
        <Link
          href={`/${lang}`}
          className="inline-flex items-center gap-2 text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
        >
          <ArrowLeft size={16} className="rtl:rotate-180" />
          {backLabel}
        </Link>

        <h1 className="mt-8 text-3xl font-bold tracking-tight text-gray-900 dark:text-white sm:text-4xl">
          {heading}
        </h1>
        <p className="mt-4 text-base leading-7 text-gray-600 dark:text-gray-300">
          {intro}
        </p>

        <div className="mt-10">{children}</div>
      </div>
    </div>
  );
}
